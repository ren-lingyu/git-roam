"""Serial bounded comparisons; preserve every attempt, never retry on failure."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

sys.dont_write_bytecode = True
STAGES = {
    'inspect-pilot': (1000, 0, [('inspect-oneshot', 'inspect-native')], '60s'),
    'inspect-scale': (10000, 0, [('inspect-oneshot', 'inspect-native')], '180s'),
    'shared-pilot': (1000, 256, [('reach-single', 'reach-multi'), ('delete-legacy', 'delete-native')], '60s'),
    'shared-scale': (10000, 256, [('reach-single', 'reach-multi'), ('delete-legacy', 'delete-native')], '120s'),
}

def main():
    parser = argparse.ArgumentParser()
    for name in ['git', 'native', 'legacy', 'time', 'timeout', 'source-manifest', 'fixture-recipe', 'harness-source']:
        parser.add_argument('--'+name, required=True)
    parser.add_argument('--stage', choices=list(STAGES), required=True)
    parser.add_argument('--heap-limit', choices=['1G'], default='1G')
    args = parser.parse_args()
    root = Path.cwd().resolve()
    output = root / 'runs'
    assert not output.is_symlink() and output.resolve().is_relative_to(root)
    output.mkdir(exist_ok=True)
    run = output / (args.stage+'-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
    run.mkdir()
    specification = importlib.util.spec_from_file_location('v020_fixture', args.fixture_recipe)
    recipe = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(recipe)
    environment = {k: v for k, v in os.environ.items() if not k.startswith('GIT_') and k != 'GHCRTS'}
    environment.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null', GIT_NO_LAZY_FETCH='1', GIT_OPTIONAL_LOCKS='0', LC_ALL='C')
    source_bytes = Path(args.source_manifest).read_bytes()
    summary = {'stage': args.stage, 'project_commit': json.loads(source_bytes)['project_commit'],
               'source_manifest_sha256': hashlib.sha256(source_bytes).hexdigest(),
               'fixture_recipe_sha256': hashlib.sha256(Path(args.fixture_recipe).read_bytes()).hexdigest(),
               'harness_source_sha256': hashlib.sha256(Path(args.harness_source).read_bytes()).hexdigest(),
               'git': recipe.checked([args.git, '--version'], env=environment).decode().strip(),
               'platform': sys.platform, 'heap_limit': args.heap_limit,
               'resource_policy': 'Serial cases/modes/repeats; GHC -N1 -M1G; one packing thread. Heap cap is not an RSS cap.',
               'cache_policy': 'Unflushed OS caches; no cold-storage claim.',
               'rss_policy': 'GNU time max RSS, not sum of simultaneous processes; pure reachability RSS includes loading outside its timed region.',
               'timing_policy': 'Inspect/delete include result-digest forcing; pure reachability excludes loading, but includes query/exclusive-set/digest forcing.',
               'count_policy': 'Git launch counts cover the measured Haskell program, excluding driver fixture generation and ref audits.',
               'measurements': [], 'complete': False}

    def save():
        (run / 'results.json').write_text(json.dumps(summary, indent=2)+'\n')

    print('Run directory:', run, flush=True)
    save()
    nodes, depth, groups, limit = STAGES[args.stage]
    repository = run / 'repository.git'
    summary['fixture'] = recipe.fixture(args.git, repository, nodes, depth, environment)

    def refs_digest():
        return hashlib.sha256(recipe.checked([args.git, '-C', str(repository), 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads/'], env=environment)).hexdigest()

    summary['refs_digest_before'] = refs_digest()
    save()
    expected = {}
    full_expected = {}
    for group_number, group in enumerate(groups):
        for repeat in range(1, 4):
            modes = group if repeat % 2 else tuple(reversed(group))
            for mode in modes:
                label = mode+'-'+str(repeat)
                stdout, stderr, timing = [run / (label+suffix) for suffix in ['.stdout', '.stderr', '.time.json']]
                executable = args.legacy if mode == 'delete-legacy' else args.native
                command = [args.timeout, '--signal=TERM', '--kill-after=5s', limit, args.time,
                           '-f', '{"wall_seconds":%e,"user_seconds":%U,"system_seconds":%S,"max_rss_kib":%M}',
                           '-o', str(timing), executable, args.git, str(repository), mode,
                           summary['fixture']['target'], str(nodes), '+RTS', '-N1', '-M1G', '-RTS']
                print('Measuring', label, flush=True)
                started = time.monotonic()
                with stdout.open('wb') as out, stderr.open('wb') as err:
                    result = subprocess.run(command, stdout=out, stderr=err, env=environment)
                observed = {'mode': mode, 'repeat': repeat, 'group': group_number,
                            'exit_code': result.returncode, 'driver_seconds': time.monotonic()-started}
                summary['measurements'].append(observed)
                if result.returncode != 0:
                    save()
                    print('Stopped on failed/timed-out measurement; no retry:', run/'results.json', flush=True)
                    return result.returncode
                observed.update(json.loads(stdout.read_text()))
                observed.update(json.loads(timing.read_text()))
                save()
                digest = observed['result_digest']
                if group_number not in expected:
                    expected[group_number] = digest
                    full_expected[group_number] = observed['full_digest']
                assert digest == expected[group_number], 'Semantic result mismatch'
                assert observed['full_digest'] == full_expected[group_number], 'Full result/confirmation mismatch'
                assert observed['nodes'] == nodes
                if mode.startswith('inspect-'):
                    assert observed['result_size'] == summary['fixture']['expected_history_commits']
                    if mode == 'inspect-native':
                        assert observed['batch_processes'] == 1
                if mode.startswith('reach-'):
                    assert observed['timed_git_processes'] == 0
                if mode.startswith('delete-'):
                    assert observed['result_size'] == 3
                assert refs_digest() == summary['refs_digest_before'], 'Read-only measurement changed refs'
                print('Completed', label, round(observed['operation_seconds'], 6), 'seconds;',
                      observed['physical_git_processes'], 'Git launches;', observed['max_rss_kib'], 'KiB', flush=True)
    summary['refs_digest_after'] = refs_digest()
    summary['medians'] = []
    for group in groups:
        for mode in group:
            rows = [r for r in summary['measurements'] if r['mode'] == mode]
            summary['medians'].append({'mode': mode,
                'operation_seconds': statistics.median(r['operation_seconds'] for r in rows),
                'physical_git_processes': rows[0]['physical_git_processes'],
                'batch_processes': rows[0]['batch_processes'],
                'max_rss_kib': statistics.median(r['max_rss_kib'] for r in rows)})
    summary['complete'] = True
    save()
    print(json.dumps(summary['medians'], indent=2), flush=True)
    print('Complete:', run/'results.json', flush=True)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
