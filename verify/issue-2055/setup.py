import pathlib,subprocess,os,tarfile,json,shutil
p=pathlib.Path('/tmp/duo-2055');p.mkdir(exist_ok=True)
brew='/opt/homebrew/bin/brew'
env=dict(os.environ,HOMEBREW_NO_AUTO_UPDATE='1',HOMEBREW_NO_INSTALL_FROM_API='1',HOMEBREW_NO_INSTALL_CLEANUP='1')
tap=pathlib.Path('/opt/homebrew/Library/Taps/homebrew/homebrew-cask');casks=tap/'Casks/d';casks.mkdir(exist_ok=True)
entries=[]
def run(*args):
 r=subprocess.run([brew,*args],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);print('COMMAND',args,'EXIT',r.returncode,'\n'+r.stdout,flush=True);return r
for name,label in [('full','Full'),('old','Old'),('pin','Pin'),('intel','Intel'),('var','Var')]:
 token='duo-2055-'+name;app='Duo2055'+label+'.app';d=p/app; (d/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
 import plistlib
 (d/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='org.duo2055.'+token,CFBundleName=app[:-4],CFBundleShortVersionString='1.0',CFBundleVersion='101',CFBundleExecutable='main',CFBundlePackageType='APPL')))
 exe=d/'Contents/MacOS/main';exe.write_text('#!/bin/sh\nexit 0\n');exe.chmod(0o755)
 archive=p/(token+'.tar.gz')
 with tarfile.open(archive,'w:gz') as t:t.add(d,arcname=app)
 version='1.0,101' if name=='full' else '1.0'
 def cask(ver,tok=token):return f'''cask "{tok}" do
  version "{ver}"
  sha256 :no_check
  url "file://{archive}"
  name "Duo2055{label}"
  desc "Disposable issue 2055 fixture"
  homepage "https://example.com"
  app "{app}"
end
'''
 path=casks/(token+'.rb');path.write_text(cask(version))
 if name!='intel':run('install','--cask',token)
 else:(p/'intel.rb').write_text(cask(version))
 new='1.0,102' if name=='full' else '2.0'
 if name=='old':
  path.unlink();path=casks/'duo-2055-new.rb';path.write_text(cask('2.0','duo-2055-new'))
  rename=tap/'cask_renames.json';shutil.copy2(rename,p/'cask_renames.original.json');ren=json.loads(rename.read_text());ren[token]='duo-2055-new';rename.write_text(json.dumps(ren))
 elif name=='var':path.write_text(cask('2.0').replace('  app ', '  on_arm do\n    version "1.0"\n  end\n  app '))
 elif name!='intel':path.write_text(cask(new))
 entries.append(dict(token='duo-2055-new' if name=='old' else token,version=new,url='file://'+str(archive),artifacts=[dict(app=[app])],old_tokens=[token] if name=='old' else [],variations={'arm64_sequoia':{'version':'1.0'},'arm64_tahoe':{'version':'1.0'}} if name=='var' else {}))
run('pin','--cask','duo-2055-pin')
(p/'catalog.json').write_text(json.dumps(entries))
# A genuine local formula install, subsequently bumped and pinned.
fdir=pathlib.Path('/opt/homebrew/Library/Taps/duo2055/homebrew-test/Formula');fdir.mkdir(parents=True,exist_ok=True)
subprocess.run(['git','init',str(fdir.parent)],stdout=subprocess.DEVNULL)
fd=p/'formula-src';fd.mkdir(exist_ok=True);(fd/'hello').write_text('fixture\n')
fa=p/'formula.tar.gz'
with tarfile.open(fa,'w:gz') as t:t.add(fd,arcname='src')
f=fdir/'duo-2055-formula.rb'
s=f'''class Duo2055Formula < Formula
 desc "Issue 2055 fixture"
 homepage "https://example.com"
 url "file://{fa}"
 version "1.0"
 sha256 :no_check
 def install
   bin.write_exec_script buildpath/"hello"
 end
end
''';f.write_text(s);run('install','--formula','duo2055/test/duo-2055-formula');f.write_text(s.replace('version "1.0"','version "2.0"'));run('pin','duo-2055-formula')
for kind in ['formula','cask']:
 r=run('outdated','--'+kind,'--json=v2');(p/(kind+'-outdated.json')).write_text(r.stdout)
run('upgrade','--formula','--dry-run','duo-2055-formula');run('upgrade','--cask','--dry-run','duo-2055-pin');run('info','--cask','--json=v2','duo-2055-new','duo-2055-var')
