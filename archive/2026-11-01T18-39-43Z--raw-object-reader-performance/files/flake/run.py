"""Reproducible fixture generation and paired complete-validator measurements."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time
import uuid


def checked(command, **kwargs):
    return subprocess.check_output(command, stderr=subprocess.PIPE, **kwargs)


def fixture(git, destination, nodes, versions, fanout, environment):
    checked([git, 'init', '--bare', '--initial-branch=main', '--object-format=sha1', '--ref-format=files', str(destination)], env=environment)
    # Stream one fast-import pack instead of spawning processes per generated
    # object. Dates, identities, UUIDs and payloads are deterministic.
    stream = destination.parent/'fixture.fast-import'
    mark = 1
    previous = []
    with stream.open('wb') as out:
        def line(value):
            out.write(value.encode()+b'\n')

        def data(value):
            body = value.encode()
            line('data '+str(len(body)))
            out.write(body+b'\n')

        line('blob')
        line('mark :1')
        data('')
        for number in range(1, nodes+1):
            node = str(uuid.UUID(int=number, version=4))
            branch = 'refs/heads/'+node

            def commit(message, parents, note=None):
                nonlocal mark
                mark += 1
                line('commit '+branch)
                line('mark :'+str(mark))
                line('committer Performance Fixture <fixture@example.invalid> 1690000000 +0000')
                data(message)
                if parents:
                    line('from :'+str(parents[0]))
                    for parent in parents[1:]:
                        line('merge :'+str(parent))
                else:
                    line('deleteall')
                    line('M 100644 :1 '+node+'/.roam')
                if note is not None:
                    line('M 100644 inline '+node+'/note.org')
                    data(note)
                line('')
                return mark

            q = commit('Root '+node, [])
            for version in range(versions):
                note = '* Node '+node+' version '+str(version)+'\n'
                w = commit('Content '+str(version), [q], note)
                q = commit('Checkpoint '+str(version), [q, w]+previous[-fanout:] if fanout else [q, w], note)
            previous.append(q)
        line('done')
    started = time.monotonic()
    with stream.open('rb') as source:
        checked([git, '-C', str(destination), '-c', 'gc.auto=0', '-c', 'pack.threads=1', 'fast-import', '--quiet', '--date-format=raw'], stdin=source, env=environment)
    inventory = checked([git, '-C', str(destination), 'count-objects', '-v'], env=environment).decode()
    digest = hashlib.sha256()
    with stream.open('rb') as generated:
        for chunk in iter(lambda: generated.read(65536), b''):
            digest.update(chunk)
    return {'nodes': nodes, 'checkpoints_per_node': versions, 'fanout': fanout,
            'generation_seconds': time.monotonic()-started,
            'stream_sha256': digest.hexdigest(),
            'objects': inventory}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--git', required=True)
    parser.add_argument('--harness', required=True)
    parser.add_argument('--time', required=True)
    parser.add_argument('--timeout', required=True)
    parser.add_argument('--source-manifest', required=True)
    parser.add_argument('--stage', choices=['pilot', 'scale'], required=True)
    parser.add_argument('--heap-limit', choices=['512m', '1G'], default='512m')
    parser.add_argument('--output', default='runs')
    args = parser.parse_args()
    cwd = Path.cwd().resolve()
    output = Path(args.output).absolute()
    if output.is_symlink() or not output.resolve().is_relative_to(cwd):
        raise SystemExit('Output must remain inside the experiment working directory')
    # Fresh owned directory per invocation; never delete or overwrite old runs.
    output.mkdir(parents=True, exist_ok=True)
    run = output/(args.stage+'-'+args.heap_limit+'-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
    run.mkdir()
    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    environment.pop('GHCRTS', None)  # Do not let inherited RTS options override the experiment's bounds.
    environment.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                       GIT_NO_LAZY_FETCH='1', GIT_OPTIONAL_LOCKS='0', LC_ALL='C')
    scenarios = [(10, 1, 0), (100, 1, 0), (1000, 1, 0), (100, 10, 2)] if args.stage == 'pilot' else [(10000, 1, 0)]
    source_manifest = Path(args.source_manifest).read_bytes()
    summary = {'stage': args.stage, 'heap_limit': args.heap_limit, 'project_commit': json.loads(source_manifest)['project_commit'],
               'source_manifest_sha256': hashlib.sha256(source_manifest).hexdigest(),
               'git': checked([args.git, '--version'], env=environment).decode().strip(),
               'platform': sys.platform, 'workload': 'Full inspectState with fresh per-call caches; no CLI rendering',
               'cache_policy': 'OS caches are not flushed; raw repeats retained, no cold-cache claim',
               'rss_policy': 'GNU time max RSS, not the sum of simultaneous process RSS',
               'resource_policy': 'Sequential cases/repeats/modes, GHC -N1 -M'+args.heap_limit+', pack.threads=1; heap limit is not an RSS limit',
               'fixtures': [], 'measurements': [], 'complete': False}

    def save():
        (run/'results.json').write_text(json.dumps(summary, indent=2)+'\n')

    save()
    print('Run directory:', run, flush=True)
    for nodes, versions, fanout in scenarios:
        case = run/f'n{nodes}-k{versions}-d{fanout}'
        case.mkdir()
        repository = case/'repository.git'
        print('Generating', case.name, flush=True)
        info = fixture(args.git, repository, nodes, versions, fanout, environment)
        info['case'] = case.name
        summary['fixtures'].append(info)
        save()
        expected_digest = None
        # Begin large scenarios with the candidate to retain a complete result
        # even if the current implementation reaches its explicit time budget.
        initial = ['persistent', 'oneshot'] if args.stage == 'scale' else ['oneshot', 'persistent']
        for repeat in range(3):
            modes = initial if repeat % 2 == 0 else list(reversed(initial))
            for mode in modes:
                label = f'{mode}-{repeat+1}'
                stdout, stderr, timing = (case/(label+suffix) for suffix in ['.stdout', '.stderr', '.time.json'])
                print('Measuring', case.name, label, flush=True)
                limit = '60s' if args.stage == 'pilot' else '180s'
                command = [args.timeout, '--signal=TERM', '--kill-after=5s', limit, args.time,
                           '-f', '{"wall_seconds":%e,"user_seconds":%U,"system_seconds":%S,"max_rss_kib":%M}',
                           '-o', str(timing), args.harness, args.git, str(repository), mode,
                           '+RTS', '-N1', '-M'+args.heap_limit, '-RTS']
                started = time.monotonic()
                with stdout.open('wb') as out, stderr.open('wb') as err:
                    result = subprocess.run(command, stdout=out, stderr=err, env=environment)
                observed = {'case': case.name, 'mode': mode, 'repeat': repeat+1, 'exit_code': result.returncode,
                            'driver_seconds': time.monotonic()-started}
                summary['measurements'].append(observed)
                if result.returncode != 0:
                    observed['incomplete'] = True
                    save()
                    print('Stopped after failed/timed-out measurement; no automatic retry. See', run/'results.json', flush=True)
                    return result.returncode
                measured = json.loads(stdout.read_text())
                measured.update(json.loads(timing.read_text()))
                observed.update(measured)
                assert measured['nodes'] == nodes
                assert measured['checkpoints'] == nodes*versions
                if expected_digest is None:
                    expected_digest = measured['result_digest']
                assert measured['result_digest'] == expected_digest, 'Validation result changed across modes/repeats'
                save()
                print('Completed:', round(measured['validator_seconds'], 4), 'seconds;', measured['physical_git_processes'], 'Git processes', flush=True)
    summary['medians'] = []
    for info in summary['fixtures']:
        for mode in ['oneshot', 'persistent']:
            values = [x for x in summary['measurements'] if x['case'] == info['case'] and x['mode'] == mode]
            summary['medians'].append({'case': info['case'], 'mode': mode,
                                       'validator_seconds': statistics.median(x['validator_seconds'] for x in values),
                                       'physical_git_processes': values[0]['physical_git_processes'],
                                       'max_rss_kib': statistics.median(x['max_rss_kib'] for x in values)})
    summary['complete'] = True
    save()
    print(json.dumps(summary['medians'], indent=2), flush=True)
    print('Complete:', run/'results.json', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
