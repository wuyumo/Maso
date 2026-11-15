#!/usr/bin/env python3
"""Read-only App-derived media ledger. No network or credentials in exports."""
from pathlib import Path
from collections import Counter,defaultdict
import argparse,csv,hashlib,html,json,mimetypes,re,threading,urllib.parse
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'docs/exercise-media-ledger'
INPUTS=['Maso/Resources/exercises.json','Maso/Resources/exercise-selection.json','Maso/Resources/CoreExerciseDemos/catalog.json','Maso/Resources/CoreExerciseDemos/revoked.json','Maso/Views/Components/ExerciseImage.swift','Maso/Data/ExerciseDemoService.swift','Maso/Data/ExerciseLibrary.swift','Maso/Resources/zh-Hans.lproj/Localizable.strings','Maso/Data/ExerciseTutorialService.swift','Maso/Views/Screens/PlanPlayerScreen.swift','Maso/Views/Components/ExerciseDemoGeneration.swift','Maso/Views/Components/CrossFadeFrames.swift','Maso/Resources/CoreExerciseDemos/poster-catalog.json']
MUSCLES={'chest':'胸','back':'背','shoulders':'肩','arms':'手臂','core':'核心','legs':'腿','thighs_hips':'大腿／髋','glutes':'臀','calves':'小腿','full_body':'全身','forearms':'前臂','neck':'颈'}
CATEGORIES={'strength':'力量','hypertrophy_focus':'增肌','cardio':'有氧','stretching':'拉伸','mobility':'活动度','plyometric':'爆发力','calisthenics':'自重','flexibility':'柔韧'}
AUDIT=ROOT/'docs/media-audit-2026-10-23/findings.json'
def production_review(rows,audit):
 findings={x['exerciseId']:x for x in audit.get('findings',[])}
 for r in rows:
  f=findings.get(r['id']);valid=bool(f and f['coverBinding']==r['listCover']['urls'] and f.get('videoSHA256')==(r['video']['sha256'] if r['video'] else None))
  flags=list(f['codes']) if valid else [];missing=not r['video'] or (r.get('origin') or {}).get('originalFormat')=='still';common=r['tier'] in ('core','supporting');source=r['defaultMedia']['type']
  reasons=[]
  if source=='youtube_thumbnail':reasons.append('YouTube 封面待升级')
  if source=='legacy_frames' and common:reasons.append('常见双帧待升级')
  if source=='placeholder':reasons.append('缺少图片与视频')
  if flags:reasons.append('封面需处理')
  if f and not valid:reasons.append('素材已变；旧审核失效')
  task='generate_video' if missing else 'cover_only' if flags else 'reuse_adopted'
  r['productionReview']={'task':task,'missingVideo':missing,'commonLegacy':source=='legacy_frames' and common,'coverFlagged':bool(flags),'codes':flags,'note':f['note'] if valid else None,'auditDate':audit.get('date') if valid else None,'staleReview':bool(f and not valid),'reasons':reasons,'rank':None,'rankingType':'编辑估计：App 高频层级优先，其次默认排序；不是实测全市场频率'}
 queue=sorted((r for r in rows if r['productionReview']['missingVideo']),key=lambda r:({'core':0,'supporting':1,'specialist':2}.get(r['tier'],3),r['defaultRank'],r['id']))
 for rank,r in enumerate(queue,1):r['productionReview']['rank']=rank
 return queue
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads((ROOT/p).read_text())
def youtube(url):
 try:
  u=urllib.parse.urlparse(url or '');host=(u.hostname or '').lower();parts=u.path.strip('/').split('/')
  if u.scheme not in ('http','https'):return None
  if host=='youtu.be':id=parts[0]
  elif host=='youtube.com' or host.endswith('.youtube.com'):id=urllib.parse.parse_qs(u.query).get('v',[None])[0] or (parts[1] if len(parts)>=2 and parts[0] in ('embed','shorts','live') else None)
  else:return None
  return id if id and re.fullmatch(r'[A-Za-z0-9_-]{11}',id) else None
 except (ValueError,IndexError):return None

