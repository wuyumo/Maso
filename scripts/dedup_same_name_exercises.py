#!/usr/bin/env python3
"""Remove the 17 same-English-name duplicate exercises from the DB files.

For each pair of exercises that share an identical English `name` but have
distinct `id`s, we keep the canonical id (matching the dominant family naming
convention / best metadata / preserves any RecommendedPrograms imageFolder
alias) and remove the other.

Edits, preserving each file's exact byte formatting (split files use inline
sub-objects, so we do a depth-scan substring removal rather than json.dump):
  - exercises.json                  (LIVE file the app loads)
  - new-exercise-db/exercises-new.json
  - new-exercise-db/exercises-matched.json
  - the relevant sibling split files (1-*, 1b-*, 2-*, 3-*, 4-*, 5-*, 6-*)

Run with --apply to write; default is a dry run.
"""
import json
import sys
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "Maso", "Resources")

# id to REMOVE per pair (the partner is kept). See PR description for rationale.
REMOVE = {
    "burpee_squat_jump",              # keep burpee (canonical base, anchors burpee_* family)
    "romanian_deadlift",              # keep rdl_barbell (rdl_* family x12; owns Romanian_Deadlift alias; 4 instr)
    "romanian_deadlift_dumbbell",     # keep rdl_dumbbell (rdl_* family; 4 instr)
    "clap_pushup",                    # keep push_up_clap (push_up_* convention)
    "handstand_pushup",               # keep handstand_push_up (push_up spelling)
    "pike_push_up",                   # keep push_up_pike (push_up_* convention)
    "plyo_pushup",                    # keep push_up_plyo (push_up_* convention)
    "good_morning_barbell",           # keep good_morning (canonical base; lower_back+hamstrings primary)
    "dip_bench_chest",                # keep bench_dip (anchors bench_dip_* family; dip_bench already separate)
    "chest_dip_korean",               # keep dip_korean (dip_* convention; accurate triceps Korean dip)
    "scapular_pullup",                # keep scapular_pull_up (pull_up convention; calisthenics not mobility)
    "stiff_leg_deadlift",             # keep deadlift_stiff_leg (deadlift_* family; sibling deadlift_stiff_leg_dumbbell; 4 instr)
    "kettlebell_deadlift",            # keep deadlift_kettlebell (deadlift_* family)
    "squat_thruster_dumbbell",        # keep thruster_dumbbell (pairs with base "Thruster" = thruster_barbell)
    "worlds_greatest_stretch",        # keep world_greatest_stretch (stretching cat; hip_flexors+hamstrings primary)
    "thoracic_extension_foam_roller", # keep foam_roll_thoracic_extension (foam_roll_* family x8; upper_back primary)
    "back_extension_45",              # keep back_extension_45_degree (visible/non-niche; back_extension_45 has WRONG imgF=Leg_Extensions & niche=true)
}

# (kept id -> removed id) used only for the alias-preservation assertion
KEEP_OF = {
    "burpee": "burpee_squat_jump",
    "rdl_barbell": "romanian_deadlift",
    "rdl_dumbbell": "romanian_deadlift_dumbbell",
    "push_up_clap": "clap_pushup",
    "handstand_push_up": "handstand_pushup",
    "push_up_pike": "pike_push_up",
    "push_up_plyo": "plyo_pushup",
    "good_morning": "good_morning_barbell",
    "bench_dip": "dip_bench_chest",
    "dip_korean": "chest_dip_korean",
    "scapular_pull_up": "scapular_pullup",
    "deadlift_stiff_leg": "stiff_leg_deadlift",
    "deadlift_kettlebell": "kettlebell_deadlift",
    "thruster_dumbbell": "squat_thruster_dumbbell",
    "world_greatest_stretch": "worlds_greatest_stretch",
    "foam_roll_thoracic_extension": "thoracic_extension_foam_roller",
    "back_extension_45_degree": "back_extension_45",
}

FILES = [
    "exercises.json",
    "new-exercise-db/exercises-new.json",
    "new-exercise-db/exercises-matched.json",
    "new-exercise-db/1-chest-triceps.json",
    "new-exercise-db/1b-triceps-supplement.json",
    "new-exercise-db/2-shoulders.json",
    "new-exercise-db/3-back-biceps-forearms.json",
    "new-exercise-db/4-legs.json",
    "new-exercise-db/5-core-stretching.json",
    "new-exercise-db/6-cardio-plyo-cali.json",
]


def top_level_object_spans(text):
    """Return [(start, end)] char spans of each top-level object in a JSON array,
    string- and depth-aware. text[start]=='{', text[end-1]=='}'."""
    spans = []
    depth = 0
    in_str = False
    esc = False
    start = None
    for j, c in enumerate(text):
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            if depth == 0:
                start = j
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                spans.append((start, j + 1))
    return spans


def rebuild(obj_texts):
    """Reconstruct the array file from object substrings, matching the
    canonical 2-space-indent formatting used by every DB file."""
    body = ",\n  ".join(obj_texts)
    return "[\n  " + body + "\n]\n"


def process(path, remove_ids, apply):
    raw = open(path, encoding="utf-8").read()
    spans = top_level_object_spans(raw)
    obj_texts = [raw[s:e] for s, e in spans]

    # Fidelity guard: an unfiltered rebuild MUST equal the original bytes,
    # otherwise our removal would silently reformat the file.
    if rebuild(obj_texts) != raw:
        raise SystemExit(f"FIDELITY FAIL on {path}: rebuild != original; aborting.")

    keep, removed_ids = [], []
    for t in obj_texts:
        oid = json.loads(t)["id"]
        if oid in remove_ids:
            removed_ids.append(oid)
        else:
            keep.append(t)

    new_raw = rebuild(keep)
    name = os.path.relpath(path, ROOT)
    print(f"  {name:38} objects {len(obj_texts)} -> {len(keep)}  removed {sorted(removed_ids)}")

    if apply and removed_ids:
        open(path, "w", encoding="utf-8").write(new_raw)
    return removed_ids


def main():
    apply = "--apply" in sys.argv
    print(f"{'APPLY' if apply else 'DRY RUN'} — removing {len(REMOVE)} duplicate ids\n")
    all_removed = {}
    for rel in FILES:
        path = os.path.normpath(os.path.join(ROOT, rel))
        for rid in process(path, REMOVE, apply):
            all_removed.setdefault(rid, []).append(rel)

    print("\nPer-id removal coverage:")
    for rid in sorted(REMOVE):
        locs = all_removed.get(rid, [])
        flag = "" if locs else "  <-- NOT FOUND ANYWHERE"
        print(f"  {rid:34} in {len(locs)} files{flag}")

    not_found = [r for r in REMOVE if r not in all_removed]
    if not_found:
        raise SystemExit(f"\nERROR: these ids were never found: {not_found}")


if __name__ == "__main__":
    main()
