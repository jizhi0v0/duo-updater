#!/usr/bin/env python3
"""Inert VM-only .app -> PKG fixture for the real Brew password channel."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tarfile

assert subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True).startswith('VirtualMac')
work = Path('/tmp/duo206x-fix-validation/pkg')
tap = Path('/opt/homebrew/Library/Taps/duo206x/homebrew-fixtures')
tokens = ['duo206x-pkg', 'duo206x-dependency', 'duo206x-conflict']
apps = ['Duo206xPkg.app', 'Duo206xDependency.app', 'Duo206xConflict.app']
receipt = 'org.duo206x.fixture.pkg'
env = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE='1', HOMEBREW_NO_INSTALL_FROM_API='1', HOMEBREW_NO_INSTALL_CLEANUP='1')


def run(args, label, check=True):
    result = subprocess.run([str(a) for a in args], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (work / (label + '.log')).write_text('exit: ' + str(result.returncode) + '\n' + result.stdout)
    print(label, result.returncode, result.stdout[-800:], flush=True)
    if check and result.returncode:
        raise RuntimeError(label)
    return result


def app(root, name, version):
    bundle = root / name
    (bundle / 'Contents/MacOS').mkdir(parents=True)
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'org.duo206x.' + name.removeprefix('Duo206x').removesuffix('.app').lower(),
        'CFBundleName': name[:-4], 'CFBundleExecutable': 'main', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': version, 'CFBundleVersion': version,
    }))
    binary = bundle / 'Contents/MacOS/main'
    binary.write_text('#!/bin/sh\nexit 0\n')
    binary.chmod(0o755)
    return bundle


def app_cask(token, name):
    bundle = app(work / token, name, '1.0')
    archive = work / (token + '.tar.gz')
    with tarfile.open(archive, 'w:gz') as tf:
        tf.add(bundle, arcname=name)
    definition = f'''cask "{token}" do
  version "1.0"
  sha256 "{hashlib.sha256(archive.read_bytes()).hexdigest()}"
  url "file://{archive}"
  name "{name[:-4]}"
  desc "Disposable VM update fixture"
  homepage "https://example.invalid"
  app "{name}"
end
'''
    (tap / 'Casks' / (token + '.rb')).write_text(definition)


action = sys.argv[1]
if action == 'prepare':
    assert os.geteuid() != 0
    assert not tap.exists() and not work.exists()
    assert all(not (Path('/Applications') / n).exists() for n in apps)
    assert all(not (Path('/opt/homebrew/Caskroom') / t).exists() for t in tokens)
    assert subprocess.run(['/usr/sbin/pkgutil', '--pkg-info', receipt], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
    work.mkdir(parents=True)
    (tap / 'Casks').mkdir(parents=True)
    (work / 'created.json').write_text(json.dumps({'tap': str(tap), 'tokens': tokens, 'apps': apps, 'receipt': receipt}))
    run(['/usr/bin/git', '-C', tap, 'init', '-q'], 'tap-init')
    run(['/usr/bin/git', '-C', tap, 'remote', 'add', 'origin', 'https://example.invalid/duo206x/homebrew-fixtures'], 'tap-remote')
    for token, name in zip(tokens, apps):
        app_cask(token, name)
    run(['/opt/homebrew/bin/brew', 'install', '--cask', 'duo206x/fixtures/duo206x-pkg'], 'seed-app-1')
    for version in ['2.0', '3.0']:
        payload = work / ('payload-' + version)
        app(payload, apps[0], version)
        run(['/usr/bin/pkgbuild', '--root', payload, '--identifier', receipt, '--version', version,
             '--install-location', '/Applications', work / ('fixture-' + version + '.pkg')], 'pkgbuild-' + version)
    action = 'offer'

if action in ['offer', 'conflict', 'checksum', 'architecture', 'macos']:
    assert (work / 'created.json').exists()
    version = '2.0' if action in ['offer', 'architecture', 'macos'] else '3.0'
    package = work / ('fixture-' + version + '.pkg')
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    if action == 'checksum':
        digest = '0' * 64
    constraint = '  depends_on cask: "duo206x/fixtures/duo206x-dependency"\n'
    if action == 'architecture':
        constraint += '  depends_on arch: :intel\n'
    if action == 'macos':
        constraint += '  depends_on macos: [:sequoia, :tahoe]\n'
    if action == 'conflict':
        run(['/opt/homebrew/bin/brew', 'install', '--cask', 'duo206x/fixtures/duo206x-conflict'], 'seed-conflict')
        constraint += '  conflicts_with cask: "duo206x/fixtures/duo206x-conflict"\n'
    (tap / 'Casks/duo206x-pkg.rb').write_text(f'''cask "duo206x-pkg" do
  version "{version}"
  sha256 "{digest}"
  url "file://{package}"
  name "Duo206xPkg"
  desc "Disposable VM package update fixture"
  homepage "https://example.invalid"
{constraint}  pkg "{package.name}"
  uninstall pkgutil: "{receipt}", quit: "org.duo206x.pkg"
end
''')
    run(['/opt/homebrew/bin/brew', 'info', '--json=v2', '--cask', 'duo206x/fixtures/duo206x-pkg'], action + '-info')
elif action == 'inspect':
    assert (work / 'created.json').exists()
    run(['/opt/homebrew/bin/brew', 'list', '--cask', '--versions'], 'installed')
    run(['/usr/sbin/pkgutil', '--pkg-info', receipt], 'package-receipt', False)
    p = Path('/Applications/Duo206xPkg.app/Contents/Info.plist')
    print(json.dumps(plistlib.loads(p.read_bytes()), indent=2))
elif action == 'untrust':
    assert os.geteuid() != 0 and (work / 'created.json').exists()
    for token in tokens:
        run(['/opt/homebrew/bin/brew', 'untrust', '--cask', 'duo206x/fixtures/' + token], 'untrust-' + token, False)
elif action == 'cleanup':
    assert os.geteuid() == 0 and (work / 'created.json').exists()
    for name in apps:
        p = Path('/Applications') / name
        if p.exists():
            shutil.rmtree(p)
    for token in tokens:
        p = Path('/opt/homebrew/Caskroom') / token
        if p.exists():
            shutil.rmtree(p)
    run(['/usr/sbin/pkgutil', '--forget', receipt], 'forget-receipt', False)
    shutil.rmtree(tap)
    (work / 'cleanup.json').write_text(json.dumps({'appsRemain': [n for n in apps if (Path('/Applications') / n).exists()], 'tapRemains': tap.exists()}))
elif action not in ['offer', 'conflict', 'checksum', 'architecture', 'macos']:
    raise SystemExit('prepare|offer|architecture|macos|conflict|checksum|inspect|untrust|cleanup')
