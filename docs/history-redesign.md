# Maso — "History" Tab Redesign: IA, Rename & Pro Tiering

Build-ready spec against the live codebase. All file paths and symbol names are real.

---

## 1. Tab rename

The tab now holds **analysis** (`ProgressChartsView`, `TrainingActivityHeatmap`, stats row) **+ records** (`InlineWorkoutCalendar`, `SessionCard` list). "History" only describes the records half.

| # | EN | zh-Hans | Covers analysis? | Covers records? | Notes |
|---|----|---------|------------------|-----------------|-------|
| A | **Progress** | **进度** | ✅ strong | ⚠️ implies records loosely | Aspirational; matches the empty-state icon already in code (`chart.line.uptrend.xyaxis`) and the existing "Progress" section header (en line 289). |
| B | Insights | 洞察 | ✅ | ❌ records feel out of place | Too "analytics-only"; mismatches the session log. |
| C | Stats | 数据 | ✅ | ❌ | Already used as a *segment* label (en 1120 / zh 1121) — reusing it for the tab collides. |
| D | Trends | 趋势 | ✅ | ❌ | Same problem as Insights. |

**RECOMMENDATION: `Progress` / `进度`.**

- It is the umbrella users already map to "am I getting stronger + here's what I did" — the exact analysis+records pairing this tab holds.
- Market precedent: Strong, Hevy, Gymshark, Liftin' all file longitudinal data under "Progress." It reads as *the value tab*, which is correct since Pro upsell lives here (`ProBanner`).
- Lowest churn: `"Progress" = "进度"` **already exists** in both Localizable files. Reuse it as the tab/nav title; do not invent a new key. The old section header named "Progress" gets renamed (see §2) to avoid a tab-title-equals-section-title collision.

**Rename touches three spots (all currently the literal string `"History"`):**
1. `RootView.swift:236` — `Label("History", systemImage: "clock.fill")` → `Label("Progress", systemImage: "chart.line.uptrend.xyaxis")` (icon now matches; `clock.fill` read as "history/time" and is wrong for an analysis tab).
2. `HistoryScreen.swift:220` — `.screenHeader("History")` → `.screenHeader("Progress")`.
3. `Localizable.strings` — `"History"` key stays (still used by other strings); the tab/title now resolves through the existing `"Progress"` key. No string edits required for the rename itself.

> Keep the type name `HistoryScreen` / file `HistoryScreen.swift` — renaming the Swift type is churn with no user value and touches `RootView`, showcase routing (`case "history"` RootView:104), and `RootTab.history`. Rename the *label*, not the *type*.

---

## 2. New IA — two segments at the very top

**Move the `Picker(.segmented)` above the stats-row + calendar card** (it currently sits *below* them, HistoryScreen:148). Per the owner's ask, the two segments lead the screen so the analysis/records split is the first thing seen.

### Segment names

| Segment | EN | zh-Hans | Holds |
|---------|----|---------|----|
| 1 (default) | **Insights** | **数据** | All training-data analysis |
| 2 | **History** | **训练记录** | Calendar + per-session log |

Rationale: the *tab* is "Progress"; inside it, segment 1 = the analysis ("Insights/数据"), segment 2 = the literal records ("History/训练记录" — reuse existing keys). This frees "History" to mean *just records*, which fixes the owner's core complaint without wasting the well-understood word. The default segment stays the data view (current default is `.stats`).

> Replace the `HistoryTab` enum `{ stats, workouts }` with `{ insights, records }` (rename cases only; `.insights` default). Update the two `Text(...).tag(...)` lines to `Text("Insights").tag(.insights)` / `Text("History").tag(.records)`.

### Layout change

Current fixed header (ProBanner + combined stats/calendar card) renders **always**, with the segment buried below. New order inside the `ScrollView` VStack:

1. `ProBanner` (unchanged, `!isPro` only)
2. **Segment `Picker` ← moved to top**
3. **If `.insights`:** stats row + Insights modules
4. **If `.records`:** the combined **3-metric row + `InlineWorkoutCalendar` card** (records context) + week-grouped `SessionCard` list

The 3-metric row (`weeklyStatsCard`/`monthlyStatsCard`) and the calendar belong with **History/records**, not Insights — they answer "what did I do / when," not "am I progressing." This also keeps the calendar's collapse/expand + month-anchor logic self-contained in the records segment.

### Module-by-module re-categorization

| Module (real symbol / file) | Today | Proposed segment | Free / Pro (proposed) |
|---|---|---|---|
| 3-metric stats row — `weeklyStatsCard`/`monthlyStatsCard` (HistoryScreen) | header (always) | **History** | Free |
| `InlineWorkoutCalendar` (per-day muscle dots) | header (always) | **History** | Free |
| This-vs-last delta tiles — `deltaRow`/`deltaTile` (ProgressChartsView) | Stats | **Insights** | Free |
| Weekly volume bar chart (8 wk) — `volumeCard`/`weeklyVolume()` | Stats | **Insights** | **Free** (the "simple chart" table-stake) |
| Estimated-1RM trend (top lift) — `oneRMCard`/`oneRMChart` | Stats (Pro-blurred) | **Insights** | **Pro** (unchanged) |
| Muscle balance (sets/region this wk) — `muscleBalanceCard` | Stats | **Insights** | **Free** (current-week snapshot) |
| Activity heatmap (16 wk) — `TrainingActivityHeatmap` | Stats "Activity" | **Insights** | Free |
| Session cards (week-grouped) + PR badge — `SessionCard`/`groupedSessions()` | Workouts | **History** | Free |
| `SessionDetailSheet` (per-exercise stats) | sheet | **History** (sheet) | Free |
| `RoutineOptimizeCard` (Today/Plans) | Today/Plans | **stays on Today/Plans** | Free teaser, Pro action (unchanged) |
| **NEW** per-lift e1RM picker, volume-trend, per-muscle-volume, frequency, PR timeline, MEV/MAV (see §4) | — | **Insights** | **Pro** |

