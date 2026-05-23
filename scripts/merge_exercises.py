#!/usr/bin/env python3
"""Merge 7 agent-generated JSON files into single exercises-new.json + dedup + validate.

Inputs:
  Maso/Resources/new-exercise-db/1-chest-triceps.json
  Maso/Resources/new-exercise-db/1b-triceps-supplement.json
  Maso/Resources/new-exercise-db/2-shoulders.json
  Maso/Resources/new-exercise-db/3-back-biceps-forearms.json
  Maso/Resources/new-exercise-db/4-legs.json
  Maso/Resources/new-exercise-db/5-core-stretching.json
  Maso/Resources/new-exercise-db/6-cardio-plyo-cali.json

Outputs:
  Maso/Resources/new-exercise-db/exercises-new.json  (merged + deduped)
  Maso/Resources/new-exercise-db/_merge-report.md     (stats + dedup decisions)

Dedup strategy: if same ID in 2+ files, keep the one whose primary muscle's
major matches the file's intended scope (e.g. pistol_squat → keep from legs not cali).
Fallback: keep first occurrence.
"""

import json
import sys
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
DB_DIR = ROOT / "Maso/Resources/new-exercise-db"

# File → expected primary major (for dedup tiebreak)
FILES = [
    ("1-chest-triceps.json",          {"chest", "arms"}),
    ("1b-triceps-supplement.json",    {"arms"}),
    ("2-shoulders.json",              {"shoulders"}),
    ("3-back-biceps-forearms.json",   {"back", "arms"}),
    ("4-legs.json",                   {"legs"}),
    ("5-core-stretching.json",        {"core", "back", "legs", "chest", "shoulders", "arms"}),  # stretching can target any
    ("6-cardio-plyo-cali.json",       {"legs", "core", "back", "chest", "shoulders", "arms"}),  # cross-body
]

# Required fields per exercise
REQUIRED_FIELDS = {
    "id", "name", "muscles", "equipment", "category",
    "movementPattern", "mechanic", "unilateral", "tempo", "level", "force",
    "imageFolder", "instructions", "video_url", "calories_estimate", "danger_warnings",
}

VALID_CATEGORIES = {"strength", "hypertrophy_focus", "cardio", "stretching", "mobility", "plyometric", "calisthenics"}
VALID_MOVEMENT_PATTERNS = {None, "push_horizontal", "push_vertical", "pull_horizontal", "pull_vertical", "hinge", "squat", "lunge", "rotation"}
VALID_MECHANICS = {"compound", "isolation"}
VALID_TEMPOS = {"strength", "hypertrophy", "endurance", "explosive", "isometric"}
VALID_LEVELS = {"beginner", "intermediate", "advanced"}
VALID_FORCES = {"push", "pull", "static"}
VALID_MAJORS = {"chest", "back", "shoulders", "arms", "legs", "core"}

def load_file(filename):
    """Return list of exercises from a file."""
    path = DB_DIR / filename
    with path.open() as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"{filename}: expected list, got {type(data)}")
    return data

def validate_exercise(ex, source_file):
    """Return list of validation errors (empty = valid)."""
    errors = []
    ex_id = ex.get("id", "<no-id>")

    # Required fields
    missing = REQUIRED_FIELDS - set(ex.keys())
    if missing:
        errors.append(f"{ex_id}: missing fields {missing}")

    # name structure
    name = ex.get("name", {})
    if not (isinstance(name, dict) and "en" in name and "zh-Hans" in name):
        errors.append(f"{ex_id}: name must be {{en, zh-Hans}}")

    # muscles structure
    muscles = ex.get("muscles", {})
    primary = muscles.get("primary", [])
    if not primary:
        errors.append(f"{ex_id}: muscles.primary is empty")
    for m in primary + muscles.get("secondary", []):
        if not isinstance(m, dict) or "major" not in m or "sub" not in m:
            errors.append(f"{ex_id}: muscle entry missing major/sub: {m}")
        elif m["major"] not in VALID_MAJORS:
            errors.append(f"{ex_id}: invalid major '{m['major']}'")

    # Enum fields
    if ex.get("category") not in VALID_CATEGORIES:
        errors.append(f"{ex_id}: invalid category '{ex.get('category')}'")
    if ex.get("movementPattern") not in VALID_MOVEMENT_PATTERNS:
        errors.append(f"{ex_id}: invalid movementPattern '{ex.get('movementPattern')}'")
    if ex.get("mechanic") not in VALID_MECHANICS:
        errors.append(f"{ex_id}: invalid mechanic '{ex.get('mechanic')}'")
    if ex.get("tempo") not in VALID_TEMPOS:
        errors.append(f"{ex_id}: invalid tempo '{ex.get('tempo')}'")
    if ex.get("level") not in VALID_LEVELS:
        errors.append(f"{ex_id}: invalid level '{ex.get('level')}'")
    if ex.get("force") not in VALID_FORCES:
        errors.append(f"{ex_id}: invalid force '{ex.get('force')}'")
    if not isinstance(ex.get("unilateral"), bool):
        errors.append(f"{ex_id}: unilateral must be bool")

    # Instructions structure
    instr = ex.get("instructions", {})
    if not (isinstance(instr, dict) and "en" in instr and "zh-Hans" in instr):
        errors.append(f"{ex_id}: instructions must be {{en[], zh-Hans[]}}")

    # Calories structure
    cal = ex.get("calories_estimate", {})
    if not (isinstance(cal, dict) and all(k in cal for k in ("low", "med", "high"))):
        errors.append(f"{ex_id}: calories_estimate must be {{low, med, high}}")

    return errors


