"""Observe standard Git using disposable repositories, never the project."""

import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys


A = "10000000-0000-4000-8000-000000000001"
B = "10000000-0000-4000-8000-000000000002"

HOOK = r'''
import json
import os
from pathlib import Path
import subprocess
import sys

git, name, phase = sys.argv[1:4]
lines = sys.stdin.read().splitlines()
actual = {}
for line in lines:
    ref = line.rsplit(" ", 1)[-1]
    p = subprocess.run([git, "rev-parse", "--verify", ref],
                       capture_output=True, text=True, timeout=10)
    actual[ref] = p.stdout.strip() if p.returncode == 0 else None
record = {"name": name, "phase": phase, "updates": lines, "actual": actual}
with Path(os.environ["GR_NATIVE_HOOK_LOG"]).open("a", encoding="utf-8") as out:
    out.write(json.dumps(record, sort_keys=True) + "\n")
reject = os.environ.get("GR_NATIVE_REJECT_REF")
if name == "guard" and phase == "prepared" and reject:
    if any(line.rsplit(" ", 1)[-1] == reject for line in lines):
        sys.exit(17)
pair = os.environ.get("GR_NATIVE_REQUIRE_PAIR")
if name == "guard" and phase == "prepared" and pair:
    present = {}
    for ref in pair.split(","):
        p = subprocess.run([git, "rev-parse", "--verify", ref],
                           capture_output=True, text=True, timeout=10)
        present[ref] = p.returncode == 0
    for line in lines:
        old, new, ref = line.split()
        if ref in present:
            present[ref] = any(character != "0" for character in new)
    if any(present.values()) and not all(present.values()):
        sys.exit(19)
'''


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def short_name(uuid):
    raw = hashlib.sha256(uuid.encode("ascii")).digest()[:5]
    return base64.b32encode(raw).decode("ascii").lower().rstrip("=")


def worktree_records(raw):
    records = []
    record = {}
    for field in raw.split("\0"):
        if not field:
            if record:
                records.append(record)
                record = {}
            continue
        key, separator, value = field.partition(" ")
        record[key] = value if separator else True
    if record:
        records.append(record)
    return records


