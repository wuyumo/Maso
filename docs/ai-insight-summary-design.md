# Maso — AI Insight Summary (Progress → Insights, top card)

Build-ready design doc. Status: **PLAN for review, build after approval.** Target: Maso-iOS (SwiftUI, DeepSeek via Cloudflare Worker, text-only, server-side). All symbols below are the real ones from the current codebase.

---

## 1. Concept & UX

A single **`AISummaryCard`** pinned at the very top of the Insights list — above every existing analytics card, above the reorder hint. It is the coach's verdict: a 1–2 sentence plain-language read of *this user's* recent training, plus 2–4 prioritized, one-tap-actionable recommendations. It is **not a chat** and **not a wall of text** — closest market analog is WHOOP's weekly recap fused with Fitbod's "the insight IS the plan change."

### Placement
Inject as the **first child of `InsightsChartsView.body`'s outer `VStack`** (input option A — "simplest"), *before* the reorder hint and the reorderable `ForEach(visibleCards)`. It is **fixed / non-reorderable**, so the drag-drop math keyed to `resolvedInsightOrder` is untouched. It renders only when `!insights.isEmpty` (same guard HistoryScreen already applies), so a brand-new user never sees a broken card.

### States
| State | Trigger | UI |
|---|---|---|
| **Insufficient data** | Below min-data threshold (see §6) — mirrors `routineSuggestion()` returning nil (`< 2 weeks` or `< 6 recent sets`) | Compact muted card: "Keep logging — your AI summary unlocks after ~2 weeks of training." No spinner, no LLM call. |
| **Idle / stale (has cache)** | Cache exists, data-hash matches | Render cached summary + "as of \\<date>" + a small **Refresh** affordance. This is the default steady state. |
| **Loading** | Explicit refresh or auto-regen fires | Cached content stays visible, dimmed, with an inline spinner bound to `AIWorkoutService` `State.generating`; **never a blank card.** First-ever generation shows a skeleton (3 shimmer rows). |
| **Generated (fresh)** | New summary parsed | TL;DR + 2–4 recommendation rows, each with an **Apply** control. Subtle "Updated" tag for one session. |
| **Error** | `AIError` (network/api/parse) | Inline chip reusing the Today pattern: "AI summary unavailable — Retry." Falls back to showing last good cache if present; if no cache, shows a deterministic rule-based mini-summary built from `routineSuggestion()` (see §3 fallback). |
| **Locked (non-Pro)** | `!settings.isPro` | See below. |

### Content structure (generated state)
1. **TL;DR** — 1–2 sentences, second-person, **every claim tied to a real number** fed in the payload. E.g. *"Volume is up 12% over last week and your bench e1RM hit a new high, but legs are under-trained — only 6 hard sets in 7 days vs a 10-set minimum."* No horoscope prose.
2. **2–4 recommendation rows**, prioritized (most important first). Each row:
   - **title** (imperative, short): "Add a leg day"
   - **detail** (one line, the *why*, grounded): "Quads/hams at 6 sets/wk — below MEV (10). Bump to ~12."
   - **Apply** affordance (trailing button, see §4): "Apply to routine" / "Add to notes".
3. **Footer**: "as of Jul 1 · based on last 14 days" + Refresh.

### Tone & length
Encouraging but **data-first, no emoji hype**. Hard cap: TL;DR ≤ 2 sentences; each recommendation detail ≤ 1 line. The whole card must be skimmable in ~5 seconds. When signal is thin, it *says so* ("only 2 sessions logged this week — rough read") rather than faking confidence.

### Free vs Pro — **Pro, with a free teaser** (reuses existing paradigm)
The deep-insight cards this sits above are *already* Pro-blurred (`proCard()` / `oneRMCard`), `routineSuggestion → optimize` is *already* Pro-gated, and Coaching Memory writes are *already* Pro-gated. So:
- **Free:** the card is visible. The **TL;DR headline is shown** (a genuine teaser — the diagnosed problem from `routineSuggestion()`, computed locally, no LLM), but the **AI-written recommendation rows are blurred** at `.blur(radius: isPro ? 0 : 7)` + `.allowsHitTesting(isPro)`, with the standard centered lock button ("Unlock your AI coach summary with Pro") whose action calls `onUnlock` → `HistoryScreen` sets `paywallPresented = true`. This exactly matches `InsightsChartsView`'s existing `proCard` treatment.
- **Pro:** full summary + working Apply buttons.
- The **LLM call is gated behind isPro** — never spend tokens for a non-Pro user; the free teaser is 100% local (`routineSuggestion()`).

---

## 2. Data payload

**Principle:** every number is computed deterministically by existing `InsightsChartsView` / `DataStore` helpers and *handed to* the model. **The LLM never computes or invents a number.** No PII (no name, DOB, bodyweight in kg is fine as a coaching input but we send age-band + goal enum instead of identity). Compact enum/number summaries only.

Built by a new `DataStore.buildSummaryPayload() -> AISummaryPayload`, assembled from these existing sources:

| Field | Source helper |
|---|---|
| `weekDelta` (pct + isNew) | `weekDeltas()` / `deltaCardOrEmpty` |
| `volumeTrend` (last 8 wk, coarse) | `weeklyVolume()` → reduce to `[Int]` (kg rounded) + a trend enum `ramping/flat/dropping` |
| `topLift` (name, e1RM now, e1RM 4wk-ago, trend enum) | `topLiftSeries()` |
| `muscleSets` (6 sections: label, sets, band enum `underMEV/inBand/overMAV`) | `weeklyLandmarkRows()` (MEV=10/MAV=20) + `weeklySetsPerSection()` for the lagging flag |
| `laggingSection` (label or null) | `weeklySetsPerSection()` `isLagging` |
| `frequency` (per section, days/wk, 4wk) | `trainingFrequencyRows()` |
| `adherence` (0–100) | `consistencyScore()` |
| `recentPRs` (≤3: exercise name + date) | `prTimeline()` (already `isPR`-filtered) |
| `diagnosis` (title, detail, focusNote) | **`routineSuggestion()`** — the pre-baked verdict + machine-ready `focusNote` |
| `profile` (goal enum, daysGoal, equipment enum, age band) | `buildAIPayload()` profile subset (reuse, strip identity) |
| `dataMonths` / `sessionCount` | `completedWorkoutCount` + weeks-of-history |

### JSON shape sent to the Worker
```json
{
  "profile": { "goal": "hypertrophy", "daysPerWeekGoal": 4, "equipment": "full_gym", "ageBand": "25-34" },
  "signal": { "weeksOfHistory": 9, "sessions14d": 7, "thin": false },
  "trend": { "volumeWoW_pct": 12, "volume8wk_kg": [8100,8600,9000,...], "trend": "ramping", "adherence_pct": 78 },
  "topLift": { "name": "Barbell Bench Press", "e1rm_now_kg": 102, "e1rm_4wk_kg": 96, "trend": "up" },
  "muscles": [
    { "section": "legs",  "sets7d": 6,  "band": "underMEV", "daysPerWeek": 1 },
    { "section": "chest", "sets7d": 16, "band": "inBand",   "daysPerWeek": 2 }
  ],
  "lagging": "legs",
  "recentPRs": [ { "exercise": "Barbell Bench Press", "daysAgo": 3 } ],
  "diagnosis": { "title": "Legs under-trained", "detail": "…", "focusNote": "bias the split toward legs" }
}
```
No user name, no raw set logs, no dates as absolute PII (use `daysAgo`). `focusNote` is passed through so the model's recommendations can be *tagged* to the same apply path the existing optimize flow already uses.

---

## 3. Prompt + structured output

