#!/usr/bin/env python3
"""Apply each compared ZIP with the production installer, preserving VM copies."""
from pathlib import Path
import json,os,re,subprocess,sys,time
root=Path.home()/'duo-verify/electron-blockmap-20261115'
comparisons=json.loads((root/os.environ.get('COMPARISON_FILE','package-comparison.json')).read_text())
results=[]
for row in comparisons:
 if len(sys.argv)>1 and row['name'] not in sys.argv[1:]:continue
 assert row.get('identityCompatible'),row['name']
 slug=re.sub(r'[^A-Za-z0-9._-]+','-',row['name']);folder=root/slug
 source=Path(row['dmgApp']['savedPath'])
 destination=Path.home()/'Applications/DuoBlockmap'/slug/source.name
 destination.parent.mkdir(parents=True,exist_ok=True)
 if not destination.exists():subprocess.run(['/usr/bin/ditto',str(source),str(destination)],check=True)
 asset=row['target']['zip']
 entry={'name':row['name'],'appPath':str(destination),'archivePath':row['zipArchive']['path'],
  'downloadURL':asset['url'],'downloadSize':row['zipArchive']['bytes'],'sha256':row['zipArchive']['sha256'],
  'sha512':asset.get('sha512'),'version':row['zipApp']['shortVersion'],'outputPath':str(folder/'install.json'),'launch':True}
 inputfile=folder/'install-input.json';inputfile.write_text(json.dumps(entry,indent=2))
 env=dict(os.environ,DUO_STATE_DIR=str(root/'duo-state'))
 started=time.time()
 try:
  p=subprocess.run([str(Path.home()/'Desktop/blockmap-verify'),str(inputfile)],capture_output=True,env=env,timeout=240)
  (folder/'install.log').write_bytes(p.stdout+p.stderr)
  result=json.loads((folder/'install.json').read_text()) if (folder/'install.json').exists() else {'name':row['name'],'state':'failed','error':p.stderr.decode(errors='replace')[-2000:]}
  result['exitCode']=p.returncode
 except Exception as e:result={'name':row['name'],'state':'failed','error':str(e)}
 result['elapsedSeconds']=round(time.time()-started,3);results.append(result)
 print(json.dumps(result,ensure_ascii=False),flush=True)
 (root/os.environ.get('RESULTS_FILE','install-results.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2))
print(json.dumps({'finished':len(results),'passed':sum(x['state']=='installed-and-launched' for x in results),'failed':sum(x['state']!='installed-and-launched' for x in results)}),flush=True)
