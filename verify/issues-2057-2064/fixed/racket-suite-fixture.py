#!/usr/bin/env python3
"""Prepare/inspect/remove the genuine Racket 9.2 -> 9.3 VM suite fixture.

`prepare` installs 9.2 using its historical official cask, with only the ARM
checksum updated to the vendor's re-signed download. It then exposes the pinned
official 9.3 cask definition. Upgrade is deliberately left to DuoUpdater's UI.
No zap, preferences reset, app launch, or diagnostic-program compilation occurs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'inspect', 'cleanup'])
    parser.add_argument('--work', type=Path, default=Path('/tmp/duo206x-fix-validation'))
    args = parser.parse_args()
    model = subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True).strip()
    if not model.startswith('VirtualMac'):
        raise SystemExit('Refusing: this fixture may run only in the macOS VM.')
    work = args.work.resolve()
    if work != Path('/private/tmp/duo206x-fix-validation'):
        raise SystemExit('Use the dedicated /tmp/duo206x-fix-validation workspace.')
    source = Path(__file__).resolve().parent
    packages = json.loads((source / 'racket-packages.json').read_text())
    evidence = work / 'evidence'
    evidence.mkdir(exist_ok=True)
    state_file = work / 'racket-fixture-state.json'
    definition = Path('/opt/homebrew/Library/Taps/homebrew/homebrew-cask/Casks/r/racket.rb')
    caskroom = Path('/opt/homebrew/Caskroom/racket')
    suites = [Path('/Applications/Racket v9.2'), Path('/Applications/Racket v9.3')]
    env = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE='1', HOMEBREW_NO_INSTALL_FROM_API='1',
               HOMEBREW_NO_INSTALL_CLEANUP='1', HOMEBREW_NO_ENV_HINTS='1')

    def run(command, label):
        completed = subprocess.run([str(v) for v in command], env=env, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (evidence / (label + '.log')).write_text(
            'command: ' + json.dumps([str(v) for v in command]) + '\n'
            + 'exit: ' + str(completed.returncode) + '\n' + completed.stdout)
        print(label, completed.returncode, completed.stdout[-1500:], flush=True)
        completed.check_returncode()
        return completed.stdout

    def brew(arguments, label):
        return run(['/opt/homebrew/bin/brew'] + arguments, label)

    def write_state(state):
        state_file.write_text(json.dumps(state, indent=2) + '\n')

    def inspect():
        members = []
        for suite in suites:
            if not suite.is_dir():
                continue
            for app in sorted(suite.glob('*.app')):
                with (app / 'Contents/Info.plist').open('rb') as stream:
                    info = plistlib.load(stream)
                run(['/usr/bin/codesign', '--verify', '--deep', '--strict', app],
                    f'racket-{suite.name}-{app.stem}-signature-verify')
                run(['/usr/bin/codesign', '-dv', '--verbose=2', app],
                    f'racket-{suite.name}-{app.stem}-signature-identity')
                members.append({'path': str(app), 'bundleID': info.get('CFBundleIdentifier'),
                                'marketing': info.get('CFBundleShortVersionString'),
                                'build': info.get('CFBundleVersion')})
        record = {'members': members, 'suitePaths': [str(p) for p in suites if p.exists()]}
        (evidence / ('racket-inspection-' + '-'.join(p.name for p in suites if p.exists()) + '.json')) \
            .write_text(json.dumps(record, indent=2) + '\n')
        brew(['info', '--cask', '--json=v2', 'racket'], 'racket-info')
        # Match the product's all-cask read. A named outdated cask makes Brew
        # exit 1 even for a valid response; its all-cask read exits 0.
        brew(['outdated', '--cask', '--json=v2'], 'racket-outdated')
        print(json.dumps(record), flush=True)

    if args.action == 'prepare':
        if state_file.exists():
            raise SystemExit('Fixture state already exists; inspect or clean up before preparing again.')
        for path in [definition, caskroom, Path('/usr/local/Caskroom/racket')] + suites:
            if path.exists() or path.is_symlink():
                raise SystemExit('Refusing to touch preexisting Racket state: ' + str(path))
        if not (definition.parents[2] / 'cask_renames.json').is_file():
            raise SystemExit('The existing official cask tap is required.')
        for version, package in packages.items():
            archive = work / 'downloads' / f'racket-{version}-aarch64-macosx-cs.dmg'
            digest = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest()
            if digest != package['sha256']:
                raise SystemExit('Payload differs from the pinned official digest: ' + str(archive))
        old = (source / 'racket-9.2.rb').read_text()
        before_hash = packages['9.2']['historicalCaskSHA256']
        if old.count(before_hash) != 1:
            raise SystemExit('Historical cask no longer has exactly the expected ARM checksum.')
        old = old.replace(before_hash, packages['9.2']['sha256'])
        current = (source / 'racket-9.3.rb').read_text()
        if 'version "9.3"' not in current or packages['9.3']['sha256'] not in current:
            raise SystemExit('Current cask does not match the pinned 9.3 artifact.')
        state = {'prepared': False, 'definition': str(definition),
                 'createdDefinitionDirectory': not definition.parent.exists(),
                 'expectedDefinition': old, 'baselineAbsent': [str(p) for p in [caskroom] + suites]}
        write_state(state)
        definition.parent.mkdir(parents=True, exist_ok=True)
        definition.write_text(old)
        (evidence / 'racket-9.2-current-signature-cask.rb').write_text(old)
        # Keep the genuine URL in the recipe. Seed only its expected cache file
        # from the separately verified download; Brew checks the digest again.
        cached = Path(brew(['--cache', '--cask', 'racket'], 'racket92-cache-path').strip().splitlines()[-1])
        downloads = Path.home() / 'Library/Caches/Homebrew/downloads'
        if cached.parent != downloads or cached.suffix != '.dmg':
            raise SystemExit('Brew returned an unexpected cache path: ' + str(cached))
        if cached.exists():
            if hashlib.file_digest(cached.open('rb'), 'sha256').hexdigest() != packages['9.2']['sha256']:
                raise SystemExit('A preexisting cache file has different bytes; left untouched.')
        else:
            run(['/bin/cp', '-c', work / 'downloads/racket-9.2-aarch64-macosx-cs.dmg', cached], 'racket92-seed-cache')
        brew(['install', '--cask', 'racket'], 'racket92-install')
        inspect()
        definition.write_text(current)
        state['prepared'] = True
        state['expectedDefinition'] = current
        write_state(state)
        brew(['outdated', '--cask', '--json=v2'], 'racket93-update-offer')
        return

    state = json.loads(state_file.read_text())
    if state['definition'] != str(definition):
        raise SystemExit('Unexpected fixture state.')
    if args.action == 'inspect':
        inspect()
        return
    if definition.exists() and definition.read_text() != state['expectedDefinition']:
        raise SystemExit('The fixture definition was changed externally; refusing cleanup.')
    if caskroom.exists():
        brew(['uninstall', '--cask', 'racket'], 'racket-cleanup')
    leftovers = [str(p) for p in [caskroom] + suites if p.exists() or p.is_symlink()]
    if leftovers:
        raise SystemExit('Brew cleanup left fixture paths: ' + ', '.join(leftovers))
    definition.unlink(missing_ok=True)
    if state['createdDefinitionDirectory']:
        try:
            definition.parent.rmdir()
        except OSError:
            pass  # Only remove a directory we created when nothing else is there.
    (evidence / 'racket-cleanup.json').write_text(json.dumps({'leftovers': leftovers}) + '\n')
    state_file.unlink()


if __name__ == '__main__':
    main()
