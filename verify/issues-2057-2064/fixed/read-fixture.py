#!/usr/bin/env python3
"""Native Brew read failure/recovery for the running UI, inside the VM only."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile

assert subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True).startswith('VirtualMac')
assert os.geteuid() != 0
work = Path('/tmp/duo206x-fix-validation/reads')
definition = Path('/opt/homebrew/Library/Taps/duo206x/homebrew-fixtures/Casks/duo206x-read.rb')
token = 'duo206x/fixtures/duo206x-read'
env = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE='1', HOMEBREW_NO_INSTALL_FROM_API='1')
action = sys.argv[1]
if action == 'prepare':
    assert not work.exists() and not definition.exists()
    assert not Path('/opt/homebrew/Caskroom/duo206x-read').exists()
    assert not Path('/opt/homebrew/bin/duo206x-read').exists()
    work.mkdir(parents=True)
    binary = work / 'duo206x-read'
    binary.write_text('#!/bin/sh\necho fixture\n')
    binary.chmod(0o755)
    archive = work / 'read.tar.gz'
    with tarfile.open(archive, 'w:gz') as tf:
        tf.add(binary, arcname=binary.name)
    text = f'''cask "duo206x-read" do
  version "1.0"
  sha256 "{hashlib.sha256(archive.read_bytes()).hexdigest()}"
  url "file://{archive}"
  name "Duo206x read recovery fixture"
  desc "Inert read-failure fixture"
  homepage "https://example.invalid"
  binary "duo206x-read"
end
'''
    definition.write_text(text)
    subprocess.run(['/opt/homebrew/bin/brew', 'install', '--cask', token], env=env, check=True)
    current = text.replace('version "1.0"', 'version "2.0"').replace('  binary ', '  deprecate! date: "2026-11-01", because: :unmaintained\n  binary ')
    (work / 'current.rb').write_text(current)
    definition.write_text(current)
elif action == 'fail':
    assert definition.read_text() == (work / 'current.rb').read_text()
    # A normal exception can fall back to installed metadata with exit 0. Keep
    # the valid cask header and explicitly abort this controlled native read.
    definition.write_text('cask "duo206x-read" do\n  abort "Duo206x controlled Brew read failure"\nend\n')
elif action == 'recover':
    assert 'Duo206x controlled Brew read failure' in definition.read_text()
    definition.write_text((work / 'current.rb').read_text())
elif action == 'cleanup':
    assert (work / 'current.rb').exists()
    definition.write_text((work / 'current.rb').read_text())
    subprocess.run(['/opt/homebrew/bin/brew', 'uninstall', '--cask', token], env=env, check=True)
    subprocess.run(['/opt/homebrew/bin/brew', 'untrust', '--cask', token], env=env, check=True)
    definition.unlink()
    (work / 'cleanup.json').write_text(json.dumps({'recordRemains': Path('/opt/homebrew/Caskroom/duo206x-read').exists(), 'definitionRemains': definition.exists()}))
else:
    raise SystemExit('prepare|fail|recover|cleanup')
