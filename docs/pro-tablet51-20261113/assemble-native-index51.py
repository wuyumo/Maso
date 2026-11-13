import json,hashlib,pathlib,shutil,zipfile,datetime,zoneinfo
from PIL import Image,ImageDraw
root=pathlib.Path('docs/pro-tablet51-20261113');rows=[]
for x in json.loads(pathlib.Path('docs/pro-red51-20261113/stage1-native-manifest.json').read_text()):
 x=dict(x);x['family']='watch' if '/watch/' in x['source'] else 'iphone';x['scene']=x.get('mode','player-heart-warning');rows.append(x)
for x in json.loads(pathlib.Path('docs/pro-watch51-20261113/native-101100/manifest.json').read_text()):
 x=dict(x);x['family']='watch';x['scene']=x['mode'];x['locale']='zh' if x['locale']=='zh-Hans' else x['locale'];x['reusedAcceptedSource']=True;rows.append(x)
for family in ['ipad','duo']:
 p=root/(family+'-manifest.json')
 if p.exists():
  for x in json.loads(p.read_text()):x=dict(x);x['scene']='player-heart-warning';rows.append(x)
assert len({(x['family'],x['locale'],x['scene']) for x in rows})==len(rows)
for x in rows:
 source=pathlib.Path(x['source']);assert source.exists() and hashlib.sha256(source.read_bytes()).hexdigest()==x['SHA256']
 image=Image.open(source);x['dimensions']=list(image.size);x['exerciseID']='bench_press_machine';x['weightKg']=50;x['reps']=8;x['sets']=3;x['bpm']=x.get('bpm',x.get('heartBpm',185));x['packagePath']='native/'+x['family']+'/'+x['locale']+'/'+x['scene']+'.png';x['physicalSyncProven']=False;x['pixelsEdited']=False
 if x['family']=='watch' and x['locale']=='ru' and x['scene']=='exercise':x['reviewNote']='Full native input Чест-пресс (Тренажёр · машина); visible Чест-пресс (Тренажёр · м… . Main movement and first machine noun readable; redundant synonym tail/closing bracket elided by original single-line UI. No product shortening/translation/layout change.'
counts={f:sum(x['family']==f for x in rows) for f in ['iphone','ipad','duo','watch']}
report={'checkedAt':datetime.datetime.now(zoneinfo.ZoneInfo('Asia/Shanghai')).isoformat(),'sourceCount':len(rows),'counts':counts,'completeExpected60':len(rows)==60,'missing':{'ipad':12-counts['ipad'],'duo':12-counts['duo']},'originalRelease43EvidenceChanged':False,'newReleaseBuildOrUpload':False,'frontendFilesChanged':False,'nativeSourcesNotFinalPosters':True,'rows':rows}
(root/'ALL-NATIVE-SOURCES.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
contacts=[]
for family in ['iphone','ipad','duo','watch']:
 items=sorted([x for x in rows if x['family']==family],key=lambda x:(x['locale'],x['scene']))
 if not items:continue
 cols=4 if family!='watch' else 6;tw=240 if family!='watch' else 208;th=round(tw*items[0]['dimensions'][1]/items[0]['dimensions'][0]);h=th+24
 canvas=Image.new('RGB',(cols*tw,((len(items)+cols-1)//cols)*h),'#dddddd');draw=ImageDraw.Draw(canvas)
 for i,x in enumerate(items):
  im=Image.open(x['source']).convert('RGB');im.thumbnail((tw,th));px=(i%cols)*tw;py=(i//cols)*h;canvas.paste(im,(px,py+24));draw.text((px+5,py+5),x['locale']+' '+x['scene']+' native',fill='black')
 contact=root/(family+'-contact.jpg');canvas.save(contact,quality=93);contacts.append(contact)
with zipfile.ZipFile(root/'all-native51-review.zip','w',zipfile.ZIP_DEFLATED) as z:
 for x in rows:z.write(x['source'],x['packagePath'])
 z.write(root/'ALL-NATIVE-SOURCES.json','ALL-NATIVE-SOURCES.json')
 for p in contacts:z.write(p,p.name)
print('SOURCE_INDEX',counts,'total',len(rows),'ZIP_BYTES',(root/'all-native51-review.zip').stat().st_size,flush=True)
