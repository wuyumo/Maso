#!/usr/bin/env python3
"""
cleanup_muscle_tags.py — Verify the muscle-tag inference rules baked into
`Maso/Data/ExerciseLibrary.swift` against `Maso/Resources/exercises.json`.

Background
----------
The bundled `exercises.json` comes from yuhonas/free-exercise-db (Unlicense).
Its `primaryMuscles` / `secondaryMuscles` vocabulary is fixed at 17 words and
does NOT distinguish obliques (it lumps the whole abdominal wall under
"abdominals"). Our Swift `MuscleGroup` enum has `.obliques` as a separate
case, so the iOS app needs to "patch" the upstream data at load time.

We patch in Swift (post-load, inside `toExercise(...)`) instead of mutating
`exercises.json` directly — that way upgrades from upstream don't conflict,
and the rules live next to the muscle enum they reference.

This script is a non-destructive *verifier* — it re-applies the same rules
in Python and prints:
  - which exercises would get `.obliques` as PRIMARY (strong keywords)
  - which exercises would get `.obliques` as SECONDARY (weak keywords +
    yuhonas already tagged abdominals)
  - any rule that produces 0 matches (= probably stale, worth re-checking)

Run it after:
  - new upstream `exercises.json` pulled in (count drifts? rules need
    updating?)
  - new keyword added to `inferExtraMuscles` in `ExerciseLibrary.swift`
    (keep the two impls in sync — if a Swift case fires here, expect the
    iOS Library Browser to show the same tag)

Usage:
    ./scripts/cleanup_muscle_tags.py

It does NOT write back to JSON; output is for human review only.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
JSON_PATH = REPO / "Maso" / "Resources" / "exercises.json"

# Strong keywords → add .obliques as PRIMARY muscle (it is the prime mover).
# Keep in sync with `strongObliquesKeywords` in
# `Maso/Data/ExerciseLibrary.swift::inferExtraMuscles(name:existingPrimary:)`.
STRONG_OBLIQUES_KEYWORDS = [
    "oblique",
    "side plank",
    "side bend",
    "russian twist",
    "wood chop",
]

# Weak keywords → only count when yuhonas already tagged "abdominals"
# (avoids false-positives on "external/internal rotation" which are rotator-cuff
# moves, not core).
# Keep in sync with `weakObliquesKeywords` in `ExerciseLibrary.swift`.
WEAK_OBLIQUES_KEYWORDS = ["twist", "rotation"]


def main() -> int:
    if not JSON_PATH.exists():
        print(f"error: cannot find {JSON_PATH}", file=sys.stderr)
        return 1
    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))

    primary_hits: list[tuple[str, list[str]]] = []
    secondary_hits: list[tuple[str, list[str], list[str]]] = []
    skipped_for_safety: list[tuple[str, list[str]]] = []
    rule_counters: dict[str, int] = {kw: 0 for kw in STRONG_OBLIQUES_KEYWORDS + WEAK_OBLIQUES_KEYWORDS}

    for ex in data:
        name = ex.get("name", "")
        lower = name.lower()
        primary = ex.get("primaryMuscles", [])
        # secondary = ex.get("secondaryMuscles", [])
        trains_abs = "abdominals" in primary  # gate for weak keywords
        strong_kw = [k for k in STRONG_OBLIQUES_KEYWORDS if k in lower]
        weak_kw = [k for k in WEAK_OBLIQUES_KEYWORDS if k in lower]

        if strong_kw:
            primary_hits.append((name, strong_kw))
            for kw in strong_kw:
                rule_counters[kw] += 1
        elif weak_kw and trains_abs:
            secondary_hits.append((name, weak_kw, primary))
            for kw in weak_kw:
                rule_counters[kw] += 1
        elif weak_kw and not trains_abs:
            skipped_for_safety.append((name, weak_kw))

    print(f"== Inputs ==")
    print(f"  exercises.json:   {len(data)} entries")
    print(f"  strong keywords:  {STRONG_OBLIQUES_KEYWORDS}")
    print(f"  weak keywords:    {WEAK_OBLIQUES_KEYWORDS}")
    print()
    print(f"== Inferred PRIMARY obliques ({len(primary_hits)}) ==")
    for name, kw in primary_hits:
        print(f"  + {name!r}  (kw={kw})")
    print()
    print(f"== Inferred SECONDARY obliques ({len(secondary_hits)}) ==")
    for name, kw, primary in secondary_hits:
        print(f"  ~ {name!r}  (kw={kw}, primary={primary})")
    print()
    print(f"== Skipped weak-keyword hits w/o abdominal primary ({len(skipped_for_safety)}) ==")
    for name, kw in skipped_for_safety:
        print(f"  - {name!r}  (kw={kw})")
    print()
    print(f"== Keyword usage counts ==")
    for kw, count in rule_counters.items():
        flag = " (UNUSED — stale rule?)" if count == 0 else ""
        print(f"  {kw!r:18s} → {count}{flag}")
    print()
    print(f"Total exercises that gain .obliques: {len(primary_hits) + len(secondary_hits)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
