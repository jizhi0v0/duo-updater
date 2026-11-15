#!/usr/bin/env python3
"""Verify real coordinator outcomes, stored download kinds and Delta evidence."""
from pathlib import Path
import json, os, subprocess

root = Path.home() / 'duo-verify/electron-blockmap-20261115/delta-ledger'
root.mkdir(parents=True, exist_ok=True)
state = root / 'state'
assert not state.exists(), 'the full-download control needs a fresh state directory'
versions = json.loads((Path.home() / 'Desktop/flyenv-versions.json').read_text())
app = Path.home() / 'Applications/DuoBlockmap/FlyEnv/FlyEnv.app'
assert app.exists()
receipts = []
for index, row in enumerate(versions):
    output = root / (row['version'] + '-result.json')
    data = {
        'name': 'FlyEnv ' + row['version'], 'appPath': str(app),
        'downloadURL': row['zip']['url'], 'mapURL': row['map']['url'],
        'downloadSize': row['zip']['size'],
        'sha256': row['zip']['digest'].removeprefix('sha256:'),
        'version': row['version'], 'outputPath': str(output),
        'launch': False, 'useCoordinator': True,
    }
    input_path = root / (row['version'] + '-input.json')
    input_path.write_text(json.dumps(data, indent=2))
    run = subprocess.run(
        [str(Path.home() / 'Desktop/blockmap-verify-delta'), str(input_path)],
        env=dict(os.environ, DUO_STATE_DIR=str(state)), capture_output=True, timeout=900)
    (root / (row['version'] + '.log')).write_bytes(run.stdout + run.stderr)
    assert run.returncode == 0, run.stdout.decode(errors='replace') + run.stderr.decode(errors='replace')
    receipt = json.loads(output.read_text())
    assert receipt['installedVersion'] == row['version']
    assert receipt['usedDelta'] == (index == 1)
    assert receipt['ledgerDownloadKind'] == ('delta' if index == 1 else 'full')
    assert receipt['deltaBadge'] == (index == 1)
    if index == 0:
        assert receipt['bytesDownloaded'] >= row['zip']['size']
    else:
        assert receipt['bytesDownloaded'] < row['zip']['size']
    receipts.append(receipt)
    print(json.dumps(receipt), flush=True)
(root / 'results.json').write_text(json.dumps(receipts, indent=2) + '\n')
