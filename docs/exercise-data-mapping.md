---
title: Exercise Data Mapping — yuhonas → Maso
---

# Exercise data mapping

Where bundled `Maso/Resources/exercises.json` (yuhonas/free-exercise-db,
Unlicense) is translated into the in-app `Exercise` model, and how we
"patch over" gaps in the upstream data without forking the JSON.

The patching layer is `Maso/Data/ExerciseLibrary.swift`. Two things happen
post-load:

1. **Equipment override** — raw exercise `name` containing `"stretch"` gets
   `equipment = "stretching"` (so users can filter all stretches in one tap,
   even when upstream tagged them `body only` / `other` / `nil`).

2. **Muscle inference** — yuhonas's 17-word muscle vocabulary doesn't cover
   `.obliques` (it lumps the entire abdominal wall under `"abdominals"`). We
   add `.obliques` to `primaryMuscles` / `muscleGroups` for exercises whose
   English names match certain keywords. Rules live in
   `inferExtraMuscles(name:existingPrimary:)`.

## Why patch in Swift, not in the JSON

Upstream `exercises.json` is read-only. If we hand-edit it, every upstream
pull becomes a merge conflict. Patching at load time:
- keeps the source-of-truth on yuhonas's side (their data team updates it)
- co-locates rules with the Swift enum they reference (`MuscleGroup`)
- means the rules are version-controlled with the code change that needs them

## Current rules (obliques)

### Strong keywords → primary muscle

| keyword     | rationale                                          |
| ----------- | -------------------------------------------------- |
| `oblique`   | name explicitly mentions the muscle                |
| `side plank`| obliques are the prime mover (anti-lateral flex)   |
| `side bend` | direct oblique loading                             |
| `russian twist` | rotational core (obliques + abs together)      |
| `wood chop` | diagonal cable/MB chop = rotational, obliques heavy |

`.obliques` is appended to `primaryMuscles` (and thus to `muscleGroups`)
when any of these substrings is found in the lowercased `name`.

### Weak keywords → secondary muscle (gated)

| keyword    | gate                                                  |
| ---------- | ----------------------------------------------------- |
| `twist`    | only fires when raw yuhonas tagged `abdominals` already |
| `rotation` | same gate                                              |

The gate exists because "internal/external rotation" is a rotator-cuff
exercise, not core. Without the gate, `Cable External Rotation` would get
`.obliques` falsely.

When the gate passes, `.obliques` is appended to `muscleGroups` only (as a
secondary).

## Verifying the rules

There's a Python verifier at `scripts/cleanup_muscle_tags.py` that re-applies
these rules in pure Python and dumps:
- every exercise that would get `.obliques` as primary
- every exercise that would get it as secondary
- every weak-keyword hit that was skipped for safety (so you can audit the gate)
- per-keyword usage counts (a rule with 0 matches is probably stale)

Run:

```bash
./scripts/cleanup_muscle_tags.py
```

It does **not** write back to JSON. The Swift implementation is the
source-of-truth; the script is a human-readable cross-check. Keep the two in
sync — if you add a keyword to `inferExtraMuscles`, add it to the script too.

## How to add a new inference rule

Use case: you notice yuhonas mistags or under-tags a muscle (e.g. serratus
isn't in their vocabulary either; rotator cuff has the same problem).

1. **Identify the muscle and your keyword set.** Find a few raw exercise
   names that should get the tag. Pick the most specific keywords; prefer
   anatomical terms ("serratus", "punch") over generic ones ("push").

2. **Decide primary vs. secondary.** Primary = the prime mover. Secondary =
   stabilizer / assistant.

3. **Add a case in `inferExtraMuscles`** (in `Maso/Data/ExerciseLibrary.swift`).
   Mirror the obliques structure: a `strongFooKeywords` array for primary, a
   `weakFooKeywords` array for secondary (with a gate to avoid false positives).

4. **Add a sibling check in `scripts/cleanup_muscle_tags.py`** with the same
   keyword lists. Run the script; eyeball the output. Adjust until it's
   clean.

5. **Rebuild** (`xcodegen generate && xcodebuild ...`) and verify in the
   Library Browser that the tags appear on the affected exercises.

## When to re-run after an upstream bump

When `Maso/Resources/exercises.json` is updated from yuhonas, re-run
`./scripts/cleanup_muscle_tags.py` and compare against the previous output.
A new exercise variant might need a keyword added, or a previously matched
exercise might have been renamed and now fall through. The script's
"Skipped weak-keyword hits" section is the best diff hint — entries that
move in/out of that bucket are the ones whose tags changed.
