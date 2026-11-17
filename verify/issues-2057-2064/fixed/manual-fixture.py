#!/usr/bin/env python3
"""Prepare/inspect/clean the genuine Adobe manual-handoff VM fixture.

Run prepare BEFORE seeding Adobe Connect with its real installer. This script
writes only one test cask definition; it never installs/reinstalls a cask or
creates an installed receipt. The test then exercises the product's manual
handoff using the already-installed, same-version Adobe copy. It does not
claim an old-to-new Adobe update.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time

WORK = Path('/tmp/duo206x-fix-validation/manual')
TAP = Path('/opt/homebrew/Library/Taps/duo206x/homebrew-fixtures')
TOKEN = 'duo206x-manual'
DEFINITION = TAP / 'Casks' / (TOKEN + '.rb')
DMG = Path('/tmp/duo-adobe-connect-2026.10.66.dmg')
DIGEST = 'f3f70e8451806394e5385d77ee653c54ec4ad79ab00e228de9e9d4addacbbc68'
VERSION = '2026.10.66,11'
TEAM = 'JQ525L2MZD'
BUNDLE_ID = 'com.adobe.cefconnect.app'
APP = Path('/Applications/Adobe Connect/Adobe Connect.app')
STATE = WORK / 'fixture-state.json'
HANDOFF = WORK / 'product-handoff.json'


def run(command, label, check=True):
    completed = subprocess.run([str(v) for v in command], text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (WORK / (label + '.log')).write_text('command: ' + json.dumps([str(v) for v in command])
                                      + '\nexit: ' + str(completed.returncode) + '\n' + completed.stdout)
    print(label, completed.returncode, completed.stdout[-1200:], flush=True)
    if check:
        completed.check_returncode()
    return completed


def app_identity(path):
    info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', path], 'app-signature')
    identity = run(['/usr/bin/codesign', '-dv', '--verbose=2', path], 'app-identity').stdout
    if ('TeamIdentifier=' + TEAM) not in identity:
        raise SystemExit('Refusing an app with a different developer identity: ' + str(path))
    if info.get('CFBundleIdentifier') != BUNDLE_ID or info.get('CFBundleShortVersionString') != '2026.10.66':
        raise SystemExit('Refusing an unexpected app/version: ' + str(path))
    return {'path': str(path), 'bundleID': info['CFBundleIdentifier'],
            'marketing': info['CFBundleShortVersionString'], 'build': info.get('CFBundleVersion'), 'team': TEAM}


def inspect(state):
    installed = app_identity(APP) if APP.is_dir() else None
    record = {
        'installedApp': installed,
        'trackedPaths': {path: Path(path).exists() for path in state['before']},
        'caskDefinitionExists': DEFINITION.exists(),
        'caskRecordExists': (Path('/opt/homebrew/Caskroom') / TOKEN).exists(),
        'handoffOnly': True,
        'productResult': json.loads(HANDOFF.read_text()) if HANDOFF.exists() else None,
    }
    (WORK / 'inspection.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'inspect', 'cleanup'])
    action = parser.parse_args().action
    model = subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True)
    if not model.startswith('VirtualMac'):
        raise SystemExit('Refusing: this fixture may run only inside the macOS VM.')
    if action == 'prepare':
        if os.geteuid() == 0:
            raise SystemExit('Prepare as the guest user so its exact home paths and GUI uid are recorded.')
        if WORK.exists() or DEFINITION.exists() or DEFINITION.is_symlink():
            raise SystemExit('Fixture state/definition already exists; inspect or clean it first.')
        if not (Path('/tmp/duo206x-fix-validation/pkg') / 'created.json').is_file() or not (TAP / '.git').is_dir():
            raise SystemExit('The package fixture must prepare and own the shared test tap first.')
        if (Path('/opt/homebrew/Caskroom') / TOKEN).exists():
            raise SystemExit('A preexisting manual-cask install must be preserved.')
        home = Path.home()
        roots = [Path('/Applications/Adobe Connect'), home / 'Applications/Adobe Connect']
        if any(path.exists() or path.is_symlink() for path in roots):
            raise SystemExit('Prepare before Adobe is seeded; preserve any preexisting installation.')
        with DMG.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha256').hexdigest()
        if actual != DIGEST:
            raise SystemExit('The cached Adobe image differs from the pinned genuine payload.')
        tracked = roots + [home / 'Library/LaunchAgents/com.adobe.connectDetector.plist', home / 'adobeconnectapp.log',
                           home / 'Library/Preferences/com.adobe.adobeconnectinstaller.app.plist',
                           home / 'Library/Preferences/com.adobe.cefconnect.app.plist']
        before = {str(path): path.exists() or path.is_symlink() for path in tracked}
        definition = f'''cask "{TOKEN}" do
  version "{VERSION}"
  sha256 "{DIGEST}"
  url "file://{DMG}"
  name "Adobe Connect manual handoff VM fixture"
  desc "Genuine signed Adobe installer for same-version handoff validation"
  homepage "https://www.adobe.com/products/adobeconnect.html"
  installer manual: "AdobeConnectInstaller.app"
  uninstall quit: "{BUNDLE_ID}"
end
'''
        WORK.mkdir(parents=True)
        state = {'startedAt': time.time(), 'uid': os.getuid(), 'home': str(home), 'before': before,
                 'temporaryDirectory': tempfile.gettempdir(), 'definition': str(DEFINITION),
                 'definitionSHA256': hashlib.sha256(definition.encode()).hexdigest(),
                 'payload': str(DMG), 'payloadSHA256': DIGEST, 'handoffOnly': True}
        STATE.write_text(json.dumps(state, indent=2) + '\n')
        DEFINITION.write_text(definition)
        print('Prepared definition only. Seed the genuine Adobe app next; no Brew receipt was created.', flush=True)
        inspect(state)
        return

    state = json.loads(STATE.read_text())
    if state['definition'] != str(DEFINITION) or not state.get('handoffOnly'):
        raise SystemExit('Unexpected fixture state.')
    if action == 'inspect':
        inspect(state)
        return

    # Never discard a receipt if a bug unexpectedly created one: preserve that
    # evidence for the caller instead of hiding it during fixture cleanup.
    if (Path('/opt/homebrew/Caskroom') / TOKEN).exists():
        raise SystemExit('Unexpected installed Brew receipt; inspect it before cleanup.')
    if DEFINITION.exists():
        if hashlib.sha256(DEFINITION.read_bytes()).hexdigest() != state['definitionSHA256']:
            raise SystemExit('The fixture definition changed; preserve it for inspection.')
        run(['/opt/homebrew/bin/brew', 'untrust', '--cask', 'duo206x/fixtures/' + TOKEN], 'untrust-manual', check=False)
        DEFINITION.unlink()
    staged_parent = None
    if HANDOFF.exists():
        result = json.loads(HANDOFF.read_text())
        staged = Path(result['stagedInstaller']).resolve()
        parent = staged.parent
        expected_parent = re.fullmatch(r'DuoUpdater-pkg-Adobe-Connect-[0-9A-Fa-f-]{36}', parent.name)
        if (staged.name != 'AdobeConnectInstaller.app' or not expected_parent
                or parent.parent != Path(state['temporaryDirectory']).resolve()):
            raise SystemExit('Unexpected staged installer location; nothing was removed there.')
        if parent.exists() and parent.stat().st_birthtime < state['startedAt']:
            raise SystemExit('Staged work directory predates this fixture; preserve it.')
        # LaunchServices may spell the temporary root with /var or /private/var.
        # Checking the executable suffix avoids deleting a still-running copy
        # merely because its argv uses the other equivalent path spelling.
        process_pattern = 'AdobeConnectInstaller.app/Contents/MacOS/AdobeConnectInstaller( |$)'
        if subprocess.run(['/usr/bin/pgrep', '-f', process_pattern], stdout=subprocess.DEVNULL).returncode == 0:
            raise SystemExit('Close the manual installer window before cleaning its files.')
        staged_parent = parent
    for root in [Path('/Applications/Adobe Connect'), Path(state['home']) / 'Applications/Adobe Connect']:
        if state['before'][str(root)]:
            continue
        if root.exists():
            app_identity(root / 'Adobe Connect.app')
            shutil.rmtree(root)
    agent = Path(state['home']) / 'Library/LaunchAgents/com.adobe.connectDetector.plist'
    if agent.exists() and not state['before'][str(agent)]:
        if plistlib.loads(agent.read_bytes()).get('Label') != 'com.adobe.connectDetector':
            raise SystemExit('Unexpected launch agent; preserve it.')
        run(['/bin/launchctl', 'bootout', 'gui/' + str(state['uid']), agent], 'detector-bootout', check=False)
        agent.unlink()
    log = Path(state['home']) / 'adobeconnectapp.log'
    if log.exists() and not state['before'][str(log)]:
        log.unlink()
    for name in ['com.adobe.adobeconnectinstaller.app.plist', 'com.adobe.cefconnect.app.plist']:
        path = Path(state['home']) / 'Library/Preferences' / name
        if path.exists() and not state['before'][str(path)] and path.stat().st_birthtime >= state['startedAt']:
            path.unlink()
    if staged_parent is not None and staged_parent.exists():
        shutil.rmtree(staged_parent)
    leftovers = {path: Path(path).exists() for path, existed in state['before'].items() if not existed}
    leftovers['definition'] = DEFINITION.exists()
    leftovers['unexpectedBrewRecord'] = (Path('/opt/homebrew/Caskroom') / TOKEN).exists()
    (WORK / 'cleanup.json').write_text(json.dumps(leftovers, indent=2) + '\n')
    print(json.dumps(leftovers, indent=2), flush=True)
    if any(leftovers.values()):
        raise SystemExit('Tracked new fixture paths remain; inspect the record.')


if __name__ == '__main__':
    main()
