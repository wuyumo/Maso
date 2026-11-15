"""Collect existing preview files; never change App adoption or owner decisions."""
from pathlib import Path
import json, hashlib, os, shutil

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs'
OUT = DOCS / 'exercise-full-gif-2026-11-02'
DECISIONS = DOCS / 'gif-review-decisions-2026-11-02'
approved = {x['exerciseId'] for x in json.loads((DECISIONS/'approved-reuse.json').read_text())['items']}
undecided = set(json.loads((DECISIONS/'undecided.json').read_text())['items'])
names = {x['id']: x['name'].get('zh-Hans', x['id']) for x in json.loads((ROOT/'Maso/Resources/exercises.json').read_text())}
candidates = {}
paths = list(DOCS.rglob('*manifest*.json')) + [p for p in OUT.rglob('*.json') if p.name != 'pending-review-items.json']
catalog = {x['exerciseId']: x['sha256'] for x in json.loads((ROOT/'Maso/Resources/CoreExerciseDemos/catalog.json').read_text())}
# An adopted MP4 has different bytes from its source GIF: follow provenance only
# when the imported MP4 is the one currently selected in the App catalog.
adopted_sources = set()
for manifest in DOCS.rglob('import-manifest.json'):
    try:
        data = json.loads(manifest.read_text())
    except (ValueError, OSError):
        continue
    rows = data if isinstance(data, list) else data.get('items', []) if isinstance(data, dict) else []
    for row in rows:
        if isinstance(row, dict) and catalog.get(row.get('exerciseId')) == row.get('sha256') and row.get('originalSHA256'):
            adopted_sources.add((row['exerciseId'], row['originalSHA256']))

def manifest_rows(data):
    if isinstance(data, list):
        for value in data:
            yield from manifest_rows(value)
    elif isinstance(data, dict):
        if data.get('exerciseId'):
            yield data
        for key in ('items', 'candidates'):
            if isinstance(data.get(key), (list, dict)):
                yield from manifest_rows(data[key])
paths += [DECISIONS/'feedback3/revision-manifest.json', DOCS/'exercise-youtube-previews-2026-10-31/manifest.json']
for path in paths:
    try:
        data = json.loads(path.read_text())
    except (ValueError, OSError):
        continue
    for row in manifest_rows(data):
        if not isinstance(row, dict):
            continue
        eid = row.get('exerciseId')
        if not eid:
            continue
        if path.parent.name == 'exercise-youtube-previews-2026-10-31' and eid not in undecided:
            continue
        status = row.get('status', row.get('reviewState', ''))
        if status not in ('review','held','pending_review','pending_owner_review','pending','self_checked','ready','prepared_not_published','approved'):
            continue
        filename = row.get('gif') or row.get('candidateGif') or (row.get('originalSource') if str(row.get('originalSource','')).endswith('.gif') else None)
        if not filename:
            continue
        file = path.parent / filename
        if not file.is_file():
            file = ROOT / filename
        if not file.is_file():
            continue
        # Only actual generated GIFs are candidates; reference/legacy media are
        # not candidate records even when mentioned in source inventories.
        if file.suffix.lower() != '.gif' or 'legacy' in file.name.lower():
            continue
        sha = hashlib.sha256(file.read_bytes()).hexdigest()
        expected = (row.get('gifSHA256') or row.get('sourceGIFSHA256')) if row.get('gif') else (row.get('candidateGifSHA256') or row.get('originalSHA256'))
        if expected and expected != sha:
            raise ValueError(f'Changed preview bytes: {file}')
        if (eid, sha) in adopted_sources:
            continue
        record = dict(exerciseId=eid, name=names.get(eid,eid), status=status,
                      gif=os.path.relpath(file, OUT), sourceGIFSHA256=sha,
                      comment=row.get('note',row.get('reviewNote','')),
                      manifest=os.path.relpath(path,OUT))
        timestamp = file.stat().st_mtime
        if eid not in candidates or timestamp > candidates[eid][0]:
            candidates[eid] = timestamp, record
# Priority stills are generated outside the HTTP server's docs root. Copy the
# exact source bytes to a content-addressed path so the review UI can serve
# them without changing any producer files or the App's selected media.
static_dir = OUT / 'review-static-candidates'
for path in OUT.glob('gaps2-static-priority*-manifest.json'):
    for row in manifest_rows(json.loads(path.read_text())):
        eid = row.get('exerciseId')
        if not eid or row.get('status') not in ('review','held','pending_review','pending_owner_review','pending','self_checked'):
            continue
        file = Path(row.get('source', ''))
        if not file.is_absolute():
            file = ROOT / file
        if not file.is_file() or file.suffix.lower() != '.png':
            continue
        sha = hashlib.sha256(file.read_bytes()).hexdigest()
        if row.get('sha256') != sha:
            raise ValueError(f'Changed static preview bytes: {file}')
        if (eid, sha) in adopted_sources:
            continue
        target = static_dir / (sha + '.png')
        static_dir.mkdir(exist_ok=True)
        if not target.exists():
            shutil.copyfile(file, target)
        if hashlib.sha256(target.read_bytes()).hexdigest() != sha:
            raise ValueError(f'Changed served static preview bytes: {target}')
        record = dict(exerciseId=eid, name=names.get(eid,eid), status=row['status'],
                      gif=os.path.relpath(target, OUT), sourceGIFSHA256=sha,
                      comment='静图候选；动态帧尚未完成。' + row.get('note',''),
                      manifest=os.path.relpath(path, OUT))
        timestamp = file.stat().st_mtime
        if eid not in candidates or timestamp > candidates[eid][0]:
            candidates[eid] = timestamp, record
