#!/usr/bin/env python3
"""Publish reviewed App catalog changes after exact D1 and remote-head checks."""
import fcntl, hashlib, json, os, plistlib, subprocess, sys, tempfile, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT/'backend/cloudflare-worker'
STATE = ROOT/'docs/exercise-media-ledger/remote-publication.json'
SOURCE = ROOT/'Maso/Resources/CoreExerciseDemos/catalog.json'
REVOCATIONS = ROOT/'Maso/Resources/CoreExerciseDemos/revoked.json'
OBJECT = 'masso-exercise-demos/exercise-demos/catalog/approved-v1.json'
def digest(b): return hashlib.sha256(b).hexdigest()
def run(args, **kw): return subprocess.run(args, cwd=WORKER, check=True, capture_output=True, **kw)
def verify_changed_assets(current, candidate):
 old = {x['exerciseId']: x for x in current.get('assets', [])}
 changed = [x for x in candidate['assets'] if old.get(x['exerciseId'], {}).get('sha256') != x['sha256']]
 if not changed: return
 info = ROOT/'build/DerivedData-Device/Build/Products/Debug-iphoneos/Maso.app/Info.plist'
 if not info.is_file(): raise RuntimeError('A current device build is needed to verify media delivery')
 config = plistlib.loads(info.read_bytes())
 bases = [config.get(key, '').rstrip('/') for key in ('MasoAIProxyURL', 'MasoAIProxyFallbackURL')
          if config.get(key, '').startswith('https://')]
 token = config.get('MasoClientToken', '')
 if not bases or not token: raise RuntimeError('Media delivery configuration unavailable')
 for item in changed:
  sha = hashlib.sha256(); offset = 0; size = item['bytes']
  while offset < size:
   end = min(offset + 1024*1024 - 1, size - 1)
   # Match ExerciseDemoService: try each configured base for every byte range.
   for base in bases:
    req = urllib.request.Request(base + item['videoPath'], headers={
     'X-Maso-Client-Token': token, 'User-Agent': 'Maso/3 CFNetwork/1568.100.1 Darwin/24.0.0',
     'Range': f'bytes={offset}-{end}'})
    try:
     with urllib.request.urlopen(req, timeout=30) as response:
      data = response.read()
      if response.status == 206 and response.headers.get('Content-Range') == f'bytes {offset}-{end}/{size}' and len(data) == end-offset+1:
       break
    except OSError:
     continue
   else:
    raise RuntimeError(f'Media range unavailable or mismatched: {item["exerciseId"]}')
   sha.update(data); offset += len(data)
  if sha.hexdigest() != item['sha256']: raise RuntimeError(f'Media hash mismatch: {item["exerciseId"]}')
 print(f'Verified {len(changed)} added or changed media files through production delivery')

def main():
 STATE.parent.mkdir(parents=True, exist_ok=True)
 lock_path = Path.home()/'Library/Caches/com.yumowu.maso/remote-catalog.lock'
 lock_path.parent.mkdir(parents=True, exist_ok=True)
 with lock_path.open('a+') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  source_sha=digest(SOURCE.read_bytes()+b'\0'+REVOCATIONS.read_bytes())
  previous=json.loads(STATE.read_text()) if STATE.exists() else None
  if previous and previous.get('sourceSHA256')==source_sha:
   print('REMOTE CATALOG unchanged');return
  with tempfile.TemporaryDirectory(prefix='masso-catalog-') as directory:
   d=Path(directory); exported=d/'d1.json'; current=d/'current.json'; candidate=d/'candidate.json'; verified=d/'verified.json'
   result=run(['wrangler','d1','execute','maso-feedback','--remote','--command','SELECT exercise_id,sha256,bytes,blob_key,published_at FROM demo_assets','--json'])
   exported.write_bytes(result.stdout)
   subprocess.run([sys.executable,str(ROOT/'scripts/prepare_remote_exercise_catalog.py'),'--d1-export',str(exported),'--output',str(candidate)],cwd=ROOT,check=True)
   run(['wrangler','r2','object','get',OBJECT,'--remote','--file',str(current)])
   current_sha=digest(current.read_bytes()); candidate_sha=digest(candidate.read_bytes())
   if current_sha != candidate_sha:
    if not previous or previous.get('publishedSHA256')!=current_sha:
     raise RuntimeError('Remote catalog changed outside this workspace; refusing to overwrite it')
    verify_changed_assets(json.loads(current.read_text()), json.loads(candidate.read_text()))
    if digest(SOURCE.read_bytes()+b'\0'+REVOCATIONS.read_bytes())!=source_sha:
     raise RuntimeError('App catalog changed while preparing publication')
    run(['wrangler','r2','object','put',OBJECT,'--remote','--file',str(candidate),'--content-type','application/json','--cache-control','no-store'])
    run(['wrangler','r2','object','get',OBJECT,'--remote','--file',str(verified)])
    if digest(verified.read_bytes())!=candidate_sha: raise RuntimeError('Published catalog readback differs')
   tmp=STATE.with_suffix('.tmp');tmp.write_text(json.dumps({'sourceSHA256':source_sha,'publishedSHA256':candidate_sha},indent=2)+'\n');os.replace(tmp,STATE)
   print('REMOTE CATALOG verified',candidate_sha)
if __name__=='__main__':
 try: main()
 except Exception as e:
  print('REMOTE CATALOG NOT PUBLISHED:',str(e),file=sys.stderr);sys.exit(1)
