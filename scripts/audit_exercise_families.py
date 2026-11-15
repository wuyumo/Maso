#!/usr/bin/env python3
"""Normalize bundled exercise families while preserving IDs and old search names."""
import json, re, subprocess, sys
from pathlib import Path
from collections import defaultdict
ROOT = Path(__file__).resolve().parent.parent
# This old restoration/renaming pass predates the reviewed exact-ID merges.
# It must not revive synonyms or undo the current suffix/attachment contract.
if (ROOT/'docs/exercise-identity-audit-2026-10-26/merge-decisions.json').exists():
    subprocess.run([sys.executable, str(ROOT/'scripts/check_exercise_identity_audit.py')], check=True)
    raise SystemExit(0)
path = ROOT / 'Maso/Resources/exercises.json'
rows = json.loads(path.read_text())
original = {e['id']: e for e in json.loads((ROOT/'Maso/Resources/new-exercise-db/exercises-matched.json').read_text())}
old = {e['id']: json.loads(json.dumps(e)) for e in rows}
ids = {e['id'] for e in rows}
restored = []
identity_decisions = ROOT / 'docs/exercise-identity-audit-2026-10-26/merge-decisions.json'
retired_synonyms = set(json.loads(identity_decisions.read_text())['aliases']) if identity_decisions.exists() else set()
for e in list(rows):
    for ident in e.get('mergedFrom', []):
        if ident not in ids and ident not in retired_synonyms:
            source = json.loads(json.dumps(original[ident]))
            source['niche'] = e.get('niche', False)
            rows.append(source); ids.add(ident); restored.append(ident)
    if e.get('mergedFrom'):
        source = original[e['id']]
        e['name'] = source['name'].copy()
        e.pop('nameParts', None)
        # A restored variant has its own ID again; true aliases still resolve unchanged.
        e['mergedFrom'] = [i for i in e['mergedFrom'] if i not in ids]

EQUIPMENT = {'barbell':'Barbell','dumbbell':'Dumbbell','cable':'Cable','machine':'Machine',
 'smith':'Smith Machine','smith machine':'Smith Machine','band':'Band','resistance band':'Band',
 'ez bar':'EZ-Bar','ez-bar':'EZ-Bar','kettlebell':'Kettlebell','rings':'Rings','ring':'Rings',
 'trx':'TRX','medicine ball':'Medicine Ball','med ball':'Medicine Ball','landmine':'Landmine',
 'trap bar':'Trap Bar','axle bar':'Axle Bar','plate':'Plate','chains':'Chains','parallel bars':'Parallel Bars',
 'parallel bar':'Parallel Bars','swiss ball':'Swiss Ball','stability ball':'Swiss Ball', 'rope':'Rope',
 'bodyweight':'Bodyweight','body only':'Bodyweight','bench':'Bench','step':'Step','sled':'Sled','t-bar':'T-Bar'}
modifiers = ['Single-Arm','One-Arm','Single-Leg','One-Leg','Close-Grip','Wide-Grip','Neutral-Grip',
 'Reverse-Grip','Underhand','Overhand','Alternating','Seated','Standing','Lying','Prone','Supine',
 'Kneeling','Half-Kneeling','Chest-Supported','Incline','Decline','Paused','Tempo','Eccentric',
 'Iso-Hold','Drop-Set','Behind-the-Back','Behind-the-Head','Low-to-High','High-to-Low','Two-Arm',
 'Deficit','Egyptian','Lean-In','Leaning','Cross-Body','21s','1.5 Rep','1.5-Rep']
modpattern = re.compile(r'^('+'|'.join(re.escape(x) for x in sorted(modifiers,key=len,reverse=True))+r')\s+', re.I)
base_alias = {'Around the World':'Around-the-World Raise','Farmer Carry':"Farmer's Carry",'Hamstring Curl':'Leg Curl',
 'Leaning Lateral Raise':'Lateral Raise','Lunges':'Lunge','Plyo Lunges':'Lunge',
 'Side Plank with Leg Raise':'Plank','Side Plank Leg Raise':'Plank', 'Side Plank Dip':'Plank',
 'Plank with Hip Dip':'Plank','Plank Reach':'Plank','Plank Shoulder Tap':'Plank','Plank Up-Down':'Plank',
 'Reverse Fly':'Rear Delt Fly','Farmer Walk on Toes':"Farmer's Carry",'Step-Back Lunge':'Lunge',
 'V Sit-Up':'V-Up','Jackknife':'V-Up','Grip Crusher':'Captains of Crush Gripper',
 'Shoulder Pass-Through':'Shoulder Dislocation','Stairmaster':'Stair Climbing',
 'Spin Bike':'Stationary Bike','Anti-Rotation Press':'Pallof Press',
 'Glute Bridge March':'Glute Bridge','Hollow Body Sit-Up':'Sit-Up','Woodchopper Reverse':'Woodchopper'}