class Fixture:
    def __init__(self, root, git, backend, object_format, global_config):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=False)
        self.git = git
        self.backend = backend
        self.object_format = object_format
        self.commands = []
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update({
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": str(global_config),
            "GIT_AUTHOR_NAME": "Git Roam Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Git Roam Fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "GIT_AUTHOR_DATE": "2000-01-01T00:00:00+0000",
            "GIT_COMMITTER_DATE": "2000-01-01T00:00:00+0000",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_ALLOW_PROTOCOL": "file",
            "GR_NATIVE_HOOK_LOG": str(root / "hook-events.jsonl"),
        })
        self._graph = None

    def run(self, repo, *args, input_text=None, ok=True, extra_env=None):
        env = dict(self.env)
        env.update(extra_env or {})
        command = [self.git, *map(str, args)]
        result = subprocess.run(
            command, cwd=repo, env=env, input=input_text,
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=10,
        )
        self.commands.append({
            "cwd": str(repo), "argv": command, "returncode": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr,
        })
        if ok and result.returncode != 0:
            raise AssertionError(
                f"Git failed ({result.returncode}): {args}\n{result.stderr}"
            )
        return result

    def text(self, repo, *args, **kwargs):
        return self.run(repo, *args, **kwargs).stdout.strip()

    def init(self, name="source.git", bare=True):
        repo = self.root / name
        args = [
            "init", "-q", "--initial-branch=main",
            f"--ref-format={self.backend}", f"--object-format={self.object_format}",
        ]
        if bare:
            args.append("--bare")
        args.append(str(repo))
        self.run(self.root, *args)
        return repo

    def tree(self, repo, uuid, version=None):
        marker = self.text(repo, "hash-object", "-w", "--stdin", input_text="")
        entries = [f"100644 blob {marker}\t.roam\n"]
        if version is not None:
            files = {"note.org": f"{uuid}: version {version}\n",
                     "stable.txt": "unchanged tracked file\n"}
            if version:
                files["new.txt"] = "new tracked payload\n"
            for name, content in sorted(files.items()):
                blob = self.text(repo, "hash-object", "-w", "--stdin",
                                 input_text=content)
                entries.append(f"100644 blob {blob}\t{name}\n")
        subtree = self.text(repo, "mktree", input_text="".join(entries))
        return self.text(repo, "mktree",
                         input_text=f"040000 tree {subtree}\t{uuid}\n")

    def commit(self, repo, tree, parents, message):
        args = ["commit-tree", tree]
        for parent in parents:
            args.extend(["-p", parent])
        return self.text(repo, *args, input_text=message + "\n")

    def graph(self):
        if self._graph is not None:
            return self._graph
        repo = self.init()
        g = {"repo": repo}
        for key, uuid in (("a", A), ("b", B)):
            root_tree = self.tree(repo, uuid)
            content_tree = self.tree(repo, uuid, 0)
            root = self.commit(repo, root_tree, [], f"{key} root")
            content = self.commit(repo, content_tree, [root], f"{key} content 0")
            checkpoint = self.commit(repo, content_tree, [root, content],
                                     f"{key} checkpoint 0")
            g[key + "root"] = root
            g[key + "0"] = checkpoint
        for key, uuid, dependency in (("a", A, g["b0"]), ("b", B, g["a0"])):
            tree = self.tree(repo, uuid, 1)
            content = self.commit(repo, tree, [g[key + "0"]], f"{key} content 1")
            checkpoint = self.commit(
                repo, tree, [g[key + "0"], content, dependency],
                f"{key} checkpoint 1",
            )
            g[key + "1"] = checkpoint
        for ref, oid in (
            (f"refs/heads/{A}", g["a0"]),
            (f"refs/heads/{B}", g["b0"]),
            ("refs/heads/candidate-a", g["a1"]),
            ("refs/heads/candidate-b", g["b1"]),
        ):
            self.run(repo, "update-ref", ref, oid)
        self.run(repo, "symbolic-ref", "HEAD", f"refs/heads/{A}")
        self._graph = g
        return g

    def clone(self, name="clone"):
        g = self.graph()
        repo = self.root / name
        self.run(self.root, "clone", "-q", f"--ref-format={self.backend}",
                 g["repo"], repo)
        return repo

    def ref(self, repo, name):
        result = self.run(repo, "rev-parse", "--verify", name, ok=False)
        return result.stdout.strip() if result.returncode == 0 else None

    def records(self, repo):
        return worktree_records(self.run(
            repo, "worktree", "list", "--porcelain", "-z"
        ).stdout)

    def attach(self):
        repo = self.graph()["repo"]
        path = self.root / "deployment" / short_name(B)
        self.run(repo, "worktree", "add", path, B)
        return repo, path

    def hooks(self, repo):
        script = self.root / "record-hook.py"
        script.write_text(HOOK, encoding="utf-8")
        for name in ("guard", "audit"):
            command = shlex.join([sys.executable, str(script), self.git, name])
            self.run(repo, "config", f"hook.{name}.event", "reference-transaction")
            self.run(repo, "config", f"hook.{name}.command", command)

    def events(self):
        log = self.root / "hook-events.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] \
            if log.exists() else []

    def txn(self, repo, lines, **kwargs):
        return self.run(
            repo, "update-ref", "--stdin",
            input_text="start\n" + "\n".join(lines) + "\nprepare\ncommit\n",
            **kwargs,
        )


def matrix_smoke(f):
    g = f.graph()
    repo, path = f.attach()
    f.hooks(repo)
    f.run(repo, "update-ref", f"refs/heads/{A}", g["a1"], g["a0"])
    require(f.ref(repo, f"refs/heads/{A}") == g["a1"], "conditional update failed")
    require(any(e["phase"] == "prepared" for e in f.events()), "named Hook missing")
    require(any(r.get("branch") == f"refs/heads/{B}" for r in f.records(repo)),
            "linked branch not recorded")
    f.run(repo, "worktree", "remove", path)
    require(f.ref(repo, f"refs/heads/{B}") == g["b0"], "remove deleted branch")
    return {"object_format": f.object_format, "ref_backend": f.backend}


