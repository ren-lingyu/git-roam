"""Copy the reviewed committed source into the experiment; do not alter Git state."""
from pathlib import Path
import hashlib
import json
import subprocess

base = Path(__file__).resolve().parent
repo = base.parent.parent
git = '/nix/store/01ffsdryzxz2vb25v5rps5vkkqr4p5zs-git-with-svn-2.56.0/bin/git'
revision = 'c1789363356cc3c7117ada31ceba6b647f6fb525'
assert not base.is_symlink() and base.resolve().is_relative_to((repo/'tmp').resolve())
source = base/'flake/source'
if source.exists():
    raise SystemExit('Refuse to overwrite an existing source snapshot')
names = subprocess.check_output([git, '-C', str(repo), 'ls-tree', '-r', '--name-only', revision]).decode().splitlines()
inventory = {}
for name in names:
    size = int(subprocess.check_output([git, '-C', str(repo), 'cat-file', '-s', revision+':'+name]))
    if size > 1048576:
        raise SystemExit('Oversized source member: '+name)
    target = source/name
    assert target.resolve().is_relative_to(base.resolve())
    data = subprocess.check_output([git, '-C', str(repo), 'show', revision+':'+name])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    inventory[name] = {'bytes': size, 'sha256': hashlib.sha256(data).hexdigest()}
(base/'flake/SOURCE.json').write_text(json.dumps({'project_commit': revision, 'files': inventory}, indent=2)+'\n')
print('Copied',len(inventory),'committed small source files; Git metadata excluded')
