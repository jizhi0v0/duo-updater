#!/usr/bin/env python3
"""Run repository checks in the dedicated macOS VM checkout, one at a time.

This compiles the repository's product/tests only, not diagnostic executables.
Use --step focused --filter '<suite regex>' first, then the required full steps.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, default=Path('/tmp/duo206x-fix-validation'))
    parser.add_argument('--step', required=True, choices=[
        'focused', 'core', 'core-appstore', 'core-rest', 'cli', 'application-build',
        'scripts', 'app', 'release-build',
    ])
    parser.add_argument('--filter', default='')
    args = parser.parse_args()
    model = subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True).strip()
    if not model.startswith('VirtualMac'):
        raise SystemExit('This runner is for a macOS VM, never the host.')
    work = args.work.resolve()
    if work != Path('/private/tmp/duo206x-fix-validation'):
        raise SystemExit('Use the dedicated /tmp/duo206x-fix-validation workspace.')
    repo = work / 'repo'
    if not (repo / 'DuoUpdaterCore/Package.swift').is_file():
        raise SystemExit('The source snapshot has not been unpacked into repo yet.')
    evidence = work / 'evidence'
    evidence.mkdir(exist_ok=True)
    lock = (work / 'product-check.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit('Another product check is using this checkout/cache.')

    env = dict(os.environ)
    env['PATH'] = '/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:' + env.get('PATH', '')
    env['APP_TESTS_DD'] = str(work / 'app-dd')
    env['LOCALIZABLE_DD'] = str(work / 'localizable-dd')
    env['UNSIGNED_RELEASE_DD'] = str(work / 'release-dd')
    env['XCODE_CLONED_SOURCE_PACKAGES'] = str(work / 'app-dd/SourcePackages')
    swift = ['/usr/bin/xcrun', 'swift']
    shared = ['--scratch-path', str(repo / 'DuoUpdaterCore/.build'), '--force-resolved-versions', '-j', '4']
    commands = {
        'focused': swift + ['test', '--package-path', str(repo / 'DuoUpdaterCore')] + shared
            + ['--filter', args.filter],
        'core': swift + ['test', '--package-path', str(repo / 'DuoUpdaterCore')] + shared,
        'core-appstore': swift + ['test', '--package-path', str(repo / 'DuoUpdaterCore')] + shared
            + ['--filter', 'MacAppStorePageCacheTests'],
        'core-rest': swift + ['test', '--package-path', str(repo / 'DuoUpdaterCore')] + shared
            + ['--skip', 'MacAppStorePageCacheTests'],
        'cli': swift + ['test', '--package-path', str(repo / 'CLI')] + shared,
        'application-build': swift + ['build', '--package-path', str(repo / 'application-test')] + shared,
        'scripts': ['/usr/bin/make', 'test-scripts'],
        'app': ['/usr/bin/make', 'test-app'],
        'release-build': ['/usr/bin/make', 'test-release-build'],
    }
    if args.step == 'focused' and not args.filter:
        raise SystemExit('--step focused requires --filter; it must not silently run everything.')
    if args.step in {'app', 'release-build'}:
        pinned = subprocess.check_output(
            ['/bin/bash', str(repo / 'scripts/pinned-xcodegen.sh')], cwd=repo, env=env, text=True).strip()
        env['PATH'] = str(Path(pinned).parent) + ':' + env['PATH']

    command = commands[args.step]
    label = f'{args.step}-{time.time_ns()}'
    output = evidence / (label + '.log')
    started = time.monotonic()
    print(f'{args.step}: log={output}', flush=True)
    with output.open('w') as log:
        log.write('command: ' + json.dumps(command) + '\n')
        log.flush()
        completed = subprocess.run(command, cwd=repo, env=env, stdout=log, stderr=subprocess.STDOUT)
    result = {
        'step': args.step, 'command': command, 'exit': completed.returncode,
        'elapsedSeconds': round(time.monotonic() - started, 3), 'output': str(output),
    }
    (evidence / (label + '.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)
    raise SystemExit(completed.returncode)


if __name__ == '__main__':
    main()
