#!/usr/bin/env python3
"""Pull adapter only. Bring a real renderer; this script never fabricates exercise video."""
import argparse,json,os,subprocess,tempfile,threading,urllib.request,urllib.error,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--renderer',required=True,help='Executable: renderer job.json output.mp4');p.add_argument('--once',action='store_true');args=p.parse_args()
if not args.base.startswith('https://'):p.error('HTTPS required')
renderer=Path(args.renderer).resolve()
if not renderer.is_file() or not os.access(renderer,os.X_OK):p.error('A real executable renderer is required before claiming jobs')
token=os.environ.get('MASSO_GPU_TOKEN','')
if len(token)<32:p.error('Set MASSO_GPU_TOKEN in this process environment; do not put it in arguments')
base=args.base.rstrip('/')+'/v1/exercise-demos'
def request(path,data=None,claim=None,raw=None):
 headers={'Authorization':'Bearer '+token}
 if claim:headers['X-Demo-Claim']=claim
 if data is not None:raw=json.dumps(data).encode();headers['Content-Type']='application/json'
 if raw is not None:headers['Content-Length']=str(len(raw))
 req=urllib.request.Request(base+path,data=raw,headers=headers,method='POST')
 with urllib.request.urlopen(req,timeout=60) as r:return json.load(r)
while True:
 job=request('/internal/claim',{})
 if not job.get('jobId'):
  if args.once:break
  time.sleep(30);continue
 jid=job['jobId'];claim=job['claimToken'];stop=threading.Event()
 def heartbeat():
  while not stop.wait(60):
   try:request('/internal/jobs/'+jid+'/heartbeat',{},claim)
   except Exception:stop.set()
 t=threading.Thread(target=heartbeat,daemon=True);t.start()
 try:
  with tempfile.TemporaryDirectory(prefix='masso-demo-') as folder:
   folder=Path(folder);spec=folder/'job.json';video=folder/'output.mp4'
   spec.write_text(json.dumps(job,ensure_ascii=False,indent=2))
   subprocess.run([str(renderer),str(spec),str(video)],check=True,timeout=3600)
   if stop.is_set():raise RuntimeError('Lease heartbeat failed; stop rendering and do not publish')
   if not video.is_file() or not 1024<=video.stat().st_size<=25*1024*1024:raise RuntimeError('Invalid output size')
   info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(video)]))
   streams=info.get('streams',[]);v=next(s for s in streams if s['codec_type']=='video')
   if v['width']!=1280 or v['height']!=1280 or v['codec_name'] not in ('h264','hevc') or not 1<=float(info['format']['duration'])<=30:raise RuntimeError('Output does not meet square video contract')
   if any(s['codec_type']=='audio' for s in streams):raise RuntimeError('Demo must not contain audio')
   request('/internal/jobs/'+jid+'/upload',claim=claim,raw=video.read_bytes())
   print(jid,'uploaded for HUMAN REVIEW; not published or charged')
 except Exception as e:
  print(jid,'failed:',type(e).__name__)
  try:request('/internal/jobs/'+jid+'/fail',{},claim)
  except Exception:pass # Expiry releases the reservation even after a lost connection.
 finally:stop.set();t.join(timeout=2)
 if args.once:break