def tracking_unique(f):
    repo = f.clone()
    g = f.graph()
    require(f.ref(repo, f"refs/heads/{B}") is None, "clone unexpectedly has local B")
    path = f.root / "deployment" / short_name(B)
    f.run(repo, "worktree", "add", path, B)
    require(f.ref(repo, f"refs/heads/{B}") == g["b0"], "wrong new branch tip")
    upstream = f.text(repo, "rev-parse", "--symbolic-full-name", B + "@{upstream}")
    require(upstream == f"refs/remotes/origin/{B}", "wrong tracking source")
    return {"upstream": upstream, "created_local_branch": True}


def tracking_existing_local(f):
    repo = f.clone()
    g = f.graph()
    f.run(repo, "branch", "--track", B, f"origin/{B}")
    f.run(repo, "update-ref", f"refs/remotes/origin/{B}", g["b1"], g["b0"])
    path = f.root / "deployment" / short_name(B)
    f.run(repo, "worktree", "add", path, B)
    require(f.ref(repo, f"refs/heads/{B}") == g["b0"], "worktree add advanced local")
    return {"existing_local_tip_unchanged": True}


def tracking_equal_remotes(f):
    repo = f.clone()
    f.run(repo, "remote", "add", "second", f.graph()["repo"])
    f.run(repo, "fetch", "-q", "second")
    path = f.root / "deployment" / short_name(B)
    result = f.run(repo, "worktree", "add", path, B, ok=False)
    accepted = result.returncode == 0
    if not accepted:
        require(f.ref(repo, f"refs/heads/{B}") is None,
                "ambiguous creation unexpectedly left a branch")
        f.run(repo, "worktree", "add", "--track", "-b", B, path, f"origin/{B}")
    require(f.ref(repo, f"refs/heads/{B}") == f.graph()["b0"], "wrong equal-tip result")
    return {"native_guess_accepted_equal_oid_sources": accepted,
            "explicit_source_fallback_succeeded": not accepted}


def tracking_different_remotes(f):
    repo = f.clone()
    g = f.graph()
    f.run(repo, "remote", "add", "second", g["repo"])
    f.run(repo, "fetch", "-q", "second")
    f.run(repo, "update-ref", f"refs/remotes/second/{B}", g["b1"], g["b0"])
    path = f.root / "deployment" / short_name(B)
    result = f.run(repo, "worktree", "add", path, B, ok=False)
    require(result.returncode != 0, "divergent remote guessing was not ambiguous")
    require(f.ref(repo, f"refs/heads/{B}") is None, "ambiguous branch created")
    f.run(repo, "config", "checkout.defaultRemote", "second")
    f.run(repo, "worktree", "add", path, B)
    require(f.ref(repo, f"refs/heads/{B}") == g["b1"], "configured guessing mismatch")
    return {"native_ambiguity_refused": True,
            "default_remote_can_silently_select_different_tip": True,
            "product_must_prevalidate_candidates": True}


def tracking_failed_worktree(f):
    repo = f.clone()
    path = f.root / "occupied"
    path.mkdir()
    payload = path / "user-data"
    payload.write_text("retain me\n")
    result = f.run(repo, "worktree", "add", path, B, ok=False)
    require(result.returncode != 0, "occupied worktree target accepted")
    require(payload.read_text() == "retain me\n", "occupied data overwritten")
    return {"new_branch_left_after_failure": f.ref(repo, f"refs/heads/{B}") is not None}


