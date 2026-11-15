#!/usr/bin/env python3
"""Read-only catalog identity/name/alias checks; fail closed on future regressions."""
import json,re,hashlib
from pathlib import Path
from collections import Counter
from exercise_identity_labels import LANGS,LABELS,primary
R=Path(__file__).resolve().parents[1]
x=json.loads((R/'Maso/Resources/exercises.json').read_text());by={e['id']:e for e in x}
d=json.loads((R/'docs/exercise-identity-audit-2026-10-26/merge-decisions.json').read_text())
assert len(by)==len(x)
for old,new in d['aliases'].items():
 assert old not in by and new in by and old in by[new].get('mergedFrom',[]),(old,new)
for lang in LANGS:
 c=Counter(e['name'][lang].strip().casefold() for e in x)
 assert all(n==1 for n in c.values()),(lang,[n for n,v in c.items() if v>1])
 for e in x:
  gear=primary(e)
  if not gear:continue
  m=re.search(r'[（(]([^()（）]+)[）)]$',e['name'][lang]);assert m,(lang,e['id'])
  assert LABELS[gear][LANGS.index(lang)].casefold() in m[1].casefold(),(lang,e['id'],gear,e['name'][lang])
sel=json.loads((R/'Maso/Resources/exercise-selection.json').read_text())
assert set(by)=={e['exerciseID'] for e in sel['entries']}
cat=(R/'Maso/Resources/CoreExerciseDemos/catalog.json').read_bytes()
assert hashlib.sha256(cat).hexdigest()==d['adoptedVideoCatalogSHA256']
assert all(e['exerciseId'] in by for e in json.loads(cat))
print(f'PASS {len(x)} actions, {len(d["aliases"])} retired aliases, unique names/all12 locales, equipment suffixes, selection/video references')
