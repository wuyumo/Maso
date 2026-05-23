#!/usr/bin/env python3
"""Fuzzy match new exercises against old exercises.json to preserve image folders.

Input:
  Maso/Resources/exercises.json                       (old, 873)
  Maso/Resources/new-exercise-db/exercises-new.json   (new, 979)

Output:
  Maso/Resources/new-exercise-db/exercises-matched.json   (new + imageFolder filled)
  Maso/Resources/new-exercise-db/_orphan-old-exercises.md  (old not matched)
  Maso/Resources/new-exercise-db/_missing-image-new.md     (new without image)
  Maso/Resources/new-exercise-db/_match-report.md          (stats)

Match algorithm:
  1. Normalize both old.name and new.name['en']: lowercase, strip parens, collapse whitespace
  2. Token sort + ratio with rapidfuzz (Levenshtein-based)
  3. ≥85 score: auto-match
  4. 70-84 score: manual review queue
  5. <70: no match

Tie-break: when multiple new exercises match the same old (e.g. "Bench Press"
matches both "bench_press_barbell" and "bench_press"), the higher-scored one wins
and the lower one gets None.
"""

import json
import re
from pathlib import Path

try:
    from rapidfuzz import fuzz
except ImportError:
    print("⚠️  rapidfuzz not installed. Run: pip3 install rapidfuzz")
    print("    Falling back to difflib (slower, less accurate)")
    from difflib import SequenceMatcher

    class fuzz:
        @staticmethod
        def token_sort_ratio(a, b):
            return SequenceMatcher(None, a, b).ratio() * 100

        @staticmethod
        def ratio(a, b):
            return SequenceMatcher(None, a, b).ratio() * 100

ROOT = Path(__file__).resolve().parent.parent

OLD_PATH = ROOT / "Maso/Resources/exercises.json"
NEW_PATH = ROOT / "Maso/Resources/new-exercise-db/exercises-new.json"
OUT_MATCHED = ROOT / "Maso/Resources/new-exercise-db/exercises-matched.json"
OUT_ORPHAN = ROOT / "Maso/Resources/new-exercise-db/_orphan-old-exercises.md"
OUT_MISSING = ROOT / "Maso/Resources/new-exercise-db/_missing-image-new.md"
OUT_REPORT = ROOT / "Maso/Resources/new-exercise-db/_match-report.md"

AUTO_MATCH_THRESHOLD = 85
REVIEW_THRESHOLD = 70