def post_checkout_failure(f):
    repo = f.clone()
    command = shlex.join([sys.executable, "-c", "import sys; sys.exit(23)"])
    f.run(repo, "config", "hook.checkout-failure.event", "post-checkout")
    f.run(repo, "config", "hook.checkout-failure.command", command)
    path = f.root / "deployment" / short_name(B)
    result = f.run(repo, "worktree", "add", path, B, ok=False)
    require(f.ref(repo, f"refs/heads/{B}") == f.graph()["b0"], "branch not established")
    return {"exit_code": result.returncode, "worktree_exists": path.is_dir(),
            "registered": any(r.get("branch") == f"refs/heads/{B}"
                              for r in f.records(repo)),
            "branch_exists": True}


def hook_transaction(f):
    g = f.graph()
    repo = g["repo"]
    f.hooks(repo)
    f.txn(repo, [
        f"update refs/heads/{A} {g['a1']} {g['a0']}",
        f"update refs/heads/{B} {g['b1']} {g['b0']}",
    ])
    prepared = [e for e in f.events() if e["phase"] == "prepared"]
    for name in ("guard", "audit"):
        require(any(e["name"] == name and len(e["updates"]) == 2 for e in prepared),
                "Hook did not receive full transaction")
    return {"both_named_hooks_received_full_transaction": True}


def batch_tracking_establishment(f):
    g = f.graph()
    f.txn(g["repo"], [
        f"update refs/heads/{A} {g['a1']} {g['a0']}",
        f"update refs/heads/{B} {g['b1']} {g['b0']}",
    ])
    repo = f.init("receiver.git")
    f.run(repo, "remote", "add", "source", g["repo"])
    f.run(repo, "fetch", "-q", "source",
          "+refs/heads/*:refs/remotes/source/*")
    f.hooks(repo)
    env = {"GR_NATIVE_REQUIRE_PAIR": f"refs/heads/{A},refs/heads/{B}"}
    single_path = f.root / "single-attempt" / short_name(A)
    single = f.run(repo, "worktree", "add", single_path, A, ok=False, extra_env=env)
    require(single.returncode != 0, "fixture closure guard accepted only one branch")
    require(f.ref(repo, f"refs/heads/{A}") is None,
            "rejected branch creation changed receiver refs")
    f.txn(repo, [
        f"create refs/heads/{A} {g['a1']}",
        f"create refs/heads/{B} {g['b1']}",
    ], extra_env=env)
    for uuid, tip in ((A, g["a1"]), (B, g["b1"])):
        require(f.ref(repo, f"refs/remotes/source/{uuid}") == tip,
                "joint target does not match its canonical source tip")
        f.run(repo, "branch", "--set-upstream-to", f"source/{uuid}", uuid)
        path = f.root / "joint-deployment" / short_name(uuid)
        f.run(repo, "worktree", "add", path, uuid, extra_env=env)
        require(f.ref(repo, f"refs/heads/{uuid}") == tip, "joint tip changed")
        require(f.text(repo, "rev-parse", uuid + "@{upstream}") == tip,
                "joint tracking source does not match selected tip")
    return {"single_creation_rejected_by_fixture_pair_guard": True,
            "joint_ref_creation_then_tracking_and_worktrees_succeeded": True,
            "guard_is_only_a_known_fixture_presence_rule_not_product_validation": True}


def hook_rejection_and_bypass(f):
    g = f.graph()
    repo = g["repo"]
    f.hooks(repo)
    env = {"GR_NATIVE_REJECT_REF": f"refs/heads/{B}"}
    result = f.txn(repo, [
        f"update refs/heads/{A} {g['a1']} {g['a0']}",
        f"update refs/heads/{B} {g['b1']} {g['b0']}",
    ], ok=False, extra_env=env)
    require(result.returncode != 0, "rejecting Hook was ignored")
    require(f.ref(repo, f"refs/heads/{A}") == g["a0"], "partial A ref change")
    require(f.ref(repo, f"refs/heads/{B}") == g["b0"], "partial B ref change")
    before = len(f.events())
    f.run(repo, "-c", "hook.guard.enabled=false", "update-ref",
          f"refs/heads/{B}", g["b1"], g["b0"], extra_env=env)
    after = f.events()[before:]
    require(after and all(e["name"] == "audit" for e in after),
            "own-only bypass disabled or invoked the wrong hooks")
    return {"rejection_preserved_both_refs": True, "audit_survives_guard_bypass": True}


