"""Deterministic legal v0.2.0 DAGs; no old q,w Checkpoint encoding."""
from pathlib import Path
import hashlib
import subprocess
import uuid

def checked(command, **kwargs):
    return subprocess.check_output(command, stderr=subprocess.PIPE, **kwargs)

def node(number):
    return str(uuid.UUID(int=number, version=4))

def fixture(git, destination, nodes, shared_depth, environment):
    assert nodes >= 3
    checked([git, 'init', '--bare', '--initial-branch=main', '--object-format=sha1',
             '--ref-format=files', str(destination)], env=environment)
    stream = destination.parent / 'fixture.fast-import'
    mark = 1
    roots = []
    checkpoints = []
    with stream.open('wb') as output:
        def line(value):
            output.write(value.encode('ascii')+b'\n')

        def data(value):
            body = value.encode('ascii')
            line('data '+str(len(body)))
            output.write(body+b'\n')

        def commit(number, message, parents, note=None):
            nonlocal mark
            mark += 1
            label = node(number)
            line('commit refs/heads/'+label)
            line('mark :'+str(mark))
            line('committer Performance Fixture <fixture@example.invalid> 1690000000 +0000')
            data(message)
            if parents:
                line('from :'+str(parents[0]))
                for parent in parents[1:]:
                    line('merge :'+str(parent))
            else:
                line('deleteall')
                line('M 100644 :1 '+label+'/.roam')
            if note is not None:
                line('M 100644 inline '+label+'/note.org')
                data(note)
            line('')
            return mark

        line('blob')
        line('mark :1')
        data('')
        # Declare all Roots before any context: even cyclic Node-level choices
        # refer to already existing Git objects and never create a commit cycle.
        for number in range(1, nodes+1):
            roots.append(commit(number, 'Root '+node(number), []))
        for number in range(1, nodes+1):
            tip = roots[number-1]
            depth = shared_depth if shared_depth and number == 1 else 1
            for version in range(depth):
                # Only the first Content changes the tree; later same-tree
                # Content is legal and makes shared ancestry cost explicit.
                tip = commit(number, 'Content '+str(version), [tip],
                             '* Node '+node(number)+'\n' if version == 0 else None)
            context = checkpoints[0] if shared_depth and number > 1 else roots[number % nodes]
            # Exactly one external context; inherit the immediate Content tree.
            checkpoints.append(commit(number, 'Checkpoint '+node(number), [tip, context]))
        line('done')
    with stream.open('rb') as input_file:
        checked([git, '-C', str(destination), '-c', 'gc.auto=0', '-c', 'pack.threads=1',
                 'fast-import', '--quiet', '--date-format=raw'], stdin=input_file, env=environment)
    digest = hashlib.sha256()
    with stream.open('rb') as input_file:
        for chunk in iter(lambda: input_file.read(65536), b''):
            digest.update(chunk)
    return {'nodes': nodes, 'shared_depth': shared_depth, 'checkpoints': nodes,
            'expected_history_commits': 3*nodes + (shared_depth-1 if shared_depth else 0),
            'target': node(nodes), 'stream_sha256': digest.hexdigest(),
            'objects': checked([git, '-C', str(destination), 'count-objects', '-v'], env=environment).decode()}
