#!/usr/bin/env python3
"""Run only INSIDE the macOS test VM. Installs and cleans up its own fixtures.

Usage: python3 fixed-vm.py --repo /path/to/duo-updater --work /tmp/duo2055vm-run
Requires Xcode/Swift, ARM Brew with its official cask tap, and (for dual-prefix
coverage) an existing separate Intel Brew plus Rosetta. Never run on the host.
"""
import argparse
import hashlib
import fcntl
import re
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tarfile
import time

TOKENS = ['fullcomma', 'fullcolon', 'old', 'new', 'pin', 'var', 'intel', 'thirdintel']
LABELS = dict(fullcomma='FullComma', fullcolon='FullColon', old='Old', pin='Pin',
              var='Var', intel='Intel', thirdintel='ThirdIntel')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--work', type=Path, required=True)
    a = ap.parse_args()
    # All mutation requires both macOS Virtual Machine hardware and explicit paths.
    model = subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True).strip()
    if not model.startswith('VirtualMac'):
        raise SystemExit('Refusing: this runner only mutates VirtualMac guests, never the host.')
    repo, work = a.repo.resolve(), a.work.resolve()
    if work.exists() or work.parent != Path('/private/tmp') or not re.fullmatch(r'duo2055vm-[A-Za-z0-9_-]+',work.name):
        raise SystemExit('Use a new /tmp/duo2055vm-* work directory.')
    lock = open('/tmp/duo2055vm-validation.lock','a')
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError: raise SystemExit('Another fixed-state VM runner is active.')
    arm = Path('/opt/homebrew/bin/brew')
    intel = Path('/usr/local/bin/brew')
    if not arm.exists() or not intel.exists():
        raise SystemExit('Both existing ARM and Intel Brew installations are required.')
    tap = Path('/opt/homebrew/Library/Taps/homebrew/homebrew-cask')
    intap = Path('/usr/local/Homebrew/Library/Taps/homebrew/homebrew-cask')
    custom = Path('/opt/homebrew/Library/Taps/duo2055vm/homebrew-fixture')
    incustom = Path('/usr/local/Homebrew/Library/Taps/duo2055vm/homebrew-fixture')
    paths = [custom, incustom]
    for root in [tap, intap]:
        if not (root/'cask_renames.json').is_file():
            raise SystemExit('Missing existing cask tap: '+str(root))
        paths += [root/'Casks/d'/('duo2055vm-'+n+'.rb') for n in TOKENS]
    paths += [Path(root)/('duo2055vm-'+n) for root in ['/opt/homebrew/Caskroom', '/usr/local/Caskroom'] for n in TOKENS]
    paths += [Path('/Applications')/('Duo2055VM'+label+'.app') for label in LABELS.values()]
    paths += [Path('/opt/homebrew/Cellar/duo2055vm-formula')]
    for p in paths:
        if p.exists() or p.is_symlink():
            raise SystemExit('Refusing to reuse preexisting fixture state: '+str(p))
    work.mkdir()
    evidence = work/'evidence'; evidence.mkdir()
    env = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE='1', HOMEBREW_NO_INSTALL_FROM_API='1',
               HOMEBREW_NO_INSTALL_CLEANUP='1', HOMEBREW_NO_ENV_HINTS='1')
    # Login-shell overrides are deliberately only supplied by a temporary rc edit.
    env.pop('HOMEBREW_AUTO_UPDATE_SECS', None)
    modified = {}
    installed = []
    count = 0
    def run(args, name=None, check=True, extra=None):
        nonlocal count
        count += 1
        r = subprocess.run([str(x) for x in args], env=env if extra is None else extra,
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        label = name or ('command-%03d' % count)
        (evidence/(label+'.log')).write_text('command: '+repr([str(x) for x in args])+'\nexit: '+str(r.returncode)+'\n'+r.stdout)
        print(label, 'exit', r.returncode, flush=True)
        if check and r.returncode:
            raise RuntimeError(label+' failed:\n'+r.stdout[-8000:])
        return r
    def brew(*args, x86=False, **kw):
        return run((['/usr/bin/arch','-x86_64',intel] if x86 else [arm])+list(args), **kw)
    def edit(p, data):
        if p not in modified:
            modified[p] = [p.read_bytes() if p.exists() else None, None]
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        modified[p][1] = data
    def make_archive(name, short, build):
        app = 'Duo2055VM'+LABELS[name]+'.app'
        d = work/'payloads'/(name+'-'+build)/app
        (d/'Contents/MacOS').mkdir(parents=True)
        (d/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='org.duo2055vm.'+name,
            CFBundleName=app[:-4], CFBundleShortVersionString=short, CFBundleVersion=build,
            CFBundleExecutable='main', CFBundlePackageType='APPL')))
        exe=d/'Contents/MacOS/main'; exe.write_text('#!/bin/sh\nexit 0\n'); exe.chmod(0o755)
        archive=work/(name+'-'+build+'.tar.gz')
        with tarfile.open(archive,'w:gz') as t: t.add(d,arcname=app)
        return app, archive
    def cask(token, app, archive, version, variation_archive=None):
        return (f'cask "{token}" do\n  version "{version}"\n  sha256 "{hashlib.sha256(archive.read_bytes()).hexdigest()}"\n'
                f'  url "file://{archive}"\n  name "{app[:-4]}"\n  desc "Disposable issue 2055 VM fixture"\n'
                '  homepage "https://example.com"\n'+(f'  on_arm do\n    version "1.0"\n    url "file://{variation_archive}"\n    sha256 "{hashlib.sha256(variation_archive.read_bytes()).hexdigest()}"\n  end\n' if variation_archive else '')+
                f'  app "{app}"\nend\n').encode()
    result = {'passed':False, 'model':model}
    try:
        run(['/usr/bin/git','-C',repo,'rev-parse','HEAD'], 'source-commit')
        run(['/usr/bin/sw_vers'], 'system')
        brew('--version', name='brew-version')
        brew('--prefix', x86=True, name='intel-prefix')
        # Build only in the VM. Keep the repository's dependency lockfile.
        core=work/'core'
        shutil.copytree(repo/'DuoUpdaterCore', core, ignore=shutil.ignore_patterns('.build','.git'))
        probe=core/'Sources/FixedVMProbe';probe.mkdir()
        shutil.copy2(repo/'verify/issue-2055/FixedVMProbe.swift', probe/'main.swift')
        manifest=core/'Package.swift';s=manifest.read_text()
        marker='        .testTarget('
        if marker not in s: raise RuntimeError('Core manifest target marker changed')
        manifest.write_text(s.replace(marker,'        .executableTarget(name: "FixedVMProbe", dependencies: ["DuoUpdaterCore"]),\n'+marker,1))
        run(['/usr/bin/xcrun','swift','build','--package-path',core,'--force-resolved-versions','--product','FixedVMProbe','-Xswiftc','-enable-testing'], 'build-probe')
        binary=core/'.build/debug/FixedVMProbe'
        if not binary.is_file(): raise RuntimeError('Missing built probe')
        entries=[]
        # ARM fixtures use real official installation receipts, then change only
        # the cask definition to advertise a newer payload.
        for name in ['fullcomma','fullcolon','old','pin','var']:
            token='duo2055vm-'+name
            app, oldarc=make_archive(name,'1.0','101')
            _, newarc=make_archive(name,'1.0' if name.startswith('full') else '2.0','102')
            oldver={'fullcomma':'1.0,101','fullcolon':'1.0:101'}.get(name,'1.0')
            newver={'fullcomma':'1.0,102','fullcolon':'1.0:102'}.get(name,'2.0')
            path=tap/'Casks/d'/(token+'.rb')
            edit(path,cask(token,app,oldarc,oldver))
            brew('install','--cask',token, name='install-'+name)
            installed.append((token,False))
            newtoken='duo2055vm-new' if name=='old' else token
            newpath=tap/'Casks/d'/(newtoken+'.rb')
            edit(newpath,cask(newtoken,app,newarc,newver,variation_archive=oldarc if name=='var' else None))
            if name=='old':
                # Keep the existing old receipt/path untouched. Only rename the
                # current tap definition, as a real upstream rename does.
                path.unlink();modified[path][1]=None
                rename=tap/'cask_renames.json';j=json.loads(rename.read_bytes());j[token]=newtoken
                edit(rename,json.dumps(j).encode())
            entry=dict(token=newtoken,version=newver,url='file://'+str(newarc),artifacts=[{'app':[app]}],old_tokens=[token] if name=='old' else [])
            if name=='var':
                # Intentionally wrong base fields; all four resolved fields
                # must come from the same ARM variation.
                entry.update(url='file:///wrong-platform.tar.gz',artifacts=[{'app':['WrongPlatform.app']}],depends_on={'macos':{'>=':['99']}})
                entry['variations']={'arm64_golden_gate':dict(version='1.0',url='file://'+str(oldarc),artifacts=[{'app':[app]}],depends_on={'macos':{'>=':['15']}})}
            entries.append(entry)
        brew('pin','--cask','duo2055vm-pin',name='pin-cask')
        # Formula checksum is real; its executable contents are valid shell.
        (custom/'Formula').mkdir(parents=True)
        run(['/usr/bin/git','init',custom], 'init-formula-tap')
        source=work/'formula-source';source.mkdir();(source/'hello').write_text('#!/bin/sh\nprintf "fixture\\n"\n')
        archive=work/'formula.tar.gz'
        with tarfile.open(archive,'w:gz') as t:t.add(source,arcname='src')
        fp=custom/'Formula/duo2055vm-formula.rb'
        formula=f'class Duo2055vmFormula < Formula\n desc "VM fixture"\n homepage "https://example.com"\n url "file://{archive}"\n version "1.0"\n sha256 "{hashlib.sha256(archive.read_bytes()).hexdigest()}"\n def install\n bin.install "hello"\n end\nend\n'
        fp.write_text(formula);brew('install','duo2055vm/fixture/duo2055vm-formula',name='install-formula');installed.append(('duo2055vm-formula',False))
        fp.write_text(formula.replace('version "1.0"','version "2.0"'));brew('pin','duo2055vm-formula',name='pin-formula')
        # Separate real Intel-prefix records: one official and one third-party.
        for name in ['intel','thirdintel']:
            app, archive=make_archive(name,'1.0','101');token='duo2055vm-'+name
            root=intap if name=='intel' else incustom
            folder=root/'Casks/d';folder.mkdir(parents=True,exist_ok=True)
            if name=='thirdintel':run(['/usr/bin/git','init',root], 'init-intel-third-party-tap')
            edit(folder/(token+'.rb'),cask(token,app,archive,'1.0'))
            qualified=token if name=='intel' else 'duo2055vm/fixture/'+token
            brew('install','--cask',qualified,x86=True,name='install-'+name);installed.append((qualified,True))
            entries.append(dict(token=token,version='2.0',url='file://'+str(archive),artifacts=[{'app':[app]}]))
        (work/'catalog.json').write_text(json.dumps(entries))
        variation_info=brew('info','--cask','--json=v2','duo2055vm-var',name='actual-platform-info')
        actual=json.loads(variation_info.stdout)['casks'][0]
        if actual['version']!='1.0' or not actual['url'].endswith('/var-101.tar.gz'):
            raise RuntimeError('Real Brew ARM variation differs from injected catalog fixture')
        for kind in ['formula','cask']:
            r=brew('outdated','--'+kind,'--json=v2',name='outdated-'+kind)
            (work/(kind+'-outdated.json')).write_text(r.stdout)
        run([binary,work,'initial'], 'probe-initial')
        # Positive unpin control proves the earlier lack of an action is pin
        # handling, not a fixture/catalog miss.
        brew('unpin','--cask','duo2055vm-pin',name='unpin-cask')
        run([binary,work,'unpinned'], 'probe-unpinned')
        brew('upgrade','--cask','duo2055vm-fullcomma','duo2055vm-fullcolon',name='upgrade-full-versions')
        run([binary,work,'upgraded'], 'probe-upgraded')
        # An unowned copy with identical filename must not be adopted.
        negative=work/'unowned/Duo2055VMOld.app';negative.parent.mkdir()
        shutil.copytree('/Applications/Duo2055VMOld.app',negative)
        run([binary,work,'unowned'], 'probe-unowned')
        # Official source must not adopt a receipt whose originating tap differs.
        receipt=Path('/opt/homebrew/Caskroom/duo2055vm-old/.metadata/INSTALL_RECEIPT.json')
        before=receipt.read_bytes();j=json.loads(before);j['source']['tap']='duo2055vm/fixture';receipt.write_text(json.dumps(j))
        try: run([binary,work,'other-tap'], 'probe-other-tap')
        finally: receipt.write_bytes(before)
        # Foreign-prefix refusal must happen before either ownership record or
        # the installed app is changed, for detection and real fetch/upgrade.
        run([binary,work,'foreign'], 'probe-foreign-prefix')
        # LaunchServices environment starts without exports inherited from our
        # CLI. The rc file has guarded backup/restore and no preexisting content
        # is discarded. brew.env remains untouched.
        for p in [Path.home()/'.config/homebrew/brew.env',Path('/opt/homebrew/etc/homebrew/brew.env'),Path('/etc/homebrew/brew.env')]:
            if p.exists(): raise RuntimeError('Environment scenario requires no existing brew.env: '+str(p))
        rc=Path.home()/'.zshrc';old=rc.read_bytes() if rc.exists() else b''
        edit(rc,old+b'\nexport HOMEBREW_NO_AUTO_UPDATE=1\nexport HOMEBREW_AUTO_UPDATE_SECS=2055\n')
        logger=work/'brew-log';logger.write_text('#!/bin/sh\nprintf "%s|%s|%s\\n" "$*" "${HOMEBREW_NO_AUTO_UPDATE-unset}" "${HOMEBREW_AUTO_UPDATE_SECS-unset}" >> '+str(work/'env-commands.txt')+'\nprintf "{}\\n"\n');logger.chmod(0o755)
        app=work/'EnvProbe.app/Contents';(app/'MacOS').mkdir(parents=True)
        shutil.copy2(binary,app/'MacOS/FixedVMProbe')
        (app/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='org.duo2055vm.env',CFBundleExecutable='FixedVMProbe',CFBundlePackageType='APPL',LSUIElement=True)))
        run(['/usr/bin/codesign','--force','--sign','-',app.parent], 'sign-env-probe')
        run(['/usr/bin/open','-n',app.parent,'--args',work,'env'], 'launch-env-probe')
        deadline=time.monotonic()+30
        while not (work/'env-result.json').exists() and time.monotonic()<deadline:time.sleep(.2)
        if not (work/'env-result.json').exists():raise RuntimeError('GUI environment probe did not finish')
        data=json.loads((work/'env-result.json').read_text())
        if not data.get('passed'):raise RuntimeError('GUI environment assertions failed: '+str(data))
        shutil.copy2(work/'env-result.json',evidence/'env-result.json');shutil.copy2(work/'env-commands.txt',evidence/'env-commands.txt')
        result['passed']=True
    except BaseException as error:
        result['failure']=str(error)
        print('FAILED',str(error),flush=True)
    finally:
        # Always attempt all own package cleanups before restoring definitions.
        cleanup=[]
        for token,x86 in reversed(installed):
            try:
                brew('unpin',token,x86=x86,check=False)
                r=brew('uninstall','--cask' if token!='duo2055vm-formula' else '--formula',token,x86=x86,check=False)
                cleanup.append([token,r.returncode])
                if r.returncode:
                    result['passed']=False;result.setdefault('cleanup_errors',[]).append('Brew uninstall failed: '+token)
            except Exception as error:
                cleanup.append([token,str(error)]);result['passed']=False;result.setdefault('cleanup_errors',[]).append('Brew cleanup exception: '+token)
        for p,(old,ours) in reversed(list(modified.items())):
            current=p.read_bytes() if p.exists() else None
            if current!=ours:
                result['passed']=False;result.setdefault('cleanup_errors',[]).append('Concurrent change: '+str(p));continue
            if old is None:
                if p.exists():p.unlink()
            else:p.write_bytes(old)
        # Homebrew can leave the old-token directory alias after migration.
        # Every path below was proven absent before this run.
        for root in ['/opt/homebrew/Caskroom','/usr/local/Caskroom']:
            for n in TOKENS:
                p=Path(root)/('duo2055vm-'+n)
                if p.is_symlink():p.unlink()
                elif p.exists():shutil.rmtree(p)
        for p in [custom,incustom]:
            if p.exists():shutil.rmtree(p)
        result['cleanup']=cleanup
        (evidence/'result.json').write_text(json.dumps(result,indent=2))
        print(json.dumps(result,indent=2),flush=True)
    return 0 if result['passed'] else 1

if __name__=='__main__':sys.exit(main())