def hook_actual_old_and_head(f):
    g = f.graph()
    repo = g["repo"]
    f.hooks(repo)
    f.run(repo, "update-ref", f"refs/heads/{A}", g["a1"])
    updates = [e for e in f.events() if e["phase"] == "prepared"]
    require(updates, "no prepared observation")
    observation = updates[0]
    require(observation["actual"].get(f"refs/heads/{A}") == g["a0"],
            "Hook could not observe actual old ref")
    before = len(f.events())
    f.run(repo, "symbolic-ref", "HEAD", f"refs/heads/{B}")
    head = [e for e in f.events()[before:] if any(
        line.rsplit(" ", 1)[-1] == "HEAD" for line in e["updates"]
    )]
    require(head, "symbolic HEAD update not observed")
    return {"unconstrained_update_input": observation["updates"],
            "actual_old_matches_existing_ref": True,
            "symbolic_head_observed": head}


def transaction_stale_old(f):
    g = f.graph()
    repo = g["repo"]
    result = f.txn(repo, [
        f"update refs/heads/{A} {g['a1']} {g['aroot']}",
        f"update refs/heads/{B} {g['b1']} {g['b0']}",
    ], ok=False)
    require(result.returncode != 0, "stale expected-old accepted")
    require(f.ref(repo, f"refs/heads/{A}") == g["a0"], "A changed")
    require(f.ref(repo, f"refs/heads/{B}") == g["b0"], "B partially changed")
    return {"no_partial_ref_update": True}


def transaction_verify(f):
    g = f.graph()
    repo = g["repo"]
    f.run(repo, "update-ref", f"refs/heads/{B}", g["b1"], g["b0"])
    result = f.txn(repo, [
        f"update refs/heads/{A} {g['a1']} {g['a0']}",
        f"verify refs/heads/{B} {g['b0']}",
    ], ok=False)
    require(result.returncode != 0, "stale read-only ref accepted")
    require(f.ref(repo, f"refs/heads/{A}") == g["a0"], "write survived failed verify")
    return {"read_dependency_verify_rejected_transaction": True}


def worktree_main_and_detached(f):
    repo = f.clone()
    result = f.run(repo, "worktree", "remove", repo, ok=False)
    require(result.returncode != 0 and repo.is_dir(), "main worktree removed")
    path = f.root / "detached"
    f.run(repo, "worktree", "add", "--detach", path, f.graph()["b0"])
    records = [r for r in f.records(repo) if r.get("worktree") == str(path)]
    require(len(records) == 1 and records[0].get("detached") is True
            and "branch" not in records[0], "detached classified as branch checkout")
    return {"main_removal_refused": True, "detached_has_no_branch": True}


def worktree_move_and_lock(f):
    repo, path = f.attach()
    moved = f.root / "manually-moved"
    f.run(repo, "worktree", "move", path, moved)
    require(any(r.get("worktree") == str(moved) for r in f.records(repo)),
            "moved path not authoritative")
    f.run(repo, "worktree", "lock", "--reason", "fixture lock", moved)
    result = f.run(repo, "worktree", "remove", moved, ok=False)
    require(result.returncode != 0 and moved.is_dir(), "locked worktree removed")
    f.run(repo, "worktree", "unlock", moved)
    f.run(repo, "worktree", "remove", moved)
    return {"moved_path_recorded": True, "locked_removal_refused": True,
            "branch_survives": f.ref(repo, f"refs/heads/{B}") == f.graph()["b0"]}


def worktree_dirty(f, kind):
    repo, path = f.attach()
    payload = path / B / "note.org"
    if kind == "untracked":
        payload = path / "untracked-user-data"
    payload.write_text("user fixture changes\n")
    if kind == "staged":
        f.run(path, "add", "--", str(payload.relative_to(path)))
    result = f.run(repo, "worktree", "remove", path, ok=False)
    require(result.returncode != 0, f"{kind} worktree removed")
    require(payload.read_text() == "user fixture changes\n", "user fixture lost")
    return {"kind": kind, "native_removal_refused": True}


