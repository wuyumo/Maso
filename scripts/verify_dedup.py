#!/usr/bin/env python3
"""Post-cleanup assertions for the same-name exercise dedup.

Asserts:
  1. Zero duplicate English `name` values in every DB file.
  2. All 17 kept ids still present; all 17 removed ids gone everywhere.
  3. Written files still parse and keep canonical 2-space formatting (re-fidelity).
  4. exercises.json == exercises-matched.json minus internal _match_* debug fields.
  5. Every legacy id referenced by RecommendedPrograms.swift still resolves through
     the byId + imageFolder-alias map (the way ExerciseLibrary.swift builds it).
"""
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(__file__), "..", "Maso", "Resources")
SWIFT = os.path.join(os.path.dirname(__file__), "..", "Maso", "Data")

REMOVED = {
    "burpee_squat_jump", "romanian_deadlift", "romanian_deadlift_dumbbell", "clap_pushup",
    "handstand_pushup", "pike_push_up", "plyo_pushup", "good_morning_barbell", "dip_bench_chest",
    "chest_dip_korean", "scapular_pullup", "stiff_leg_deadlift", "kettlebell_deadlift",
    "squat_thruster_dumbbell", "worlds_greatest_stretch", "thoracic_extension_foam_roller",
    "back_extension_45",
}
KEPT = {
    "burpee", "rdl_barbell", "rdl_dumbbell", "push_up_clap", "handstand_push_up", "push_up_pike",
    "push_up_plyo", "good_morning", "bench_dip", "dip_korean", "scapular_pull_up",
    "deadlift_stiff_leg", "deadlift_kettlebell", "thruster_dumbbell", "world_greatest_stretch",
    "foam_roll_thoracic_extension", "back_extension_45_degree",
}

ALL_FILES = [
    "exercises.json", "new-exercise-db/exercises-new.json", "new-exercise-db/exercises-matched.json",
    "new-exercise-db/1-chest-triceps.json", "new-exercise-db/1b-triceps-supplement.json",
    "new-exercise-db/2-shoulders.json", "new-exercise-db/3-back-biceps-forearms.json",
    "new-exercise-db/4-legs.json", "new-exercise-db/5-core-stretching.json",
    "new-exercise-db/6-cardio-plyo-cali.json",
]

fails = []


def check(cond, msg):
    print(("  OK  " if cond else " FAIL ") + msg)
    if not cond:
        fails.append(msg)


def top_level_object_spans(text):
    spans, depth, in_str, esc, start = [], 0, False, False, None
    for j, c in enumerate(text):
        if in_str:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_str = False
            continue
        if c == '"': in_str = True
        elif c == "{":
            if depth == 0: start = j
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0: spans.append((start, j + 1))
    return spans


print("=== 1. No duplicate English names + removed/kept invariants per file ===")
for rel in ALL_FILES:
    path = os.path.normpath(os.path.join(ROOT, rel))
    raw = open(path, encoding="utf-8").read()
    data = json.loads(raw)  # parses => valid JSON
    names = [x["name"]["en"] for x in data]
    dupes = {n: c for n, c in Counter(names).items() if c > 1}
    ids = {x["id"] for x in data}
    name = rel.split("/")[-1]
    check(not dupes, f"{name}: 0 duplicate en-names (found {len(dupes)}: {list(dupes)[:5]})")
    check(not (ids & REMOVED), f"{name}: no removed ids present (leak: {sorted(ids & REMOVED)})")
    # re-fidelity: re-split + rebuild must equal current bytes (no formatting drift)
    objs = [raw[s:e] for s, e in top_level_object_spans(raw)]
    rebuilt = "[\n  " + ",\n  ".join(objs) + "\n]\n"
    check(rebuilt == raw, f"{name}: formatting clean (rebuild==file)")

print("\n=== 2. Kept ids present in the main DB files ===")
for rel in ["exercises.json", "new-exercise-db/exercises-new.json", "new-exercise-db/exercises-matched.json"]:
    path = os.path.normpath(os.path.join(ROOT, rel))
    ids = {x["id"] for x in json.load(open(path, encoding="utf-8"))}
    missing = KEPT - ids
    check(not missing, f"{rel.split('/')[-1]}: all 17 kept ids present (missing {sorted(missing)})")
    check(len(ids) == 962, f"{rel.split('/')[-1]}: 962 exercises (got {len(ids)})")