def pick_winner(candidates, expected_majors_by_file):
    """Tiebreak: choose exercise whose primary major matches the file's expected scope."""
    for cand, source_file in candidates:
        expected = expected_majors_by_file.get(source_file, set())
        primary_major = cand["muscles"]["primary"][0]["major"]
        if primary_major in expected:
            return cand, source_file
    return candidates[0]


def main():
    all_exercises_by_id = defaultdict(list)  # id -> [(exercise, source_file)]
    all_errors = []
    file_counts = {}

    # Load all files
    expected_majors_by_file = {f: m for f, m in FILES}
    for filename, _ in FILES:
        try:
            exercises = load_file(filename)
        except FileNotFoundError:
            print(f"⚠️  {filename}: not found, skipping")
            continue
        file_counts[filename] = len(exercises)
        for ex in exercises:
            # Validate first
            errs = validate_exercise(ex, filename)
            all_errors.extend(errs)
            if not errs:  # only include valid exercises in merge
                all_exercises_by_id[ex["id"]].append((ex, filename))

    # Dedup
    final_exercises = []
    dedup_log = []
    for ex_id, candidates in sorted(all_exercises_by_id.items()):
        if len(candidates) == 1:
            final_exercises.append(candidates[0][0])
        else:
            winner, winner_file = pick_winner(candidates, expected_majors_by_file)
            losers = [src for ex, src in candidates if src != winner_file]
            dedup_log.append(f"- `{ex_id}`: kept from {winner_file}, dropped {losers}")
            final_exercises.append(winner)

    # Write merged file
    out_path = DB_DIR / "exercises-new.json"
    with out_path.open("w") as f:
        json.dump(final_exercises, f, ensure_ascii=False, indent=2)

    # Write report
    report = [
        "# Merge Report",
        "",
        f"**Total exercises (after dedup)**: {len(final_exercises)}",
        f"**Validation errors**: {len(all_errors)}",
        f"**Duplicate IDs across files**: {len(dedup_log)}",
        "",
        "## File counts (input)",
        "",
    ]
    for f, n in file_counts.items():
        report.append(f"- `{f}`: {n}")
    report.append("")

    if all_errors:
        report.append("## Validation Errors")
        report.append("")
        for e in all_errors[:50]:
            report.append(f"- {e}")
        if len(all_errors) > 50:
            report.append(f"...and {len(all_errors)-50} more")
        report.append("")

    if dedup_log:
        report.append("## Dedup Log")
        report.append("")
        report.extend(dedup_log)

    report.append("")
    report.append("## Category breakdown")
    report.append("")
    cat_count = defaultdict(int)
    for ex in final_exercises:
        cat_count[ex["category"]] += 1
    for cat, n in sorted(cat_count.items(), key=lambda x: -x[1]):
        report.append(f"- `{cat}`: {n}")

    report.append("")
    report.append("## Primary major breakdown")
    report.append("")
    major_count = defaultdict(int)
    for ex in final_exercises:
        major_count[ex["muscles"]["primary"][0]["major"]] += 1
    for major, n in sorted(major_count.items(), key=lambda x: -x[1]):
        report.append(f"- `{major}`: {n}")

    with (DB_DIR / "_merge-report.md").open("w") as f:
        f.write("\n".join(report))

    print(f"✅ Merged {len(final_exercises)} exercises")
    print(f"   Errors: {len(all_errors)}")
    print(f"   Dedup: {len(dedup_log)} duplicates resolved")
    print(f"   Output: {out_path}")
    print(f"   Report: {DB_DIR / '_merge-report.md'}")

    if all_errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