def worktree_ignored_hazard(f):
    repo, path = f.attach()
    (repo / "info" / "exclude").write_text("ignored-user-data\n")
    payload = path / "ignored-user-data"
    payload.write_text("disposable ignored fixture\n")
    require(f.text(path, "status", "--porcelain") == "", "ignored fixture not ignored")
    f.run(repo, "worktree", "remove", path)
    require(not path.exists(), "native ignored-file behavior changed")
    return {"native_clean_status_and_remove_discard_ignored_files": True,
            "product_requires_additional_data_guard": True}


def worktree_nested(f):
    g = f.graph()
    repo = g["repo"]
    (repo / "info" / "exclude").write_text("deployment/\n")
    outer = f.root / "outer"
    f.run(repo, "worktree", "add", outer, A)
    inner = outer / "deployment" / short_name(B)
    f.run(repo, "worktree", "add", inner, B)
    require(f.text(outer, "status", "--porcelain") == "", "nested path not ignored")
    records = f.records(repo)
    require(any(r.get("worktree") == str(inner) for r in records),
            "nested linked worktree not recorded")
    f.run(repo, "worktree", "remove", inner)
    f.run(repo, "worktree", "remove", outer)
    return {"ignored_nested_linked_worktrees_supported": True,
            "deepest_first_removal_succeeded": True}


def worktree_duplicate_and_symlink(f):
    repo, existing = f.attach()
    duplicate = f.run(repo, "worktree", "add", f.root / "duplicate", B, ok=False)
    require(duplicate.returncode != 0 and existing.is_dir(),
            "duplicate checkout was not safely refused")
    real_root = f.root / "actual-directory"
    real_root.mkdir()
    link_root = f.root / "symbolic-directory"
    link_root.symlink_to(real_root, target_is_directory=True)
    requested = link_root / short_name(A)
    f.run(repo, "worktree", "add", requested, A)
    require((real_root / short_name(A)).is_dir(), "native symlink traversal absent")
    return {"duplicate_checkout_refused": True,
            "native_add_follows_symlink_parent": True,
            "requested_path": str(requested),
            "actual_path": str(requested.resolve()),
            "product_requires_path_boundary_preflight": True}


def fast_forward(f, kind):
    repo = f.clone()
    g = f.graph()
    payload = repo / A / "note.org"
    if kind in ("unrelated", "staged"):
        payload = repo / A / "stable.txt"
    elif kind in ("untracked", "ignored"):
        payload = repo / A / "new.txt"
    if kind != "clean":
        payload.write_text("local fixture change\n")
    if kind == "ignored":
        (repo / ".git" / "info" / "exclude").write_text(A + "/new.txt\n")
    if kind == "staged":
        f.run(repo, "add", "--", str(payload.relative_to(repo)))
    result = f.run(repo, "merge", "--ff-only", "--no-autostash",
                   "--no-overwrite-ignore", "refs/remotes/origin/candidate-a", ok=False)
    expected_success = kind in ("clean", "unrelated")
    if kind != "staged":
        require((result.returncode == 0) == expected_success,
                f"unexpected native fast-forward result for {kind}")
    accepted = result.returncode == 0
    require(f.ref(repo, "HEAD") == (g["a1"] if accepted else g["a0"]),
            "HEAD does not match reported fast-forward")
    if kind != "clean":
        require(payload.read_text() == "local fixture change\n",
                "fast-forward lost local fixture changes")
    if kind == "staged":
        require(f.text(repo, "diff", "--cached", "--name-only") == A + "/stable.txt",
                "staged fixture modification lost")
    if kind == "clean":
        require(f.text(repo, "status", "--porcelain") == "", "index not synchronized")
    return {"kind": kind, "accepted": accepted, "local_changes_preserved": kind != "clean"}


