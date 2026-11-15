#!/usr/bin/env python3
"""Owner-only offline library import. Never give the review token to a renderer."""
import argparse,json,os,subprocess,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--manifest',required=True,help='JSON array: exerciseId, file, approved (human review)');p.add_argument('--apply',action='store_true');args=p.parse_args()
if not args.base.startswith('https://'):p.error('HTTPS required')
manifest=Path(args.manifest).resolve();rows=json.loads(manifest.read_text());token=os.environ.get('MASSO_DEMO_REVIEW_TOKEN','')
if args.apply and len(token)<32:p.error('Set owner-only MASSO_DEMO_REVIEW_TOKEN')
for row in rows:
 if row.get('approved') is not True:print(row.get('exerciseId'),'SKIP: not human-approved');continue
 video=(manifest.parent/row['file']).resolve();size=video.stat().st_size
 if not 1024<=size<=25*1024*1024:raise ValueError('Invalid size: '+row['exerciseId'])
 info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(video)]))
 streams=info['streams'];v=next(s for s in streams if s['codec_type']=='video')
 if v['width']!=v['height'] or not 512<=v['width']<=2048 or v['codec_name'] not in ('h264','hevc') or any(s['codec_type']=='audio' for s in streams):raise ValueError('Invalid media contract: '+row['exerciseId'])
 if not 1<=float(info['format']['duration'])<=30:raise ValueError('Invalid duration')
 if not args.apply:print(row['exerciseId'],'validated; dry run, no upload');continue
 req=urllib.request.Request(args.base.rstrip('/')+'/v1/exercise-demos/internal/import/'+row['exerciseId'],data=video.read_bytes(),method='POST',headers={'Authorization':'Bearer '+token,'Content-Type':'video/mp4','Content-Length':str(size),'X-Demo-Reviewed':'technique,identity,crop,loop'})
 with urllib.request.urlopen(req,timeout=90) as response:print(row['exerciseId'],json.load(response)['status'])
