#!/usr/bin/env python3
"""Cold full install, then a genuine 4.20.1 -> 4.20.2 production blockmap update."""
from pathlib import Path
import json,os,subprocess,urllib.request,hashlib
root=Path.home()/'duo-verify/electron-blockmap-20261115/FlyEnv'
root.mkdir(parents=True,exist_ok=True)
versions=json.loads((Path.home()/'Desktop/flyenv-versions.json').read_text())
old=root/'bootstrap-4.20.1.zip'
if not old.exists():
 with urllib.request.urlopen(versions[0]['zip']['url'],timeout=60) as r,old.open('wb') as f:
  while True:
   b=r.read(1024*1024)
   if not b:break
   f.write(b)
assert hashlib.sha256(old.read_bytes()).hexdigest()==versions[0]['zip']['digest'].removeprefix('sha256:')
base=root/'bootstrap';base.mkdir(exist_ok=True)
if not (base/'FlyEnv.app').exists():subprocess.run(['/usr/bin/ditto','-x','-k',str(old),str(base)],check=True)
app=Path.home()/'Applications/DuoBlockmap/FlyEnv/FlyEnv.app'
app.parent.mkdir(parents=True,exist_ok=True)
if not app.exists():subprocess.run(['/usr/bin/ditto',str(base/'FlyEnv.app'),str(app)],check=True)
state=root/'duo-state';env=dict(os.environ,DUO_STATE_DIR=str(state));receipts=[]
assert not (state/'Caches/com.duoupdater.installers').exists(),'cold test needs its own unused state directory'
for row in versions:
 inp={'name':'FlyEnv '+row['version'],'appPath':str(app),'downloadURL':row['zip']['url'],'mapURL':row['map']['url'],
  'downloadSize':row['zip']['size'],'sha256':row['zip']['digest'].removeprefix('sha256:'),'version':row['version'],
  'outputPath':str(root/(row['version']+'-install.json')),'launch':False}
 inputfile=root/(row['version']+'-input.json');inputfile.write_text(json.dumps(inp,indent=2))
 p=subprocess.run([str(Path.home()/'Desktop/blockmap-verify-v2'),str(inputfile)],capture_output=True,env=env,timeout=900)
 (root/(row['version']+'-install.log')).write_bytes(p.stdout+p.stderr)
 assert p.returncode==0,p.stdout.decode(errors='replace')+p.stderr.decode(errors='replace')
 receipt=json.loads(Path(inp['outputPath']).read_text());receipts.append(receipt)
 assert receipt['archiveSHA256']==inp['sha256'],'target whole-archive hash differs'
 print(json.dumps(receipt),flush=True)
 assert list((state/'Caches/com.duoupdater.installers').glob('*/archive.zip')),'successful install did not seed the next update cache'
assert receipts[0]['bytesDownloaded']>=versions[0]['zip']['size'],'cold cache unexpectedly skipped the full archive'
assert receipts[1]['bytesDownloaded']<versions[1]['zip']['size'],'next update did not save network bytes'
assert receipts[1]['downloadedArchive']=='electron-update.zip','next update did not reconstruct from ranges'
(root/'results.json').write_text(json.dumps(receipts,indent=2))
print(json.dumps({'fullBytes':versions[1]['zip']['size'],'actualBytesIncludingMap':receipts[1]['bytesDownloaded'],'savingPercent':round(100*(1-receipts[1]['bytesDownloaded']/versions[1]['zip']['size']),2)}),flush=True)