def fast_forward_divergence(f):
    repo = f.clone()
    payload = repo / A / "note.org"
    payload.write_text("local divergent content\n")
    f.run(repo, "add", "--", str(payload.relative_to(repo)))
    f.run(repo, "commit", "-q", "-m", "local Content")
    old = f.ref(repo, "HEAD")
    result = f.run(repo, "merge", "--ff-only", "--no-autostash",
                   "--no-overwrite-ignore", "refs/remotes/origin/candidate-a", ok=False)
    require(result.returncode != 0 and f.ref(repo, "HEAD") == old,
            "divergent history was integrated")
    require(f.text(repo, "status", "--porcelain") == "", "divergence dirtied worktree")
    return {"divergence_refused_without_merge_commit": True}


def cross_node_ancestry_trap(f):
    g = f.graph()
    repo = g["repo"]
    tree = f.tree(repo, A, 1)
    content = f.commit(repo, tree, [g["aroot"]], "alternate Content from Root")
    candidate = f.commit(repo, tree, [g["aroot"], content, g["b1"]],
                         "alternate formal history with foreign path to a0")
    require(f.run(repo, "merge-base", "--is-ancestor", g["a0"], candidate,
                  ok=False).returncode == 0, "expected foreign Git ancestry absent")
    first_parent_chain = f.text(repo, "rev-list", "--first-parent", candidate).splitlines()
    require(g["a0"] not in first_parent_chain, "old formal history accidentally retained")
    require(f.text(repo, "show", "-s", "--format=%P", candidate).split()[0] == g["aroot"],
            "fixture formal predecessor mismatch")
    return {"git_ancestry_true_but_same_node_formal_retention_false": True,
            "foreign_path": ["alternate-a", "b1", "a0"]}


def stale_cross_node_interleaving(f):
    g = f.graph()
    repo = g["repo"]
    old_a, old_b = f.ref(repo, f"refs/heads/{A}"), f.ref(repo, f"refs/heads/{B}")
    f.run(repo, "update-ref", f"refs/heads/{A}", g["a1"], old_a)
    f.run(repo, "update-ref", "-d", f"refs/heads/{B}", old_b)
    require(f.ref(repo, f"refs/heads/{B}") is None, "B not deleted")
    f.run(repo, "cat-file", "-e", g["b0"] + "^{commit}")
    require(g["b0"] in f.text(repo, "show", "-s", "--format=%P", g["a1"]).split(),
            "A does not directly retain B object")
    return {"deterministic_stale_read_interleaving": True,
            "independent_expected_old_updates_both_succeeded": True,
            "required_branch_missing_but_dependency_object_present": True,
            "product_hooks_and_postchecks_not_implemented_here": True}


def verify_guards_deletion(f):
    g = f.graph()
    repo = g["repo"]
    f.run(repo, "update-ref", f"refs/heads/{A}", g["a1"], g["a0"])
    result = f.txn(repo, [
        f"delete refs/heads/{B} {g['b0']}",
        f"verify refs/heads/{A} {g['a0']}",
    ], ok=False)
    require(result.returncode != 0, "stale deletion read accepted")
    require(f.ref(repo, f"refs/heads/{B}") == g["b0"], "B removed despite failed verify")
    return {"enumerated_read_guard_rejected_stale_delete": True}


def same_ref_cas_race(f):
    g = f.graph()
    repo = g["repo"]
    tree = f.tree(repo, A, 1)
    alternate = f.commit(repo, tree, [g["a0"]], "competing Content")
    def update(oid):
        return f.run(repo, "update-ref", f"refs/heads/{A}", oid, g["a0"], ok=False)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(update, [g["a1"], alternate]))
    require(sum(p.returncode == 0 for p in results) == 1, "CAS had other than one winner")
    require(f.ref(repo, f"refs/heads/{A}") in (g["a1"], alternate), "unexpected final ref")
    return {"exactly_one_expected_old_writer_succeeded": True}


