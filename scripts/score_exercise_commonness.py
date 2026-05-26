#!/usr/bin/env python3
"""
Score each exercise by an estimated "commonness" — used to inform cuts of niche
/ noise exercises.

We have 979 exercises but no real usage telemetry. So we score using proxies:
  +30  name matches a canonical "everyone-knows-this" exercise (bench press,
       squat, deadlift, pull-up, row, lat pulldown, hip thrust, leg press,
       bicep curl, tricep pushdown, lateral raise, face pull, crunch, plank,
       lunge, push-up, dip, dumbbell press, military press, leg curl/extension,
       calf raise, shrug, RDL/SLDL, lat pulldown, chin-up, T-bar row).
  +12  equipment is "mainstream gym": body_only / barbell / dumbbell /
       cable / bench_flat / bench_incline / pull_up_bar / machine.
   +6  equipment is "common-but-not-everywhere": kettlebell / ez_bar /
       resistance_band / smith_machine / squat_rack / leg_press_machine.
   -8  equipment is "niche": wrist_roller / sledgehammer / fat_grip /
       grip_crusher / rice_bucket / yoga_strap / pvc_pipe / ...
   +5  has demo video (proxy for popularity in source content)
   +6  category strength + mechanic compound (big-name lifts)
   +3  category calisthenics / cardio (familiar to general users)
   -4  category mobility / stretching (specialized)
   -6  name contains "concentration", "drag", "21s", "21 ", "guillotine",
       "uchi mata", "windshield" — telltale niche cues.

Output: docs/exercise_commonness.md — markdown table sorted by score desc.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXERCISES = os.path.join(ROOT, "Maso/Resources/exercises.json")
OUT = os.path.join(ROOT, "docs/exercise_commonness.md")


CANONICAL_KEYWORDS = [
    # Compounds — the "everyone has heard of these"
    "bench press", "incline bench", "decline bench", "dumbbell bench",
    "squat", "front squat", "barbell squat", "goblet squat",
    "deadlift", "romanian deadlift", "stiff-leg", "sumo deadlift",
    "overhead press", "military press", "shoulder press", "ohp",
    "pull-up", "pullup", "pull up", "chin-up", "chinup", "chin up",
    "push-up", "pushup", "push up",
    "row", "bent-over row", "bent over row", "barbell row", "dumbbell row",
    "t-bar row", "cable row", "seated row",
    "lat pulldown", "pulldown",
    "hip thrust", "glute bridge",
    "leg press", "hack squat",
    "dip", "ring dip",
    # Big accessories
    "bicep curl", "barbell curl", "dumbbell curl", "hammer curl",
    "preacher curl", "ez curl", "concentration curl",
    "tricep pushdown", "triceps pushdown", "tricep extension",
    "triceps extension", "skull crusher", "skullcrusher",
    "close-grip bench", "close grip bench",
    "lateral raise", "side lateral", "front raise",
    "rear delt", "reverse fly", "reverse flye", "face pull",
    "shrug",
    "leg curl", "leg extension",
    "calf raise", "seated calf",
    "lunge", "walking lunge", "split squat", "bulgarian",
    # Core
    "crunch", "plank", "russian twist", "leg raise", "sit-up", "sit up",
    "mountain climber", "hollow hold", "v-up", "v up",
    # Cardio
    "treadmill", "elliptical", "stationary bike", "spin bike",
    "rowing machine", "jump rope", "stair", "burpee",
    # Plyometric
    "box jump", "jump squat", "tuck jump", "broad jump",
    # Stretching (the few that everyone does)
    "hamstring stretch", "quad stretch", "hip flexor stretch",
    "cobra", "child's pose", "downward dog", "pigeon pose",
]


MAINSTREAM_EQ = {
    "body_only", "barbell", "dumbbell", "cable",
    "bench_flat", "bench_incline", "pull_up_bar", "machine",
}
COMMON_EQ = {
    "kettlebell", "ez_bar", "ez_curl_bar", "resistance_band", "band",
    "smith_machine", "squat_rack", "leg_press_machine",
    "rack", "power_rack",
    "bench_decline", "preacher_bench",
    "dip_bar", "dip_bars", "dip_station",
    "rings", "gymnastic_rings",
    "trx",
    "treadmill", "stationary_bike", "elliptical",
    "rowing_machine", "spin_bike", "stairmaster",
    "plyo_box", "jump_rope",
    "leg_curl_machine", "leg_extension_machine", "calf_raise_machine",
    "lat_pulldown_machine",
    "hip_thrust_machine",
    "hyperextension_bench",
    "trap_bar",
}
NICHE_EQ = {
    "wrist_roller", "sledgehammer", "fat_grip",
    "grip_crusher", "rice_bucket", "yoga_strap", "pvc_pipe",
    "tibialis_machine", "donkey_calf_machine", "sissy_squat_machine",
    "reverse_hyper_machine", "ghd_machine",
    "ab_wheel",
    "captains_chair",
    "weight_belt", "dip_belt", "chains",
    "axle_bar", "safety_squat_bar", "belt_squat_machine",
    "platform", "sled", "prowler", "ski_erg", "arc_trainer", "assault_bike",
    "battle_rope", "sliders", "swiss_ball", "exercise_ball",
    "medicine_ball", "foam_roller",
    "abductor_machine", "adductor_machine",
    "back_extension_machine", "hack_squat_machine",
    "glute_kickback_machine",
    "parallel_bars", "push_up_handles",
    "weight_plate", "landmine",
    "towel",
}
NOISE_NAME_CUES = [
    "concentration", "drag curl", "21s", "21 ", "guillotine",
    "uchi mata", "windshield", "kroc", "yates",
    "hindu", "russian dip",
    "tate press",
    "around the world", "around-the-world",
]


def name_canonical_score(name_lc):
    """+30 if name contains a canonical keyword."""
    for kw in CANONICAL_KEYWORDS:
        if kw in name_lc:
            return 30
    return 0


def equipment_score(eqs):
    """Mainstream / common / niche by best-of-set."""
    score = 0
    for q in eqs or []:
        if q in MAINSTREAM_EQ:
            score = max(score, 12)
        elif q in COMMON_EQ:
            score = max(score, 6)
        elif q in NICHE_EQ:
            score = min(score, -8)
    # If empty / no eq known, neutral
    return score


def noise_penalty(name_lc):
    for cue in NOISE_NAME_CUES:
        if cue in name_lc:
            return -6
    return 0


def category_score(category, mechanic):
    if category == "strength":
        return 6 if mechanic == "compound" else 0
    if category == "calisthenics":
        return 3
    if category == "cardio":
        return 3
    if category == "plyometric":
        return 1
    if category in ("mobility", "stretching"):
        return -4
    return 0


def score_exercise(e):
    name = e.get("name", {})
    if isinstance(name, dict):
        name_en = name.get("en") or ""
    else:
        name_en = str(name)
    name_lc = name_en.lower()
    s = 0
    s += name_canonical_score(name_lc)
    s += equipment_score(e.get("equipment") or [])
    s += 5 if e.get("video_url") else 0
    s += category_score(e.get("category"), e.get("mechanic"))
    s += noise_penalty(name_lc)
    return s, name_en


def main():
    with open(EXERCISES) as f:
        data = json.load(f)
    rows = []
    for e in data:
        s, name_en = score_exercise(e)
        rows.append({
            "id": e["id"],
            "name": name_en,
            "category": e.get("category"),
            "mechanic": e.get("mechanic"),
            "equipment": ", ".join(e.get("equipment") or []),
            "has_video": "✓" if e.get("video_url") else "",
            "score": s,
        })
    rows.sort(key=lambda r: (-r["score"], r["name"]))

    # Buckets for the report
    keep = [r for r in rows if r["score"] >= 25]
    maybe = [r for r in rows if 10 <= r["score"] < 25]
    weak = [r for r in rows if -5 <= r["score"] < 10]
    cut = [r for r in rows if r["score"] < -5]

    # Group counts by category to summarize
    from collections import Counter
    cat_counts = Counter(r["category"] for r in rows)

    lines = []
    lines.append("# Exercise Commonness Audit")
    lines.append("")
    lines.append(f"_Total exercises: {len(rows)} • Generated by `scripts/score_exercise_commonness.py`._")
    lines.append("")
    lines.append("## Why this exists")
    lines.append("")
    lines.append("We have **979** exercises bundled but no real usage telemetry. This audit estimates "
                 "how recognizable each exercise is to a general gym-goer based on:")
    lines.append("- whether the name matches a canonical lift (bench press, squat, pull-up, …)")
    lines.append("- equipment popularity (mainstream / common / niche)")
    lines.append("- has a demo video (proxy for content quality / familiarity)")
    lines.append("- category bias (strength / calisthenics / cardio score above mobility / stretching)")
    lines.append("- penalties for telltale-niche name cues (\"concentration\", \"21s\", \"Yates\", …)")
    lines.append("")
    lines.append("**Recommendation buckets** (you decide where to cut):")
    lines.append("")
    lines.append(f"| Bucket | Score | Count | Suggestion |")
    lines.append(f"|---|---|---|---|")
    lines.append(f"| **Keep — core** | ≥ 25 | {len(keep)} | Definitely keep, well-known to most users |")
    lines.append(f"| **Keep — common** | 10 – 24 | {len(maybe)} | Familiar variations; safe to keep |")
    lines.append(f"| **Borderline** | -5 – 9 | {len(weak)} | Niche or specialized; consider trimming |")
    lines.append(f"| **Cut candidates** | < -5 | {len(cut)} | Niche equipment + obscure name; recommend cut |")
    lines.append("")
    lines.append("## Category breakdown")
    lines.append("")
    lines.append("| Category | Count |")
    lines.append("|---|---|")
    for c, n in cat_counts.most_common():
        lines.append(f"| {c} | {n} |")
    lines.append("")

    def render_table(rs, title):
        lines.append(f"## {title} ({len(rs)})")
        lines.append("")
        lines.append("| Score | Name | Category | Mechanic | Equipment | Video | ID |")
        lines.append("|---:|---|---|---|---|:---:|---|")
        for r in rs:
            lines.append(
                f"| {r['score']} | {r['name']} | {r['category']} | {r['mechanic'] or ''} | "
                f"{r['equipment']} | {r['has_video']} | `{r['id']}` |"
            )
        lines.append("")

    render_table(cut, "Cut candidates")
    render_table(weak, "Borderline")
    render_table(maybe, "Keep — common")
    render_table(keep, "Keep — core")

    with open(OUT, "w") as f:
        f.write("\n".join(lines))

    print(f"Wrote {OUT}")
    print(f"  Keep core:     {len(keep)}")
    print(f"  Keep common:   {len(maybe)}")
    print(f"  Borderline:    {len(weak)}")
    print(f"  Cut candidates: {len(cut)}")


if __name__ == "__main__":
    main()
