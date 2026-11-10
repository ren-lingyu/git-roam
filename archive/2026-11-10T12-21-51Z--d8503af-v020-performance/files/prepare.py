"""Recover committed production plus a narrowly reverted algorithm control."""
from pathlib import Path
import hashlib
import json
import subprocess

GIT = '/nix/store/01ffsdryzxz2vb25v5rps5vkkqr4p5zs-git-with-svn-2.56.0/bin/git'
COMMIT = 'd8503afd02ae02ab38c604888c0c84e1e2a3cbdb'
here = Path(__file__).resolve().parent
repo = here.parent.parent
assert here.is_relative_to((repo / 'tmp').resolve())
assert not (here / 'flake/source').exists()
assert not (here / 'flake/legacy-source').exists()

def git(*arguments):
    return subprocess.check_output([GIT, '-C', str(repo), *arguments])

files = {}
for entry in git('ls-tree', '-rlz', COMMIT).split(b'\0'):
    if not entry:
        continue
    meta, raw = entry.split(b'\t', 1)
    mode, kind, oid, size = meta.split()
    name = raw.decode()
    assert mode == b'100644' and kind == b'blob' and int(size) <= 1048576, name
    data = git('cat-file', 'blob', oid.decode())
    files[name] = {'blob': oid.decode(), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    for variant in ['source', 'legacy-source']:
        target = here / 'flake' / variant / name
        assert target.resolve().is_relative_to((here / 'flake' / variant).resolve())
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

name = 'cabal/src/GitRoam/Application/Delete.hs'
control = here / 'flake/legacy-source' / name
old = '''    fromOthers <-
        either
            (throwE . show)
            pure
            (reachableHistoryFrom history (Map.elems candidateRefs))'''
new = '''    fromOthers <- fmap Set.unions $ mapM (either (throwE . show) pure . reachableHistory history) (Map.elems candidateRefs)'''
text = control.read_text()
assert text.count(old) == 1
control.write_text(text.replace(old, new))
manifest = {'project_commit': COMMIT, 'source_state': 'exact committed production tree',
            'files': files, 'legacy_control': {'path': name, 'old': old, 'replacement': new,
                'sha256': hashlib.sha256(control.read_bytes()).hexdigest(),
                'meaning': 'Only Delete.collect remaining-tip walk reverted; not an old released binary'}}
(here / 'flake/SOURCE.json').write_text(json.dumps(manifest, indent=2)+'\n')
lock = (repo / '.agents/archive/2026-11-01T18-39-43Z--raw-object-reader-performance/files/flake/flake.lock').read_bytes()
assert hashlib.sha256(lock).hexdigest() == 'a82c0afd58ec776c8a39b110ddf9ad4d53b495aeee1b858aee28e0e842484419'
(here / 'flake/flake.lock').write_bytes(lock)
print('Prepared', len(files), 'committed files and one-function algorithm control.')