New method on `AIWorkoutService`: **`summarizeTraining(payload:) async throws -> AISummary`** — reuses the exact Worker plumbing (`POST {proxyURL}/v1/chat/completions`, `X-Maso-Client-Token`, `deepseek-chat`, `response_format: json_object`, `isConfigured` gate). Low temp (**0.3** — this is interpretation, not creativity), `max_tokens: 1024`.

### System prompt (grounding is the whole game)
> You are a strength-training coach. You will be given a JSON summary of ONE athlete's recent training, with all numbers pre-computed. **Rules: (1) Never state a number that is not present in the input. (2) Never name an exercise that is not in `topLift.name` or `recentPRs`. (3) Interpret only what the data shows; if `signal.thin` is true, hedge explicitly. (4) Do not give medical advice. (5) Output 2–4 recommendations, most important first — prefer the one implied by `diagnosis`. (6) Each recommendation must pick an `action` from the allowed enum.** Respond ONLY as JSON.

### User prompt
The serialized payload JSON + the allowed `action` enum + one line: *"The single most important fix is likely: \\<diagnosis.title> — \\<diagnosis.detail>."* (seeds priority; the model may reorder but has the deterministic verdict in hand).

### Output schema (parsed by a new `parseSummaryResponse`, mirroring `parseResponse`: strip ```json fences → `JSONDecoder`)
```json
{
  "tldr": "string (<= 2 sentences)",
  "recommendations": [
    {
      "id": "string",
      "title": "string",
      "detail": "string (one line)",
      "muscle": "legs | back | ... | null",
      "lift": "string | null",
      "action": {
        "type": "regenerate_routines | add_sets | add_coach_note | none",
        "focusNote": "string | null",     // for regenerate_routines
        "muscle": "string | null",         // for add_sets
        "note": "string | null"            // for add_coach_note
      }
    }
  ]
}
```
Codable structs: `private struct AISummaryResponse { tldr; recommendations:[AISummaryRec] }`, `AISummaryRec`, `AISummaryAction`. `action.type` is a string enum with a `.none` fallback so an unknown/hallucinated type degrades to advice-only (no crash, no bad apply).

### Deterministic fallback (no LLM / error / not configured)
Build an `AISummary` locally from `routineSuggestion()`: `tldr` = its `detail`, one recommendation with `action = regenerate_routines(focusNote:)`. Guarantees the card is never empty and the Apply path still works offline — same philosophy as `generateAIRoutines`' `tunedRecommendedPlans` fallback.

---

## 4. Apply-to-routine flow — **THE CRUX**

Each recommendation's `action.type` maps to an **existing** hook. We invent **zero** new AI endpoints for apply; we reuse the `routineSuggestion → RoutineOptimizeCard → handleOptimize` machinery that already turns a verdict into science-checked routines.

| `action.type` | Recommendation example | Mechanism (existing) | Confirm UX |
|---|---|---|---|
| **`regenerate_routines`** | "Legs under-trained → add a leg day" | `DataStore.generateAIRoutines(focusNote: action.focusNote, surface:"summary")` → returns `(plans, usedFallback)`, each already through `enforceScience`. Same call `handleOptimize` makes. | Tapping Apply pushes the **existing routine-preview UI** the optimize flow uses (candidate routines shown before save). User taps **Save** → `savePlan(_)` (respects `canSaveMorePlans` 3-cap → paywall). **Nothing auto-writes.** |
| **`add_sets`** | "Add 2 sets of a hamstring movement to Leg Day" | If a saved plan already targets that muscle: draft a modified `Plan` (append/bump sets on the matching step), show diff, on confirm → `updatePlan(_)`. If no matching plan → degrade to `regenerate_routines` with a `focusNote` for that muscle. | **Preview-before-apply**: show the changed step(s) inline ("Leg Day: +2 sets Romanian Deadlift"), Confirm → `updatePlan`. Reversible (standard edit). |
| **`add_coach_note`** | "You prefer barbells — keep future plans barbell-first" | `DataStore.appendCoachNote(_)` → persists a de-duped bullet into `settings.coachMemory`, injected into **every** future generation via `coachMemoryBlock`. Long-term personalization vs one-shot focusNote. | One-tap toggle "Remember this" with a confirmation toast; reversible by editing coach memory. Pro-gated at call site (already is). |
| **`none`** | Pure observation ("Bench PR 3 days ago — nice momentum") | No button, advice only. | — |

### Key design decisions
- **Preview before apply, always.** Per the market pitfall "silent/opaque auto-adjustment," we never mutate a routine on tap. `regenerate_routines` and `add_sets` both show what will change and require a Save/Confirm. This reuses the optimize flow's existing preview surface.
- **`enforceScience` is the backstop.** Every path that produces routine steps (`generateAIRoutines` internally, and any `add_sets` draft should call `applyScience(to:)` before preview) so an LLM suggestion can't violate compound-first / ≤2-per-section / push≥pull.
- **Apply is Pro-gated** with the same `guard data.settings.isPro else { paywallPresented = true; return }` used by `handleOptimize`/`sendRefine`.
- **The hardest 20%** is `add_sets` matching a recommendation's `muscle` to an existing `Plan`'s steps. Recommendation: for **MVP, collapse `add_sets` into `regenerate_routines`** (send the muscle as `focusNote`) so v1 has exactly one robust apply path, and add true in-place `add_sets` in phase 3 once the summary itself is proven.

---

## 5. Refresh cadence, caching & cost

LLM calls are paid + slow — **never regenerate on screen open.** Cadence = *weekly recap + on-demand refresh* (WHOOP model), which the input's best-practices explicitly endorse.

### Cache (new fields on `UserSettings`/`Settings`)
```
aiSummaryCacheJSON: String?      // encoded AISummary
aiSummaryDataHash: String?       // hash of the payload's material fields
aiSummaryGeneratedAt: Date?
```
- **Data-hash** = stable hash over the *material* payload fields (weekDelta bucket, each muscle band, volume trend enum, topLift e1RM rounded, adherence bucket, diagnosis.focusNote). Deliberately **coarse** so trivial jitter (one extra warmup set) doesn't invalidate it.
- **Regenerate only when:** (a) user taps **Refresh**, OR (b) `dataHash` changed **and** (`≥ 3 new sessions since last gen` OR `≥ 7 days elapsed`). This gives an automatic weekly-ish beat without nagging.
- **On Insights open:** render cache immediately, show "as of \\<date>". If regen conditions are met, fire **one** background refresh (dimmed spinner over cache). Otherwise do nothing.
- **Cold start (no cache, threshold met):** generate once, then cache.

### Cost controls
- Gated behind isPro → no spend on free users.
- Coarse hash + the 3-session/7-day rule caps calls to roughly **weekly per active Pro user**.
- `max_tokens: 1024`, temp 0.3, single request (no chat loop).
- Graceful degradation: any failure shows last cache or the deterministic `routineSuggestion()` fallback — the user never sees a dead card, and we never retry-storm.

---

## 6. Pro gating, privacy, empty-data