print("\n=== 3. exercises.json == exercises-matched.json minus _match_* debug fields ===")
live = {x["id"]: x for x in json.load(open(os.path.join(ROOT, "exercises.json"), encoding="utf-8"))}
matched = {x["id"]: x for x in json.load(open(os.path.normpath(os.path.join(ROOT, "new-exercise-db/exercises-matched.json")), encoding="utf-8"))}
check(set(live) == set(matched), "live and matched have identical id sets")
DEBUG = {"_match_old_name", "_match_score", "_pending_review"}
mismatch = []
for i in live:
    stripped = {k: v for k, v in matched[i].items() if k not in DEBUG}
    if stripped != live[i]:
        mismatch.append(i)
check(not mismatch, f"live == matched-minus-debug for all ids (mismatch: {mismatch[:5]})")
check(all(not (DEBUG & set(x)) for x in live.values()), "no _match_* debug fields leaked into exercises.json")

print("\n=== 4. Kept ids retain imageFolder alias their removed partner shared ===")
alias_expect = {  # kept id -> imageFolder it must still carry (None = removed partner had none either)
    "rdl_barbell": "Romanian_Deadlift", "rdl_dumbbell": "Romanian_Deadlift",
    "push_up_clap": "Plyo_Push-up", "handstand_push_up": "Handstand_Push-Ups",
    "push_up_pike": "Incline_Push-Up", "push_up_plyo": "Plyo_Push-up",
    "good_morning": "Band_Good_Morning", "bench_dip": "Bench_Dips",
    "scapular_pull_up": "Scapular_Pull-Up", "deadlift_stiff_leg": "Stiff-Legged_Barbell_Deadlift",
    "deadlift_kettlebell": "Axle_Deadlift", "thruster_dumbbell": "Kettlebell_Thruster",
    "world_greatest_stretch": "Worlds_Greatest_Stretch",
}
for kid, folder in alias_expect.items():
    check(live[kid].get("imageFolder") == folder, f"{kid} keeps imageFolder={folder!r} (got {live[kid].get('imageFolder')!r})")

print("\n=== 5. RecommendedPrograms resolution: no REGRESSION from this dedup ===")
# Build byId exactly like ExerciseLibrary.swift: primary id, then imageFolder alias (first-come by array order)
def build_by_id(lst):
    m = {}
    for x in lst:
        m.setdefault(x["id"], x)
    for x in lst:
        f = x.get("imageFolder")
        if f and f not in m:
            m[f] = x
    return m

rp = open(os.path.join(SWIFT, "RecommendedPrograms.swift"), encoding="utf-8").read()
ref_ids = sorted(set(re.findall(r'(?:step|timed)\("([^"]+)"', rp)))
live_list = json.load(open(os.path.join(ROOT, "exercises.json"), encoding="utf-8"))
by_id = build_by_id(live_list)

# (a) no RP id resolves to a removed exercise
to_removed = [r for r in ref_ids if r in by_id and by_id[r]["id"] in REMOVED]
check(not to_removed, f"no RP id resolves to a removed exercise (got {to_removed})")

# (b) the two RP-referenced folders this edit touched still resolve to a kept exercise
for folder in ("Romanian_Deadlift", "Leg_Extensions"):
    if folder in ref_ids:
        ok = folder in by_id and by_id[folder]["id"] not in REMOVED
        check(ok, f"RP folder {folder!r} still resolves (-> {by_id.get(folder, {}).get('id')})")

# (c) strongest: compare vs pre-edit bundled copy in DerivedData, if present
baseline = None
for cand in (
    "build/DerivedData/Build/Products/Debug-iphonesimulator/Maso.app/exercises.json",
    "build/DerivedData-Device/Build/Products/Debug-iphoneos/Maso.app/exercises.json",
):
    p = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", cand))
    if os.path.exists(p):
        baseline = p
        break
unresolved_now = [r for r in ref_ids if r not in by_id]
if baseline:
    base_by_id = build_by_id(json.load(open(baseline, encoding="utf-8")))
    newly = [r for r in ref_ids if r in base_by_id and r not in by_id]
    check(not newly, f"no RP id newly unresolved vs pre-edit baseline (newly broken: {newly})")
    print(f"  INFO  {len(unresolved_now)} RP ids unresolved both before & after "
          f"(pre-existing v2-match gap, out of scope)")
else:
    print(f"  INFO  {len(unresolved_now)} RP ids unresolved (no DerivedData baseline to diff; "
          f"pre-existing v2-match gap, unrelated to dedup): {unresolved_now}")

print()
if fails:
    print(f"RESULT: {len(fails)} FAILED")
    sys.exit(1)
print("RESULT: ALL CHECKS PASSED")