def build():
 exercises=read(INPUTS[0]);selection={x['exerciseID']:x for x in read(INPUTS[1])['entries']};catalog=read(INPUTS[2]);revoked=set(read(INPUTS[3]));swift=(ROOT/INPUTS[4]).read_text()
 tutorial_source=(ROOT/'Maso/Data/ExerciseTutorialService.swift').read_text()
 tutorial_match=re.search(r'static let reviewed: \[String: String\] = \[(.*?)\n    \]',tutorial_source,re.S)
 assert tutorial_match,'Tutorial fallback parser requires review'
 tutorials=dict(re.findall(r'"([^"]+)": "(BV[A-Za-z0-9]{10})"',tutorial_match.group(1)))
 assert not set(tutorials)-{e['id'] for e in exercises},'Unknown tutorial exercise ID'
 # Extract the App's reviewed ownership declarations directly, not a second maintained map.
 match=re.search(r'let reviewed: \[String: String\] = \[(.*?)\n        \]',swift,re.S);assert match,'App ownership parser requires review'
 reviewed=dict(re.findall(r'"([^"]+)": "([^"]+)"',match[1]));retiredmatch=re.search(r'let retired: Set<String> = \[(.*?)\]',swift,re.S);assert retiredmatch
 retired=set(re.findall(r'"([^"]+)"',retiredmatch[1]));groups=defaultdict(list)
 for e in exercises:
  if e.get('imageFolder'):groups[e['imageFolder']].append(e['id'])
 owners={}
 for folder,ids in groups.items():
  if folder in retired:continue
  if reviewed.get(folder) in ids:owners[folder]=reviewed[folder]
  elif len(ids)==1:owners[folder]=ids[0]
 # A renderer-order change must be reviewed rather than silently emitting stale semantics.
 hero=swift.split('struct FullBleedExerciseImage',1)[1].split('// Spotify',1)[0]
 order=['exercise.customImageData','ExerciseDemoService.shared.files','CoreExerciseDemos.thumbnail','ExerciseMediaPolicy.ownsLegacy','ExerciseMediaPolicy.youtubeThumbnail','exercise.photoURL']
 positions=[hero.index(x) for x in order];assert positions==sorted(positions),'Hero fallback policy changed; update ledger resolver'
 player=(ROOT/'Maso/Views/Screens/PlanPlayerScreen.swift').read_text()
 training=player.split('private var backgroundLayer:',1)[1].split('private var trainingMediaBackdrop:',1)[0]
 assert 'contentMode: .fit' in training, 'Workout media sizing changed; review ledger policy'
 assert 'var contentMode: ContentMode = .fill' in hero, 'Detail media sizing changed; review ledger policy'
 listing=swift.split('struct ExerciseImage:',1)[1].split('var body: some View',1)[1].split('private var gradient',1)[0]
 list_order=['customImageData','ExerciseDemoService.shared.files','currentBundledPoster','hasAdoptedMedia','ExerciseMediaPolicy.ownsLegacy','ExerciseMediaPolicy.youtubeThumbnail','else if let photoURL']
 pos=[listing.index(x) for x in list_order];assert pos==sorted(pos),'List fallback policy changed; update ledger resolver'
 ids={x['id'] for x in exercises};assert len(ids)==len(exercises),'Duplicate exercise IDs'
 assert len({x['exerciseId'] for x in catalog})==len(catalog),'Duplicate demo ID'
 assert all(x['exerciseId'] in ids for x in catalog),'Orphan demo ID'
 demos={x['exerciseId']:x for x in catalog};provenance={};manifestpaths=sorted((ROOT/'docs').glob('*/import-manifest.json'))
 for p in manifestpaths:
  data=json.loads(p.read_text())
  if isinstance(data,list):
   for x in data:
    if isinstance(x,dict) and x.get('sha256') and x.get('source'):provenance[x['sha256']]={**x,'manifest':str(p.relative_to(ROOT))}
 families=defaultdict(list)
 for e in exercises:
  sel=selection.get(e['id'],{});family=sel.get('displayFamilyID') or (e.get('nameParts') or {}).get('base') or e['id'];families[family].append(e)
 familylabels={}
 for f,es in families.items():
  representative=min(es,key=lambda e:selection.get(e['id'],{}).get('defaultRank',100000));np=representative.get('nameParts') or {};familylabels[f]=(np.get('localizedBase') or {}).get('zh-Hans') or np.get('base') or f
 equipmentlabels=dict(re.findall(r'^"equipment\.([^"]+)" = "([^"]*)";', (ROOT/INPUTS[7]).read_text(),re.M));equipmentlabels.setdefault('body_only',equipmentlabels.get('bodyweight','徒手'))
 poster_hashes=read('Maso/Resources/CoreExerciseDemos/poster-catalog.json')
 rows=[];localsources={};fingerprintpaths=[ROOT/p for p in INPUTS]+manifestpaths
 for e in exercises:
  id=e['id'];sel=selection.get(id,{});np=e.get('nameParts') or {};family=sel.get('displayFamilyID') or np.get('base') or id;demo=demos.get(id);folder=e.get('imageFolder');owned=folder and owners.get(folder)==id;yt=youtube(e.get('video_url'));thumb=ROOT/'Maso/Resources/CoreExerciseDemos'/f'{id}.jpg'
  legacy=['https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main/exercises/'+urllib.parse.quote(folder,safe='/')+f'/{n}.jpg' for n in (0,1)] if owned else []
  fallback={'type':'legacy_frames','label':'旧双帧图','urls':legacy} if legacy else {'type':'youtube_thumbnail','label':'YouTube 封面','urls':['https://img.youtube.com/vi/'+yt+'/mqdefault.jpg']} if yt else {'type':'project_photo','label':'项目照片','urls':[e['photoURL']]} if e.get('photoURL') else {'type':'placeholder','label':'无可用图片配置','urls':[]}
  default=fallback;cover=fallback;origin=None;issues=[]
  if demo:
   assert demo.get('status')=='ready' and re.fullmatch('[0-9a-f]{64}',demo['sha256']),'Invalid demo metadata'
   assert demo.get('mediaType','video') in ('gif','video','mp4'),'Unknown adopted media type; review the catalog'
   is_gif=demo.get('mediaType')=='gif'
   assert demo['sha256'] not in revoked,'Revoked video is still in catalog'
   assert demo['videoPath']=='/v1/exercise-demos/video/'+demo['sha256'],'Video path/hash mismatch'
   default={'type':'adopted_gif' if is_gif else 'adopted_video','label':'已采用 GIF' if is_gif else '已采用视频','urls':['/video/'+demo['sha256']]}
   if demo.get('verification')=='unverified':default['label']='已采用素材 · 未核实';issues.append('素材未核实，动作或器械可能有误')
   if thumb.exists() and poster_hashes.get(id)==demo['sha256']:cover={'type':'bundled_cover','label':'素材随包封面','urls':['media/covers/'+id+'.jpg']};fingerprintpaths.append(thumb)
   else:
    cover={'type':'placeholder','label':'等待当前素材','urls':[]}
    issues.append('当前素材缺少对应版本的随包封面；列表先显示占位')
   cover=dict(cover, runtimePreferred={'type':'gif_first_frame' if is_gif else 'video_first_frame','sha256':demo['sha256'],'videoPath':demo['videoPath'],'condition':'当前演示已下载且可解码；否则回退此随包封面'})
   source=provenance.get(demo['sha256']);origin={'batch':Path(source['manifest']).parent.name,'manifest':source['manifest'],'originalFile':Path(source.get('originalSource',source['source'])).name,'originalFormat':source.get('originalFormat','mp4'),'atlasId':source.get('sourceExerciseId'),'note':source.get('reviewNote'),'localAvailable':Path(source['source']).is_file()} if source else {'batch':'未记录导入批次','manifest':None,'localAvailable':False}
   if source and source.get('originalFormat') in ('gif','still') and not is_gif:
    default['label']=('已采用静图（兼容播放）' if source['originalFormat']=='still' else '已采用 GIF（兼容播放）') + (' · 未核实' if demo.get('verification')=='unverified' else '')
   if source and Path(source['source']).is_file():localsources[demo['sha256']]=Path(source['source'])
  elif fallback['type']=='project_photo':issues.append('仅记录当前图片地址；原始拍摄／生成出处未记录')
  elif fallback['type']=='placeholder':issues.append('无默认图片配置')
  primary=list(dict.fromkeys(m['major'] for m in e.get('muscles',{}).get('primary',[])))
  rows.append({'id':id,'names':e['name'],'familyId':family,'familyName':familylabels[family],'variation':np.get('variation'),'category':e.get('category'),'categoryName':CATEGORIES.get(e.get('category'),e.get('category')),'primaryMuscles':primary,'primaryMuscleLabels':[MUSCLES.get(m,m) for m in primary],'equipment':e.get('equipment',[]),'equipmentLabels':[equipmentlabels.get(v,v) for v in e.get('equipment',[])],'tier':sel.get('tier','unclassified'),'defaultRank':sel.get('defaultRank',100000),'programmingGroupId':sel.get('programmingGroupID'),'pattern':sel.get('pattern') or e.get('movementPattern'),'defaultMedia':default,'listCover':cover,'fallback':fallback,'video':demo,'origin':origin,'youtubeURL':e.get('video_url'),'bilibiliURL':('https://www.bilibili.com/video/'+tutorials[id]+'/') if id in tutorials else None,'bilibiliSearchURL':'https://search.bilibili.com/video?'+urllib.parse.urlencode({'keyword':re.sub(r'[（）()·]', ' ',e['name'].get('zh-Hans',e['name']['en']))+' 教学'}),'legacyOwner':owners.get(folder) if folder else None,'legacyFolder':folder,'photoURL':e.get('photoURL'),'issues':issues})
 rows.sort(key=lambda r:(r['defaultRank'],r['names'].get('en',''),r['id']))
 audit=json.loads(AUDIT.read_text()) if AUDIT.exists() else {};queue=production_review(rows,audit)
 if AUDIT.exists():fingerprintpaths.append(AUDIT)
 fingerprints={str(p.relative_to(ROOT)):sha(p) for p in sorted(set(fingerprintpaths)) if p.is_file()}
 revision=hashlib.sha256(json.dumps(fingerprints,sort_keys=True).encode()).hexdigest()
 stills=sum((r.get('origin') or {}).get('originalFormat')=='still' for r in rows)
 gifs=sum(r['video'] is not None and r['video'].get('mediaType')=='gif' and (r.get('origin') or {}).get('originalFormat')!='still' for r in rows)
 payload={'schemaVersion':1,'sourceRevision':revision,'scope':'App repository defaults; not individual-device overrides or live server discovery','summary':{'exercises':len(rows),'families':len(families),'adoptedVideos':len(demos)-stills-gifs,'adoptedGIFs':gifs,'adoptedStills':stills,'defaultMediaCounts':dict(Counter(r['defaultMedia']['type'] for r in rows)),'localVideoSources':len(localsources),'missingVideo':len(queue),'commonLegacy':sum(r['productionReview']['commonLegacy'] for r in rows),'coverFlagged':sum(r['productionReview']['coverFlagged'] for r in rows),'staleReviews':sum(r['productionReview']['staleReview'] for r in rows)},'sourceFiles':fingerprints,'rows':rows}
 return payload,localsources

