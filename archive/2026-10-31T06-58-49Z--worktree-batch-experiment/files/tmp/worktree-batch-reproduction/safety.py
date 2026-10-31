"""Check whole-batch preflight, native cleanup, and metadata rollback."""

import os
from pathlib import Path
import subprocess
import tempfile


binary = os.environ["GIT_BIN"]
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
os.environ["GIT_CONFIG_GLOBAL"] = "/dev/null"


def run(repo, *args, data=None, env=None, success=True):
    result = subprocess.run([binary, "-C", str(repo), *args], input=data,
                            text=True, capture_output=True, env=env, timeout=30)
    if success:
        assert result.returncode == 0, result.stderr
    else:
        assert result.returncode != 0, "Expected failure"
    return result


cases = ("invalid-last-branch", "duplicate-path", "duplicate-branch",
         "nested-paths", "existing-user-directory", "during-registration",
         "after-registration", "occupied-branch", "force-rejected")
for backend in ("files", "reftable"):
    for case in cases:
        with tempfile.TemporaryDirectory(prefix="worktree-safety-") as scratch:
            root = Path(scratch)
            repo = root / "repo"
            subprocess.run([binary, "init", "-q", "--template=", "--initial-branch=main",
                            "--ref-format=" + backend, str(repo)], check=True,
                           capture_output=True, timeout=30)
            run(repo, "config", "user.name", "Experiment")
            run(repo, "config", "user.email", "experiment@example.invalid")
            run(repo, "-c", "commit.gpgSign=false", "commit", "--allow-empty", "-qm", "seed")
            for branch in ("node-a", "node-b"):
                run(repo, "branch", branch)
            a, b = root / "a", root / "b"
            entries = [(a, "node-a"), (b, "node-b")]
            env = os.environ.copy()
            extra = []
            if case == "invalid-last-branch":
                entries[1] = (b, "missing")
            elif case == "duplicate-path":
                entries[1] = (a, "node-b")
            elif case == "duplicate-branch":
                entries[1] = (b, "node-a")
            elif case == "nested-paths":
                entries[1] = (a / "child", "node-b")
            elif case == "existing-user-directory":
                b.mkdir()
                (b / "user.txt").write_text("preserve me\n")
            elif case == "during-registration":
                env["GIT_TEST_WORKTREE_BATCH_FAIL_DURING"] = "node-b"
            elif case == "after-registration":
                env["GIT_TEST_WORKTREE_BATCH_FAIL_AFTER"] = "1"
            elif case == "occupied-branch":
                run(repo, "worktree", "add", "--no-checkout", str(root / "occupied"), "node-b")
            elif case == "force-rejected":
                extra = ["--force"]
            before = run(repo, "worktree", "list", "--porcelain").stdout
            admin = repo / ".git" / "worktrees"
            before_ids = set(admin.iterdir()) if admin.exists() else set()
            result = run(repo, "worktree", "add", "--batch", "--no-checkout", *extra,
                         data="".join(f"{path}\t{branch}\n" for path, branch in entries),
                         env=env, success=False)
            assert run(repo, "worktree", "list", "--porcelain").stdout == before, result.stderr
            assert (set(admin.iterdir()) if admin.exists() else set()) == before_ids, result.stderr
            assert not a.exists(), result.stderr
            if case == "existing-user-directory":
                assert (b / "user.txt").read_text() == "preserve me\n"
            else:
                assert not b.exists(), result.stderr
            assert not (repo / ".git" / "worktree-batch.lock").exists()
            print(f"OK ({backend}): {case}", flush=True)