- **Gating:** reuse both existing patterns. **Card visible to all** (free teaser = local `routineSuggestion()` TL;DR). **AI recommendation rows blurred** via `proCard()`-style `.blur(radius: isPro ? 0 : 7)` + `.allowsHitTesting(isPro)` + lock button → `onUnlock` → `paywallPresented = true` → `.sheet { PaywallScreen() }`. **Apply actions** hard-gated with the `guard isPro` pattern. `isPro` is the single source (`MasoFlags.iapEnabled` is TRUE, so this is live). `ProBanner` already sits atop the list for non-Pro.
- **Min-data threshold:** reuse `routineSuggestion()`'s existing guard — **≥ 2 weeks of history AND ≥ 6 recent sets.** Below that → "Insufficient data" state, **no LLM call.** When `signal.thin` (e.g. < 3 sessions in the window) the prompt forces an explicit hedge instead of confident advice (pitfall: "advice that outruns the signal").
- **Privacy:** data goes to DeepSeek **server-side via the Worker** exactly like every other AI call — the binary holds no key. Payload is **enum/number summaries only, no PII**: no name, no absolute dates (use `daysAgo`), no raw set-by-set logs, age sent as a band. This is a *smaller, less-identifying* payload than the routine generator already sends. No new privacy surface is opened.

---

## 7. Phased build plan

### Phase 1 — MVP (summary card, read-only, cached, Pro-gated)
1. **`AISummaryPayload` + `AISummary` models** — new file `Maso/Models/AISummary.swift` (Codable payload + parsed summary + `AISummaryAction`).
2. **`AIWorkoutService.summarizeTraining(payload:)`** — `AIWorkoutService.swift`: new method reusing Worker plumbing; `buildSummaryPrompt`; `parseSummaryResponse` (mirror `parseResponse`); temp 0.3, max_tokens 1024.
3. **`DataStore.buildSummaryPayload()`** + **`generateSummary()`** (calls service, caches, deterministic `routineSuggestion()` fallback) — `DataStore.swift`.
4. **Cache fields** on `Settings.swift` (`aiSummaryCacheJSON` / `aiSummaryDataHash` / `aiSummaryGeneratedAt`) + hash helper.
5. **`AISummaryCard.swift`** — new view in `Maso/Views/Components/`. All states (§1). Recommendation rows render but Apply buttons are **disabled/"coming soon"** in MVP OR wired only to `regenerate_routines`.
6. **Placement** — inject as first child of `InsightsChartsView.body`'s VStack (fixed, non-reorderable); pass `onUnlock` through from `HistoryScreen`.
7. **Localizable** — all strings.

### Phase 2 — Apply flow (the crux)
8. Wire **`regenerate_routines`** → `generateAIRoutines(focusNote:surface:"summary")` → existing routine-preview → `savePlan`. Pro-gate + paywall.
9. Wire **`add_coach_note`** → `appendCoachNote` with confirm toast.
10. Refresh cadence logic (hash + 3-session/7-day rule + Refresh button + background regen).

### Phase 3 — polish
11. True in-place **`add_sets`** (muscle→Plan step matching + `applyScience` + `updatePlan` diff preview).
12. Optional inline mini-viz (reuse a small volume bar) so the TL;DR points at something visual.

### Risks (flagged)
- **Hallucination / grounding (highest):** mitigated by computing every number deterministically and forbidding un-provided numbers/exercises in the prompt; `parseSummaryResponse` degrades unknown `action.type` to `.none`. Still the #1 thing to QA — spot-check that TL;DR only cites payload numbers.
- **The apply mapping is the hardest part:** `add_sets` in-place editing is genuinely fiddly — **defer to Phase 3**; ship v1 with `regenerate_routines` + `add_coach_note` only, both of which are just thin wrappers over machinery that already works.
- **Cost/latency:** controlled by Pro-gate + coarse-hash weekly cadence + cache-first render; never blocks the Insights list.
- **Empty/thin data:** hard threshold reuses `routineSuggestion()`'s guard so we never generate confident noise for new users.

### Files touched (summary)
- **New:** `Maso/Models/AISummary.swift`, `Maso/Views/Components/AISummaryCard.swift`
- **Edit:** `Maso/Data/AIWorkoutService.swift` (`summarizeTraining` + prompt + parse), `Maso/Data/DataStore.swift` (`buildSummaryPayload`, `generateSummary`, hash), `Maso/Models/Settings.swift` (cache fields), `Maso/Views/Screens/InsightsChartsView.swift` (inject card), `Maso/Views/Screens/HistoryScreen.swift` (pass `onUnlock`), `Localizable`.

---

