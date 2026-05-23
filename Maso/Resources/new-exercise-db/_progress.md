# Exercise DB Generation — Progress Tracker

Started: 2026-05-23

## Phase 1 — Data Generation (✅ Complete)

| # | Scope | Target | Actual | Output | Status |
|---|---|---|---|---|---|
| 1 | Chest (~120) — agent cut by socket error mid-stream | ~180 | 121 (mostly chest) | `1-chest-triceps.json` | ⚠️ partial |
| 1b | Triceps supplement | ~60 | 62 | `1b-triceps-supplement.json` | ✅ |
| 2 | Shoulders | ~100 | 114 | `2-shoulders.json` | ✅ |
| 3 | Back + Biceps + Forearms | ~200 | 199 | `3-back-biceps-forearms.json` | ✅ |
| 4 | Legs (quads/hams/glutes/calves/etc.) | ~250 | 250 | `4-legs.json` | ✅ |
| 5 | Core + Stretching | ~120 | 120 | `5-core-stretching.json` | ✅ |
| 6 | Cardio + Plyo + Cali + Mobility | ~150 | 150 | `6-cardio-plyo-cali.json` | ✅ |
| A | Anatomy redraw research | 2-3 options | 3 approaches | `_anatomy-research.md` | ✅ |

**Raw total**: 1018 exercises (across 7 files, before dedup).

## Phase 1.5 — Merge + Validate (✅ Complete)

Script: `scripts/merge_exercises.py`

- Schema validated: 0 errors after expanding `movementPattern` enum with `lunge`, `rotation`
- Cross-file deduplication: 37 duplicate IDs resolved
- **Merged total: 979 unique exercises** → `exercises-new.json`
- Report: `_merge-report.md`

## Phase 1.6 — Anatomy decision (✅ Complete)

User picked **Approach 1: MuscleMap SwiftUI SDK** (`melihcolpan/MuscleMap`).
- MIT, iOS 17+, 0 dependencies, 21/27 sub-muscle native coverage
- Will be integrated in Phase 3.5

## Phase 2 — Fuzzy match against old library (✅ Complete)

Script: `scripts/fuzzy_match_old_exercises.py`

Algorithm:
- Token sort + token set + partial ratio (rapidfuzz)
- Semantic opposites filter (push ≠ pull, abduction ≠ adduction, etc.)
- Equipment + primary muscle bonus
- No tiebreak — multiple new exercises CAN share an image folder (variants of same movement)

### Results
| Category | Count | % of new |
|---|---|---|
| ✅ Auto-matched (≥85) | **849** | **86.7%** |
| 🟡 Review queue (70-84) | 108 | 11.0% |
| 🔴 No match (<70) | 22 | 2.3% |
| Orphan old (lost) | 572 / 873 | 65.5% |

Output: `exercises-matched.json` (979 exercises with `imageFolder` filled where matched).

### Deliverable reports (跟用户最终要的两个列表)
- `_orphan-old-exercises.md` — **572 old exercises** that the new DB doesn't cover (will be lost on migration)
- `_missing-image-new.md` — 22 no-match + 108 review queue (new exercises without images)

## Phase 3 — App schema migration (⏳ Pending)
- Update `Maso/Models/Exercise.swift` with new fields
- Update `Maso/Data/ExerciseLibrary.swift` parser
- Update `Maso/Models/MuscleGroup.swift` with 27 sub-muscles
- Update SwiftUI components (BodyHint, MuscleSelector, ExerciseLibraryBrowser)
- Migrate user data: `Settings.favoriteExerciseIds`, plan steps (use `Plans v1 → v2 migration`)

## Phase 3.5 — MuscleMap integration (⏳ Pending)
- Add SPM dep
- Write `Maso/Models/MuscleMapping.swift` (Maso.MuscleGroup ↔ MuscleMap.Muscle)
- Rewrite `BodyHint.swift` to wrap MuscleMap's BodyView

## Phase 4 — Validation + reports (⏳ Pending)
- App boot + library browser load test
- Image CDN URL probe (validate matched folders return 200)
- Final orphan + missing-image polish based on user manual review