CASES = [
    ("tracking-unique", tracking_unique),
    ("tracking-existing-local", tracking_existing_local),
    ("tracking-equal-remotes", tracking_equal_remotes),
    ("tracking-different-remotes", tracking_different_remotes),
    ("tracking-failed-worktree", tracking_failed_worktree),
    ("post-checkout-failure", post_checkout_failure),
    ("hook-full-transaction", hook_transaction),
    ("batch-tracking-establishment", batch_tracking_establishment),
    ("hook-rejection-own-bypass", hook_rejection_and_bypass),
    ("hook-actual-old-symbolic-head", hook_actual_old_and_head),
    ("transaction-stale-old", transaction_stale_old),
    ("transaction-verify", transaction_verify),
    ("worktree-main-detached", worktree_main_and_detached),
    ("worktree-move-lock", worktree_move_and_lock),
    ("worktree-dirty-staged", lambda f: worktree_dirty(f, "staged")),
    ("worktree-dirty-unstaged", lambda f: worktree_dirty(f, "unstaged")),
    ("worktree-dirty-untracked", lambda f: worktree_dirty(f, "untracked")),
    ("worktree-ignored-native-hazard", worktree_ignored_hazard),
    ("worktree-nested", worktree_nested),
    ("worktree-duplicate-symlink", worktree_duplicate_and_symlink),
    ("ff-clean", lambda f: fast_forward(f, "clean")),
    ("ff-unrelated-dirty", lambda f: fast_forward(f, "unrelated")),
    ("ff-overlapping-dirty", lambda f: fast_forward(f, "overlap")),
    ("ff-untracked", lambda f: fast_forward(f, "untracked")),
    ("ff-ignored", lambda f: fast_forward(f, "ignored")),
    ("ff-staged", lambda f: fast_forward(f, "staged")),
    ("ff-divergence", fast_forward_divergence),
    ("cross-node-ancestry-trap", cross_node_ancestry_trap),
    ("stale-cross-node-interleaving", stale_cross_node_interleaving),
    ("verify-guards-delete", verify_guards_deletion),
    ("same-ref-cas-race", same_ref_cas_race),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--git", required=True)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    require(Path(args.git).is_absolute(), "test Git must be an explicit absolute path")
    require(not args.workspace.exists(), "refuse to reuse an existing fixture workspace")
    args.workspace.mkdir(parents=True)
    args.output.mkdir(parents=True, exist_ok=True)
    global_config = args.workspace / "global.gitconfig"
    global_config.write_text("")
    results, commands = [], []

    def execute(name, test, backend, object_format):
        fixture = Fixture(args.workspace / name, args.git, backend, object_format,
                          global_config)
        result = {"name": name, "backend": backend, "object_format": object_format}
        try:
            result["observations"] = test(fixture)
            result["status"] = "pass"
        except Exception as error:
            result["status"] = "fail"
            result["error"] = str(error)
        results.append(result)
        commands.extend({"case": name, **command} for command in fixture.commands)
        print(result["status"].upper() + " " + name, flush=True)

    for backend in ("files", "reftable"):
        for object_format in ("sha1", "sha256"):
            execute(f"matrix-{backend}-{object_format}", matrix_smoke,
                    backend, object_format)
        for name, test in CASES:
            execute(backend + "-" + name, test, backend, "sha1")

    require(base64.b32encode(bytes(range(5))).decode().lower() == "aaaqeaye",
            "Base32 five-byte ordering vector failed")
    require(len(short_name(A)) == 8 and "=" not in short_name(A), "short-name format")
    version = subprocess.run([args.git, "--version"], capture_output=True,
                             text=True, check=True, timeout=10).stdout.strip()
    report = {
        "git_version": version,
        "git_executable": args.git,
        "passed": sum(r["status"] == "pass" for r in results),
        "failed": sum(r["status"] == "fail" for r in results),
        "matrix": "Full scenarios on files/reftable SHA-1; object/ref/worktree/Hook smoke on SHA-1/SHA-256.",
        "minimum_git_254_verified": False,
        "results": results,
    }
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.output / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    print("RESULTS " + json.dumps(report, sort_keys=True), flush=True)
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
