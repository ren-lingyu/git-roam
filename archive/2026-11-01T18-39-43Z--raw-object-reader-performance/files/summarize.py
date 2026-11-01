"""Produce a bounded report from the completed local experiment results."""
from pathlib import Path
import json
import statistics

base = Path(__file__).resolve().parent
sources = {
    'pilot': base/'runs/pilot-20261101T182250.448312Z/results.json',
    'scale512': base/'runs/scale-20261101T182446.910300Z/results.json',
    'scale1g': base/'runs/scale-1G-20261101T183048.065324Z/results.json',
}

def read(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size < 1048576
    return json.loads(path.read_text())

results = {name: read(path) for name, path in sources.items()}
assert results['pilot']['complete'] and results['scale1g']['complete']
rows = []
for source, limit in [('pilot', '512 MiB'), ('scale1g', '1 GiB')]:
    result = results[source]
    for info in result['fixtures']:
        case = info['case']
        by_mode = {mode: [m for m in result['measurements'] if m['case'] == case and m['mode'] == mode] for mode in ['oneshot', 'persistent']}
        for values in by_mode.values():
            assert len(values) == 3 and all(m['exit_code'] == 0 for m in values)
        digests = {m['result_digest'] for values in by_mode.values() for m in values}
        assert len(digests) == 1
        median = lambda mode, key: statistics.median(m[key] for m in by_mode[mode])
        old = median('oneshot', 'validator_seconds')
        new = median('persistent', 'validator_seconds')
        rows.append(f"| {info['nodes']:,} | {info['checkpoints_per_node']} | {info['fanout']} | {limit} | {old:.4f} | {new:.4f} | {old/new:.1f}x | {by_mode['oneshot'][0]['physical_git_processes']:,} / {by_mode['persistent'][0]['physical_git_processes']} | {median('oneshot','max_rss_kib')/1024:.1f} / {median('persistent','max_rss_kib')/1024:.1f} |")

large = results['scale1g']['measurements']
ranges = {mode: [m['validator_seconds'] for m in large if m['mode'] == mode] for mode in ['oneshot','persistent']}
lines = [
    '# Raw Git object reader performance: local measured results',
    '',
    'Baseline project: `c1789363356cc3c7117ada31ceba6b647f6fb525`. Product source and Git state were unchanged.',
    'Linux x86_64, locked standard Git 2.56.0 and GHC 9.12.3; the same production package definition and validator were used in both modes.',
    '',
    '## Completed paired measurements',
    '',
    'Each cell is the median of three runs. Times measure complete `inspectState` including result normalization, excluding CLI selection/rendering.',
    'Current = the existing per-object native process adapter. Persistent = an experiment-only single `cat-file --batch` process adapter.',
    '',
    '| Nodes | Checkpoints/Node | Max external fanout | Managed heap cap | Current seconds | Persistent seconds | Time ratio | Git processes current / persistent | Median max RSS MiB current / persistent |',
    '|---:|---:|---:|---|---:|---:|---:|---:|---:|',
    *rows,
    '',
    'Every completed pair and repetition agreed on managed refs and retained Checkpoint digests. Caches inside the validator were fresh per invocation; filesystem caches were not flushed.',
    f"10,000-Node raw time range: current {min(ranges['oneshot']):.4f}–{max(ranges['oneshot']):.4f}s; persistent {min(ranges['persistent']):.4f}–{max(ranges['persistent']):.4f}s.",
    '',
    '## Original 512 MiB scale attempt',
    '',
    'The persistent adapter completed once in 2.5497s, with 11 Git processes and 185.7 MiB max RSS.',
    'The current adapter then hit the deliberately configured 512 MiB GHC heap ceiling: exit 251 after 120.89s, max RSS 290.5 MiB. This was heap exhaustion, not a deadline or an OS OOM.',
    'The stage stopped immediately without retry. It has no valid paired median or speedup. The later 1 GiB run is separate, explicitly authorized, and preserves the original failed result.',
    'The managed heap ceiling is not equivalent to RSS or total concurrent memory; do not infer a minimum physical-RAM requirement from that failure alone.',
    '',
    '## Interpretation and limits',
    '',
    '- Per-object process creation is a measured scalability problem in the current full-check path, even with one Checkpoint and a tiny note per Node.',
    '- A persistent raw-object transport is an effective optimization direction while retaining the current DAG and per-call caches. This experiment does not change product code or create a permanent cache.',
    '- The candidate also changes pipe/buffer/environment/async overhead. No claim isolates all gains to fork/exec, proves a memory leak, or identifies the source of the memory difference.',
    '- Fixtures use SHA-1/files refs, packed objects, deterministic small payloads and simple histories. The additional pilot covers longer history and direct dependencies. Dense large knowledge DAGs, large files, other platforms and cold disks were not measured.',
    '- Only one measurement runs at a time. Nix max-jobs/cores, GHC capabilities and fixture pack threads are one. Max RSS is GNU time per-invocation accounting, not a sum across simultaneous processes.',
    '- The experiment adapter is not production-ready: process lifecycle, stderr draining, short/malformed replies, cancellation and serialization need implementation and regression coverage before integration.',
    '',
    '## Evidence',
    '',
]
for key, path in sources.items():
    lines.append(f'- [{key} raw results]({path.relative_to(base)}).')
lines += ['', 'Inputs, resource policy and reproduction commands are in [README.md](README.md).', '']
(base/'REPORT.md').write_text('\n'.join(lines))
print('\n'.join(rows))
print('Report:', base/'REPORT.md')