Free tier stays genuinely useful (calendar, full log, session detail, current-week volume bar, this-vs-last deltas, muscle-balance snapshot, activity heatmap, basic PR badges) — matching Hevy/Strong free norms — while the *longitudinal/per-muscle/multi-lift* depth becomes the Pro draw.

---

## 3. Pro tiering (grounded in MARKET's free/premium line)

MARKET's de-facto line: **free = log + review your own training; gate depth & intelligence** (long-range windows, trend charts, cross-cutting per-muscle analytics, strength scores, MEV/MAV, recovery modeling). The only "universally safe thing to charge for is intelligence layered on top of data the user could otherwise see for free."

Maso today gates **only** the 1RM trend — too thin. Strategy: keep a complete free logger, push **all longitudinal & per-muscle intelligence** into Pro.

| Capability | Free | Pro |
|---|---|---|
| Workout logging, full session log, `SessionDetailSheet` | ✅ unlimited | ✅ |
| Calendar (`InlineWorkoutCalendar`) + 3-metric row | ✅ | ✅ |
| Streak / adherence (basic) — `currentWeekStreak()` | ✅ | ✅ |
| This-week-vs-last deltas — `deltaRow` | ✅ | ✅ |
| **Weekly volume bar (last 8 wk)** — `volumeCard` | ✅ (the "one simple chart") | ✅ + **all-time range** |
| Muscle balance — **current week** | ✅ snapshot | ✅ + **trend over time** |
| Activity heatmap (16 wk) | ✅ | ✅ + all-time |
| PR badges on session cards | ✅ (the dopamine hook stays free) | ✅ |
| **Estimated-1RM trend** | 🔒 | ✅ (already gated) |
| **Per-lift e1RM progression (any lift, picker)** | 🔒 | ✅ new |
| **Per-muscle volume/tonnage over time** | 🔒 | ✅ new |
| **Training frequency per muscle** | 🔒 | ✅ new |
| **PR timeline / history view** | 🔒 | ✅ new |
| **Sets-per-muscle vs MEV/MAV/MRV landmarks** | 🔒 | ✅ new (whitespace) |
| **Consistency/monotony score, all-time tonnage** | 🔒 | ✅ new |
| AI routine optimization (`RoutineOptimizeCard` action) | teaser | ✅ (already gated) |

This mirrors **Strong's "graphs are paid"** for the deep charts while keeping a **Hevy-grade free logger** — the safest spot in the bifurcated market for an indie at Maso's price.

---

## 4. New premium metrics to ADD (zero new data collection)

All computable from `data.sets: [SetRecord]` + `data.exById` per `CURRENT.availableData` ("Feasible premium metrics with zero new data collection"). Add as new private card builders in `ProgressChartsView.swift` (or a sibling `InsightsChartsView.swift`), each gated with the **existing** blur+lock pattern (`oneRMCard`, lines 84–117).

| Metric | What it shows | Data (confirmed available) | Tier |
|---|---|---|---|
| **Per-lift e1RM progression** | e1RM trend for *any chosen* lift, not just top — adds an exercise picker above `oneRMChart` | `topLiftSeries()` already builds per-day best e1RM (Epley); generalize to take an `exerciseId`. "per-exercise per-day best e1RM time series for ANY lift" ✅ | Pro |
| **Total-volume trend (all-time)** | Volume line beyond the free 8-week window | `weeklyVolume()` per ISO week; just extend the window ✅ | Pro |
| **Per-muscle volume over time** | Weekly tonnage per major section, trend lines / stacked | "per-muscle weekly volume/tonnage trends" ✅ via `ex.primaryMuscles.first.section` (already used in `weeklySetsPerSection`) | Pro |
| **Training frequency per muscle** | How many days/wk each muscle is hit | per-day section counts from `data.sets` ✅ | Pro |
| **PR timeline** | Chronological list of PRs (weight/e1RM/rep/volume) | `data.isPR(record)` already flags PRs per record ✅ | Pro |
| **Sets/muscle vs MEV/MAV/MRV** | Weekly hard-sets per muscle with green/under/over band vs ~10–20 set targets | `weeklySetsPerSection()` gives the count; add static landmark thresholds ✅. **Market whitespace** — almost no app ships this. | Pro |
| **Consistency / monotony score** | Single adherence/variability number (days/wk vs `weeklyTrainingDays`) | week-streak + per-week set counts ✅ | Pro |
| **All-time tonnage** | Lifetime cumulative weight moved (vanity + load proxy) | sum `weight*reps` over all sets ✅ | Pro |

Lead with **per-lift e1RM picker** + **MEV/MAV landmarks** — the first generalizes Maso's already-gated hero chart (cheap, high perceived value), the second is genuine market whitespace the evidence-based crowd will pay for.

---

## 5. Muscle Status (Today) — decision

`MuscleStatusOverviewCard` (Today, fully free today). Three options:

- **Keep fully free** — loses a strong Pro lever; the per-muscle fatigue map is exactly the kind of "intelligence layered on data" MARKET says is the *only* safe thing to charge for (it's Fitbod's entire paid differentiator and WHOOP's whole product).
- **Fully Pro** — too aggressive. It sits at the **top of the training entry screen** and drives `onStartGapWorkout` (builds the next workout from gaps). Gating it cripples the free core loop and the app's "smart coach" first impression — bad for conversion and reviews.
- **✅ RECOMMENDED: tease-free, full-value-Pro.**

**Implementation (cleanest, reuses existing gate):**
- Free: render the **body map heat-shading** (it's beautiful and sells the product) but show it **coarse-only** — force the existing `coarseOnly` path (already exists for `!settings.muscleDetailEnabled`) regardless of setting, and **replace the 4-tier legend + per-muscle precision with a Pro nudge**.
- Pro: full per-muscle fatigue precision (fine `MuscleStatusCompute.opacityFor`), the 4-tier legend (Heavy fatigue → Fresh), and the `Train-the-gaps` CTA with specific `gapMuscles`.
- Free CTA: small "Unlock per-muscle recovery with Pro" row under the map → `paywall`. Keep the empty-history "Finish-a-workout" nudge as-is.

This keeps the *visual hook* (the glowing body) free to drive desire, gates the *actionable precision* (which muscle exactly, train-the-gaps targeting) — directly modeling the Fitbod/WHOOP recovery-as-premium pattern while staying brand-friendly (privacy-forward, generous-but-honest).

> Reuse the `oneRMCard` blur+lock approach: blur the legend/precision column, overlay the unlock button. No new gating mechanism — `data.settings.isPro` + an `onUnlock` closure threaded from `TodayScreen` to the card (same as `HistoryScreen` passes `onUnlock = { paywallPresented = true }`).

---

## 6. Build plan (ordered)

1. **`Maso/Views/RootView.swift`** — tab label `"History"`→`"Progress"`, icon `clock.fill`→`chart.line.uptrend.xyaxis` (line 236). Leave `RootTab.history`, `case "history"` routing, type name untouched.
2. **`Maso/Views/Screens/HistoryScreen.swift`** —
   - `.screenHeader("History")`→`"Progress"` (line 220).
   - Rename `HistoryTab` cases `stats/workouts`→`insights/records`, default `.insights`; update the two `.tag()` + `Text()` (148–151) to `Insights`/`History`.
   - **Move the `Picker` to the top** of the VStack (above ProBanner-or-card); restructure so 3-metric row + `InlineWorkoutCalendar` render under `.records`, charts under `.insights`. ⚠️ *Risk:* the calendar's `calendarCollapsed`/`calendarMonthAnchor` state + the `geo.size.height` centering for the empty state must stay wired — re-test expand/collapse and the no-workouts empty state after the move.
   - Rename the in-segment section header `"Progress"`→ a new `"Trends"` (or drop it) to avoid colliding with the new tab title. Add localized key.
3. **`Maso/Views/Components/ProgressChartsView.swift`** — add new Pro card builders (§4), each using the `oneRMCard` blur+lock pattern reading `data.settings.isPro` + `onUnlock`. Generalize `topLiftSeries()` to accept an `exerciseId` for the lift picker. Add MEV/MAV landmark constants. ⚠️ *Risk:* `isEmpty` gating — ensure new Pro cards still render (blurred) for free users so the upsell is visible, matching current `oneRMCard` behavior.
4. **`Maso/Views/Components/MuscleStatusOverviewCard.swift`** — add `isPro` branch: free = `coarseOnly` map + blurred legend + unlock nudge; Pro = full precision + legend + gap CTA. Thread `onUnlock` from `TodayScreen.swift` (mirror HistoryScreen).
5. **`Maso/Views/Screens/TodayScreen.swift`** — pass `onUnlock` (paywall) into `MuscleStatusOverviewCard` (line ~102).
6. **Localizable (`Maso/Resources/{en,zh-Hans}.lproj/Localizable.strings`)** —
   - Reuse existing `"Progress"="进度"` (tab/title), `"History"="训练记录"`, `"Stats"`→ repurpose or add `"Insights"="数据"`.
   - Add: `"Insights"`, `"Trends"` (new section header), unlock strings for each new Pro card + Muscle Status nudge (`"Unlock per-muscle recovery with Pro"`), MEV/MAV labels, PR-timeline title, frequency title.
   - ⚠️ *Risk:* both `lproj` must stay key-parallel (project is en + zh-Hans only). Add every new key to both.

**Verify:** run `verify-app` (Maso skill) — confirms compile, exercises.json integrity, and that Today / Insights / History segments render distinctly — before device install. No `project.yml` change needed unless a new `InsightsChartsView.swift` file is added (then add to `project.yml` + `xcodegen generate`).

**Lowest-risk first ship:** steps 1–2 + 6 (rename + IA reorder) are pure restructuring with no new data math — land and verify those, then layer the new Pro metrics (3) and Muscle Status gating (4–5) in a second pass.",
    "market": {
      "apps": [
        {
          "name": "Strong",
          "freeAnalytics": "Per-exercise history list, auto-updating estimated 1RM calculator (tap an exercise to see current e1RM), basic personal-record badges, full past-workout log, body-measurement logging. Workout summary shows that session's total volume/sets/duration.",
          "premiumAnalytics": "All progression-over-time CHARTS (e1RM trend per lift, max-weight trend, volume trend), advanced volume & frequency analytics per muscle group, plate-calculator/extra-set features, unlimited routines, CSV export. Free is capped at 3 custom routines and the trend charts are gated.",
          "notes": "Pro $9.99/mo or $59.99/yr. The classic 'logging is free, the GRAPHS are paid' model. Free is a great logger but you can't visualize progression without Pro — the single biggest gripe in reviews."
        },
        {
          "name": "Hevy",
          "freeAnalytics": "Generous free analytics: per-exercise charts (e1RM, heaviest weight, 1RM, total volume, reps), sets-per-muscle-group-per-week, muscle-distribution chart, PR tracking, workout duration/volume/set counts, body-measurement charts. Distinguishes itself by NOT gating analytics depth.",
          "premiumAnalytics": "Pro mainly removes the 3-month history window (Pro = year/all-time data ranges on every chart), plus unlimited routines (free caps routines/folders), advanced custom exercise fields, more widgets, Apple Watch extras. The analytics TYPES are the same; Pro buys time-depth + routine count.",
          "notes": "Pro ~$2.99/mo / ~$23.99/yr — deliberately cheap. The market's most analytics-generous free tier; it gates DEPTH-OF-HISTORY rather than metric type. Strongest free competitor to copy."
        },
        {
          "name": "Fitbod",
          "freeAnalytics": "Effectively none post-trial. 7-day trial only; after it expires the app stops working (no degraded free logging tier).",
          "premiumAnalytics": "Everything is paid: per-muscle recovery/readiness map (its signature feature — color-coded fresh vs fatigued muscles driving next workout), volume-per-muscle tracking, e1RM and strength progression charts, PR tracking, muscle-balance views, well-designed data viz.",
          "notes": "~$15.99/mo or ~$95.99/yr (raised in 2026). Subscription-only AI-generated training. Its differentiator is the muscle-RECOVERY/readiness visualization, not raw stat charts."
        },
        {
          "name": "Boostcamp",
          "freeAnalytics": "Unusually generous free: workout tracking, progressive-overload tracking, PR tracking, RPE/RIR logging, plate calculator, rest timers, basic progress, plus 11,000+ free programs. Core analytics are free-forever.",
          "premiumAnalytics": "Pro adds advanced analytics (deeper volume/strength insight, e1RM trends, more detailed charts), 20+ exclusive coach programs, premium tools for lifters wanting deeper insight.",
          "notes": "Pro $59.99/yr ($4.99/mo annual) or $14.99/mo. Positions free tier as a real product; gates the 'advanced analytics' layer and premium programs. Program-library-first."
        },
        {
          "name": "JEFIT",
          "freeAnalytics": "1,400+ exercise library, unlimited logging, community routines, basic logging history. Limited charts on free.",
          "premiumAnalytics": "Elite unlocks the full analytics suite: NSPI (Normalized Strength Performance Index — single overall strength score), per-exercise 1RM-progression charts, per-muscle-group volume charts, total-volume-over-time, body measurements, training streaks, AI progression. Removes ads.",
          "notes": "Elite ~$12.99/mo or ~$69.99/yr. The most chart-heavy/'data nerd' app; nearly all the rich analytics sit behind Elite. NSPI is its signature single-number metric."
        },
        {
          "name": "FitNotes (FitNotes 2)",
          "freeAnalytics": "Original FitNotes (Android): fully free, all graphs included — estimated 1RM (weight & reps), max weight, workout volume, per-exercise progression, PR tracking. No analytics paywall at all.",
          "premiumAnalytics": "Original app has no premium analytics. FitNotes 2 (iOS rebuild) caps the FREE tier at ~12 saved workouts; paying removes the workout-count limit. Every analytics feature is otherwise unlocked — the gate is data quantity, not metric type.",
          "notes": "Beloved by powerlifters for being free + offline + simple. Gates STORAGE (workout count on iOS), never the charts. A counter-model to volume-of-history gating."
        },
        {
          "name": "Setgraph",
          "freeAnalytics": "Free-forever core loop: unlimited workout logging with no exercise cap, and charts across 4 categories — pounds-per-rep (lb/rep, an intensity proxy), sets, reps, and volume — per exercise.",
          "premiumAnalytics": "Premium unlocks beyond the 5-free-workout evaluation cap into full ongoing tracking; deeper/expanded analytics and history. (Reviews note a small free workout allowance to trial premium.)",
          "notes": "Chart-forward indie tracker; markets itself on clean per-exercise graphs. Mixed signals on exact free cap (free-forever core vs 5-workout trial), suggesting a generous-but-evolving line."
        },
        {
          "name": "Liftin'",
          "freeAnalytics": "Core experience free forever: workout logging plus graphs to visualize short- and long-term progress (per-exercise progression visuals).",
          "premiumAnalytics": "Liftin Pro: advanced progress analytics and PR tracking (v2 expanding summer 2026).",
          "notes": "Smaller indie tracker. Free covers basic progress graphs; Pro gates 'advanced' analytics + PR depth — the conventional indie split."
        },
        {
          "name": "Caliber",
          "freeAnalytics": "Free self-guided tier (no ads): 500+ exercise demo videos with muscle-group info, workout logging, basic progress tracking, and a Strength Score (strength relative to age/gender potential) is a headline metric.",
          "premiumAnalytics": "Caliber Plus / coaching tiers add the full Strength Score analytics, deeper progress analytics, and (paid) human coaching. Higher tiers are coaching-priced, not analytics-priced.",
          "notes": "Free $0, Plus ~$19/mo, 1:1 coaching $600–$1,400/3mo. Monetizes COACHING, not stats. Its distinctive metric is the normalized Strength Score (like a relative-strength percentile)."
        },
        {
          "name": "Gymshark Training (Conditioning)",
          "freeAnalytics": "Completely free, no paywall: progress tracking with visual graphs that map 1-rep-max across key lifts, plus workout tracking for all levels.",
          "premiumAnalytics": "None — all features free (brand/marketing-funded, drives apparel sales rather than subscriptions).",
          "notes": "Loss-leader model: free analytics including 1RM trend charts because the product is brand affinity + apparel, not the app itself. Light on serious hypertrophy analytics (no per-muscle volume vs landmarks)."
        },
        {
          "name": "Apple Fitness (Fitness app / Fitness+)",
          "freeAnalytics": "With Apple Watch (no subscription): Activity rings (Move/Exercise/Stand), per-workout summaries (active calories, avg HR, duration), Trends (90-day vs 365-day rolling comparisons of pace/distance/cardio etc.), HR zones, cardio fitness (VO2max estimate), Training Load (recent vs typical effort, 7d vs 28d) on newer watchOS, awards/streaks.",
          "premiumAnalytics": "Fitness+ ($9.99/mo / $79.99/yr) is guided video CLASSES, not deeper personal analytics. Strength-specific lifting analytics (e1RM, per-muscle volume, set tracking) are essentially absent — it's cardio/ring/health-oriented.",
          "notes": "Free analytics are tied to owning the hardware, not a subscription. Strong on activity/cardio/recovery trends, weak-to-absent on resistance-training set/volume/1RM analytics that lifters want."
        },
        {
          "name": "Strava",
          "freeAnalytics": "Unlimited activity uploads, per-activity summaries, basic segment views (top-10 leaderboard), kudos/social, basic routes. Manual strength/'Workout' logging exists but with minimal analytics.",
          "premiumAnalytics": "Subscription gates the analytics that matter: Fitness & Freshness (CTL/ATL/Form training-load model), Performance Predictions/race finish predictions, full segment leaderboards & filtering, power analysis, custom HR zones, grade-adjusted pace, heatmaps, Athlete Intelligence (AI workout summaries).",
          "notes": "$9.99/mo / $79.99/yr. Endurance-first; not a lifting analytics tool. Relevant as the canonical example of gating the TREND/LOAD model (Fitness & Freshness) behind premium while keeping raw logging free."
        },
        {
          "name": "WHOOP",
          "freeAnalytics": "None — subscription-only. No free tier; the band is bundled with membership and stops working (and data becomes inaccessible) if you cancel.",
          "premiumAnalytics": "Everything: daily Recovery score (HRV/RHR/sleep), Strain (cardiovascular load 0–21), Sleep performance, Stress, and (Peak) Healthspan/WHOOP Age. Strain quantifies cardiovascular effort, not lifting volume/tonnage.",
          "notes": "One $199/yr, Peak $239/yr (~$30/mo). Pure readiness/recovery play. Not strength-specific — no e1RM/volume/sets — but the benchmark for RECOVERY & READINESS framing lifters increasingly want."
        },
        {
          "name": "Garmin Connect",
          "freeAnalytics": "No subscription required (paid via hardware): Training Load (EPOC-based), Training Status, Load Focus (anaerobic/high-aerobic/low-aerobic balance), Acute vs Chronic load, Body Battery (recovery), VO2max, Recovery Time, HRV Status, sleep. Free premade workouts.",
          "premiumAnalytics": "Connect+ ($6.99/mo / $69.99/yr, 2025+) adds AI 'Active Intelligence' insights, expanded charts/comparisons, and some premium views — but the core training-load/recovery analytics remain free with the device.",
          "notes": "Hardware-funded like Apple. Deep endurance/recovery analytics free; strength tracking exists (reps/sets, muscle-map of worked muscles) but is shallow on e1RM/volume-trend vs dedicated lifting apps."
        }
      ],
      "rankedMetrics": [
        {
          "metric": "Estimated 1RM / strength progression per lift (e1RM trend over time)",
          "whyUsersCare": "The single clearest answer to 'am I getting stronger?' It normalizes different rep/weight combos into one comparable number per lift, so a line going up = progress regardless of whether you did 5x5 or 8x3. It's the metric lifters check first and the one that drives program decisions.",
          "typicalTier": "Free to CALCULATE the current number (Strong, FitNotes, Hevy); the TREND CHART over time is the classic premium gate (Strong Pro, JEFIT Elite). Hevy/FitNotes give the trend free."
        },
        {
          "metric": "Total volume & volume trend (tonnage = sets x reps x weight over time)",
          "whyUsersCare": "Volume is the primary driver of hypertrophy, so the volume-over-time line is the hypertrophy lifter's main progress signal and the key to progressive overload. Per-session total volume confirms today's effort; the trend confirms the program is working.",
          "typicalTier": "Per-session total volume is universally FREE. The volume-TREND chart is split: free in Hevy/FitNotes/Boostcamp/Setgraph, premium in Strong/JEFIT."
        },
        {
          "metric": "Volume per muscle group + muscle balance (e.g. sets/volume to chest vs back vs legs)",
          "whyUsersCare": "Serious hypertrophy training is planned per-muscle, not per-lift. Lifters use this to ensure each muscle gets enough stimulus and to catch imbalances (e.g. pushing >> pulling) that cause plateaus or injury. It's what separates 'data nerd' apps from simple loggers.",
          "typicalTier": "Increasingly FREE in the best loggers (Hevy's sets-per-muscle-group + muscle-distribution chart; JEFIT per-muscle, though gated to Elite). Often premium or absent in simpler apps. A strong differentiator."
        },
        {
          "metric": "Sets-per-muscle-per-week vs science landmarks (MEV / MAV / MRV)",
          "whyUsersCare": "The evidence-based crowd (RP/Israetel followers) programs by hard sets per muscle per week against ~10–20 set targets (MEV ~6–10, MAV ~12–20, MRV ~20+). An app that shows 'chest: 8 sets this week' with a green/under/over band tells them exactly whether to add or cut volume — turning raw logs into a coaching decision.",
          "typicalTier": "Rare; the weekly sets-per-muscle COUNT exists free in Hevy. Explicit comparison AGAINST MEV/MAV landmarks is mostly absent market-wide — a genuine whitespace / premium opportunity."
        },
        {
          "metric": "Training frequency per muscle (how often each muscle is hit per week)",
          "whyUsersCare": "Frequency interacts with volume: hitting a muscle 2x/week generally beats 1x for the same weekly sets. Lifters use it to validate split design (PPL, upper/lower) and to spot neglected muscles.",
          "typicalTier": "FREE where it exists (Hevy, Fitbod's recovery view implies it); often bundled into the muscle-group analytics. Sometimes premium (JEFIT)."
        },
        {
          "metric": "PRs / PR timeline (per-exercise records: weight, e1RM, rep, volume PRs)",
          "whyUsersCare": "PRs are the dopamine + motivation layer and a concrete progress proof. A PR timeline doubles as a strength-progression record. Highly valued for adherence/retention even by casual lifters.",
          "typicalTier": "Basic PR badges almost universally FREE (Strong, Hevy, Boostcamp, FitNotes, Gymshark). A full PR TIMELINE/history view is sometimes premium (Liftin Pro, Strong charts)."
        },
        {
          "metric": "Consistency / adherence / streak (workouts per week, calendar heatmap)",
          "whyUsersCare": "Consistency is the real determinant of long-term results; the streak/heatmap is the behavioral hook that drives habit and retention. Lifters use it as accountability; product teams love it for engagement.",
          "typicalTier": "FREE almost everywhere (calendar/streak is a standard engagement feature). Apple Fitness rings & JEFIT streaks are headline free features."
        },
        {
          "metric": "Tonnage (cumulative weight moved, per session and lifetime)",
          "whyUsersCare": "A motivating 'how much have I moved' vanity-plus-progress number; for powerlifters it's a load-management proxy. Overlaps heavily with total volume but framed as a single big number.",
          "typicalTier": "FREE (it's just summed volume; shown in session summaries everywhere). Lifetime/all-time tonnage may sit behind history-depth paywalls (Hevy Pro time ranges)."
        },
        {
          "metric": "Rep / intensity distribution (% of sets in strength vs hypertrophy vs endurance rep ranges; load %1RM; RPE/RIR distribution)",
          "whyUsersCare": "Advanced lifters periodize across rep ranges and intensities. Seeing 'too much of my work is in the 12+ rep low-load zone' or RPE creeping up informs deloads and block design. Setgraph's lb/rep is a simple intensity proxy.",
          "typicalTier": "Mostly PREMIUM or absent. RPE/RIR LOGGING is often free (Boostcamp), but the distribution ANALYTICS are advanced/premium territory — another whitespace."
        },
        {
          "metric": "Bodyweight & body-composition trend (plus measurements)",
          "whyUsersCare": "Context for everything else: strength gains during a cut vs bulk read very differently, and body-part measurements track hypertrophy where the scale can't. Lifters overlay weight against strength to judge recomposition.",
          "typicalTier": "Logging + basic chart usually FREE (Strong, Hevy, FitNotes). Longer-range/all-time trend can hit the history-depth paywall (Hevy Pro)."
        },
        {
          "metric": "Workout duration / density (time per session, set density, rest-time analytics)",
          "whyUsersCare": "Efficiency and intensity proxy — same volume in less time = higher density = progress; also helps people fit training into limited time. More of a 'nice to have' than a primary driver for most lifters.",
          "typicalTier": "Per-session duration is FREE everywhere; duration TRENDS and rest/density analytics are premium or absent."
        },
        {
          "metric": "Muscle recovery / readiness (per-muscle fatigue map; whole-body readiness/strain)",
          "whyUsersCare": "Answers 'what should I train today / am I recovered?' Fitbod's color-coded muscle-recovery map is its signature, and WHOOP/Garmin/Apple sell whole-body readiness. Growing in importance as recovery-aware training goes mainstream, but for pure strength logging it's secondary to progression metrics.",
          "typicalTier": "PREMIUM / subscription-defining in dedicated tools (Fitbod gates it entirely; WHOOP is subscription-only). Whole-body readiness is FREE-with-hardware on Garmin (Body Battery) and Apple (Training Load). Largely absent from cheap pure loggers."
        }
      ],
      "freePremiumLine": "The de-facto industry line: FREE should cover everything needed to log and review your own training — unlimited (or near-unlimited) workout logging, the full exercise library, per-exercise history, current estimated 1RM, per-session totals (volume/sets/tonnage/duration), basic PR badges, and a consistency calendar/streak; the best free tiers (Hevy, FitNotes, Boostcamp) go further and include per-exercise progression charts and sets-per-muscle-group views. What it's considered fair to GATE behind premium is depth and intelligence rather than the raw existence of a stat: long-range/all-time history windows (Hevy's classic move — 3 months free vs all-time paid), trend/progression CHARTS over time (Strong's model), advanced cross-cutting analytics (per-muscle volume trends, frequency, rep/intensity distribution, MEV/MAV landmark comparisons, strength scores like JEFIT's NSPI or Caliber's Strength Score), recovery/readiness modeling (Fitbod, WHOOP, Strava's Fitness & Freshness), AI insights, unlimited routines/templates, and data export (CSV). The market is bifurcating: ultra-cheap loggers (Hevy ~$24/yr) win by giving away analytics depth and gating only history-range and routine count, while premium AI/recovery products (Fitbod ~$96/yr, WHOOP ~$239/yr) gate everything because the analytics IS the product — so the only universally safe thing to charge for is intelligence layered on top of data the user could otherwise see for free."
    },
    "current": {
      "historyStructure": "HistoryScreen.swift (/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/HistoryScreen.swift) is one ScrollView. Fixed header zone (always shown, NOT in the segmented tabs): (1) ProBanner marketing card only when !isPro; (2) one combined card holding the 3-metric statsRow + divider + InlineWorkoutCalendar (7-day strip default, taps/chevron expand to a month grid). statsRow swaps copy with calendar state: collapsed = weeklyStatsCard (Days this week / Week streak / Sets this week), expanded = monthlyStatsCard (Days this month / Week streak / Sets this month). Below is a 2-segment Picker(.segmented), enum HistoryTab { stats, workouts }, default .stats, rendered only if at least one session exists; otherwise a No-workouts-yet empty state replaces both tabs. SEGMENT 1 Stats: a PROGRESS section = ProgressChartsView (only if !charts.isEmpty), then an ACTIVITY section = TrainingActivityHeatmap (only if !activity.isEmpty); if both empty a Keep-training nudge. SEGMENT 2 Workouts: past sessions grouped by week via weekGroupedSessions(), each week a header (This week / Last week / Jun 9-15) with SessionCard rows (tap -> SessionDetailSheet, long-press -> Delete). Top-right toolbar: Share (UnifiedShareCard) button + Settings gear. There is NO separate 1RM/strength tab; lift progression lives inside the Stats segment's ProgressChartsView.",
      "modules": [
        {
          "name": "3-metric stats row (Days / Week streak / Sets, this-week or this-month)",
          "location": "HistoryScreen.swift weeklyStatsCard / monthlyStatsCard / statsCard (top combined card)",
          "dataSource": "Computed in HistoryScreen from data.sets: workoutDateSet() intersect week/month, setsThisWeekCount()/setsThisMonthCount(), currentWeekStreak() = consecutive weeks where trainedDays >= settings.weeklyTrainingDays",
          "currentTier": "free"
        },
        {
          "name": "InlineWorkoutCalendar (7-day strip <-> month grid, per-day muscle dots)",
          "location": "HistoryScreen.swift body (InlineWorkoutCalendar, embedded:true); fed by workoutDateSet() + musclesPerDayMap()",
          "dataSource": "data.sets -> startOfDay set for highlighted days; musclesPerDayMap maps each day to up to 3 major-muscle accent colors via data.exById + MuscleSelector.majorOf",
          "currentTier": "free"
        },
        {
          "name": "This week vs last - delta tiles (Volume %, Sets %)",
          "location": "ProgressChartsView.swift deltaRow / deltaTile (weekDeltas())",
          "dataSource": "data.sets grouped by ISO week: volume = sum(weight*reps), sets = count; this-week vs last-complete-week % change, or NEW for first week",
          "currentTier": "free"
        },
        {
          "name": "Weekly volume bar chart (last 8 weeks, total kg lifted)",
          "location": "ProgressChartsView.swift volumeCard / weeklyVolume()",
          "dataSource": "data.sets: sum weight*reps per ISO week, last 8 weeks (missing weeks filled 0); unit-converted via settings.weightUnit. Renders if >=1 week has volume>0",
          "currentTier": "free"
        },
        {
          "name": "Estimated 1RM trend (top lift, Epley per-day best)",
          "location": "ProgressChartsView.swift oneRMCard / oneRMChart / topLiftSeries()",
          "dataSource": "data.sets: picks exercise with most weighted sets; per-day best e1RM = w*(1+reps/30) Epley. Renders if series.count>=1",
          "currentTier": "pro - blurred + lock overlay 'Unlock strength trends with Pro' when !isPro; tap calls onUnlock -> paywall. Real curve renders underneath the blur."
        },
        {
          "name": "Muscle balance (sets per major region this week, lagging region dimmed)",
          "location": "ProgressChartsView.swift muscleBalanceCard / weeklySetsPerSection()",
          "dataSource": "data.sets last 7 days: count per 6 major sections (chest/back/shoulders/arms/core/legs) via ex.primaryMuscles.first.section; lowest non-zero flagged isLagging",
          "currentTier": "free"
        },
        {
          "name": "Training activity heatmap (16-week GitHub/Duolingo grid, 4 set-count tiers)",
          "location": "ProgressChartsView.swift struct TrainingActivityHeatmap (same file); rendered as the ACTIVITY section in HistoryScreen",
          "dataSource": "data.sets last 16 weeks: per-day set count -> 4 accent-opacity tiers (0 / 1-5 / 6-12 / 13+). Renders if >=1 day has sets",
          "currentTier": "free"
        },
        {
          "name": "Session cards (week-grouped) + PR trophy badge",
          "location": "HistoryScreen.swift SessionCard / groupedSessions() / sessionCardRow (Workouts segment)",
          "dataSource": "data.sets aggregated by (planId, calendar day) into SessionSummary: exerciseCount, setCount, muscles, prCount via data.isPR per record",
          "currentTier": "free"
        },
        {
          "name": "SessionDetailSheet (per-exercise stats: best weight x reps / duration, list/grid, photo, repeat)",
          "location": "HistoryScreen.swift SessionDetailSheet / exerciseStats(for:) / ExerciseStatRow / ExerciseStatCard",
          "dataSource": "data.sets for that (planId, day): per exercise bestWeight=max(weight), bestReps=max(reps), totalDuration, setCount; data.exById for metadata",
          "currentTier": "free"
        },
        {
          "name": "RoutineOptimizeCard (data-driven optimization suggestion, Pro feature 2)",
          "location": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/RoutineOptimizeCard.swift; shown on Today/Plans Saved page (TodayScreen.swift line 156), NOT inside History",
          "dataSource": "DataStore.routineSuggestion(): diagnoses lagging muscle section / stalled main lift (e1RM plateau) / adherence drop from data.sets (needs >=2 weeks coverage + >=6 recent sets)",
          "currentTier": "pro action - card itself is a free teaser to everyone; the 'Optimize with AI' button is Pro-gated in PlansScreen.handleOptimize (non-Pro -> paywall)"
        }
      ],
      "todayMuscleStatus": "The Today tab Muscle Status card is MuscleStatusOverviewCard (/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/MuscleStatusOverviewCard.swift), placed at the top of TodayScreen.swift (line 102) above the recommended-workout card, only when mode != .myPlans. It shows: a MUSCLE STATUS kicker (waveform icon) with an optional tipLine on the right (trained X ago); a left body map (shared MuscleVisualBlock, square slot 130pt) heat-shaded by fatigue via MuscleStatusCompute.opacityFor over data.sets (coarseOnly when !settings.muscleDetailEnabled); a right column with a 4-tier legend (Heavy fatigue / Recovering / Mostly recovered / Fresh) and either an All-caught-up label or a Train-the-gaps CTA (onStartGapWorkout builds + starts a plan from gapMuscles). Fatigue model = MuscleStatusComputed.swift: per-set stress (primary 1.0 / synergist 0.4) with 24h half-life exponential decay, saturating to fatigue = 1 - exp(-stress/2), opacity thresholds 0.65/0.35/0.12. Empty-history first day shows a Finish-a-workout nudge instead of a misleading legend. TIER: free - no isPro / paywall / blur gating anywhere in this card.",
      "availableData": "DataStore (/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift) exposes data.sets: [SetRecord] (newest-first; Plan.swift line 77: id, exerciseId, exerciseName, category, weight?, reps?, duration?, performedAt, planId?, planName?), data.plans (Plan has lastUsedAt, source/resolvedSource, steps), and data.exById ([String: Exercise] with muscleGroups, primaryMuscles, section, category, equipment). Already-exposed derived metrics: completedWorkoutCount (distinct training calendar days); lastSet(forExerciseId:) (last time 100kg x 8); estimatedMaxLoad(forExerciseId:) (historical best Epley e1RM); isPR(record) (this set's e1RM beats history); routineSuggestion() (lagging-section / stalled-lift e1RM-plateau / adherence-drop diagnosis); MuscleStatusCompute.muscleFatigueMap (per-muscle fatigue 0..1 with 24h decay) and muscleLastTrainedMap (per-muscle last-trained date). Cheaply computable WITHOUT new collection (some already done inline in chart/stats code, not all surfaced): weekly volume (sum weight*reps) per ISO week and week-over-week % delta; per-day/per-week set counts; sets-per-major-section (muscle balance / lagging); per-exercise per-day best e1RM time series (strength progression for ANY lift, not just the top one); 16-week daily activity counts; week-streak vs weeklyTrainingDays goal; PR count per session; per-exercise total/best weight, reps, duration per session; days-per-week adherence average. From settings also: weightUnit, bodyweight/age/gender, trainingGoal/Kind, weeklyTrainingDays, wantStrengthen, coachMemory. Feasible premium metrics with zero new data collection: per-muscle weekly volume/tonnage trends, estimated-1RM tables for all main lifts, lifetime total tonnage, PR history timeline, volume-load per muscle vs recovery, training-monotony/consistency score, rep-PRs, set-count progression per exercise, time-under-tension from duration.",
      "currentProGating": "MasoFlags.iapEnabled is currently TRUE in source (Maso/Models/Settings.swift line 7) - note CLAUDE.md narrative says false, but the live code is true, so real free/pro gating IS active. isPro (UserSettings.isPro) = (!iapEnabled || proSubscription != nil || (#if DEBUG debugProUnlock)). With iapEnabled=true and no subscription, free users are genuinely gated. Gating across the analytics surface: (1) HistoryScreen ProBanner rendered only when !data.settings.isPro (line 87-88); tap sets paywallPresented -> PaywallScreen sheet. (2) ProgressChartsView Estimated-1RM card is the ONLY locked chart: reads data.settings.isPro (line 86) and when false applies .blur(radius:7) + .allowsHitTesting(false) to the real chart and overlays an Unlock-strength-trends-with-Pro lock button calling onUnlock (HistoryScreen passes onUnlock = { paywallPresented = true }). Everything else in History/Stats - delta tiles, weekly volume bars, muscle balance, activity heatmap, session cards, session detail, the whole calendar + 3-metric row - is FREE (no isPro checks). (3) Today's MuscleStatusOverviewCard is fully free. (4) RoutineOptimizeCard (Today/Plans, not History): card is a free teaser; only the Optimize-with-AI action is Pro-gated in PlansScreen.handleOptimize (non-Pro -> paywall). Separately, plan saving is gated via FreeLimit.maxPlans=3 / canSaveMorePlans (settings.isPro || plans.count<3), and custom-exercise image import has a Pro gate - both outside the analytics surface."
    }
  },
  "workflowProgress": [
    {
      "type": "workflow_phase",
      "index": 1,
      "title": "Research"
    },
    {
      "type": "workflow_phase",
      "index": 2,
      "title": "Synthesize"
    },
    {
      "type": "workflow_agent",
      "index": 1,
      "label": "research:market",
      "phaseIndex": 1,
      "phaseTitle": "Research",
      "agentId": "a4f6c819cf9496bcf",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782838189564,
      "queuedAt": 1782838189555,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "The de-facto industry line: FREE should cover everything ne…",
      "promptPreview": "You are a fitness-product analyst. Research how leading workout/strength-training apps present TRAINING-DATA ANALYTICS and where they draw the free-vs-premium line, then distill what serious lifters actually care about. Use WebSearch/WebFetch where helpful (load them via ToolSearch); supplement with your own knowledge (data through early 2026).

Cover these apps (and any other notable ones): Stron…",
      "lastProgressAt": 1782838353483,
      "tokens": 52151,
      "toolCalls": 9,
      "durationMs": 163919,
      "resultPreview": "{"apps":[{"name":"Strong","freeAnalytics":"Per-exercise history list, auto-updating estimated 1RM calculator (tap an exercise to see current e1RM), basic personal-record badges, full past-workout log, body-measurement logging. Workout summary shows that session's total volume/sets/duration.","premiumAnalytics":"All progression-over-time CHARTS (e1RM trend per lift, max-weight trend, volume trend),…"
    },
    {
      "type": "workflow_agent",
      "index": 2,
      "label": "research:current",
      "phaseIndex": 1,
      "phaseTitle": "Research",
      "agentId": "a2216210cee1288a5",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782838189569,
      "queuedAt": 1782838189555,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "HistoryScreen.swift (/Users/yumowu/Projects/Maso-iOS/Maso/V…",
      "promptPreview": "Map the CURRENT training-analytics surface in the Maso iOS app at /Users/yumowu/Projects/Maso-iOS. Read the real files: Maso/Views/Screens/HistoryScreen.swift (the Stats | Workouts segmented tabs, calendar, week-grouped sessions), Maso/Views/Components/ProgressChartsView.swift (all chart modules — delta tiles, muscle-balance card, training heatmap, lift progression, their data thresholds), the Tod…",
      "lastProgressAt": 1782838396247,
      "tokens": 141168,
      "toolCalls": 19,
      "durationMs": 206677,
      "resultPreview": "{"historyStructure":"HistoryScreen.swift (/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/HistoryScreen.swift) is one ScrollView. Fixed header zone (always shown, NOT in the segmented tabs): (1) ProBanner marketing card only when !isPro; (2) one combined card holding the 3-metric statsRow + divider + InlineWorkoutCalendar (7-day strip default, taps/chevron expand to a month grid). statsRow swap…"
    },
    {
      "type": "workflow_agent",
      "index": 3,
      "label": "synthesize:design",
      "phaseIndex": 2,
      "phaseTitle": "Synthesize",
      "agentId": "aad61b5dca4bbe538",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782838396250,
      "queuedAt": 1782838396248,
      "attempt": 1,
      "lastToolName": "Bash",
      "lastToolSummary": "grep -n "History\\|Stats\\|Workouts\\|Progress\\|Activity\\|训练…",
      "promptPreview": "Design a redesign of the Maso iOS 'History' tab — its information architecture, tab name, and Pro tiering — for a solo, privacy-forward indie fitness app with a live paywall (Maso Pro). The owner's asks: (1) rename the tab (it now holds BOTH training-data analysis AND history records, so 'History' is wrong); (2) put the two segments [training data] and [history records] at the very top + re-catego…",
      "lastProgressAt": 1782838509040,
      "tokens": 76860,
      "toolCalls": 6,
      "durationMs": 112790,
      "resultPreview": "I have everything needed. Note the important nuance: the current tab label key is `"History"` (zh = "训练记录") and the nav title also uses `"History"` — but `screenHeader("History")` passes a literal, and `Label("History", ...)` too, both resolving via Localizable. Here is the design doc.

---

# Maso — "History" Tab Redesign: IA, Rename & Pro Tiering

Build-ready spec against the live codebase. All …"
    }
  ],
  "totalTokens": 270179,
  "totalToolCalls": 34
