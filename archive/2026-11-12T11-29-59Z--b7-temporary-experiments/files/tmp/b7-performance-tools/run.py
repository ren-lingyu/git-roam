"""Opt-in native fixtures and observations; only writes below --directory."""
import argparse
import json
import os
import pathlib
import platform
import statistics
import subprocess
import time


def node(i):
    return f"{i:08x}-0000-4000-8000-000000000000"


def git(args, repo, extra=(), data=b""):
    result = subprocess.run([args.git, *extra], cwd=repo, input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=args.environment, timeout=args.timeout, check=True)
    return result.stdout


def fixture(args, repo, count, backend):
    repo.mkdir()
    start = time.monotonic()
    git(args, repo, ["init", "-q", "--initial-branch=main", f"--ref-format={backend}",
                     f"--object-format={args.object_format}"])
    records = []
    for i in range(1, count + 1):
        records.append(f"commit refs/heads/{node(i)}\nmark :{i}\n"
                       "committer Benchmark <bench@example.invalid> 1700000000 +0000\n"
                       f"data 4\nRoot\nM 100644 inline {node(i)}/.roam\ndata 0\n\n")
    mark = count
    if args.shape == "shared":
        previous = 1
        # A shared Content ancestry and one context Checkpoint per other Node.
        for _ in range(count):
            mark += 1
            records.append(f"commit refs/heads/{node(1)}\nmark :{mark}\n"
                           "committer Benchmark <bench@example.invalid> 1700000001 +0000\n"
                           f"data 7\nContent\nfrom :{previous}\n\n")
            previous = mark
        for i in range(2, count + 1):
            mark += 1
            records.append(f"commit refs/heads/{node(i)}\nmark :{mark}\n"
                           "committer Benchmark <bench@example.invalid> 1700000002 +0000\n"
                           f"data 10\nCheckpoint\nfrom :{i}\nmerge :{previous}\n\n")
    records.append("done\n")
    git(args, repo, ["fast-import", "--quiet", "--done"], "".join(records).encode())
    refs = git(args, repo, ["for-each-ref", "--format=%(refname) %(objectname)", "refs/heads/"]).decode().splitlines()
    remote = "".join(f"create refs/remotes/origin/{ref.rsplit('/', 1)[-1]} {oid}\n"
                     for ref, oid in map(str.split, refs))
    git(args, repo, ["update-ref", "--stdin"], remote.encode())
    # Exactly two associated worktrees regardless of total Node count.
    for i in (1, 2):
        git(args, repo, ["worktree", "add", "-q", str(repo.parent / f"{repo.name}-wt-{i}"), node(i)])
    if args.shape == "config-errors":
        with (repo / ".git" / "config").open("a") as config:
            for i in range(1, count + 1):
                config.write(f'\n[branch "{node(i)}"]\n\tremote\n')
    objects = git(args, repo, ["rev-list", "--objects", "--all"]).splitlines()
    kinds = git(args, repo, ["cat-file", "--batch-check=%(objecttype)"],
                b"".join(row.split(b" ")[0] + b"\n" for row in objects)).splitlines()
    return {"generation_seconds": time.monotonic() - start,
            "local_refs": count, "remote_refs": count, "unique_tips": count,
            "reachable_commits": kinds.count(b"commit"), "trees": kinds.count(b"tree"),
            "blobs": kinds.count(b"blob"), "registered_worktrees": 3,
            "associated_worktrees": 2, "config_entries": count if args.shape == "config-errors" else 0}


def run(args):
    args.directory = args.directory.resolve()
    if args.directory.exists():
        raise SystemExit("Refusing to use an existing directory; choose a fresh fixture directory")
    args.directory.mkdir(parents=True)
    args.environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    args.environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
    metadata = {"baseline": args.baseline, "git": git(args, args.directory, ["--version"]).decode().strip(),
                "object_format": args.object_format, "system": platform.platform(),
                "processor": args.hardware or platform.processor(), "cpu_count": os.cpu_count(),
                "cache": "warm OS cache; fixture generation immediately precedes queries; no persistent app cache",
                "instrumentation": "same-binary proxy counts native Git launches and raw stdin requests; timings include proxy overhead",
                "runner": str(pathlib.Path(args.runner).resolve())}
    output = args.directory / "results.jsonl"
    if output.exists():
        raise SystemExit("Refusing to overwrite existing results; use a fresh directory")
    with output.open("w") as results:
        for backend in args.backends:
            for count in args.sizes:
                repo = args.directory / f"{args.shape}-{backend}-{count}"
                parameters = fixture(args, repo, count, backend)
                workloads = [(name, "all") for name in args.workloads]
                workloads += [(name, node(1)) for name in ("tip", "status") if name in args.workloads]
                for workload, selector in workloads:
                    samples = []
                    for repetition in range(args.repetitions):
                        log = args.directory / "counter.log"
                        log.write_bytes(b"")
                        started = time.monotonic()
                        result = subprocess.run([args.runner, args.git, str(repo), workload, selector, str(log)],
                                                env=args.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                                timeout=args.timeout, check=True)
                        sample = json.loads(result.stdout)
                        expected_complete = args.shape != "config-errors" or workload not in ("default", "remote")
                        if sample["complete"] != expected_complete:
                            raise RuntimeError(f"Unexpected query completeness for {args.shape}/{workload}: {sample}")
                        sample["wall_seconds"] = time.monotonic() - started
                        entries = log.read_text().splitlines()
                        processes = [entry for entry in entries if entry.startswith("process ")]
                        sample.update(native_processes=len(processes), batch_sessions=sum('"--batch"' in entry for entry in processes),
                                      batch_requests=entries.count("request"), ref_enumerations=sum('"for-each-ref"' in entry for entry in processes))
                        samples.append(sample)
                    metrics = {key: statistics.median(sample[key] for sample in samples)
                               for key in samples[0] if key != "complete"}
                    row = dict(metadata, shape=args.shape, backend=backend, nodes=count, workload=workload,
                               selected_nodes=(0 if workload == "repo" else count if selector == "all" else 1),
                               selected_worktrees=(2 if selector == "all" else 1) if workload == "status" else 0,
                               repetitions=args.repetitions, fixture=parameters, median=metrics,
                               all_complete=all(sample["complete"] for sample in samples), samples=samples)
                    results.write(json.dumps(row, sort_keys=True) + "\n")
                    results.flush()
                    print(backend, count, args.shape, workload, selector, round(metrics["wall_seconds"], 3),
                          "processes", metrics["native_processes"], "requests", metrics["batch_requests"], flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", required=True)
    parser.add_argument("--git", required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--hardware", default="", help="CPU/model description if platform.processor is empty")
    parser.add_argument("--directory", type=pathlib.Path, required=True)
    parser.add_argument("--sizes", type=int, nargs="+", default=[10, 100, 1000, 10000])
    parser.add_argument("--backends", nargs="+", choices=["files", "reftable"], default=["files", "reftable"])
    parser.add_argument("--workloads", nargs="+", choices=["repo", "tip", "default", "remote", "commit", "status", "check", "check-refs"], default=["repo", "tip", "default", "remote", "commit", "status", "check", "check-refs"])
    parser.add_argument("--shape", choices=["roots", "shared", "config-errors"], default="roots")
    parser.add_argument("--object-format", choices=["sha1", "sha256"], default="sha1")
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=120)
    options = parser.parse_args()
    if min(options.sizes) < 2 or options.repetitions < 1:
        parser.error("At least two Nodes and one repetition required")
    run(options)