alias_variation = {'Leaning Lateral Raise':'Leaning','Plyo Lunges':'Plyometric',
 'Side Plank with Leg Raise':'Side Leg Raise','Side Plank Leg Raise':'Side Leg Raise','Side Plank Dip':'Side Hip Dip',
 'Plank with Hip Dip':'Hip Dip','Plank Reach':'Reach','Plank Shoulder Tap':'Shoulder Tap','Plank Up-Down':'Up-Down',
 'Farmer Walk on Toes':'On Toes','Step-Back Lunge':'Reverse','Glute Bridge March':'March',
 'Hollow Body Sit-Up':'Hollow Body','Woodchopper Reverse':'Reverse','Spin Bike':'Spin'}
base_alias.update({'21s Lateral Raise':'Lateral Raise','Bent-Over Rear Delt Raise':'Rear Delt Fly',
 'Cable Chest Press':'Chest Press','High Cable Chest Press':'Chest Press','Low Cable Chest Press':'Chest Press',
 'Cable Crossover':'Chest Fly','Crossover':'Chest Fly','Pec Deck':'Chest Fly',
 'Child Pose':"Child's Pose",'Cross-Bench Dumbbell Pullover':'Pullover',
 'Feet-Elevated Bench Dip':'Bench Dip','Floor Triceps Kickback':'Triceps Kickback',
 'Hammer-Grip Front Raise':'Front Raise','High Face Pull':'Face Pull',
 'Hyperextension':'Back Extension','Mountain Climbers':'Mountain Climber',
 'Overhead Triceps Extension':'Triceps Extension','French Press':'Triceps Extension',
 'Donkey Calf Raise':'Calf Raise','Rack Pull':'Deadlift','Bound':'Bounding', 'Jumps':'Jump',
 'Skater Jumps':'Skater Hop','Squat to Box':'Squat','Superman Hold':'Superman','Weighted Chest Dip':'Chest Dip',
 'Fly Around the World':'Around-the-World Raise','Prowler Push':'Sled Push'})
alias_variation.update({'21s Lateral Raise':'21s','Bent-Over Rear Delt Raise':'Bent-Over',
 'High Cable Chest Press':'High','Low Cable Chest Press':'Low','Crossover':'Crossover','Cable Crossover':'Crossover',
 'Pec Deck':'Pec Deck','Cross-Bench Dumbbell Pullover':'Cross-Bench',
 'Feet-Elevated Bench Dip':'Feet-Elevated','Floor Triceps Kickback':'Floor',
 'Hammer-Grip Front Raise':'Hammer-Grip','High Face Pull':'High',
 'Overhead Triceps Extension':'Overhead','French Press':'Overhead',
 'Donkey Calf Raise':'Donkey','Rack Pull':'Rack','Squat to Box':'Box',
 'Superman Hold':'Hold','Weighted Chest Dip':'Weighted'})