items = sorted((v[1] for v in candidates.values()), key=lambda x: (x['status']=='held',x['name']))
(OUT/'pending-review-items.json').write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n')
template = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Masso 待确认动作</title>
<style>*{box-sizing:border-box}body{margin:0;padding:16px;background:#151719;color:#fff;font:16px system-ui}header{display:flex;gap:12px;align-items:center;flex-wrap:wrap}h1{font-size:22px}button,select,textarea,input{font:inherit;padding:10px;border-radius:8px}button{cursor:pointer}main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;margin-top:16px}article{background:#262a2c;padding:12px;border-radius:14px;display:grid;grid-template-columns:58% 1fr;gap:12px;align-items:start}img{width:100%;border-radius:8px}h2{font-size:17px;margin:0 0 8px}textarea{width:100%;height:80px;margin:8px 0}small{color:#b8bec2;overflow-wrap:anywhere}a{color:#8ad8b0}[hidden]{display:none!important}.label{color:#8ad8b0;font-size:13px}@media(max-width:1000px){main{grid-template-columns:1fr}}@media(max-width:550px){article{grid-template-columns:1fr}body{padding:10px}}</style>
<header><h1>待确认动作</h1><span id="count"></span><input id="q" placeholder="搜索动作"><label><input id="only" type="checkbox" checked>仅未决策</label><button id="copy">复制全部决策 JSON</button><button id="download">导出 JSON</button><a href="review.html">全部制作预览</a></header><p>每个动作只显示最新候选；已采用的批准版本不在此页。带已知问题的候选仍标为待修，确认仅记录你的决策。</p><main id="cards"></main><textarea id="fallback" hidden></textarea>
<script>
const items=__ITEMS__,key='masso-pending-review-v1';let saved={};try{saved=JSON.parse(localStorage.getItem(key)||'{}')}catch{}
const nodes=[];const label={review:'待确认',approved:'通过',held:'需修改',rejected:'不可用',generation_blocked:'生成失败'};
for(const item of items){const a=document.createElement('article'),img=document.createElement('img'),side=document.createElement('div'),title=document.createElement('h2'),badge=document.createElement('span'),id=document.createElement('small'),note=document.createElement('textarea'),select=document.createElement('select'),confirm=document.createElement('button');const sk=item.exerciseId+'|'+item.sourceGIFSHA256,decision=saved[sk];img.src=item.gif;img.alt=item.name;img.loading='lazy';title.textContent=item.name+' ';badge.className='label';badge.textContent=label[decision?.status]||'未决策';title.append(badge);id.textContent=item.exerciseId+' · '+(item.status==='held'?'候选有已知问题':'候选待确认');note.value=decision?.comment??item.comment;note.setAttribute('aria-label',item.name+' 修改意见');for(const [value,text] of Object.entries(label)){const o=document.createElement('option');o.value=value;o.textContent=text;select.append(o)}select.value=decision?.status||(item.status==='held'?'held':'review');select.setAttribute('aria-label',item.name+' 决策');confirm.textContent='确认';confirm.onclick=()=>{saved[sk]={exerciseId:item.exerciseId,status:select.value,comment:note.value,sourceGIFSHA256:item.sourceGIFSHA256,gif:item.gif,confirmedAt:new Date().toISOString()};localStorage.setItem(key,JSON.stringify(saved));badge.textContent=label[select.value];filter()};side.append(title,id,select,note,confirm);a.append(img,side);document.querySelector('#cards').append(a);nodes.push({a,item,sk})}
function filter(){let visible=0;const q=document.querySelector('#q').value.toLowerCase();for(const {a,item,sk} of nodes){const done=saved[sk]&&saved[sk].status!=='review';a.hidden=(!((item.name+' '+item.exerciseId).toLowerCase().includes(q)))||(document.querySelector('#only').checked&&done);if(!a.hidden)visible++}document.querySelector('#count').textContent=visible+' / '+items.length}
document.querySelector('#q').oninput=filter;document.querySelector('#only').onchange=filter;
function exported(){return JSON.stringify({schema:'masso.pending-review.v1',reviews:Object.values(saved)},null,2)}
document.querySelector('#copy').onclick=async()=>{try{await navigator.clipboard.writeText(exported());document.querySelector('#copy').textContent='已复制'}catch{const t=document.querySelector('#fallback');t.hidden=false;t.value=exported();t.select()}};
document.querySelector('#download').onclick=()=>{const u=URL.createObjectURL(new Blob([exported()],{type:'application/json'})),a=document.createElement('a');a.href=u;a.download='masso-pending-review.json';a.click();setTimeout(()=>URL.revokeObjectURL(u),1000)};filter();
</script></html>'''
(OUT/'review-pending.html').write_text(template.replace('__ITEMS__',json.dumps(items,ensure_ascii=False).replace('</','<\\/')))
link = '<p><a href="review-pending.html">查看全部待确认动作 →</a></p>'
page=OUT/'review.html'
text=page.read_text()
if 'href="review-pending.html"' not in text:
    text=text.replace('<main>',link+'<main>',1)
    page.write_text(text)
import subprocess
subprocess.run(['python3', str(ROOT/'scripts/merge_new_gif_previews.py')], check=True)
print(f'Collected {len(items)} latest candidates')
