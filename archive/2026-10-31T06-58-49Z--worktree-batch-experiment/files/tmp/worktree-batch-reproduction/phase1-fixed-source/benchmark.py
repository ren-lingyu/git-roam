"""Compare the same pinned Git source with zero, one, and three patches."""

import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time


def git(binary, repo, *args, data=None):
    return subprocess.run(
        [binary, "-C", str(repo), *args],
        input=data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=180,
    ).stdout


os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
os.environ["GIT_CONFIG_GLOBAL"] = "/dev/null"
variants = {
    "baseline-sequential": os.environ["BASELINE_GIT"],
    "reuse-sequential": os.environ["REUSE_GIT"],
    "final-batch": os.environ["PATCHED_GIT"],
}
rows = []
print("backend\tvariant\tworktrees\trepeat\tseconds", flush=True)
for backend in ("files", "reftable"):
    for count in (700, 1500, 5000):
        for variant, binary in variants.items():
            if count != 700 and variant != "final-batch":
                continue
            for repeat in range(1, 4):
                with tempfile.TemporaryDirectory(prefix="worktree-benchmark-") as scratch:
                    root = Path(scratch)
                    repo = root / "repo"
                    subprocess.run(
                        [binary, "init", "-q", "--template=", "--initial-branch=main",
                         "--ref-format=" + backend, str(repo)],
                        check=True, capture_output=True, timeout=30,
                    )
                    git(binary, repo, "config", "user.name", "Experiment")
                    git(binary, repo, "config", "user.email", "experiment@example.invalid")
                    git(binary, repo, "-c", "commit.gpgSign=false", "commit",
                        "--allow-empty", "-qm", "seed")
                    oid = git(binary, repo, "rev-parse", "HEAD").strip()
                    git(binary, repo, "update-ref", "--stdin", data="".join(
                        f"create refs/heads/node-{i} {oid}\n" for i in range(count)
                    ))
                    targets = [(root / f"node-{i}", f"node-{i}") for i in range(count)]
                    started = time.perf_counter()
                    if variant == "final-batch":
                        git(binary, repo, "worktree", "add", "--batch", "--no-checkout",
                            data="".join(f"{path}\t{branch}\n" for path, branch in targets))
                    else:
                        for path, branch in targets:
                            git(binary, repo, "worktree", "add", "--no-checkout", str(path), branch)
                    elapsed = time.perf_counter() - started
                    listing = git(binary, repo, "worktree", "list", "--porcelain")
                    assert sum(line.startswith("worktree ") for line in listing.splitlines()) == count + 1
                    assert all((path / ".git").is_file() for path, _ in targets)
                    admin = repo / ".git" / "worktrees"
                    assert len(list(admin.iterdir())) == count
                    assert not any((entry / "locked").exists() for entry in admin.iterdir())
                    row = dict(backend=backend, variant=variant, worktrees=count,
                               repeat=repeat, seconds=elapsed)
                    rows.append(row)
                    print(f"{backend}\t{variant}\t{count}\t{repeat}\t{elapsed:.6f}", flush=True)

summaries = []
for backend, variant, count in dict.fromkeys(
    (row["backend"], row["variant"], row["worktrees"]) for row in rows
):
    values = [row["seconds"] for row in rows if
              (row["backend"], row["variant"], row["worktrees"]) == (backend, variant, count)]
    summaries.append(dict(backend=backend, variant=variant, worktrees=count,
                          median_seconds=statistics.median(values)))
result = dict(
    system=platform.system(), machine=platform.machine(),
    git_binaries=variants, git_versions={
        key: subprocess.check_output([binary, "--version"], text=True).strip()
        for key, binary in variants.items()
    },
    method="fresh empty repository per sample; setup, validation and cleanup excluded; no checkout; three repetitions; warm shared source/object environment; not a cold-cache benchmark",
    samples=rows, summaries=summaries,
)
Path("results.json").write_text(json.dumps(result, indent=2) + "\n")
