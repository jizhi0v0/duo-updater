#!/usr/bin/env python3
"""Download and compare each proposed ZIP against its currently selected DMG in the VM."""
from pathlib import Path
import concurrent.futures,hashlib,json,os,plistlib,re,subprocess,urllib.request,urllib.parse,time
root=Path.home()/'duo-verify/electron-blockmap-20261115'
root.mkdir(parents=True,exist_ok=True)
targets=json.loads((Path.home()/'Desktop'/os.environ.get('TARGETS_FILE','migration-targets.json')).read_text())
def run(args,timeout=180):
 p=subprocess.run(args,capture_output=True,timeout=timeout)
 return p.returncode,p.stdout,p.stderr
def download(asset,dest):
 url=asset['url'];u=urllib.parse.urlsplit(url);url=urllib.parse.urlunsplit(u._replace(path=urllib.parse.quote(u.path,safe='/%:@')))
 if not dest.is_file():
  req=urllib.request.Request(url,headers={'User-Agent':'DuoUpdater/0.1','Accept-Encoding':'identity'})
  with urllib.request.urlopen(req,timeout=60) as response,dest.with_suffix(dest.suffix+'.partial').open('wb') as out:
   while True:
    b=response.read(1024*1024)
    if not b:break
    out.write(b)
  dest.with_suffix(dest.suffix+'.partial').rename(dest)
 h=hashlib.sha256()
 with dest.open('rb') as f:
  while True:
   b=f.read(1024*1024)
   if not b:break
   h.update(b)
 if asset.get('size') is not None:assert dest.stat().st_size==asset['size'], 'archive size mismatch'
 if asset.get('digest'):assert asset['digest']=='sha256:'+h.hexdigest(),'GitHub archive digest mismatch'
 if asset.get('sha512'):
  import base64
  h512=hashlib.sha512()
  with dest.open('rb') as f:
   while True:
    b=f.read(1024*1024)
    if not b:break
    h512.update(b)
  assert base64.b64encode(h512.digest()).decode()==asset['sha512'],'manifest sha512 mismatch'
 return {'path':str(dest),'bytes':dest.stat().st_size,'sha256':h.hexdigest()}
def apps_at(base):
 out=[];pending=[(base,0)]
 while pending:
  p,depth=pending.pop()
  if p.is_symlink():continue
  if p.suffix=='.app':out.append(p);continue
  if depth<3:
   try:pending.extend((x,depth+1) for x in p.iterdir() if x.is_dir() and not x.is_symlink())
   except OSError:pass
 return out
def find_app(base,bundle_id):
 found=[]
 for p in apps_at(base):
  try:info=plistlib.loads((p/'Contents/Info.plist').read_bytes())
  except Exception:continue
  if info.get('CFBundleIdentifier')==bundle_id:found.append(p)
 assert len(found)==1, f'expected one {bundle_id}, got {[str(x) for x in found]}'
 return found[0]
def identity(app):
 info=plistlib.loads((app/'Contents/Info.plist').read_bytes());exe=info.get('CFBundleExecutable','')
 assert exe and '/' not in exe
 verify=run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)])
 sig=run(['/usr/bin/codesign','-d','--verbose=4','--arch','arm64',str(app)])
 s=(sig[1]+sig[2]).decode(errors='replace')
 team=re.search(r'^TeamIdentifier=(.*)$',s,re.M);cdhash=re.search(r'^CDHash=(.*)$',s,re.M)
 arch=run(['/usr/bin/lipo','-archs',str(app/'Contents/MacOS'/exe)])
 asar=app/'Contents/Resources/app.asar';ah=None
 if asar.is_file():
  h=hashlib.sha256()
  with asar.open('rb') as f:
   while True:
    b=f.read(1024*1024)
    if not b:break
    h.update(b)
  ah=h.hexdigest()
 return {'path':str(app),'bundleID':info.get('CFBundleIdentifier'),'shortVersion':info.get('CFBundleShortVersionString'),'buildVersion':info.get('CFBundleVersion'),'team':team[1] if team else None,'arm64CDHash':cdhash[1] if cdhash else None,'architectures':arch[1].decode().strip().split(),'codesignExit':verify[0],'codesignError':verify[2].decode(errors='replace')[-2000:],'asarSHA256':ah}
def prepare(t):
 slug=re.sub(r'[^A-Za-z0-9._-]+','-',t['name']);folder=root/slug;folder.mkdir(exist_ok=True)
 receipt={'name':t['name'],'target':t,'startedAt':time.time()}
 try:
  receipt['dmgArchive']=download(t['dmg'],folder/'current.dmg')
  receipt['zipArchive']=download(t['zip'],folder/'target.zip')
  zipdir=folder/'zip';zipdir.mkdir(exist_ok=True)
  if not list(zipdir.iterdir()):
   code,out,err=run(['/usr/bin/ditto','-x','-k',str(folder/'target.zip'),str(zipdir)],timeout=300)
   assert code==0,err.decode(errors='replace')
  zipapp=find_app(zipdir,t['bundleID']);receipt['zipApp']=identity(zipapp)
  mount=folder/'mount';mount.mkdir(exist_ok=True)
  code,out,err=run(['/usr/bin/hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mount),'-plist',str(folder/'current.dmg')],timeout=180)
  assert code==0,err.decode(errors='replace')
  try:
   plist=plistlib.loads(out);receipt['dmgApp']=identity(find_app(mount,t['bundleID']))
   dmgsaved=folder/'dmg-app';dmgsaved.mkdir(exist_ok=True)
   dest=dmgsaved/Path(receipt['dmgApp']['path']).name
   if not dest.exists():
    code,out,err=run(['/usr/bin/ditto',receipt['dmgApp']['path'],str(dest)],timeout=300)
    assert code==0,err.decode(errors='replace')
   receipt['dmgApp']['savedPath']=str(dest)
  finally:run(['/usr/bin/hdiutil','detach',str(mount)],timeout=120)
  a,b=receipt['dmgApp'],receipt['zipApp']
  receipt['identityCompatible']=all(a[k]==b[k] for k in ['bundleID','shortVersion','buildVersion','team']) and a['codesignExit']==b['codesignExit']==0 and 'arm64' in b['architectures']
  receipt['sameArm64CDHash']=a['arm64CDHash']==b['arm64CDHash'] and a['arm64CDHash'] is not None
  receipt['sameAsar']=a['asarSHA256']==b['asarSHA256']
  receipt['state']='packages-compared'
 except Exception as e:receipt['state']='failed';receipt['error']=str(e)
 receipt['finishedAt']=time.time()
 (folder/'packages.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2))
 print(json.dumps({k:receipt.get(k) for k in ['name','state','identityCompatible','sameArm64CDHash','sameAsar','error']},ensure_ascii=False),flush=True)
 return receipt
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
 results=list(ex.map(prepare,targets))
(root/os.environ.get('COMPARISON_FILE','package-comparison.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2))
print(json.dumps({'finished':len(results),'compatible':sum(x.get('identityCompatible') is True for x in results),'failed':sum(x['state']=='failed' for x in results)}),flush=True)