def normalize(s):
    """Normalize an exercise name for comparison."""
    s = s.lower()
    s = re.sub(r"\(.*?\)", " ", s)  # strip parentheticals
    s = re.sub(r"[-_,.]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


"""Semantic opposites — penalize matches that contain opposing terms."""
OPPOSITES = [
    ("abduction", "adduction"), ("abduct", "adduct"),
    ("push", "pull"), ("press", "pull"),
    ("curl", "row"), ("curl", "extension"), ("curl", "raise"),
    ("flexion", "extension"),
    ("incline", "decline"), ("upper", "lower"),
    ("internal", "external"), ("front", "rear"), ("front", "back"),
]


def has_opposite_terms(name_a, name_b):
    """Return True if one name has term X and other has opposite Y."""
    a, b = name_a.lower(), name_b.lower()
    for w1, w2 in OPPOSITES:
        if (w1 in a and w2 in b and w1 not in b) or (w2 in a and w1 in b and w2 not in a):
            return True
    return False


def match_best(new_ex, old_records):
    """Return (best_old_record, score) for a new exercise. Considers semantic constraints."""
    en_name = new_ex["name"]["en"]
    norm_new = normalize(en_name)
    new_primary_majors = {m["major"] for m in new_ex.get("muscles", {}).get("primary", [])}
    new_equipment = set(new_ex.get("equipment", []))

    best = None
    best_score = 0
    for old in old_records:
        old_name = old["name"]
        norm_old = normalize(old_name)

        # Skip semantically opposite matches (push vs pull, abduction vs adduction, etc.)
        if has_opposite_terms(norm_new, norm_old):
            continue

        # Three scoring strategies, take max
        s1 = fuzz.token_sort_ratio(norm_new, norm_old)
        s2 = fuzz.token_set_ratio(norm_new, norm_old) if hasattr(fuzz, "token_set_ratio") else s1
        s3 = fuzz.partial_ratio(norm_new, norm_old) if hasattr(fuzz, "partial_ratio") else s1
        score = max(s1, s2, s3)

        # Bonus: equipment match (old has simple equipment string, new has list)
        old_eq = (old.get("equipment") or "").lower().replace(" ", "_")
        eq_match_bonus = 0
        if old_eq and any(eq.lower() in old_eq or old_eq in eq.lower() for eq in new_equipment):
            eq_match_bonus = 5

        # Bonus: primary muscle major match
        old_primaries = old.get("primaryMuscles", [])
        muscle_match_bonus = 0
        # Map old muscle names to new majors
        OLD_TO_MAJOR = {
            "chest": "chest",
            "lats": "back", "middle back": "back", "lower back": "back", "traps": "back",
            "shoulders": "shoulders",
            "biceps": "arms", "triceps": "arms", "forearms": "arms",
            "quadriceps": "legs", "hamstrings": "legs", "glutes": "legs", "calves": "legs",
            "adductors": "legs", "abductors": "legs",
            "abdominals": "core", "neck": "back",
        }
        old_majors = {OLD_TO_MAJOR.get(m, "") for m in old_primaries}
        if new_primary_majors & old_majors:
            muscle_match_bonus = 5

        final_score = min(100, score + eq_match_bonus + muscle_match_bonus)

        if final_score > best_score:
            best_score = final_score
            best = old
    return best, best_score


def main():
    with OLD_PATH.open() as f:
        old_exercises = json.load(f)
    with NEW_PATH.open() as f:
        new_exercises = json.load(f)

    print(f"Old: {len(old_exercises)} exercises")
    print(f"New: {len(new_exercises)} exercises")

    # For each new, find best old match
    matches = []  # list of (new, best_old, score)
    used_old_ids = {}  # old_id -> (best_score, new_idx)

    for new_idx, new_ex in enumerate(new_exercises):
        best_old, score = match_best(new_ex, old_exercises)
        matches.append((new_ex, best_old, score))

    # No tiebreak: multiple new exercises CAN share the same old image folder.
    # Reason: variants of the same movement (Barbell Row / Barbell Row (Smith) / Row (Underhand))
    # legitimately share an illustration. Image is just a visual cue for the movement family.
    used_old_ids = set()  # track which old IDs got reused (for orphan calc)

    # Build final matched output
    matched_new = []
    auto_matched_count = 0
    review_queue = []  # 70-84
    no_match = []     # <70

    for new_idx, (new_ex, best_old, score) in enumerate(matches):
        result = dict(new_ex)  # shallow copy
        if score >= AUTO_MATCH_THRESHOLD and best_old:
            result["imageFolder"] = best_old["id"]
            result["_match_score"] = round(score, 1)
            result["_match_old_name"] = best_old["name"]
            auto_matched_count += 1
            used_old_ids.add(best_old["id"])
        elif REVIEW_THRESHOLD <= score < AUTO_MATCH_THRESHOLD and best_old:
            result["imageFolder"] = None  # need manual review
            result["_pending_review"] = {"old_candidate": best_old["id"], "old_name": best_old["name"], "score": round(score, 1)}
            review_queue.append((new_ex["id"], new_ex["name"]["en"], best_old["name"], round(score, 1)))
        else:
            result["imageFolder"] = None
            no_match.append((new_ex["id"], new_ex["name"]["en"], best_old["name"] if best_old else "", round(score, 1), "below threshold"))
        matched_new.append(result)

    # Orphans: old exercises not used by any new at threshold (regardless of sharing)
    orphan_old = [o for o in old_exercises if o["id"] not in used_old_ids]

    # Write matched
    with OUT_MATCHED.open("w") as f:
        json.dump(matched_new, f, ensure_ascii=False, indent=2)

    # Write orphan report
    orphan_lines = [
        "# 旧动作库中完全没被新库替换的动作",
        "",
        f"**Count**: {len(orphan_old)} / {len(old_exercises)}",
        "",
        "These exercises in the OLD `exercises.json` have no auto-match in the new DB at score ≥85. They will be **lost** when migrating to the new DB unless you manually add equivalents.",
        "",
        "| Old ID | Old Name | Primary Muscles | Category | Equipment |",
        "|---|---|---|---|---|",
    ]
    for o in orphan_old:
        primary = ",".join(o.get("primaryMuscles", []))
        orphan_lines.append(f"| `{o['id']}` | {o['name']} | {primary} | {o.get('category', '')} | {o.get('equipment', '')} |")
    OUT_ORPHAN.write_text("\n".join(orphan_lines))

    # Write missing-image report (new exercises with no image folder assigned)
    missing_lines = [
        "# 新动作库中没有图片素材的动作",
        "",
        f"**Count**: {len(matched_new) - auto_matched_count} / {len(matched_new)}",
        "",
        "These new exercises did NOT auto-match an old exercise's image folder. They need fallback (placeholder/category icon).",
        "",
        "## Manual review queue (score 70-84)",
        "",
        f"**Count**: {len(review_queue)} — borderline matches, you decide if name normalization will fix.",
        "",
        "| New ID | New EN Name | Best Old Candidate | Score |",
        "|---|---|---|---|",
    ]
    for new_id, new_name, old_name, score in review_queue:
        missing_lines.append(f"| `{new_id}` | {new_name} | {old_name} | {score} |")

    missing_lines.append("")
    missing_lines.append("## No match (score <70 or lost tiebreak)")
    missing_lines.append("")
    missing_lines.append(f"**Count**: {len(no_match)} — definitely need a fallback image.")
    missing_lines.append("")
    missing_lines.append("| New ID | New EN Name | Best Candidate | Score | Why |")
    missing_lines.append("|---|---|---|---|---|")
    for new_id, new_name, old_name, score, reason in no_match:
        missing_lines.append(f"| `{new_id}` | {new_name} | {old_name} | {score} | {reason} |")
    OUT_MISSING.write_text("\n".join(missing_lines))

    # Stats report
    report_lines = [
        "# Match Report",
        "",
        f"**Old DB**: {len(old_exercises)} exercises",
        f"**New DB**: {len(new_exercises)} exercises",
        "",
        "## Match results",
        "",
        f"- ✅ **Auto-matched (≥85 score)**: {auto_matched_count} ({auto_matched_count/len(new_exercises)*100:.1f}% of new)",
        f"- 🟡 **Review queue (70-84)**: {len(review_queue)}",
        f"- 🔴 **No match (<70 or tiebreak loss)**: {len(no_match)}",
        "",
        f"## Image coverage",
        "",
        f"- New exercises WITH old image: {auto_matched_count}",
        f"- New exercises WITHOUT old image: {len(matched_new) - auto_matched_count}",
        f"- Image coverage: {auto_matched_count/len(matched_new)*100:.1f}%",
        "",
        f"## Orphan old exercises",
        "",
        f"- Old exercises NOT preserved by new DB: {len(orphan_old)}",
        f"- Old DB preservation rate: {(len(old_exercises) - len(orphan_old))/len(old_exercises)*100:.1f}%",
        "",
        "## Outputs",
        "",
        f"- `exercises-matched.json` — new DB with imageFolder filled (auto-matches only)",
        f"- `_orphan-old-exercises.md` — old exercises that have no equivalent in new DB",
        f"- `_missing-image-new.md` — new exercises without image (review queue + no match)",
    ]
    OUT_REPORT.write_text("\n".join(report_lines))

    print(f"\n✅ Match complete.")
    print(f"   Auto-matched: {auto_matched_count} ({auto_matched_count/len(new_exercises)*100:.1f}%)")
    print(f"   Review queue: {len(review_queue)}")
    print(f"   No match:     {len(no_match)}")
    print(f"   Orphan old:   {len(orphan_old)}")
    print(f"\nReports:")
    print(f"   {OUT_MATCHED}")
    print(f"   {OUT_ORPHAN}")
    print(f"   {OUT_MISSING}")
    print(f"   {OUT_REPORT}")


if __name__ == "__main__":
    main()