def render(data):
 template=(OUT/'template.html').read_text();return template.replace('/*__LEDGER__*/', 'window.LEDGER='+json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c')+';')
def export(check=False):
 data,_=build();queue=sorted((r for r in data['rows'] if r['productionReview']['missingVideo']),key=lambda r:r['productionReview']['rank']);contents={'catalog.json':json.dumps(data,ensure_ascii=False,indent=2)+'\n','index.html':render(data),'production-queue.json':json.dumps({'sourceRevision':data['sourceRevision'],'rankingType':'App selection tier then defaultRank; editorial estimate, not measured global frequency','excludesAdoptedVideos':data['summary']['adoptedVideos'],'rows':queue},ensure_ascii=False,indent=2)+'\n'}
 import io
 s=io.StringIO();fields=['id','nameZh','nameEn','family','category','muscles','equipment','tier','defaultMedia','cover','sourceURL','sourceBatch','sha256','issues','productionRank','productionTask','reviewReasons','coverReview'];w=csv.DictWriter(s,fieldnames=fields,lineterminator='\n');w.writeheader()
 for r in data['rows']:w.writerow(dict(zip(fields,[r['id'],r['names'].get('zh-Hans'),r['names'].get('en'),r['familyName'],r['categoryName'],' / '.join(r['primaryMuscleLabels']),' / '.join(r['equipment']),r['tier'],r['defaultMedia']['label'],r['listCover']['label'],r['video']['videoPath'] if r['video'] else ' | '.join(r['defaultMedia']['urls']),r['origin']['batch'] if r['origin'] else '',r['video']['sha256'] if r['video'] else '',' / '.join(r['issues']),r['productionReview']['rank'],r['productionReview']['task'],' / '.join(r['productionReview']['reasons']),r['productionReview']['note']])))
 contents['catalog.csv']='\ufeff'+s.getvalue()
 stale=[name for name,body in contents.items() if not (OUT/name).exists() or (OUT/name).read_text()!=body]
 if check:
  for r in data['rows']:
   if r['listCover']['type']=='bundled_cover':
    target=OUT/r['listCover']['urls'][0];original=ROOT/'Maso/Resources/CoreExerciseDemos'/(r['id']+'.jpg')
    if not target.is_file() or sha(target)!=sha(original):stale.append(str(target.relative_to(OUT)))
 if check and stale:raise ValueError('Ledger stale: '+', '.join(stale)+'; run python3 scripts/exercise_media_ledger.py sync')
 if not check:
  import shutil
  covers=OUT/'media/covers';covers.mkdir(parents=True,exist_ok=True)
  expected={r['id']+'.jpg' for r in data['rows'] if r['listCover']['type']=='bundled_cover'}
  for f in covers.glob('*.jpg'):
   if f.name not in expected:f.unlink()
  for name in expected:shutil.copy2(ROOT/'Maso/Resources/CoreExerciseDemos'/name,covers/name)
  for name,body in contents.items():
   p=OUT/name;import tempfile
   with tempfile.NamedTemporaryFile('w',dir=p.parent,encoding='utf-8',delete=False) as f:f.write(body);tmp=Path(f.name)
   tmp.replace(p)
 print(('CHECK' if check else 'SYNC')+' PASS '+json.dumps(data['summary'],ensure_ascii=False));return data

class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_HEAD(self):self.respond(False)
 def do_GET(self):self.respond(True)
 def respond(self,body):
  path=urllib.parse.urlparse(self.path).path
  try:
   if path in ('/','/index.html','/catalog.json'):
    data,_=build();raw=(render(data) if path!='/catalog.json' else json.dumps(data,ensure_ascii=False)).encode();return self.send(raw,'text/html; charset=utf-8' if path!='/catalog.json' else 'application/json',body)
   if path=='/catalog.csv':export();return self.send((OUT/'catalog.csv').read_bytes(),'text/csv; charset=utf-8',body)
   if path=='/production-queue.json':
    data,_=build();rows=sorted((r for r in data['rows'] if r['productionReview']['missingVideo']),key=lambda r:r['productionReview']['rank']);return self.send(json.dumps({'sourceRevision':data['sourceRevision'],'rows':rows},ensure_ascii=False).encode(),'application/json',body,filename='Masso-missing-video-queue.json')
   if path.startswith('/media/covers/'):
    id=Path(path).stem
    if not re.fullmatch('[a-z0-9_]+',id):return self.send_error(404)
    return self.send((ROOT/'Maso/Resources/CoreExerciseDemos'/f'{id}.jpg').read_bytes(),'image/jpeg',body)
   if path.startswith('/video/'):
    digest=path.removeprefix('/video/');data,files=build();file=files.get(digest)
    if not file:return self.send_error(404,'Local adopted source unavailable; no substitute video')
    # Verify once per file identity. Never display an old/changed source under the current hash.
    stamp=(str(file),file.stat().st_mtime_ns,file.stat().st_size,digest)
    if stamp not in VERIFIED:
     if sha(file)!=digest:return self.send_error(409,'Source checksum differs from adopted video')
     VERIFIED.add(stamp)
    size=file.stat().st_size;start=0;end=size-1;header=self.headers.get('Range');status=200
    if header:
     m=re.fullmatch(r'bytes=(\d*)-(\d*)',header)
     if not m:return self.send_error(416)
     if not m[1]:start=max(0,size-int(m[2]))
     else:start=int(m[1]);end=min(int(m[2]) if m[2] else end,end)
     if start>=size or start>end:return self.send_error(416)
     status=206
    match=next((r['video'] for r in data['rows'] if r['video'] and r['video']['sha256']==digest),None)
    if not match:return self.send_error(404)
    mime='image/gif' if match.get('mediaType')=='gif' else 'video/mp4'
    self.send_response(status);self.send_header('Content-Type',mime);self.send_header('Accept-Ranges','bytes');self.send_header('Content-Length',str(end-start+1));self.send_header('Cache-Control','no-store')
    if status==206:self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
    self.end_headers()
    if body:
     with file.open('rb') as f:f.seek(start);self.wfile.write(f.read(end-start+1))
    return
   return self.send_error(404)
  except (BrokenPipeError,ConnectionResetError):pass
  except Exception as e:return self.send_error(500,str(e))
 def send(self,raw,kind,body,filename=None):
  self.send_response(200);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(raw)));self.send_header('Cache-Control','no-store')
  if filename:self.send_header('Content-Disposition',f'attachment; filename="{filename}"')
  self.end_headers()
  if body:self.wfile.write(raw)
VERIFIED=set()
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('command',choices=['sync','check','serve']);p.add_argument('--port',type=int,default=8791);a=p.parse_args()
 if a.command=='serve':
  export();print(f'http://127.0.0.1:{a.port}/',flush=True);ThreadingHTTPServer(('127.0.0.1',a.port),Handler).serve_forever()
 else:
  try:
   export(a.command=='check')
   if a.command=='sync':
    # Publishing only happens when the adopted catalog differs from the last
    # verified publication; failures leave the previous remote snapshot intact.
    import subprocess,sys
    publication=subprocess.run([sys.executable,str(ROOT/'scripts/publish_remote_exercise_catalog.py')],cwd=ROOT)
    if publication.returncode: print('WARNING: remote catalog remains unsynchronized; retry sync after resolving the cause',file=sys.stderr)
  except (AssertionError,ValueError) as e:p.exit(1,str(e)+'\n')