Ready to build on approval. Recommended v1 scope: **Phase 1 + `regenerate_routines`/`add_coach_note` apply** — everything reuses existing, science-guarded machinery; defer in-place `add_sets` to Phase 3.",
    "market": {
      "apps": [
        {
          "name": "WHOOP (AI Coach + Weekly Plan)",
          "aiFeature": "Two-part system. (1) WHOOP Coach: an OpenAI-powered conversational chat that reads thousands of your data points (Recovery, Strain, Sleep, Stress, Journal) and answers questions like 'should I train hard today?' with grounded, science-referenced replies. (2) Weekly Plan / weekly performance recap: dynamically sets and adjusts daily targets (Strain, sleep-need, recovery goal) based on recent trends, plus an in-depth weekly recap with progress visuals and tailored recommendations.",
          "howPresented": "Coach is chat-first: conversational, second-person, answers in seconds, cites your actual numbers ('your recovery is 42% because HRV dropped and you got 5h12m sleep') and pairs a claim with a research-backed rationale. Weekly recap is a structured card/scroll digest with charts, week-over-week deltas, and a short prioritized recommendation list. Tone is coach-like and encouraging but data-first. Length: chat is tight; weekly recap is a skimmable digest, not a wall of text.",
          "applyMechanism": "Mostly advise + set targets, not auto-rewrite a strength plan. It tells you today's optimal Strain target and whether to push or recover, and the Weekly Plan adjusts your targets automatically as data comes in. WHOOP has no exercise-by-exercise plan to auto-edit; it steers behavior via daily/weekly target adjustment and conversational guidance you choose to follow.",
          "tier": "Requires paid WHOOP membership (the whole device is subscription-based; Coach + Weekly Plan are included, no separate charge). No meaningful free tier.",
          "notes": "The strongest 'grounded in YOUR numbers + cited science' model on the market. Weekly cadence for the recap, on-demand for Coach — good separation. Privacy handled explicitly: conversations not shared without consent, metrics anonymized before hitting OpenAI's model. Main limitation: it interprets and advises but doesn't own a structured training program to mutate."
        },
        {
          "name": "Oura (Oura Advisor)",
          "aiFeature": "AI personal-health companion that turns sleep/activity/recovery/readiness data into personalized, actionable guidance. Analyzes trends across days/weeks/months, stores 'Memories' (your goals, life events, biometrics) to keep context across sessions, and can build multi-day Action Plans around a goal (better sleep, less sedentary time, stress resilience). A proprietary women's-health LLM (2026) adds clinically-grounded cycle/hormone guidance.",
          "howPresented": "Revamped chat experience with inline data visualizations, trend analysis, and dynamic topic suggestions. Pre-written prompt chips lower the barrier to engage. Entry points seeded across the Today tab (+ button, menu). Conversational and warm; can render its own charts inline to back a claim. Advice framed as 'here's what your data shows, here's one thing to try.'",
          "applyMechanism": "Advise + build Action Plans you opt into. It does not run a workout program, so nothing auto-executes on a training plan; instead it proposes concrete behavioral changes and structures them into a plan you accept and it then tracks against.",
          "tier": "Requires Oura Membership (~$5.99/mo). Rolled out to all members in 2025. Ring hardware separate.",
          "notes": "Best-in-class at long-horizon trend framing and persistent memory (context carries between chats). Clinically-grounded women's-health model shows the credibility play: cite established medical standards, reviewed by board-certified clinicians. Wellness-positioned, not a training-load engine — advice is lifestyle/recovery, not sets-and-reps."
        },
        {
          "name": "Fitbod",
          "aiFeature": "Recovery-driven adaptive strength engine. Assigns every muscle group a 0-100% recovery score from your recent training history (plus cardio pulled from Apple Health/Fitbit/Strava), then two engines act on it: an Exercise Selector (what to do, favoring recovered muscles) and a Capability Recommender (how much weight/sets/reps). Progressive overload is applied automatically. Trained on 400M+ logged workouts.",
          "howPresented": "Not a chat and not a text essay — the interpretation IS the generated workout plus a visual muscle-recovery body map (colored by freshness). Rationale is lightweight and inline ('these muscles are fresh, so today targets them'). Very low-friction: you see the recommendation as the plan itself, not as a report you have to read.",
          "applyMechanism": "Auto-generates the plan (strongest 'apply' model here). Each day it builds the session from recovery + goals; you can override by swapping exercises, adjusting weights, or logging a Max Effort Day, and those edits feed back to improve future recommendations. Effectively suggest-with-easy-override rather than pure auto or pure advice.",
          "tier": "Subscription (Fitbod Elite); free trial then paid. Core AI generation is the paid product.",
          "notes": "Great example of 'advice tied to a concrete plan change' — there's no gap between insight and action because the insight is rendered as the workout. Risk: recovery %/1RM estimates are modeled heuristics, so credibility depends on the visible body-map making the reasoning legible. Learns from feedback, which compounds accuracy over time."
        },
        {
          "name": "Freeletics (AI Coach)",
          "aiFeature": "One of the original 'AI coach' apps: builds and continuously adapts a bodyweight/gym training journey to your goal, level, equipment, available time and feedback. After each session you rate difficulty ('too hard / just right / too easy') and the next session's volume/intensity adapts. Added conversational coaching layers to answer questions and adjust.",
          "howPresented": "Coach presents the next session as a ready-to-do workout with a short rationale for why it changed ('you found last week tough, so we're deloading'). Feedback capture is a simple tap-scale, not free text. Tone is motivational; interpretation is brief and tied directly to the upcoming session.",
          "applyMechanism": "Auto-adapts the plan session-to-session based on your ratings and completion. Suggest+auto blend: the plan regenerates automatically, you approve by starting it.",
          "tier": "Freemium; the adaptive AI Coach is the paid subscription (Freeletics Coach). Free tier is limited.",
          "notes": "Pioneered the 'rate perceived effort → plan adapts' loop that's now table stakes. Because adaptation is driven by cheap explicit feedback (not just sensors), it works without a wearable — a robustness advantage. Advice is always actionable because it only ever changes the next workout."
        },
        {
          "name": "TrainerRoad (Adaptive Training + Red Light Green Light)",
          "aiFeature": "Cycling-first ML system. Adaptive Training measures your performance on every workout (via post-ride Survey + power data), estimates ability per training zone, and adjusts upcoming workout difficulty to keep progression on track. Red Light Green Light watches fatigue signals and flags when you're heading toward burnout, automatically swapping in easier sessions or rest.",
          "howPresented": "Presented as plan changes, not prose. After a ride it shows which upcoming workouts were made easier/harder and by how much, with a brief reason. Red/Green is a simple traffic-light signal on the calendar. Minimal narrative — the value is the concrete adjustment, which you can inspect. Some users note it adjusts 'without much explanation.'",
          "applyMechanism": "Auto-adjusts the plan (accept-by-default). Adaptations are applied to your calendar automatically; you can accept/decline specific ones. Strong, hands-off 'apply' mechanism grounded in measured power.",
          "tier": "Paid subscription only (no free tier). Adaptive Training is core, included.",
          "notes": "Credibility comes from being grounded in objective power output + a large modeled dataset of rider responses, not vibes. Trade-off vs LLM coaches: reliable and fatigue-aware but terse and cycling-only; it tells you WHAT changed better than WHY. Good model for 'weekly-ish cadence, concrete plan mutation.'"
        },
        {
          "name": "Athletica",
          "aiFeature": "Adaptive endurance (swim/bike/run/tri) AI. Periodizes your plan off Critical Power / Critical Pace profiling, then analyzes performance and recovery to adjust each workout. Layers an AI chat coach on top for questions. Aims to be transparent and formula-driven rather than a black box.",
          "howPresented": "Transparent, principled plan: shows the periodization logic and threshold numbers (CP/CPace) driving your zones, so you can see WHY a workout is what it is. Chat coach answers in conversational form. More explanatory than TrainerRoad — leans into showing its reasoning.",
          "applyMechanism": "Adjusts workouts automatically from performance/recovery, but leaves more day-to-day 'push or back off' judgment to the athlete than TrainerRoad's fully hands-off swaps. Suggest + partial auto.",
          "tier": "Paid subscription (with trial). Positioned at self-coached endurance athletes.",
          "notes": "Illustrates the 'transparent, sports-science-grounded' credibility path: expose the model (Critical Power periodization) instead of hiding it. Multi-sport. Good contrast case — Athletica explains and empowers; TrainerRoad automates and simplifies. Choose based on whether your users want to understand or to be told."
        },
        {
          "name": "Gyroscope",
          "aiFeature": "Aggregator that pulls data from many sources (steps, sleep, HR, workouts, nutrition, mood) into unified daily/weekly/monthly 'story' reports and an AI Coach that summarizes trends and nudges toward goals. Focus is whole-life health synthesis rather than a single training program.",
          "howPresented": "Beautifully-designed narrative report cards — a magazine-style weekly/monthly recap with charts and short annotated highlights, plus AI-generated commentary. Emphasis on visual storytelling and trend framing over interactive chat. Skimmable, image-forward.",
          "applyMechanism": "Advise only. It summarizes and nudges (goals, streaks, suggestions) but doesn't own or mutate a structured workout plan — the user acts on the advice manually.",
          "tier": "Freemium; the richer AI Coach / advanced reports are behind Gyroscope's paid membership tiers.",
          "notes": "Strong on presentation and cross-source synthesis (the 'summary' craft), weaker on 'apply' — there's no plan to change, so advice can feel like observation rather than instruction. Useful as a design reference for how to make a weekly recap feel premium and readable."
        },
        {
          "name": "Runna",
          "aiFeature": "Personalized, adaptive running plans (5k to marathon). Science-backed plans that continuously update as you progress, change your schedule, or miss sessions. Uses an Estimated Race Time / Race Predictor to set pace targets, and gives per-workout AI insights after each run. Adds a guided/conversational support layer plus 24/7 human support.",
          "howPresented": "Post-run AI insight: a short, personalized readout on how the session went vs targets, in plain language. Plan changes surface as an updated schedule. Pace targets are always tied to your predicted race time, so advice is concretely numeric. Encouraging, runner-friendly tone; concise per-workout cards.",
          "applyMechanism": "Auto-adapts the plan (progressive overload, pace targets, reschedules when you move/miss sessions). Suggest+auto: your calendar updates and you run what's next. The Race Predictor is the lever that recalibrates every pace target.",
          "tier": "Paid subscription (free trial). The plan + AI adjustments are the paid product.",
          "notes": "Clean example of tying interpretation to a concrete, ever-present number (predicted race time → every pace target). Adaptation from real completion data + explicit schedule changes. Users note it shines when you already have a training base — a reminder that adaptive advice needs enough signal to be credible."
        },
        {
          "name": "Strava (Athlete Intelligence)",
          "aiFeature": "Generative-AI activity summaries. On upload of a run/ride/walk/hike, it turns the activity's stats (pace, HR, elevation, power, Relative Effort) into a plain-language summary, and aggregates 30-day trends for smarter cross-workout insights. Now out of beta; supports many sport types incl. virtual runs/rides, power and segment analysis.",
          "howPresented": "A short auto-generated text summary attached to each activity — 'here's what this workout was and how it compares.' Casual, readable, second-person. Deliberately simple: translates numbers most athletes ignore into a sentence or two. Not a chat; not a coach that prescribes.",
          "applyMechanism": "Advise / summarize only. Strava has no training plan to mutate; it interprets what you did and flags trends, leaving any plan change entirely to the user.",
          "tier": "Strava Premium (subscriber-only).",
          "notes": "Best-in-class at the pure 'summarize' half of the brief — turning raw activity data into a friendly readout — but has no 'apply' mechanism at all, which is exactly the gap dedicated AI coaches fill. Useful contrast: a summary with no actionable, plan-tied next step reads as a nice-to-have, not a coach."
        },
        {
          "name": "Apple Fitness / Apple Health",
          "aiFeature": "As of early 2026, largely rules-based rather than generative: Apple Watch delivers Training Load (relative effort trend), Vitals (overnight metric outlier alerts), and Activity trends/coaching-style notifications. Apple previewed an AI health-coach initiative ('Project Mulberry'/an AI-assisted Health+ direction) but a full conversational AI coach was not broadly shipped as of this writing.",
          "howPresented": "Notifications and trend cards, not conversational prose. Training Load shows a simple up/steady/down read on recent effort; Vitals surfaces 'these metrics are outside your typical range.' Terse, glanceable, system-notification style. Encouraging Activity-ring nudges.",
          "applyMechanism": "Advise / alert only. No adaptive training plan to auto-adjust; Apple presents trends and outliers and leaves action to the user (or third-party apps reading HealthKit).",
          "tier": "Free with Apple Watch for core metrics; some guided-content lives in Apple Fitness+ (paid). No paid AI coach shipped broadly yet.",
          "notes": "Massive data/distribution advantage but conservative and rules-based on interpretation — reflects Apple's caution around health claims and hallucination risk. The gap here (great data, thin interpretation, no plan to action) is precisely the opening third-party AI coaches exploit."
        },
        {
          "name": "Hevy / Strong (strength loggers)",
          "aiFeature": "Primarily manual loggers, not AI coaches. Both surface computed analytics — volume, estimated 1RM, PRs, muscle-group distribution, progression charts. Hevy has moved faster on 'smart' features (routine suggestions, progression hints, and a Hevy Coach/pro direction) but neither offers a mature generative weekly-summary-and-adapt engine comparable to WHOOP/Fitbod as of early 2026.",
          "howPresented": "Charts, tables, PR badges and progression graphs — the interpretation is quantitative dashboards, not narrative AI text. Any 'insight' is a computed stat or a simple rule-based nudge ('add weight, you hit all reps'), presented inline next to the exercise/history.",
          "applyMechanism": "Mostly advise via computed stats; Hevy's progression suggestions can pre-fill next-session weights (a light suggest-to-accept), but there's no fatigue-aware auto-rewriting of the program. The user drives the plan.",
          "tier": "Freemium. Advanced analytics and any smart/coach features sit behind Hevy Pro / Strong Pro.",
          "notes": "Included as the 'baseline' contrast: excellent structured data capture but minimal AI interpretation — a clear whitespace for an AI layer that reads their own logged sets and produces a grounded weekly summary + concrete next-session changes. Their strength (clean per-set data) is exactly what a credible AI summary needs as raw material."
        }
      ],
      "bestPractices": [
        "Ground every single claim in the user's own numbers. The most credible feature (WHOOP) never says 'you seem tired' — it says 'recovery is 42% because HRV is down 12ms and you slept 5h12m.' Quote the actual metric, the actual delta, and the threshold it crossed. A summary that could apply to anyone reads as gimmick; one built from this user's data reads as a coach.",
        "Prioritize 2-3 actions, not a wall of text. Lead with the single most important thing to do differently, then at most one or two more. Fitbod/TrainerRoad succeed partly because the 'insight' is compressed into one concrete change; long essays get skimmed and ignored.",
        "Tie advice to a concrete, executable plan change — close the gap between insight and action. The strongest apps make the recommendation the plan: Fitbod renders it as today's workout, Runna recalibrates every pace target, TrainerRoad rewrites the calendar. Advice with no button to apply it (Strava, Gyroscope, Apple) feels like observation, not coaching.",
        "Anchor everything to one legible, always-present number. Runna hangs every pace target off predicted race time; Athletica exposes Critical Power/Pace; Fitbod shows a recovery %. A visible anchor lets the user sanity-check the advice and understand why it changed — this is what converts 'trust me' into 'I can see why.'",
        "Use the right cadence: weekly recap + on-demand chat, not a notification on every app open. WHOOP separates a weekly performance recap (reflection) from an on-demand Coach (questions). Over-frequent auto-summaries train users to dismiss them; a predictable weekly beat plus 'ask me anything' respects attention.",
        "Show your reasoning / expose the model when users want depth. Athletica wins credibility by showing the periodization logic and threshold numbers rather than a black box. Offer a one-line 'why' by default with an option to drill in — legibility builds trust and lets experienced users catch bad calls.",
        "Adapt from cheap explicit feedback, not just sensors. Freeletics' 'too hard / just right / too easy' tap and TrainerRoad/Runna's post-session survey give a reliable adaptation signal that works even without a wearable and directly reflects perceived effort — robust and hard to hallucinate.",
        "Cite science / clinical grounding, and scope it honestly. WHOOP references performance research; Oura's women's-health model cites established medical standards reviewed by clinicians. Pairing a personal number with a credible mechanism ('X because Y, which research links to Z') is far more persuasive than either alone.",
        "Carry context between interactions (memory). Oura Advisor stores goals, life events and past guidance as 'Memories' so it doesn't re-ask or contradict itself. A summary that remembers last week's advice and reports whether it worked feels like a relationship, not a fresh cold read each time.",
        "Make adaptations inspectable and reversible. TrainerRoad lets you accept/decline specific plan changes; Fitbod lets you swap exercises and learns from it. Auto-adjust is fine when the user can see exactly what changed and undo it — silent changes erode trust.",
        "Be honest about uncertainty and thresholds. Say when signal is thin ('only 2 runs logged this week — treat this as a rough read') rather than manufacturing confident advice. Runna users note the engine needs a training base to be good; surfacing that limitation is more credible than pretending otherwise.",
        "Render interpretation visually, not only as prose. Fitbod's colored recovery body-map and Gyroscope/Strava's chart-forward summaries make trends graspable at a glance and give the text something concrete to point at — lowers reading effort and raises perceived quality."
      ],
      "pitfalls": [
        "Generic, horoscope-style advice that isn't tied to the user's data. If the summary would read the same for any user ('stay hydrated and get good sleep!'), it destroys credibility instantly. This is the #1 failure mode of bolt-on LLM summaries — plausible prose, no personal grounding.",
        "Hallucinated numbers or claims. LLMs will confidently invent a stat, misread a trend, or cite a mechanism that doesn't exist. In a health/training context a wrong 'your HRV dropped, back off' (when it didn't) is both a trust killer and a safety issue. Anything numeric should be computed deterministically and fed to the model, never generated by it.",
        "Over-frequent nagging. A summary on every app open, or a push notification after every workout, trains users to swipe it away. Frequency should match how often there's genuinely something new and actionable — weekly recap + on-demand beats constant chatter.",
        "Advice the app can't actually action. Telling a user to 'add a tempo run and cut back-squat volume 10%' is worthless if there's no plan to apply it to (Strava, Apple, loggers). The insight-to-action gap makes even good advice feel academic. Only prescribe changes your product can execute or at least draft.",
        "Silent or opaque auto-adjustment. Changing the plan without showing what changed or why (a known TrainerRoad critique) leaves users confused and unable to trust or override the system. Auto-apply must be paired with a visible, inspectable, reversible change log.",
        "Cost and latency at scale. Per-user LLM weekly summaries and always-on chat coaches are expensive and can be slow; a coach that takes 8 seconds to answer or that you rate-limit aggressively feels worse than a fast rules-based card. Budget for caching, cheaper models for routine summaries, and graceful degradation.",
        "Privacy and data-sharing exposure. Sending biometric/health data to a third-party model (WHOOP routes anonymized metrics through OpenAI's partner) is a real risk surface. Users must be told what leaves the device, it should be anonymized/consented, conversations shouldn't be stored or shared without permission, and health-data regulations (HIPAA-adjacent expectations, GDPR) apply.",
        "Advice that outruns the signal. Generating confident recommendations from 1-2 data points, a new user with no history, or a week with missing sessions produces noise dressed as insight. Gate the summary behind a minimum-data threshold and downgrade confidence when signal is thin.",
        "Contradiction and lack of memory. Without persistent context the coach re-asks known facts, gives advice that conflicts with last week's, or ignores stated goals/injuries — making it feel like a stranger every session and quickly untrustworthy.",
        "Unsafe or over-medical claims. Straying into diagnosis, ignoring injury/deload needs, or pushing intensity when recovery signals say rest can harm users and create liability. This is why Apple stays conservative and Oura routes women's-health guidance through clinician-reviewed standards — the model must respect hard safety guardrails and defer to human/medical judgment.",
        "Feedback loops that reward gaming. If adaptation keys purely on completion or self-rated ease, users can nudge the system toward easier plans (or it can spiral into deloads) — a fitness-quality failure. Balance perceived-effort signals against objective output (power, pace, load).",
        "Motivational tone masking weak substance. Emoji-laden hype ('Crushing it! 🔥') with no real numbers behind it reads as gimmicky and patronizing to serious users. Tone should be encouraging but the substance must carry it, not the other way around."
      ]
    },
    "current": {
      "availableMetrics": [
        {
          "metric": "Week-over-week volume & set delta (WeekChange: .pct/.isNew/.none)",
          "source": "InsightsChartsView.weekDeltas() (helper) + deltaCardOrEmpty",
          "whatItTells": "This week vs last complete week: % change in tonnage (Σ weight×reps) and total set count. Tells if the user is progressing, holding, or backing off right now. Returns nil until ≥1 prior week exists (skip for brand-new users)."
        },
        {
          "metric": "Weekly training volume (last 8 weeks, kg)",
          "source": "InsightsChartsView.weeklyVolume() → [VolPoint(week, volume)]",
          "whatItTells": "Trailing 8-week tonnage per week (missing weeks padded to 0 for a continuous bar). Tells the overall training-load trajectory — ramping, plateaued, or dropping."
        },
        {
          "metric": "Top-lift estimated 1RM trend (Epley)",
          "source": "InsightsChartsView.topLiftSeries() → (name, [RMPoint]); e1RM = w*(1+r/30), best-per-day",
          "whatItTells": "The user's most-trained weighted lift and its day-by-day best estimated 1RM over time. Tells whether their flagship lift is getting stronger."
        },
        {
          "metric": "Per-lift e1RM series (any lift, picker-selectable)",
          "source": "InsightsChartsView.weightedLifts() (lift list by set count) + e1rmSeries(forExerciseId:)",
          "whatItTells": "For ANY weighted exercise, day-by-day best e1RM. Tells strength progression per movement — the raw signal for detecting per-lift stalls."
        },
        {
          "metric": "Weekly sets per muscle section + lagging flag",
          "source": "InsightsChartsView.weeklySetsPerSection() → [SectionSets(label,sets,isLagging)] over 6 sections (chest/back/shoulders/arms/core/legs)",
          "whatItTells": "Last-7-days hard-set count per major muscle group, with the least-trained group flagged. Tells muscle-balance / which region is being skipped THIS week."
        },
        {
          "metric": "MEV/MAV landmark rows (10/20 set science bands)",
          "source": "InsightsChartsView.weeklyLandmarkRows() → [LandmarkRow(label,sets)] vs static mevSets=10 / mavSets=20",
          "whatItTells": "Each muscle's weekly hard sets scored against Renaissance-Periodization landmarks: under-MEV = insufficient stimulus, MEV–MAV = effective band, over-MAV = possibly excessive. The most 'coach-like' balance signal already computed."
        },
        {
          "metric": "Per-muscle weekly volume (8-week stacked, kg)",
          "source": "InsightsChartsView.perMuscleWeeklyVolume() → [SectionWeekVol(week,section,volume)]",
          "whatItTells": "Tonnage per muscle section per week over 8 weeks. Tells how load is distributed across the body over time (not just count)."
        },
        {
          "metric": "Training frequency per muscle (days/week, last 4 weeks)",
          "source": "InsightsChartsView.trainingFrequencyRows() → [FreqRow(label,daysPerWeek)]",
          "whatItTells": "Average sessions/week that hit each muscle section over the trailing 4 weeks. Tells whether each muscle gets enough frequency (e.g. 2×/wk) vs being crammed into one day."
        },
        {
          "metric": "PR timeline",
          "source": "InsightsChartsView.prTimeline() → [PRItem(date,exercise,oneRM)] filtered by DataStore.isPR($0)",
          "whatItTells": "Every set flagged as a personal record (e1RM beats all prior history for that lift), newest-first. Tells recent momentum / bright-spot wins to celebrate in a summary."
        },
        {
          "metric": "PR detection primitive",
          "source": "DataStore.isPR(SetRecord) + estimatedMaxLoad(forExerciseId:excluding:)",
          "whatItTells": "Boolean: is this set a new e1RM high vs historical max (first-ever attempt = not a PR). The underlying rule that powers the PR timeline and could tag PRs inside a summary."
        },
        {
          "metric": "Consistency / adherence score (0–100%)",
          "source": "InsightsChartsView.consistencyScore() → % of last-8-weeks that met weeklyTrainingDays goal",
          "whatItTells": "Share of recent weeks where the user hit their days/week goal (only counts weeks after they started). Tells reliability/habit strength."
        },
        {
          "metric": "All-time tonnage",
          "source": "InsightsChartsView.allTimeTonnage() → Σ weight×reps across all sets",
          "whatItTells": "Lifetime cumulative load lifted. A motivating grand-total stat for a summary header."
        },
        {
          "metric": "Completed workout count (distinct training days)",
          "source": "DataStore.completedWorkoutCount → Set(startOfDay of every set).count",
          "whatItTells": "Total number of distinct days trained (multiple sessions/day = 1). Milestone/engagement metric; already drives review + reminder prompts."
        },
        {
          "metric": "Diagnosed single most-actionable problem (lagging / stall / adherence)",
          "source": "DataStore.routineSuggestion() → RoutineSuggestion(id,title,detail,focusNote); helper stalledLiftSuggestion(in:)",
          "whatItTells": "THE ready-made coaching verdict: prioritizes (1) a muscle section trained ≤40% of the top section or fully missing over 3 weeks, (2) a plateaued main lift (last e1RM ≤99% of recent peak), (3) attendance below goal-1. Needs ≥2 weeks + ≥6 recent sets or returns nil. This is the exact 'what should I change' sentence an AI summary should surface — and it already carries a machine-ready focusNote."
        },
        {
          "metric": "Last set per exercise",
          "source": "DataStore.lastSet(forExerciseId:)",
          "whatItTells": "Most recent weight×reps for a lift ('last time: 100kg × 8'). Context for phrasing concrete progression suggestions."
        }
      ],
      "aiInfra": "The AI pipeline is Maso/Data/AIWorkoutService.swift — a @MainActor @Observable singleton (AIWorkoutService.shared) that is TEXT-ONLY and SERVER-SIDE. It never talks to an LLM directly: it POSTs to a Cloudflare Worker proxy at {proxyURL}/v1/chat/completions (proxyURL from Info.plist key MasoAIProxyURL, injected via Secrets.xcconfig; auth via X-Maso-Client-Token header = MasoClientToken). The Worker adds the real DeepSeek API key server-side and forwards to api.deepseek.com (model "deepseek-chat", OpenAI-compatible chat/completions, response_format json_object). The binary holds NO API key. isConfigured = !proxyURL.isEmpty && !clientToken.isEmpty — UI gates on this (not on a user toggle since Path B).

Entry points, all async, all returning parsed Swift objects:
- generateToday(payload,library,maxExercises,surface) → Plan?  (one session; temp 0.7, max_tokens 2048)
- generateRoutines(payload,library,count,maxExercises,surface) → [Plan]?  (N distinct routines forming a weekly split, each with its own rationale; temp 0.8, max_tokens 4096)
- pickFreeWorkoutExercises(payload,targetMuscles,candidates) → [String]?  (ordered exercise-id list from a pre-filtered candidate set)

Prompt construction (buildPrompt / buildRoutinesPrompt): USER PROFILE (gender/age/weight/days/goal/equipment + coachMemoryBlock), RECENT WORKOUTS (last 14 days, from AIPayload.recentHistory), a GUIDELINES block of hard science rules (compound-first, ≤2 same-section, isolation ≤40%, push≥pull, 48h recovery, goal-driven rep/set bands), an optional PRIORITY line injected from payload.focusNote, and a candidateNames(from:) whitelist — the LLM MUST copy exercise_name verbatim from that list (fixes the old free-naming → match-miss → empty-plan bug). AIPayload is built by DataStore.buildAIPayload() (profile + goal-derived rep/set/rest bands + equipment + coachMemory + 14-day aggregated history).

Structured JSON parsing: parseResponse / parseRoutinesResponse / parsePickerResponse strip ```json fences, then JSONDecoder into private Codable AIResponse {name, rationale, steps:[AIStep{exercise_name,sets,reps,weight_kg,duration_seconds}]} (and AIRoutinesResponse{routines:[...]} with a bare-array fallback). buildPlan(from:) fuzzy-matches each exercise_name → real exerciseId via matchExercise (exact → token-subset → Jaccard≥0.5, plus a nameSynonyms map), clamps sets/reps/weight/duration, marks source=.ai + autoGenerated=true, and attaches the LLM's rationale onto the Plan. Errors are a private enum AIError {network/api/parse} with .userMessage (shown inline) and .analyticsReason (network/api/parse) for the ai_routine_generate_fail event; state is an @Observable State {idle/generating/success(Date)/failure(String)} that the UI binds spinners to.

Science backstop: DataStore.enforceScience(steps, exById) runs AFTER every generation (via applyScience) on AI, template, AND community plans — using only 100%-populated fields (mechanic compound/isolation, force push/pull/static, primaryMuscles.first.section) to (a) sort compound-first, (b) cap ≤2 per section, (c) guarantee a compound in slot 1, (d) nudge push≥pull. It never cuts a routine to 0. This is the code-side guarantee that the prompt's prose rules actually hold.",
      "applyMechanisms": [
        {
          "name": "generateAIRoutines(focusNote:surface:)",
          "howItWorks": "THE crux. Async; builds a fresh AIPayload, sets payload.focusNote, calls AIWorkoutService.generateRoutines for count=clamp(weeklyTrainingDays,2...4) real AI routines, runs each through enforceScience, and returns (plans, usedFallback). On failure/not-configured it returns local tunedRecommendedPlans with usedFallback=true. focusNote is injected into the prompt's PRIORITY line — so a diagnosed problem (e.g. 'bias the split toward legs') directly steers the regenerated routines. This is how an AI recommendation becomes concrete new routine objects the user can save.",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift (func generateAIRoutines ~line 1171)"
        },
        {
          "name": "routineSuggestion() + RoutineOptimizeCard + handleOptimize",
          "howItWorks": "The existing 'AI recommendation → routine change' loop end-to-end. routineSuggestion() diagnoses ONE top problem from ~3 weeks of sets (lagging/missing muscle → stalled main lift → low adherence), needs ≥2 weeks + ≥6 sets else nil, and emits a RoutineSuggestion{id,title,detail,focusNote}. RoutineOptimizeCard renders title/detail + an 'Optimize with AI' button (visible to all as a teaser). TodayScreen shows it when !plans.isEmpty (onOptimize closure bubbles up). PlansScreen.handleOptimize(suggestion) gates on isPro (else paywallPresented=true), then calls startGenerateRoutines(focusNote: suggestion.focusNote, surface:'optimize') → generateAIRoutines. So the summary's verdict already has a one-tap path to become a regenerated, science-checked routine set. A summary card would slot in front of exactly this machinery.",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift (routineSuggestion ~1207) + /Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/RoutineOptimizeCard.swift + /Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift (handleOptimize ~447, startGenerateRoutines ~427) + TodayScreen.swift (~158)"
        },
        {
          "name": "Coaching Memory (settings.coachMemory + appendCoachNote + coachMemoryBlock)",
          "howItWorks": "A persistent free-text preference store. DataStore.appendCoachNote(note) appends a de-duped '- bullet' to settings.coachMemory (Pro-gated at the call site — PlansScreen.sendRefine writes it only after the isPro check). buildAIPayload injects it (trimmed, last ~1200 chars) into every prompt via AIPayload.coachMemoryBlock as a 'COACH NOTES — always respect these' section. So any accepted natural-language recommendation from a summary ('add more legs', 'skip barbell') can be persisted once and bias ALL future generations, not just the next one — long-term personalization on top of the immediate focusNote.",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift (appendCoachNote ~122, buildAIPayload coachMemory ~1373) + AIWorkoutService.swift (coachMemoryBlock ~744)"
        },
        {
          "name": "enforceScience(steps,exById) / applyScience(to:)",
          "howItWorks": "Static function run on every generated plan (AI + template + community) to enforce hard rules on 100%-populated fields: compound-first sort, ≤2 exercises per muscle section, guaranteed compound in slot 1, push≥pull nudge; never empties a routine. applyScience wraps it for a single Plan on the AI paths. Guarantees that whatever an AI summary triggers cannot violate basic programming science even if the LLM misbehaves.",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift (enforceScience ~573, applyScience ~1125)"
        },
        {
          "name": "savePlan / updatePlan / createBlankPlan (routine persistence + edit/replace)",
          "howItWorks": "How a routine actually changes on disk. savePlan(plan)→Bool copies a generated/AI plan into data.plans (preserving resolvedSource so the AI badge survives the re-id), enforcing the free 3-save cap via canSaveMorePlans (isPro || plans.count<3) — returns false → caller shows paywall. updatePlan(plan) upserts into plans, and when globalExerciseParamSyncEnabled, propagates changed params of existing steps to every plan (+aiTodayPlan) via syncExerciseParams. createBlankPlan makes an empty editable routine. Together these are the write path any 'apply summary → routine' feature would call after generateAIRoutines produces candidates.",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift (savePlan ~937, updatePlan ~638, syncExerciseParams ~664, createBlankPlan ~879)"
        },
        {
          "name": "aiTodayPlan write path (refreshAIWorkoutIfNeeded / forceRefreshAIWorkout / generateFirstPlanViaAI)",
          "howItWorks": "How today's recommended session gets replaced. Each builds a payload, calls generateToday, runs applyScience, and assigns to data.aiTodayPlan (+ lastAIRefreshAt), with aiTodayFailed driving an inline 'AI unavailable — Retry' chip on Today. A summary that suggests changing TODAY's workout (vs the weekly routines) would flow through this same aiTodayPlan slot.",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift (refreshAIWorkoutIfNeeded ~1103, forceRefreshAIWorkout ~1132, generateFirstPlanViaAI ~1151)"
        }
      ],
      "proGating": "Pro gating is centralized on settings.isPro (Maso/Models/Settings.swift). isPro returns true if !MasoFlags.iapEnabled OR proSubscription != nil — MasoFlags.iapEnabled is currently TRUE (line 7), so real free/Pro gating is live and the paywall shows for non-subscribers. Two visual patterns exist and both are already used by the exact surfaces this feature touches: (1) blur+lock — proCard() and oneRMCard in InsightsChartsView render the real content underneath at .blur(radius: isPro ? 0 : 7) + .allowsHitTesting(isPro) with a centered lock button ('Unlock deep insights with Pro') whose action calls onUnlock → HistoryScreen sets paywallPresented=true; isEmpty checks data only, never isPro, so the hook is always visible. (2) hard gate + paywall sheet — PlansScreen.handleOptimize / sendRefine do `guard data.settings.isPro else { paywallPresented = true; return }`, and paywallPresented drives `.sheet(isPresented:){ PaywallScreen() }`. There's also a save-count gate (canSaveMorePlans: isPro || plans.count<3). This is a NATURAL Pro item: the deep-insight cards it would sit above are ALREADY Pro-blurred, routineSuggestion→optimize is ALREADY Pro-gated, and Coaching Memory writes are ALREADY Pro-gated — so an 'AI summary + apply' card fits the existing paradigm exactly (show the card/verdict as a free teaser, blur the AI-written summary text and/or gate the 'Apply to my routine' action behind the same paywallPresented→PaywallScreen sheet). ProBanner is the standard upsell strip already rendered atop the Insights list when !isPro.",
      "insightsPlacement": "HistoryScreen (Maso/Views/Screens/HistoryScreen.swift) renders Progress as a top segmented Picker with two tabs: HistoryTab.insights and .records (line ~131, .pickerStyle(.segmented)). When there are sessions and historyTab == .insights (line 138), it renders a SINGLE `InsightsChartsView(data:, onUnlock:{ paywallPresented = true })` — built at line 97 — padded by MasoMetrics.pagePaddingHorizontal, but ONLY if `!insights.isEmpty` (else a 'Keep training…' placeholder). Above it (outside the segment) sits the ProBanner when !isPro (lines 88-92). InsightsChartsView is itself the whole card list: its body (line 54) does `VStack(alignment:.leading, spacing:16){ optional reorder hint (if cards.count>=2); ForEach(visibleCards){ id in card(id).draggable(...).dropDestination(...) } }`, where visibleCards = settings.resolvedInsightOrder filtered by hasData. So a summary card would sit ABOVE the cards in one of two clean spots: (A) simplest — inject it as the first child of that VStack, before the reorder hint + ForEach, so it always leads the analytics list; or (B) place it in HistoryScreen between the ProBanner and the InsightsChartsView call (still inside the historyTab==.insights branch, above line 143 `insights`). Because the per-card list is a self-contained reorderable ForEach keyed to resolvedInsightOrder, dropping a fixed (non-reorderable) summary card as the VStack's first element keeps it pinned at the top without touching the drag/drop reorder math."
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
      "agentId": "a2da25e18fe2abc7f",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782887202868,
      "queuedAt": 1782887202859,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "promptPreview": "You are a fitness-product analyst. Research how leading fitness/health apps use AI to SUMMARIZE a user's training data and give ACTIONABLE recommendations the user can apply to their plan. Use WebSearch/WebFetch (load via ToolSearch) + your own knowledge (through early 2026).

Cover apps with real "AI coach / weekly summary / adaptive plan" features: WHOOP (AI Coach + weekly performance summary), …",
      "lastProgressAt": 1782887383058,
      "tokens": 45732,
      "toolCalls": 8,
      "durationMs": 180190,
      "resultPreview": "{"apps":[{"name":"WHOOP (AI Coach + Weekly Plan)","aiFeature":"Two-part system. (1) WHOOP Coach: an OpenAI-powered conversational chat that reads thousands of your data points (Recovery, Strain, Sleep, Stress, Journal) and answers questions like 'should I train hard today?' with grounded, science-referenced replies. (2) Weekly Plan / weekly performance recap: dynamically sets and adjusts daily tar…"
    },
    {
      "type": "workflow_agent",
      "index": 2,
      "label": "research:current",
      "phaseIndex": 1,
      "phaseTitle": "Research",
      "agentId": "a7550bc99510707fd",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782887202874,
      "queuedAt": 1782887202859,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "The AI pipeline is Maso/Data/AIWorkoutService.swift — a @Ma…",
      "promptPreview": "Inventory what the Maso iOS app at /Users/yumowu/Projects/Maso-iOS ALREADY has to power an "AI training-data summary + apply-to-routine" feature. Read the real files. Report:
- availableMetrics: the derived training metrics computable for a summary — read Maso/Views/Components/InsightsChartsView.swift (its data helpers: weekDeltas, weeklyVolume, weeklySetsPerSection, topLiftSeries/e1RM, MEV/MAV la…",
      "lastProgressAt": 1782887344313,
      "tokens": 126825,
      "toolCalls": 17,
      "durationMs": 141439,
      "resultPreview": "{"availableMetrics":[{"metric":"Week-over-week volume & set delta (WeekChange: .pct/.isNew/.none)","source":"InsightsChartsView.weekDeltas() (helper) + deltaCardOrEmpty","whatItTells":"This week vs last complete week: % change in tonnage (Σ weight×reps) and total set count. Tells if the user is progressing, holding, or backing off right now. Returns nil until ≥1 prior week exists (skip for brand-n…"
    },
    {
      "type": "workflow_agent",
      "index": 3,
      "label": "synthesize:design",
      "phaseIndex": 2,
      "phaseTitle": "Synthesize",
      "agentId": "aed03dffecaa563c2",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782887383061,
      "queuedAt": 1782887383060,
      "attempt": 1,
      "lastToolName": "mcp__ccd_session__mark_chapter",
      "lastToolSummary": "AI Insight Summary plan",
      "promptPreview": "Design a build-ready plan for an "AI Insight Summary" feature at the TOP of the Maso iOS Progress→Insights segment. It should: analyze the user's recent training data, give a quick plain-language interpretation + prioritized, concrete recommendations (how to progress, how to improve fitness, which muscles are undertrained), and let the user APPLY a recommendation directly to their Training Routine…",
      "lastProgressAt": 1782887497317,
      "tokens": 48741,
      "toolCalls": 1,
      "durationMs": 114256,
      "resultPreview": "Here is the design doc.

---

# Maso — AI Insight Summary (Progress → Insights, top card)

Build-ready design doc. Status: **PLAN for review, build after approval.** Target: Maso-iOS (SwiftUI, DeepSeek via Cloudflare Worker, text-only, server-side). All symbols below are the real ones from the current codebase.

---

## 1. Concept & UX

A single **`AISummaryCard`** pinned at the very top of the In…"
    }
  ],
  "totalTokens": 221298,
  "totalToolCalls": 26
