"""Merge latest candidates into the original review UI, retaining version-bound decisions."""
from pathlib import Path
import json, re, html, hashlib, os
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
DOCS=ROOT/'docs'
page=DOCS/'exercise-youtube-previews-2026-10-31/review.html'
source=DOCS/'exercise-full-gif-2026-11-02'
items=json.loads((source/'pending-review-items.json').read_text())
rows={x['id']:x for x in json.loads((DOCS/'exercise-media-ledger/catalog.json').read_text())['rows']}
s=page.read_text()
# Reconcile imported decisions against their exact source bytes.  Old ID-only
# keys stay untouched; a new version must never inherit an old approval.
feedback=DOCS/'gif-review-decisions-2026-11-03/feedback6/execution-queue.json'
if feedback.exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads(feedback.read_text())['items']:
        eid=row.get('exerciseId'); sha=row.get('sourceGIFSHA256')
        if not eid or not sha or not row.get('hashVerified'):
            continue
        key=eid+'|'+sha
        status=row.get('decision','review')
        if row.get('action')=='revise' and status=='review':
            status='held'
        # Prefilled review notes are context, not an owner's decision; the card
        # already displays its own data-note and remains visible as undecided.
        comment = '' if status=='review' and row.get('commentOrigin')=='prefilled_manifest_note' else row.get('comment','')
        submitted[key]={'status':status,'comment':comment,
                        'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
# Apply the owner's later feedback only to the exact reviewed source bytes.
feedback7=DOCS/'gif-review-decisions-2026-11-04/feedback7/execution-queue.json'
if feedback7.exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads(feedback7.read_text())['items']:
        eid=row.get('exerciseId'); sha=row.get('sourceSHA256')
        if not eid or not sha or not row.get('shaVerified'):
            continue
        status='held' if row.get('action')=='revise' else row.get('decision','review')
        comment=row.get('comment','')
        if status=='review' and row.get('commentOrigin')=='prefilled_or_previous':
            comment=''
        submitted[eid+'|'+sha]={'status':status,'comment':comment,'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
feedback8=DOCS/'gif-review-decisions-2026-11-04/feedback8/execution-queue.json'
if feedback8.exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads(feedback8.read_text())['items']:
        eid=row.get('exerciseId'); sha=row.get('sourceSHA256')
        if not eid or not sha or not row.get('shaVerified'):
            continue
        status='held' if row.get('action')=='revise' else row.get('decision','review')
        comment=row.get('comment','')
        if status=='review' and row.get('commentOrigin')=='prefilled_or_previous':
            comment=''
        submitted[eid+'|'+sha]={'status':status,'comment':comment,'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
feedback9=DOCS/'gif-review-decisions-2026-11-05/feedback9/execution-queue.json'
if feedback9.exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads(feedback9.read_text())['items']:
        eid=row.get('exerciseId'); sha=row.get('sourceSHA256')
        if not eid or not sha or not row.get('shaVerified'):
            continue
        status=row['normalizedStatus']
        comment=row.get('rawDecision',{}).get('comment','')
        submitted[eid+'|'+sha]={'status':status,'comment':comment,'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
feedback10=DOCS/'gif-review-decisions-2026-11-05/feedback10/execution-queue.json'
if feedback10.exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads(feedback10.read_text())['items']:
        eid=row.get('exerciseId'); sha=row.get('sourceSHA256')
        if not eid or not sha or not row.get('sourceVerified'):
            continue
        status='held' if row.get('action')=='revise' else row.get('rawDecision',{}).get('status','review')
        submitted[eid+'|'+sha]={'status':status,'comment':row.get('rawDecision',{}).get('comment',''), 'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
feedback11=DOCS/'gif-review-decisions-2026-11-05/feedback11/execution-queue.json'
if feedback11.exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads(feedback11.read_text())['items']:
        eid=row.get('exerciseId'); sha=row.get('sourceSHA256')
        if not eid or not sha or not row.get('sourceVerified'):
            continue
        status='held' if row.get('action')=='revise' else row.get('rawDecision',{}).get('status','review')
        submitted[eid+'|'+sha]={'status':status,'comment':row.get('rawDecision',{}).get('comment',''), 'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
feedback12=DOCS/'gif-review-decisions-2026-11-05/feedback12/execution-queue.json'
if feedback12.exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads(feedback12.read_text())['items']:
        eid=row.get('exerciseId'); sha=row.get('sourceSHA256')
        if not eid or not sha or not row.get('sourceVerified'):
            continue
        status='held' if row.get('action')=='revise' else row.get('rawDecision',{}).get('status','review')
        submitted[eid+'|'+sha]={'status':status,'comment':row.get('rawDecision',{}).get('comment',''), 'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
feedback13=DOCS/'gif-review-decisions-2026-11-12/feedback13/execution-queue.json'
if feedback13.exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads(feedback13.read_text())['items']:
        eid=row.get('exerciseId'); sha=row.get('sourceSHA256')
        if not eid or not sha or not row.get('sourceVerified'):
            continue
        submitted[eid+'|'+sha]={'status':row['normalizedStatus'],
            'comment':row.get('rawDecision',{}).get('comment',''),
            'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
choice_base=DOCS/'gif-owner-new-media-choice-2026-11-12'
if (choice_base/'adoption.json').exists():
    marker='const submitted='
    start=s.index(marker)+len(marker)
    submitted,end=json.JSONDecoder().raw_decode(s[start:])
    for row in json.loads((choice_base/'execution-queue.json').read_text())['items']:
        eid=row['exerciseId']; sha=row['selectedGIFSHA256']
        if not row.get('sourceVerified'):
            continue
        submitted[eid+'|'+sha]={'status':'approved',
            'comment':'用户在新素材多版本选择页明确选定本单帧版本。',
            'exerciseId':eid,'sourceGIFSHA256':sha}
    s=s[:start]+json.dumps(submitted,ensure_ascii=False).replace('</','<\\/')+s[start+end:]
backup=source/'original-youtube-review-before-merge.html'
if not backup.exists():backup.write_text(s)
changed=0
for item in items:
    eid=item['exerciseId']; gif=(source/item['gif']).resolve()
    pattern=r'<article\b[^>]*>.*?</article>'
    existing=next((m for m in re.finditer(pattern,s,re.S) if re.search(r'<small>'+re.escape(eid)+r'</small>',m.group())),None)
    if existing:
        image=re.search(r'<img[^>]*src="([^"]+)"',existing.group())
        old=page.parent/html.unescape(image[1]) if image else None
        # Unchanged original previews retain their original ID-based review history.
        if old and old.is_file() and hashlib.sha256(old.read_bytes()).hexdigest()==item['sourceGIFSHA256'] and 'data-source-sha=' not in existing.group():
            continue
        s=s[:existing.start()]+s[existing.end():]
    status='held' if item['status']=='held' else 'review'
    name=item['name']; note=item.get('comment',''); sha=item['sourceGIFSHA256']
    card='<article data-status="'+status+'" data-source-sha="'+sha+'" data-note="'+html.escape(note,quote=True)+'" data-search="'+html.escape((eid+' '+name).lower(),quote=True)+'"><img loading="lazy" src="'+html.escape(os.path.relpath(gif,page.parent),quote=True)+'" alt="'+html.escape(name,quote=True)+'"><div class="info"><b>'+html.escape(name)+'</b><small>'+eid+'</small><span class="tag">新版 · '+('待修' if status=='held' else '待核实')+'</span><p>'+html.escape(note)+'</p></div></article>'
    muscle=(rows.get(eid,{}).get('primaryMuscles') or ['core'])[0]
    section=re.search(r'(<section class="muscle-section" data-section="'+re.escape(muscle)+r'">.*?<div class="grid">)',s,re.S)
    if section:s=s[:section.end()]+card+s[section.end():]
    else:raise ValueError('Missing muscle section '+muscle)
    changed+=1
if 'const exerciseId=info.querySelector' not in s:
    s=s.replace("id=info.querySelector('small').textContent,original=c.dataset.status", "id=info.querySelector('small').textContent+(c.dataset.sourceSha?'|'+c.dataset.sourceSha:''),original=c.dataset.status")
    s=s.replace("note.value=saved[id]?.comment??submitted[id]?.comment??''", "note.value=saved[id]?.comment??submitted[id]?.comment??c.dataset.note??''")
    s=s.replace("saved[id]={...previous,status:choice.value,comment:note.value.trim()}", "saved[id]={...previous,status:choice.value,comment:note.value.trim(),exerciseId:info.querySelector('small').textContent,sourceGIFSHA256:c.dataset.sourceSha||null}")
    s=s.replace("let id=c.querySelector('small').textContent,meta=metadata[id]||{};let decided", "let exerciseId=c.querySelector('small').textContent,id=exerciseId+(c.dataset.sourceSha?'|'+c.dataset.sourceSha:''),meta=metadata[exerciseId]||{};let decided")
# Classify the actual image bytes: a one-frame GIF is a still, too.
def classify_card(match):
    card = match.group()
    image = re.search(r'<img[^>]*src="([^"]+)"', card)
    media_type = 'unknown'
    batch = ''
    if image:
        file = page.parent / html.unescape(image.group(1)).split('?', 1)[0]
        for part in file.resolve().parts:
            found = re.fullmatch(r'exercise-media-fill-(\d{4}-\d{2}-\d{2})(?:-motion)?', part)
            if found:
                batch = found.group(1)
        try:
            with Image.open(file) as im:
                media_type = 'animated' if getattr(im, 'n_frames', 1) > 1 else 'still'
        except (OSError, ValueError):
            pass
    card = re.sub(r' data-media-type="[^"]*"', '', card, count=1)
    card = re.sub(r' data-batch="[^"]*"', '', card, count=1)
    return card.replace('<article ', '<article data-batch="'+batch+'" data-media-type="'+media_type+'" ', 1)
s = re.sub(r'<article\b[^>]*>.*?</article>', classify_card, s, flags=re.S)
if 'id="media-type"' not in s:
    s = s.replace('<select id="muscle">', '<select id="media-type"><option value="">全部素材</option><option value="animated">动图</option><option value="still">静图</option><option value="unknown">类型待确认</option></select> <select id="muscle">', 1)
if "document.querySelector('#media-type').value" not in s:
    s = s.replace("&&(!muscleFilter.value", "&&(!document.querySelector('#media-type').value||c.dataset.mediaType===document.querySelector('#media-type').value)&&(!muscleFilter.value", 1)
    s = s.replace("q.oninput=s.onchange=muscleFilter.onchange=", "q.oninput=s.onchange=document.querySelector('#media-type').onchange=muscleFilter.onchange=", 1)
# This intake stays in the original left-media/right-review page. Batch filtering
# only changes visibility; exact-SHA decisions and history storage remain intact.
batch_counts = {}
for batch in re.findall(r'data-batch="(\d{4}-\d{2}-\d{2})"', s):
    batch_counts[batch] = batch_counts.get(batch, 0) + 1
batch_control = '<select id="review-batch" aria-label="素材批次"><option value="">全部批次</option>'
for batch, total in sorted(batch_counts.items(), reverse=True):
    batch_control += '<option value="'+batch+'">'+batch+' 新素材（'+str(total)+'）</option>'
batch_control += '</select>'
if 'id="review-batch"' in s:
    s = re.sub(r'<select id="review-batch"[^>]*>.*?</select>', lambda _: batch_control, s, count=1, flags=re.S)
else:
    s = s.replace('<select id="muscle">', batch_control+' <select id="muscle">', 1)
if "document.querySelector('#review-batch').value" not in s:
    s = s.replace("&&(!muscleFilter.value", "&&(!document.querySelector('#review-batch').value||c.dataset.batch===document.querySelector('#review-batch').value)&&(!muscleFilter.value", 1)
    s = s.replace("q.oninput=s.onchange=", "q.oninput=s.onchange=document.querySelector('#review-batch').onchange=", 1)
if 'const requestedBatch=' not in s:
    s = s.replace("q.oninput=s.onchange=", "const requestedBatch=new URLSearchParams(location.search).get('batch');if(requestedBatch&&[...document.querySelector('#review-batch').options].some(o=>o.value===requestedBatch))document.querySelector('#review-batch').value=requestedBatch;q.oninput=s.onchange=", 1)
# Refresh count text from actual cards; avoid old hard-coded batch counts.
count=len(re.findall(r'<article\b',s));new_count=len(re.findall(r'data-source-sha=',s))
s=re.sub(r'<p class="counts">.*?</p>', '<p class="counts">共 '+str(count)+' 个动作，含 '+str(new_count)+' 个新版候选。新版按素材 SHA 单独确认，原决策保留；待修缺陷继续显示。</p>',s,count=1,flags=re.S)
page.write_text(s)
print(f'Merged {changed} latest versions; {count} total cards, {new_count} version-bound candidates')
