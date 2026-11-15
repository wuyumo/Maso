#!/usr/bin/env python3
"""Prepare a fail-closed remote catalog from the app's adopted IDs and hashes.
D1 export is read-only evidence; never infer ownership from version or timestamps.
"""
import argparse, hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--d1-export', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
app = json.loads((ROOT/'Maso/Resources/CoreExerciseDemos/catalog.json').read_text())
revoked = set(json.loads((ROOT/'Maso/Resources/CoreExerciseDemos/revoked.json').read_text()))
raw = json.loads(a.d1_export.read_text())
rows = raw[0]['results']
index = {(r['exercise_id'], r['sha256']): r for r in rows}
assert len(index) == len(rows), 'Duplicate ID/SHA pairs require review'
assets = []
for entry in app:
    eid, sha = entry['exerciseId'], entry['sha256']
    assert entry.get('status') == 'ready' and sha not in revoked
    row = index.get((eid, sha))
    assert row is not None and row['bytes'] == entry['bytes'], f'Unpublished or mismatched exact version: {eid}'
    expected = f'/v1/exercise-demos/video/{sha}'
    assert entry['videoPath'] == expected
    kind = 'gif' if row['blob_key'].lower().endswith('.gif') else 'video'
    assert entry.get('mediaType', 'video') == kind, f'Media type mismatch: {eid}'
    assets.append({k: v for k,v in {'exerciseId': eid, 'status': 'ready', 'sha256': sha,
        'bytes': row['bytes'], 'videoPath': expected, 'mediaType': kind,
        'verification': entry.get('verification')}.items() if v is not None})
assert len({x['exerciseId'] for x in assets}) == len(assets)
content = (json.dumps({'version': 1, 'assets': assets}, ensure_ascii=False, separators=(',', ':'))+'\n').encode()
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_bytes(content)
print(f'Prepared {len(assets)} exact adopted versions; sha256={hashlib.sha256(content).hexdigest()}')