changes=[]
for e in rows:
    before=e['name']['en']; parts=e.get('nameParts')
    if parts:
        base=parts['base']; eq=parts.get('equipment'); var=parts.get('variation')
    else:
        pre=before.split('(')[0].strip(); tail=before.split('(',1)[1].rstrip(')') if '(' in before else ''
        vs=[]; eqs=[]
        for piece in re.split(r'[,·]',tail):
            piece=piece.strip()
            if not piece:continue
            if piece.lower() in EQUIPMENT:eqs.append(EQUIPMENT[piece.lower()])
            else:vs.append(piece)
        for key in sorted(EQUIPMENT,key=len,reverse=True):
            if pre.lower().startswith(key+' ') and key not in ['bench','step','rope','plate','sled']:
                eqs.insert(0,EQUIPMENT[key]);pre=pre[len(key):].strip();break
        while (m:=modpattern.match(pre)):
            vs.insert(0,m.group(1));pre=pre[m.end():].strip()
        base=pre;eq=' / '.join(dict.fromkeys(eqs)) or None;var=' '.join(vs) or None
    oldbase=base
    # Reviewed families: variations remain individually selectable, never deleted.
    if base.endswith('Push-Up') and base != 'Soleus Push-Up':
        var=' '.join(filter(None,[base[:-len('Push-Up')].strip(),var])) or None;base='Push-Up'
    elif base.endswith('Pull-Up'):
        var=' '.join(filter(None,[base[:-len('Pull-Up')].strip(),var])) or None;base='Pull-Up'
    elif base in ['Curl','Bicep Curl','Bicep Curl Hold'] or (base.endswith('Curl') and not any(k in base for k in ['Wrist','Finger','Nordic','Leg','Hamstring'])):
        descriptor=base.removesuffix('Curl').strip() if base.endswith('Curl') else 'Hold' if base.endswith('Hold') else ''
        if descriptor in ['Bicep','Biceps']:descriptor=''
        var=' '.join(filter(None,[descriptor,var])) or None;base='Bicep Curl'
    elif base.endswith('Row') and base not in ['Upright Row','Rear Delt Row']:
        var=' '.join(filter(None,[base[:-3].strip(),var])) or None;base='Row'
    elif base.endswith('Lunge') and base != 'Lunge Stretch':
        var=' '.join(filter(None,[base[:-5].strip(),var])) or None;base='Lunge'
    elif base.endswith('Deadlift'):
        var=' '.join(filter(None,[base[:-8].strip(),var])) or None;base='Deadlift'
    elif base.endswith('Squat') and base != 'Split Squat':
        if base.endswith('Split Squat'):
            var=' '.join(filter(None,[base.removesuffix('Split Squat').strip(),var])) or None;base='Split Squat'
        else:
            var=' '.join(filter(None,[base[:-5].strip(),var])) or None;base='Squat'
    elif base in ['Arnold Press','Military Press','Bradford Press','Z Press','Viking Press','Log Press']:
        if base!='Military Press':var=' '.join(filter(None,[base.removesuffix('Press').strip(),var]))
        base='Overhead Press'
    elif base in ['Floor Press','Spoto Press','Board Press','Guillotine Press','Bench Press Static Hold']:
        var=' '.join(filter(None,[base.removesuffix('Press').strip() if base.endswith('Press') else 'Static Hold',var])) or None;base='Bench Press'
    elif base in base_alias:
        var=' '.join(filter(None,[alias_variation.get(base),var])) or None;base=base_alias[base]
    if base=='Press':
        majors={m['major'] for m in e['muscles']['primary']}
        base='Overhead Press' if 'shoulders' in majors else 'Chest Press'
    # Identity words that equipment heuristics must not erase.
    special={'sled_push':('Sled Push',None,'Sled'),'sled_pull':('Sled Pull','Backward','Sled'),
             'barbell_holds':('Grip Hold',None,'Barbell'),'sprint_intervals_track':('Running','Sprint Intervals',None),
             'depth_drop_landing':('Landing','Depth Drop',None),'depth_jump':('Jump','Depth',None)}
    if e['id'] in special:base,var,eq=special[e['id']]
    var=re.sub(r'\bBiceps?\b', '', var).strip() if var and base=='Bicep Curl' else var
    var=re.sub(r'\s+',' ',var).strip() if var else None
    if var and eq:
        for term in eq.split(' / '):
            var=re.sub(r'\b'+re.escape(term)+r'\b','',var,flags=re.I).strip(' ·,') or None
            if var is None:break
    e['nameParts']={'variation':var,'base':base,'equipment':eq}
    if parts and parts.get('localizedBase'):
        e['nameParts']['localizedBase'] = parts['localizedBase']
    detail=' · '.join(v for v in [eq,var] if v)
    after=base+(f' ({detail})' if detail else '')
    e['name']['en']=after
    if before!=after:
        e['aliases']=list(dict.fromkeys(e.get('aliases',[])+[before]))
    prev=old.get(e['id'])
    if prev is None or prev.get('nameParts')!=e['nameParts'] or prev['name']['en']!=after:
        changes.append((e['id'],prev['name']['en'] if prev else '[restored] '+before,after))
rows.sort(key=lambda e:e['id'])
assert len({e['id'] for e in rows})==len(rows)
assert all(e['nameParts']['base'] for e in rows)
assert set(old)<=set(e['id'] for e in rows)
path.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
groups=defaultdict(list)
for e in rows:groups[e['nameParts']['base']].append(e)
report=['# Exercise family and naming audit','', 'Current rule: `Base (Equipment · Variation)`. All IDs and previous English names are preserved; old names remain search aliases.', '',f'{len(rows)} exercises · {len(groups)} families · {len(restored)} restored variants · {len(changes)} reviewed changes.', '', '## Changes','', '| ID | Before | After |','|---|---|---|']
report += [f'| {i} | {b} | {a} |' for i,b,a in changes]
report += ['', '## Complete family inventory','']
for base,es in sorted(groups.items()):
    report += [f'### {base} ({len(es)})']+[f'- `{e["id"]}` — {e["name"]["en"]}' for e in es]+['']
if changes:
    (ROOT/'docs/exercise-family-audit.md').write_text('\n'.join(report)+'\n')
print(f'{len(rows)} exercises; {len(groups)} families; restored {len(restored)}; changed {len(changes)}')
