#!/usr/bin/env python3
"""
Tag niche exercises with `"niche": true` in JSON.

Threshold: commonness score < 0 (from score_exercise_commonness.py).
Result: ~60 exercises get the flag. The runtime ExercisePickerSheet hides
them by default; a separate "Browse rare/specialized" entry opens a sheet
listing only the niche ones.

Operates on (keeps the three files in sync):
  - Maso/Resources/exercises.json (runtime)
  - Maso/Resources/new-exercise-db/exercises-new.json (source)
  - Maso/Resources/new-exercise-db/exercises-matched.json (source)

Idempotent: re-running re-evaluates from scratch — exercises that no longer
qualify lose the flag.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from score_exercise_commonness import score_exercise  # noqa: E402

THRESHOLD = 0  # score < THRESHOLD → niche

TARGETS = [
    "Maso/Resources/exercises.json",
    "Maso/Resources/new-exercise-db/exercises-new.json",
    "Maso/Resources/new-exercise-db/exercises-matched.json",
]


def main():
    # First pass: read the runtime file to compute niche IDs
    primary = os.path.join(ROOT, TARGETS[0])
    with open(primary) as f:
        data = json.load(f)
    niche_ids = set()
    for e in data:
        s, _ = score_exercise(e)
        if s < THRESHOLD:
            niche_ids.add(e["id"])
    print(f"Niche threshold: score < {THRESHOLD}")
    print(f"Niche IDs: {len(niche_ids)}")

    # Apply to all three files
    for rel in TARGETS:
        fp = os.path.join(ROOT, rel)
        with open(fp) as f:
            data = json.load(f)
        tagged = 0
        untagged = 0
        for e in data:
            if e["id"] in niche_ids:
                if not e.get("niche"):
                    e["niche"] = True
                    tagged += 1
                else:
                    # already tagged from prev run, keep
                    pass
            else:
                # Re-evaluate: if it had niche=true but shouldn't anymore, remove
                if "niche" in e:
                    del e["niche"]
                    untagged += 1
        with open(fp, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"  {rel}: +{tagged} tagged, -{untagged} untagged")

    # Sanity dump
    print("\nTagged niche exercises (sample):")
    with open(primary) as f:
        data = json.load(f)
    niche_items = [e for e in data if e.get("niche")]
    for e in niche_items[:15]:
        name = e["name"].get("en", e["id"]) if isinstance(e.get("name"), dict) else e["id"]
        print(f"  - {name}")
    if len(niche_items) > 15:
        print(f"  … and {len(niche_items) - 15} more")


if __name__ == "__main__":
    main()
