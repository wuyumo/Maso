#!/usr/bin/env python3
"""Derive bundled list posters from SHA-verified adopted video sources."""
import hashlib, importlib.util, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('ledger',ROOT/'scripts/exercise_media_ledger.py')
ledger=importlib.util.module_from_spec(spec);spec.loader.exec_module(ledger)
data,sources=ledger.build()
records=[];missing=[]
for row in data['rows']:
 video=row['video']
 if not video: continue
 source=sources.get(video['sha256'])
 if not source:
  missing.append(row['id']);continue
 assert hashlib.sha256(source.read_bytes()).hexdigest()==video['sha256'],row['id']
 target=ROOT/'Maso/Resources/CoreExerciseDemos'/(row['id']+'.jpg')
 subprocess.run(['ffmpeg','-v','error','-y','-i',str(source),'-frames:v','1','-vf','scale=360:360:force_original_aspect_ratio=decrease','-q:v','3',str(target)],check=True)
 records.append({'exerciseId':row['id'],'source':str(source),'sourceSHA256':video['sha256'],'poster':str(target.relative_to(ROOT)),'posterSHA256':hashlib.sha256(target.read_bytes()).hexdigest(),'derivation':'first decoded frame, ffmpeg; adopted source unchanged'})
poster_map={row['exerciseId']:row['sourceSHA256'] for row in records}
(ROOT/'Maso/Resources/CoreExerciseDemos/poster-catalog.json').write_text(json.dumps(poster_map,ensure_ascii=False,indent=2)+'\n')
out=ROOT/'docs/exercise-list-posters-2026-11-03/import-manifest.json'
out.write_text(json.dumps({'posters':records,'unavailableLocalSources':missing},indent=2)+'\n')
print(f'Generated {len(records)} SHA-bound posters; {len(missing)} sources unavailable locally')
