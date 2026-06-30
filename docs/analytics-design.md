# Maso Product Analytics — Build-Ready Design

Privacy-forward, solo-shipper-friendly product analytics for Maso-iOS. No PII, no IDFA/ATT, per-install anonymous id, offline-buffered, MasoFlags-gated, mirroring the existing `AIWorkoutService` / `FeedbackStore` patterns.

---

## 1. Event taxonomy

All events carry an implicit envelope (added by the service, not per-call): `anon_id` (per-install UUID from `UserSettings`), `ts` (ISO8601), `app_version`, `os_version`, `language`, `session_seq` (monotonic per cold-launch). Properties below are event-specific. **No free text, no exercise names, no plan titles — only ids/enums/counts/bools.**

### Lifecycle

| event | properties |
|---|---|
| `app_launch` | `is_fresh_install: Bool`, `onboarding_completed: Bool`, `days_since_install: Int` |
| `app_foreground` | `seconds_backgrounded: Int` |
| `app_background` | `session_event_count: Int` (events this fg session) |
| `tab_switch` | `tab: String` (plans/today/library/history) |
| `settings_toggle` | `key: String` (health/reminders/exercise_sync/weight_unit/week_start), `value: String`, `permission_granted: Bool?` |

### Feature usage

| event | properties |
|---|---|
| `ai_routine_generate_start` | `surface: String` (onboarding/today_refresh/ai_segment), `mode: String` (today/routines) |
| `ai_routine_generate_success` | `surface`, `step_count: Int`, `source: String` (ai/fallback) |
| `ai_routine_generate_fail` | `surface`, `reason: String` (not_configured/empty_match/network/api/parse) |
| `tune_with_ai_send` | `text_len: Int`, `contained_url: Bool`, `is_pro: Bool` |
| `coach_note_append` | `note_count: Int` (total deduped notes) |
| `routine_save` | `source: String` (ai/classics/custom), `at_free_cap: Bool` |
| `routine_delete` | `source: String`, `age_days: Int` |
| `routine_create_blank` | — |
| `niche_exercise_adopt` | — |
| `custom_exercise_add` | — |
| `exercise_detail_open` | `is_custom: Bool`, `is_niche: Bool` |
| `image_import_start` | — |
| `image_import_result` | `result: String` (qr/ocr/empty) |
| `image_import_commit` | `recognized_count: Int`, `result: String` (qr/ocr) |
| `workout_share` | `surface: String` (workout_complete/history/calendar) |
| `routine_share` | — |
| `plate_calculator_open` | — |
| `paywall_shown` | `source: String` (new_plan_cap/save_cap/tune/optimize/charts/custom_exercise/settings) |
| `paywall_purchase_attempt` | `plan: String` (monthly/yearly/lifetime), `intro_eligible: Bool` |
| `paywall_purchase_result` | `plan`, `success: Bool` |
| `paywall_restore_result` | `restored: Bool` |

### Funnel

| event | properties |
|---|---|
| `onboarding_start` | — (fired on first render of `genderStep`) |
| `onboarding_step_advance` | `to_step: Int` (1..7), `to_step_name: String`, `direction: String` (forward/back) |
| `onboarding_complete` | `gender: String`, `goal_kind: String`, `age_band: String` (e.g. "25-34"), `weight_band: String`, `weekly_days: Int`, `focus_count: Int`, `equipment_count: Int` |
| `reached_home` | `ai_today_failed: Bool` (fired in `onDone` when `onboardingCompleted` flips) |
| `workout_start` | `source: String` (recommended/ai/free/replay/gap/classic), `step_count: Int`, `planId_hash: String` |
| `workout_complete_set` | `set_index: Int`, `kind: String` (strength/cardio/rest), `trigger: String` (manual/countdown) |
| `workout_finish` | `finish_type: String` (natural/early/auto_idle), `total_sets: Int`, `done_sets: Int`, `duration_sec: Int`, `pr_count: Int` |

### Retention

| event | properties |
|---|---|
| `workout_day_first` | fired once per distinct calendar day with a real set (drives "returned"); `distinct_day_count: Int` |
| `streak_week_extended` | `weeks: Int` |
| `review_prompt_offered` | (at `completedWorkoutCount>=3`) |
| `reminder_prompt_offered` | (at `completedWorkoutCount>=2`) |
| `reminder_opt_in` | `accepted: Bool` |

> `planId_hash` = first 8 chars of SHA256(planId) — stable per install for plan-rotation analysis, but not reversible to a title. Age/weight are **banded**, never raw, to keep events non-identifying.

---

## 2. Funnels

### Funnel A — Activation (the make-or-break path)
The single most valuable analysis; the understanding phase flagged the 7-step wizard + activation gap as HIGH risk.

1. `app_launch` (`is_fresh_install=true`)
2. `onboarding_start`
3. `onboarding_step_advance to_step=2` (goal) … through `to_step=7` (equipment) — **6 sub-stages, each an abandonment point**
4. `onboarding_complete`
5. `ai_routine_generate_success` (surface=onboarding) **OR** `ai_routine_generate_fail` (the "AI wow degraded" branch)
6. `reached_home`
7. `workout_start` (source=recommended/ai) — *the activation gap*
8. `workout_complete_set set_index=0` — **truest activation milestone** ("reached set 1")
9. `workout_finish` (finish_type=natural)

Key drop-off cuts: between each `onboarding_step_advance` (which of the 7 screens bleeds users), `onboarding_complete → workout_start` (activation gap), and `generate_fail` rate at step 5 (AI promise broken).

### Funnel B — In-workout completion
Per-session funnel, started by any `workout_start`.

1. `workout_start`
2. `workout_complete_set set_index=0` (first set)
3. `workout_complete_set set_index>=median` (mid-workout persistence)
4. `workout_finish`
   - split by `finish_type`: `natural` (real) vs `early` (user bailed via End) vs `auto_idle` (6h-idle false positive — **must be excluded** from "completed" rate)

### Funnel C — Retention / comeback
Cross-session, anchored on `anon_id` + `days_since_install`.

1. `reached_home` (D0)
2. first `workout_day_first distinct_day_count=1` (activated)
3. `workout_day_first distinct_day_count=2` (**returned — the core retention proof**)
4. `reminder_prompt_offered` → `reminder_opt_in accepted=true`
5. `streak_week_extended` (habit formed)

The "one-and-done" churn cohort = `distinct_day_count=1` with no second `workout_day_first` and `reminder_opt_in` never fired (below threshold) — surfaced directly by querying for stalls at stage 2→3.

---

## 3. Instrumentation map

Each row: event → exact call-site (file : symbol), verified against CALLSITES. `Analytics.track(...)` goes at the noted line/branch. All call-sites are `@MainActor`; `track()` is non-blocking (enqueue + return).

| event | file : symbol |
|---|---|
| `app_launch` | `Maso/MasoApp.swift` : `MasoApp.body` WindowGroup `.task` (line ~73) — guard out `MASO_SHOWCASE_SEED` |
| `app_foreground` / `app_background` | `Maso/MasoApp.swift` : `.onChange(of: scenePhase)` (active branch ~67-69; background/inactive ~60-65). **Single site** — do NOT also fire from RootView's second scenePhase handler |
| `tab_switch` | `Maso/Views/RootView.swift` : add `.onChange(of: tab)` on `TabView(selection:$tab)` (~line 228); param = new `RootTab` |
| `settings_toggle` (health) | `Maso/Views/Screens/SettingsScreen.swift` : ToggleRow "Apple Health" `Binding.set` (line 107-112), include auth result from `HealthKitService.requestAuthorization()` |
| `settings_toggle` (reminders) | `SettingsScreen.swift` : "Workout reminders" `Binding.set` (line 128-135), include `WorkoutReminderScheduler.requestAuthorization()` result |
| `settings_toggle` (exercise_sync/units/week_start) | `SettingsScreen.swift` : add `.onChange` on `globalExerciseParamSyncEnabled` (line 145), `weightUnit` (81), `weekStartDay` (91). **Never** instrument `debugProUnlock` (line 224, `#if DEBUG`) |
| `onboarding_start` | `Maso/Views/Onboarding/OnboardingScreen.swift` : `.onAppear` of the root body when `step == .gender` (one-shot `@State` guard) |
| `onboarding_step_advance` | `OnboardingScreen.swift` : `advance(to:)` (line 345) — single forward choke point; `goBack()` (line 350) for `direction=back` |
| `onboarding_complete` | `OnboardingScreen.swift` : `confirm()` (line 382) — read the 7 prefs being written; **band** age/weight before track |
| `reached_home` | `RootView.swift` : `onDone` closure (line 125-128) where `onboardingCompleted=true` |
| `ai_routine_generate_start` | `Maso/Data/AIWorkoutService.swift` : `generateToday` `state=.generating` (line 69); `generateRoutines` (line 103) |
| `ai_routine_generate_success` | `AIWorkoutService.swift` : `generateToday` `.success` (line 79); `generateRoutines` (line 115). Surface passed by caller (`DataStore.generateFirstPlanViaAI`/`refreshAIWorkoutIfNeeded`/`generateAIRoutines`) |
| `ai_routine_generate_fail` | `AIWorkoutService.swift` : `.failure` branches (66/75/82/85; routines 99/111/117/120); `reason` from `AIError` |
| `tune_with_ai_send` | `Maso/Views/Screens/PlansScreen.swift` : `sendRefine()` (line 208), after non-empty guard; use `containsURL` helper (line 220) |
| `coach_note_append` | `Maso/Data/DataStore.swift` : `appendCoachNote(_:)` only on the non-skipped mutate path (line 134) |
| `routine_save` | `DataStore.swift` : `savePlan(_:)` (line 906) — track on both `true` and the `false`/at-cap return |
| `routine_delete` | `DataStore.swift` : `deletePlan(_:)` (line 949) |
| `routine_create_blank` | `DataStore.swift` : `createBlankPlan` (line 849) |
| `niche_exercise_adopt` | `DataStore.swift` : `adoptNicheExercise(_:)` (line 88), after double-adopt guard (89) |
| `custom_exercise_add` | `DataStore.swift` : `addCustomExercise` (line 102) |
| `image_import_start` | `Maso/Views/Screens/TodayScreen.swift` : `PhotoImportModifier` `.onChange(of: pickedImage)` (line 535) |
| `image_import_result` | `TodayScreen.swift` : result switch (lines 543-547) |
| `image_import_commit` | `TodayScreen.swift` : `ImportedPlanSheet.onAdd` (552) + `RoutineReviewSheet.onCommit` (564) |
| `workout_start` | `Maso/State/TrainingSession.swift` : `TrainingSessionStore.start(planId:plan:segments:)` (line 96). `source` passed by `RootView.startTrainingNow` (738). **Do not** fire from `restorePersistedSession` (235) |
| `workout_complete_set` | `TrainingSession.swift` : `advance(record:)` at the `completedSets.insert` (line 401); `trigger` via `curWasStrength`/`seg.kind` |
| `workout_finish` | `TrainingSession.swift` : `advance` completed branch (407-416) `finish_type=natural`; `finishEarly()` (476) `early`; `checkAutoComplete()` (184) `auto_idle` |
| `workout_share` | `Maso/Views/Components/Share/ShareImageButton.swift` : inside the share-completion handler (covers all surfaces once); `surface` param from caller |
| `routine_share` | `PlansScreen.swift` : `sharePlan` (line 1053) |
| `plate_calculator_open` | `PlanPlayerScreen.swift` : Weight-metric tap → `plateCalcOpen` |
| `paywall_shown` | `Maso/Views/Screens/PaywallScreen.swift` : `.task` (line 88) — single impression site; `source` passed in by presenter |
| `paywall_purchase_attempt` / `_result` | `PaywallScreen.swift` : `handlePurchase()` — before `await subs.purchase` (282/286), and on the ok bool (288) |
| `paywall_restore_result` | `PaywallScreen.swift` : `handleRestore()` ok determination (line 302) |
| `workout_day_first` | `DataStore.swift` : in `recordSet` after insert, when `startOfDay(set.date)` is newly added to the distinct-day set (compute from `completedWorkoutCount` line 773 transition 0→1, 1→2…) |
| `review_prompt_offered` | `DataStore.swift` : `shouldOfferReview()` true branch (line 780-786) |
| `reminder_prompt_offered` | `DataStore.swift` : `shouldOfferReminderPrompt()` true branch (line 790-797) |
| `reminder_opt_in` | `SettingsScreen.swift` reminders Binding.set (shares site with `settings_toggle`; emit both or just the toggle with a `prompt_origin` flag) |

---

## 4. Architecture — `Analytics` service

A small, dependency-free service mirroring `AIWorkoutService` (static config + `URLSession`) and `FeedbackStore` (offline outbox). Buffer lives in its own JSON file under `Documents/` (not the main snapshot, to avoid bloating `maso-data.json` writes). Sinks are pluggable so backend choice (section 5) is swappable without touching call-sites.

### Flag + opt-out

```swift
// Maso/Models/Settings.swift — MasoFlags (line 6-8)
enum MasoFlags {
    static let iapEnabled = true
    static let analyticsEnabled = true   // compile-time kill switch
}

// struct UserSettings (~line 81) — co-located, rides the existing snapshot
var anonymousId: String = UUID().uuidString   // per-install, resets on delete+reinstall
var analyticsOptOut: Bool = false             // user-facing toggle, defaults opt-IN
```

### Core types

```swift
// Maso/Data/Analytics/AnalyticsEvent.swift
struct AnalyticsEvent: Codable, Sendable {
    let name: String
    let ts: Date                       // iso8601 on encode
    let props: [String: AnyCodableScalar]   // String/Int/Double/Bool only — compile-time enforced
}

// Maso/Data/Analytics/AnalyticsSink.swift
protocol AnalyticsSink: Sendable {
    /// Returns true if the batch was accepted (so the buffer can drop it).
    func send(_ batch: [AnalyticsEvent], envelope: AnalyticsEnvelope) async -> Bool
}

struct AnalyticsEnvelope: Codable, Sendable {   // shared, non-PII
    let anonId: String
    let appVersion: String      // FeedbackStore.appVersionString
    let osVersion: String       // FeedbackStore.osVersionString
    let language: String        // LanguageManager
}
```

### Service (singleton, mirrors AIWorkoutService.shared + FeedbackStore outbox)

```swift
// Maso/Data/Analytics/Analytics.swift
@MainActor @Observable final class Analytics {
    static let shared = Analytics()

    private var buffer: [AnalyticsEvent] = []       // loaded from Documents/maso-analytics.json
    private var lastFlushAt: Date?
    private let flushThreshold = 20                  // events
    private let flushInterval: TimeInterval = 60*30  // or on background
    private var sink: AnalyticsSink = NoOpSink()     // swapped at boot per section 5

    // — the only API call-sites use —
    nonisolated func track(_ name: String, _ props: [String: AnyCodableScalar] = [:]) {
        // hop to main, append to buffer; cheap & non-blocking
        Task { @MainActor in self.enqueue(name, props) }
    }

    private func enqueue(_ name: String, _ props: ...) {
        #if DEBUG
        guard /* opt-in to send in debug */ false else { print("📊 \\(name) \\(props)"); return }
        #endif
        guard MasoFlags.analyticsEnabled,
              !data.settings.analyticsOptOut,
              ProcessInfo.processInfo.environment["MASO_SHOWCASE"] == nil
        else { return }
        buffer.append(AnalyticsEvent(name: name, ts: Date(), props: props))
        persist()                                    // atomic write, like PersistenceController.save
        if buffer.count >= flushThreshold { Task { await flush() } }
    }

    func configure(sink: AnalyticsSink) { self.sink = sink }   // called once at boot

    func flush() async {                             // FeedbackStore digest pattern
        guard !buffer.isEmpty else { return }
        let batch = buffer
        let ok = await sink.send(batch, envelope: makeEnvelope())
        if ok { buffer.removeFirst(batch.count); lastFlushAt = Date(); persist() }
        // failure → keep buffer, retry next launch/foreground/threshold
    }
}
```

### Wiring
- **Boot:** in `MasoApp.body .task` (line ~73) — mint `anonymousId` if empty, `Analytics.shared.configure(sink:)`, then `track("app_launch", ...)`.
- **Flush triggers:** `flush()` on `app_background` (scenePhase inactive/background, alongside `flushSave`) and opportunistically when threshold hit; cap batch size and drop oldest beyond e.g. 1,000 buffered to bound disk.
- **Threading:** `track` is `nonisolated` and hops to `@MainActor` — call-sites stay synchronous and never block UI; network send is `async` off the main actor inside the sink.
- **No PII guarantee:** `props` is `[String: AnyCodableScalar]` (scalars only) — there is no code path to attach a name/title/note. Age & weight are banded at the `onboarding_complete` call-site; plan ids are hashed.

---

## 5. Backend options

| Option | What ships | App Store privacy-label impact | Effort | Cross-user aggregate? |
|---|---|---|---|---|
| **(a) On-device only** + in-app Insights/debug screen | `Analytics` buffer + a read-only SwiftUI screen reading the local JSON; sink = `NoOpSink` (never sends) | **Zero.** `NSPrivacyTracking` stays false, `NSPrivacyCollectedDataTypes` stays empty — nothing leaves the device. No policy change. | Low (no backend, no dashboard infra) | **No** — you only ever see your own device, useless for funnel/churn across users |
| **(b) Cloudflare Worker `/analytics` route** → KV or D1 | New route on `maso-ai.wuyumo.workers.dev`, reuse `X-Maso-Client-Token`; `WorkerSink` POSTs batched envelope+events; D1 table `events(anon_id, name, ts, props_json)`; you write SQL/a tiny query page | Add **one** `NSPrivacyCollectedDataTypes` entry: *Product Interaction / Other Usage Data*, **Not Linked to Identity, Not Used for Tracking**. `NSPrivacyTracking` stays false. Add an analytics clause to `privacy-policy.html`. | Medium (Worker route + D1 schema + you build queries/dashboard) | **Yes**, full control, IP visible only to your own Worker |
| **(c) TelemetryDeck** (privacy-first vendor) | Add SPM package, `TelemetryDeckSink`; signals mapped from `track()` | Same one `NSPrivacyCollectedDataTypes` entry (*Product Interaction*, Not Linked, No Tracking). TelemetryDeck is explicitly **no IDFA / no ATT / "Data Not Linked to You"**; add their vendor mention to the policy. | Low (SDK + instant hosted dashboards/funnels) | **Yes**, hosted dashboards out of the box; less control, third party in the path |

### Recommendation (solo, privacy-forward)

**Primary: (c) TelemetryDeck**, behind the `AnalyticsSink` protocol — it gives a solo shipper instant funnels/retention dashboards with the smallest privacy-label footprint and zero backend maintenance, and it matches the existing privacy posture (no ATT/IDFA, Data Not Linked to You). The same single `NSPrivacyCollectedDataTypes` entry covers it whether you pick (b) or (c), so the App Store cost is identical to building your own.

**Phased path:**
1. **Phase 0 (this PR):** ship the backend-agnostic core with `NoOpSink` + the local Insights debug screen (= option a). No privacy-label change. You validate event firing on your own device immediately, App-Review-safe.
2. **Phase 1:** drop in `TelemetryDeckSink`, add the one `NSPrivacyCollectedDataTypes` entry + privacy-policy clause, ship the user opt-out toggle. Live cross-user funnels (A/B/C) with no dashboard work.
3. **Phase 2 (optional, only if you outgrow it):** swap in `WorkerSink` → D1 (option b) for full ownership and custom SQL, reusing the exact same call-sites and protocol — no instrumentation changes.

---

## 6. Build plan (ordered)

**Core (backend-agnostic) first:**

1. **Edit** `Maso/Models/Settings.swift` — add `MasoFlags.analyticsEnabled`; add `UserSettings.anonymousId` (default `UUID().uuidString`) and `analyticsOptOut: Bool = false`. (Backward-safe: tolerant decode in `PersistenceController.load`.)
2. **Edit** `Maso/Data/DataStore.swift` — in `bootstrap`/`freshInstall`, mint `anonymousId` if empty and `save()`; expose a read accessor for the service.
3. **Add** `Maso/Data/Analytics/AnalyticsEvent.swift` — `AnalyticsEvent`, `AnyCodableScalar`, `AnalyticsEnvelope`.
4. **Add** `Maso/Data/Analytics/AnalyticsSink.swift` — `AnalyticsSink` protocol + `NoOpSink`.
5. **Add** `Maso/Data/Analytics/Analytics.swift` — the `@Observable` singleton: buffer, atomic JSON persist to `Documents/maso-analytics.json` (copy `PersistenceController` write-atomic pattern), `track`, `flush`, MasoFlags + opt-out + showcase gating, `#if DEBUG` print path.
6. **Add** `Maso/Data/Analytics/AnalyticsBuffer.swift` (or fold into 5) — file-backed outbox modeled on `FeedbackStore` (load/persist/trim).
7. **Edit** `project.yml` then `xcodegen generate` — register the new `Analytics/` files (per the xcodegen-managed convention).

**Instrument the call-sites (per section 3), in funnel-priority order:**

8. **Edit** `Maso/MasoApp.swift` — boot config + `configure(sink: NoOpSink())` + `app_launch`; foreground/background + `flush()`.
9. **Edit** `Maso/Views/Onboarding/OnboardingScreen.swift` — `onboarding_start`, `onboarding_step_advance` (`advance`/`goBack`), `onboarding_complete` (banded). *(Funnel A)*
10. **Edit** `Maso/Views/RootView.swift` — `reached_home` (onDone), `tab_switch`.
11. **Edit** `Maso/State/TrainingSession.swift` — `workout_start`, `workout_complete_set`, `workout_finish` (3 finish types). *(Funnel B)*
12. **Edit** `Maso/Data/DataStore.swift` — `workout_day_first`, `review_prompt_offered`, `reminder_prompt_offered`, `routine_save/delete/create_blank`, `niche_exercise_adopt`, `custom_exercise_add`, `coach_note_append`. *(Funnel C + feature usage)*
13. **Edit** `Maso/Data/AIWorkoutService.swift` — `ai_routine_generate_start/success/fail` (with `surface` threaded from callers).
14. **Edit** `Maso/Views/Screens/PlansScreen.swift` — `tune_with_ai_send`, `routine_share`.
15. **Edit** `Maso/Views/Screens/TodayScreen.swift` — `image_import_start/result/commit`.
16. **Edit** `Maso/Views/Screens/SettingsScreen.swift` — `settings_toggle` (health/reminders/exercise_sync/units/week_start) + `reminder_opt_in`.
17. **Edit** `Maso/Views/Screens/PaywallScreen.swift` — `paywall_shown` + purchase/restore events.
18. **Edit** `Maso/Views/Components/Share/ShareImageButton.swift` + `PlanPlayerScreen.swift` — `workout_share`, `plate_calculator_open`.

**Sink + disclosure (Phase 1):**

19. **Add** `Maso/Data/Analytics/TelemetryDeckSink.swift` (or `WorkerSink.swift`) + SPM package in `project.yml`; switch `MasoApp` boot to `configure(sink:)` with it.
20. **Add** opt-out row to `Maso/Views/Screens/SettingsScreen.swift` ("Share anonymous usage data", bound to `analyticsOptOut` inverted).
21. **Edit** `Maso/PrivacyInfo.xcprivacy` — add one `NSPrivacyCollectedDataTypes` entry (Product Interaction, Not Linked, No Tracking).
22. **Edit** `docs/privacy-policy.md` (→ `privacy-policy.html`) — add the anonymous-usage-analytics clause; update the App Store privacy questionnaire.
23. **Optional** `Maso/Views/Screens/AnalyticsInspectorScreen.swift` — `#if DEBUG` local buffer viewer (delivers option (a) value for self-QA).

**Verify:** run the `verify-app` skill (showcase mode must emit zero events — confirms the `MASO_SHOWCASE` gate), then `./scripts/install_iphone.sh`.",
    "screens": {
      "screens": [
        {
          "name": "Onboarding (first-run wizard)",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Onboarding/OnboardingScreen.swift",
          "whatUserDoes": "7-step one-question-per-screen wizard: pick gender, training goal, age (wheel), body weight (wheel, defaults to gender average), days/week (wheel, default 3), focus muscles (multi-select), available equipment (multi-select). Option-type steps (gender) auto-advance; wheel/multi steps use Next/Back. Final 'Build My Routine' triggers an AIGeneratingView progress overlay (4-step checklist bound to the real first-plan LLM call) then lands on Today.",
          "entryPoints": "Shown by RootView whenever data.settings.onboardingCompleted == false (fresh install / cleared local data). onDone closure flips onboardingCompleted + flushSave to enter the main TabView. Also receives maso:// import deep links during onboarding (stashes importedPlan)."
        },
        {
          "name": "Today tab",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/TodayScreen.swift",
          "whatUserDoes": "Landing tab (RootView default = .today). Renders in mode .trainToday: a MuscleStatusOverviewCard (fatigue/recovery map + 'days since last session' tip + optional 'Train the gaps' one-tap catch-up workout), an emphasized 'Today's Workout' WorkoutCard (start it, or tap to open detail), and a 'Free workout' entry card (play button → exercise picker). Shows an inline 'AI plan unavailable — Retry' chip when LLM generation fails. Tapping a card opens PlanDetailSheet; gear opens Settings.",
          "entryPoints": "First bottom tab ('Today', figure.strengthtraining icon). onStart→startTraining (Player), onFreeWorkout→ExercisePickerSheet, onNewPlan→blank-plan PlanDetailSheet, onOpenSettings→Settings sheet, onGoToDiscover→Plans tab. Same TodayScreen component is reused embedded as the Plans/Saved subpage via mode .myPlans."
        },
        {
          "name": "Plans tab — Saved segment",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift",
          "whatUserDoes": "Default segment of the Plans tab. Lists the user's saved routines as WorkoutCards (tap → PlanDetailSheet to edit/start; long-press → Edit/Delete with confirm). Shows a RoutineOptimizeCard ('Optimize with AI', Pro-gated) when enough data exists. Empty state offers 'Generate with AI' / 'Browse Classics' buttons. Implemented by embedding TodayScreen(mode:.myPlans).",
          "entryPoints": "Second bottom tab ('Plans', square.stack icon) → PlansScreen segmented Picker default .saved. Toolbar '+' menu = Create my own (blank PlanDetailSheet, paywall-gated past FreeLimit.maxPlans) / Import from photo (PhotoPicker → OCR/QR). Gear → Settings."
        },
        {
          "name": "Plans tab — AI Routines segment",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift",
          "whatUserDoes": "Generates a batch of LLM workout routines from the user's Training Preferences. User taps a Training Preferences card (PlanRationaleCard) to open the TrainingPreferencesSheet and edit days/goal/exercise count/sets/equipment/focus, then 'Generate routines'. A conversational 'Tune-with-AI' composer (Pro-gated) lets the user type plain-language changes ('bad shoulder, no overhead') that become a focusNote + persist to coach memory. Result cards (✨AI badge) can be previewed and saved via '+ Add to my plans'. Shows fallback chip + Retry when LLM is unreachable.",
          "entryPoints": "Plans tab segmented Picker → 'AI Routines'. Auto-generates a batch on first open. Also reached from Today/Saved empty-state 'Generate with AI', and from RoutineOptimizeCard 'Optimize with AI' (handleOptimize switches to this segment with a focusNote)."
        },
        {
          "name": "Plans tab — Classics segment",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift",
          "whatUserDoes": "Browse curated classic templates (5x5, PPL, 5/3/1, etc.) from CommunityPlans. Filter by Level and Days/week via two dropdown chips. Each card (🎗Classics badge) previews in PlanDetailSheet and can be saved to My Routines via star/Save (paywall when at free cap).",
          "entryPoints": "Plans tab segmented Picker → 'Classics'. Also reached from Today/Saved empty-state 'Browse Classics' (onBrowseClassics switches segment)."
        },
        {
          "name": "Exercises tab (Exercise Library)",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/ExerciseLibraryBrowser.swift",
          "whatUserDoes": "Browse the ~900-exercise library grouped by muscle region. Search box + Muscle/Equipment/Movement filter chips; a contacts-style right-side scrubber rail with per-region muscle-icon dots jumps to and follows sections. Tapping a row opens ExerciseDetailSheet (instructions, target muscle map, category, demo). Variant groups collapse under a base exercise. The '+' adds an exercise via AddExerciseChoiceSheet → either CustomExerciseFormSheet (Create your own, Pro-gated, name+photo+metadata) or NicheLibraryBrowseSheet (Browse rare → adopt niche moves). Custom moves can be deleted (blocked if referenced).",
          "entryPoints": "Third bottom tab ('Exercises', dumbbell icon), rendered embedded in RootView's NavigationStack with screenHeader('Exercises'). Toolbar '+' sets libraryAddRequested → opens add-choice sheet; gear → Settings. Also reachable as a LibraryEntryRow concept and via Settings/Plans deep links (router .library)."
        },
        {
          "name": "History tab — Stats segment",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/HistoryScreen.swift",
          "whatUserDoes": "Top: 3 metric columns (Days / Week streak / Sets — week or month scope) + an InlineWorkoutCalendar (7-day strip that taps/chevron-expands to a full month with colored muscle dots per day). Stats segment shows ProgressChartsView (weekly volume + 1RM, some Pro-gated → paywall) and a TrainingActivityHeatmap, with empty/encouragement states. A ProBanner (Free users) opens the paywall.",
          "entryPoints": "Fourth bottom tab ('History', clock icon) → segmented Picker default .stats. Top-right Share button (UnifiedShareCard) and gear (Settings)."
        },
        {
          "name": "History tab — Workouts segment",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/HistoryScreen.swift",
          "whatUserDoes": "Past sessions grouped by week (This week / Last week / date range) as SessionCards showing date, plan name, exercises·sets, PR trophy count, muscle map, and optional session photo. Tap → SessionDetailSheet (per-exercise best set, add/replace/remove photo, delete an exercise, Repeat Workout, share). Long-press → Delete workout (removes all that day's SetRecords/PRs, confirm). 'Repeat' replays the session (original or synthesized plan).",
          "entryPoints": "History tab segmented Picker → 'Workouts'. SessionDetailSheet → onReplay routes to RootView.startTraining (Player)."
        },
        {
          "name": "Workout Player (full-screen)",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlanPlayerScreen.swift",
          "whatUserDoes": "Apple-Music-style full-screen training driver. Exercise stage shows name, last-time summary, Sets/Reps/Weight/Time metrics; primary 42pt button = complete set / play-pause / skip rest; back button = previous segment; stop = end. Rest stage shows a shrinking countdown ring + Up Next. A drag-to-resize inline playlist lets the user jump segments, edit a step (EditCurrentStepSheet: sets/reps/weight/duration/per-set, with global param sync), replace an exercise (ExercisePickerSheet), add an exercise ('+ Add exercise' footer), or swipe-delete a step. Weight metric → PlateCalculatorSheet. Drag down to minimize to the MiniBar (session keeps running). On finish: optional SaveChangesConfirmView (if routine params were edited), then auto-opens a ShareCustomizeSheet/WorkoutDetailShareCard; free workouts prompt 'Save as plan'; milestone prompts for reminders / App Store review.",
          "entryPoints": "RootView .fullScreenCover(playerPresented). Reached from every Start/Repeat/Free-workout/gap-workout/showcase path via startTraining→startTrainingNow. Minimized via TrainingMiniBar.onTap (RootView miniBarContent) which sets playerPresented=true. Replacing an in-progress workout shows a 'Replace?' alert first."
        },
        {
          "name": "Settings sheet",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/SettingsScreen.swift",
          "whatUserDoes": "Scrollable settings: Maso Pro banner/status (hidden when MasoFlags.iapEnabled=false); Profile (gender/age/body weight); Training Preferences (shared TrainingSettingsSection); Units (weight kg/lb, distance km/mi, week-start day); Apple Health toggle (requests HealthKit auth, writes completed workouts); Reminders toggle (local recovery nudges); Exercise data toggle (global param sync across routines); Language picker; legal/About links (Privacy, Terms, Health & Safety detail, Version, Pexels credit); DEBUG-only 'Unlock Pro' toggle. Done dismisses.",
          "entryPoints": "Gear button on Today / Exercises / Plans / History toolbars → RootView settingsPresented sheet (NavigationStack{SettingsScreen}). Opens nested sheets: PaywallScreen, LanguagePickerSheet; NavigationLink → HealthSafetyDetail."
        },
        {
          "name": "Paywall (Maso Pro)",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PaywallScreen.swift",
          "whatUserDoes": "StoreKit 2 paywall: hero + 6-item value list + 3 plan cards (Monthly / Yearly default+POPULAR / Lifetime) with locale-aware pricing and intro-trial eligibility, a CTA (Start free trial / Buy lifetime), and Restore Purchases + Terms + Privacy links. Purchase/restore flow with confirm + error alerts.",
          "entryPoints": "Presented as a sheet from many spots: RootView (hitting FreeLimit.maxPlans on new plan), PlansScreen (save past free cap, Tune-with-AI / Optimize when not Pro), HistoryScreen ProBanner + locked charts, ExerciseLibraryBrowser (custom exercise = Pro), SettingsScreen 'Try Maso Pro' banner. Currently effectively dormant (iapEnabled=false → everything unlocked, Pro section hidden)."
        },
        {
          "name": "PlanDetailSheet (view/edit/new routine)",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift",
          "whatUserDoes": "Edit a routine: rename, see muscle map, reorder/swipe-edit/swipe-delete steps, tap a step → EditStepView (sets/reps/weight/rest), tap step image → ExerciseDetailSheet, '+ Add exercise' (multi-select picker), replace an exercise, Start workout (big CTA), Share (RoutineShareCard image + App Store QR via system share sheet), or Delete plan. Discover-preview variant shows '★ Add to my plans / Saved' instead of Start.",
          "entryPoints": "Tapping any WorkoutCard/PlanRow on Today/Saved/AI/Classics; RootView '+' new blank plan (sheet item newPlanForEdit); RootView showcase plan_detail. Shared by both owned-plan editing and Discover preview (onAddToSaved param toggles mode)."
        },
        {
          "name": "ExercisePickerSheet",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift",
          "whatUserDoes": "Pick exercises with search + Muscle/Equipment/Movement filters and variant-group collapse. Single-select (tap → detail → add, or directPick for replace) or multi-select (free workout / add-to-plan with a bottom 'Start workout'/'Add (N)' CTA). Can switch to niche/rare mode and create a custom exercise from an empty search.",
          "entryPoints": "RootView Free-workout sheet (multiSelect → startFreeWorkout); PlanDetailSheet add (multiSelect) + replace; PlanPlayer add-step + replace-exercise."
        },
        {
          "name": "ImportedPlanSheet / RoutineReviewSheet (image & deep-link import)",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/ImportedPlanSheet.swift",
          "whatUserDoes": "ImportedPlanSheet previews a routine decoded from a maso:// share-card QR deep link and adds it to My Routines. RoutineReviewSheet lets the user confirm/correct exercises recognized via OCR from a third-party screenshot before saving.",
          "entryPoints": "RootView .onOpenURL(maso://import) → importedPlan sheet (invalid → 'Invalid routine link' alert). RoutineImportFlow modifier on TodayScreen/PlansScreen: '+ → Import from photo' → PhotoPicker → RoutineImageImporter → deepLink (ImportedPlanSheet) / recognized (RoutineReviewSheet) / empty (failure alert)."
        },
        {
          "name": "CommunityScreen",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/CommunityScreen.swift",
          "whatUserDoes": "Browse community/curated plans ('See what others train') and add them to My Routines.",
          "entryPoints": "TodayScreen presents it via communityPresented sheet, but no live UI control sets that flag in the shipped Plans/Today IA (Classics/community content now lives in the Plans 'Classics' segment), so this sheet is largely vestigial in the current navigation."
        },
        {
          "name": "LanguagePickerSheet",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/LanguagePickerSheet.swift",
          "whatUserDoes": "Choose the app language (System / English / 简体中文) via LanguageManager.",
          "entryPoints": "Settings → Language → 'App Language' row → showLanguagePicker sheet."
        },
        {
          "name": "PlateCalculatorSheet",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlateCalculatorSheet.swift",
          "whatUserDoes": "Given a target weight, shows the barbell plate breakdown per side.",
          "entryPoints": "Player exercise stage: tapping the Weight metric (when weight>0) opens plateCalcOpen sheet."
        }
      ],
      "notableFeatures": [
        "Information architecture: RootView drives an iOS TabView with 4 visible bottom tabs (Today / Plans / Exercises / History). RootTab enum also declares a .library case but the Exercises tab uses .library tag while .plans hosts the segmented Plans tab; router maps Settings/deep-link requests for .library/.plans onto the Plans tab + trainPage. UI tab order is set manually, not by enum declaration order.",
        "Segmented sub-navigation: Plans tab = Saved | AI Routines | Classics (PlansScreen.RoutinesTab); History tab = Stats | Workouts (HistoryScreen.HistoryTab). These segments are the main analytics sub-surfaces.",
        "Workout Player is a fullScreenCover, not a tab — central feature with exercise/rest stages, resizable inline playlist, per-step edit/replace/add/delete, plate calculator, and a multi-step completion funnel (SaveChangesConfirm → auto Share → free-workout Save-as-plan → reminder/review prompts).",
        "TrainingMiniBar: when a session is active and the player is minimized, a MiniBar is injected via .safeAreaInset on every tab (RootView.miniBarContent) showing the current segment/countdown with tap-to-reopen, advance, and play/pause; a 1Hz SessionTickerView in RootView drives it app-wide.",
        "Paywall / Pro gating is present and wired throughout (new-plan cap via FreeLimit.maxPlans, save-to-saved cap, AI tune/optimize, locked charts, custom exercises) but is currently dormant: MasoFlags.iapEnabled=false makes isPro always true, hides the Settings Pro section, and disables IAP for the free launch. There is also a DEBUG-only 'Unlock Pro' toggle.",
        "AI generation is real (Path B): server-side Cloudflare Worker → DeepSeek LLM. Surfaces include onboarding first-plan generation (AIGeneratingView), the AI Routines segment (generateAIRoutines), Today's recommended fallback (aiTodayFailed Retry chip), and the Pro conversational Tune-with-AI composer that persists to coaching memory. Each surface has explicit fallback-to-local-template + Retry handling and an ✨AI source badge.",
        "Share/export family: a unified renderer (ShareImageRenderer/ShareImageButton/ShareCustomizeSheet) produces share-card images — UnifiedShareCard (History overview / session), WorkoutDetailShareCard (post-workout, auto-opened on completion), RoutineShareCard (plan), each embedding a maso:// QR or App Store QR. Round-trips with the image-import (QR deep link + OCR) path.",
        "Image import: '+ → Import from photo' on Plans/Today runs RoutineImageImporter on a picked photo — QR share-card → ImportedPlanSheet (lossless), or OCR of a third-party screenshot → RoutineReviewSheet (confidence-graded confirm), or failure alert. Also maso:// deep links via onOpenURL.",
        "Exercise library is a top-level tab (~900 exercises) with muscle-region grouping, a contacts-style scrubber rail, variant grouping, custom-exercise creation (Pro), and a 'rare/niche' adopt flow (NicheLibraryBrowseSheet). The same picker/search/filter logic is shared between the library browser and ExercisePickerSheet.",
        "Apple Watch + HealthKit cross-cut the app: an opt-in Settings toggle requests HealthKit auth and writes completed workouts (RootView.catchUpHealthKitSync on completion/foreground/scene-phase). The phone is source-of-truth and skips writing a day's session when the Watch ran its own HKWorkoutSession (anti double-count via WatchSyncManager).",
        "Local-notification features: rest/countdown end notifications scheduled when backgrounding mid-session (RestNotificationScheduler), and opt-in recovery 'workout reminders' (WorkoutReminderScheduler) offered after the 2nd workout and toggleable in Settings.",
        "Showcase/screenshot mode: RootView.applyShowcaseModeIfNeeded reads the MASO_SHOWCASE env var to deep-land on library/routines/plan_detail/history/settings/free_workout/player/rest for the App Store screenshot pipeline — useful as deterministic entry points for analytics/QA. No effect for real users.",
        "Dead/legacy screens present in Maso/Views/Screens but NOT wired into navigation (referenced only by their own #Preview): QuickWorkoutScreen.swift (superseded by the multi-select ExercisePickerSheet free-workout flow), WorkoutCalendarScreen.swift (superseded by InlineWorkoutCalendar in History), and FeedbackSheet.swift (feedback is sent automatically via FeedbackStore digest on launch/foreground, not shown as a screen). CommunityScreen is reachable in code but has no live UI trigger in the current IA."
      ]
    },
    "funnel": {
      "funnelStages": [
        {
          "stage": "Install & cold start",
          "represents": "App opened for the first time with no on-disk save. The store boots into the empty/fresh state (empty plans+sets) and routes the whole screen to onboarding.",
          "codeLocation": "DataStore freshInstall path (DataStore.swift ~line 191-198: UserSettings() with onboardingCompleted=false, gender/age/weight=nil). RootView.body gate `if !data.settings.onboardingCompleted { OnboardingScreen {...} }` (RootView.swift:122-138).",
          "dropoffRisk": "Low-to-medium. Standard cold-start abandonment — but there is NO value shown before the questionnaire (no preview, no skip). A user who opened out of idle curiosity can bounce on the very first screen (genderStep) before answering anything."
        },
        {
          "stage": "Onboarding step machine (7 questions)",
          "represents": "User answers the 7-step wizard: gender -> goal -> age -> weight -> days/week -> focus muscles -> equipment. Each answered step advances the Step enum and the 7-segment progress bar.",
          "codeLocation": "OnboardingScreen.swift Step enum `gender=1, goal, age, weight, days, focus, equipment` (line 15-18); `@State private var step` (line 20); per-step advance via `advance(to:)`/`selectGender`/`selectGoal` (line 345-371) and `primaryAction` Next buttons (line 331-341). Progress = capsules filled where `s.rawValue <= step.rawValue` (line 77-82).",
          "dropoffRisk": "HIGH — this is the deepest unmonitored funnel. 7 sequential required screens before ANY payoff. Three interaction models (auto-advance tap, wheel+Next, multi-select+Next) and a wheel picker with a known finicky scrollPosition init (line 416-421, 458-464). Each step is an independent abandonment opportunity; no progress is persisted until `confirm()`, so quitting mid-wizard loses everything and restarts at step 1 next launch."
        },
        {
          "stage": "Confirm & first AI plan generation",
          "represents": "User taps 'Build My Routine' on the equipment step. Preferences are persisted, the AI-generating overlay shows, and the first plan is generated: local starter routines seeded immediately, then a real LLM call for today's recommendation.",
          "codeLocation": "OnboardingScreen.confirm() writes settings + `data.flushSave()` then `generating=true` and `Task { await data.generateFirstPlanViaAI() }` (line 382-403). DataStore.generateFirstPlanViaAI() (DataStore.swift:1096-1109): `seedStarterRoutines()` (line 883, guards plans.isEmpty, takes prefix(2) of tunedRecommendedPlans) then `AIWorkoutService.shared.generateToday(...)` -> success sets `aiTodayPlan`, failure sets `aiTodayFailed=true`. AIGeneratingView ties its 'Building' step to the real call via `isReady`/`finishIfReady` with 0.8s min dwell + 9s safety fallback (OnboardingScreen.swift:573-608).",
          "dropoffRisk": "Medium. The overlay is a ~4s perceived wait gated on a network LLM call; the 9s safety timeout (line 588) means a slow/failed network still lands but on fallback templates (aiTodayFailed). CLAUDE.md notes a latent xcconfig `//`-comment bug that previously broke the proxy URL entirely. Risk: killing the app during the ~4s transition re-shows onboarding (onboardingCompleted only set in onDone). The AI 'wow' moment silently degrades to local templates on any proxy failure."
        },
        {
          "stage": "Land on Today / first session start",
          "represents": "Onboarding overlay completes, onboardingCompleted is set, app switches to the TabView landing on Today. User taps start on the recommended workout (or center-tab quick-start / free workout) which expands the plan into segments and presents the full-screen player.",
          "codeLocation": "onDone closure sets `data.settings.onboardingCompleted = true; data.flushSave()` (RootView.swift:125-128). Start path: TodayScreen onStart -> RootView.startTraining(_:) (RootView.swift:569-579) -> startTrainingNow (line 738-747): `expandPlan(...)`, `session.start(planId:plan:segments:)`, `playerPresented=true`. TrainingSessionStore.start() creates the Session and Live Activity (TrainingSession.swift:96-121). Source plan = `data.todayRecommendedPlan ?? data.aiTodayPlan` (RootView.swift:525).",
          "dropoffRisk": "Medium-high — the classic activation gap. There is a gap between 'plan exists' and 'user actually presses play.' If the AI call failed (aiTodayFailed) Today shows an 'AI unavailable' chip, undercutting the promised value right at activation. An empty/zero-step plan is guarded (`!plan.steps.isEmpty`, line 526), so a bad plan silently does nothing on tap — a dead-end with no feedback."
        },
        {
          "stage": "Complete sets (in-workout progress)",
          "represents": "User works through segments: tapping the primary button to complete a strength set, or letting a cardio/rest countdown expire. Each real completion records a SetRecord and marks the (stepId,setN) done.",
          "codeLocation": "TrainingSession.advance(record:) (TrainingSession.swift:361-440): builds a SetRecord for exercise segments not already in completedSets, calls `record?(rec)`, inserts into `completedSets`, then `nextLandingIndex(...)` to move on. Auto-advance on countdown via SessionTickerView (line 1126-1141) calling `store.advance { rec in data.recordSet(rec) }`. Persistence is per-mutation via `session didSet -> persistActiveSession()` (line 44-48).",
          "dropoffRisk": "Medium. Mid-workout abandonment is normal, but two structural risks: (1) the 6h-idle auto-complete (`autoCompleteAfter`, line 94; `checkAutoComplete`, line 184-195) silently marks a forgotten session 'completed' rather than abandoned, polluting the completion signal; (2) session is restorable after an app kill (`restorePersistedSession`, line 235-304), which is good for retention but means a 'partial' session can resurrect. First set completed is the truest activation milestone — and nothing explicitly tracks 'reached set 1.'"
        },
        {
          "stage": "Finish & save/share workout",
          "represents": "Last undone segment is consumed -> session.completed flips true. Player shows an optional 'save changes to routine' confirm (if params were edited), then the CompletedView with duration, set count, PR count, muscles, and a share card. User taps Close to end.",
          "codeLocation": "Completion set in advance() when `nextLandingIndex` returns nil: `s.completed=true` + `Haptics.trainingComplete()` + LiveActivity.end() (TrainingSession.swift:407-416). Player branch on `store.session?.completed == true` (PlanPlayerScreen.swift:193-241): optional SaveChangesConfirmView gated by `canSaveChangesToPlan && !planSaveDecisionMade` (line 199-215), then CompletedView (line 219-240) with onClose -> `store.endedExplicitly=true; store.end(); dismiss()`. HealthKit write triggered by RootView.onChange(of: session.completed) (RootView.swift:267-271). `completedPRCount` via `data.isPR` (PlanPlayerScreen.swift:1033-1038; DataStore.isPR line 838-844 — first-ever exercise is NOT a PR).",
          "dropoffRisk": "Low-to-medium for the user (workout already done), but a friction point: the extra SaveChangesConfirmView interstitial sits between finishing and the rewarding share card if any param was edited. Drop-off risk here is mostly about NOT capturing the reward moment — first-timers have no PR (isPR returns false with no history), so the completion card's headline stat is empty on the very first workout, weakening the payoff."
        },
        {
          "stage": "Return later (retention loop)",
          "represents": "User comes back on a later day. App refreshes today's AI plan if the day rolled over, and recordSet history drives streaks, LRU plan rotation, review prompts, and reminders. A second distinct workout day is the core retention proof.",
          "codeLocation": "RootView .task + scenePhase active -> `data.refreshAIWorkoutIfNeeded()` (RootView.swift:240-256); DataStore.refreshAIWorkoutIfNeeded gates on same-day cache (DataStore.swift:1048-1067). Return-day proof = HistoryScreen.groupedSessions() (HistoryScreen.swift:590) aggregating SetRecords by (planId, calendar day); weekly streak loop (HistoryScreen.swift:474-480). recordSet advances `plan.lastUsedAt` for LRU (DataStore.swift:763-770). Milestone hooks: `shouldOfferReview()` at completedWorkoutCount>=3 (line 780-786), `shouldOfferReminderPrompt()` at >=2 (line 790-797).",
          "dropoffRisk": "HIGH — the make-or-break stage. Comeback reminders only fire if the user already opted in (`workoutRemindersEnabled` defaults false, Settings.swift:152), and the opt-in prompt itself only appears AFTER 2 completed workouts (shouldOfferReminderPrompt) — so a one-and-done user gets zero re-engagement nudge. No install-date / firstSeenAt anchor exists, so there's no early-life churn detection. completedWorkoutCount counts distinct days, so a user who never returns is invisible to every milestone."
        }
      ],
      "retentionSignals": [
        "RETURNED — distinct workout days: DataStore.completedWorkoutCount (DataStore.swift:773-776) = Set of startOfDay over all sets. A second distinct day = the user came back. This is the cleanest 'returned' signal in the codebase.",
        "RETURNED — HistoryScreen.groupedSessions() (HistoryScreen.swift:590) aggregates SetRecords into per-(planId, day) session cards; >1 session card on different days = repeat usage. Sessions only exist if recordSet was called, i.e. real sets were logged.",
        "STUCK AROUND — weekly streak: HistoryScreen streak loop (line 474-480) counts consecutive weeks where trainedDays >= goal. A growing streak is the strongest 'habit formed' signal. It tolerates an in-progress current week (line 469-472), so it doesn't false-zero.",
        "STUCK AROUND — review milestone consumed: shouldOfferReview() returns true once completedWorkoutCount >= 3 and flips settings.hasRequestedReview (DataStore.swift:780-786). hasRequestedReview=true on disk implies the user reached 3+ workouts.",
        "STUCK AROUND — reminder opt-in offered/accepted: shouldOfferReminderPrompt() fires at completedWorkoutCount >= 2 (line 790-797); settings.workoutRemindersEnabled=true (Settings.swift:152) means the user accepted comeback nudges — a self-declared intent to keep returning.",
        "ENGAGEMENT DEPTH — plan LRU rotation: recordSet advances plans[idx].lastUsedAt (DataStore.swift:763-770), and todayRecommendedPlan/pickTodayPlan rotates A->B->C off it. Multiple plans with recent, spread-out lastUsedAt = a user cycling through a real weekly split (deep engagement), vs. a single repeatedly-used plan.",
        "ENGAGEMENT DEPTH — PR accumulation: data.isPR (DataStore.swift:838-844) requires prior history for the same exercise, so any PR>0 proves the user has done that lift before on an earlier session = progressive overload over time.",
        "CHURN / DROP-OFF — onboarding never finished: settings.onboardingCompleted stays false (only set in RootView onDone, RootView.swift:126). A persisted fresh-install profile with onboardingCompleted=false on relaunch = user bounced inside the 7-step wizard.",
        "CHURN — AI value never delivered: settings/state aiTodayFailed=true (DataStore.swift:1063-1066, 1090, 1106) means the headline 'AI' feature degraded to local templates on this device — a leading churn indicator since the core promise wasn't met.",
        "CHURN — abandoned-but-auto-completed session: TrainingSessionStore.checkAutoComplete() (TrainingSession.swift:184-195) flips completed=true after 6h idle. A 'completion' produced this way (no Haptics.trainingComplete, no explicit Close) is really an abandonment masquerading as a finish — a false-positive in the completion funnel to watch for.",
        "CHURN — one-and-done: completedWorkoutCount stuck at 1 with no later groupedSessions day = activated but never retained. Notably this user is BELOW the reminder-prompt threshold (needs 2), so the app sends them no comeback signal at all — the highest-leverage churn cohort and currently the least addressed."
      ]
    },
    "callsites": {
      "callSites": [
        {
          "event": "app_launch",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/MasoApp.swift",
          "symbol": "MasoApp.body — WindowGroup .task { } closure",
          "note": "Cold-start init. The WindowGroup-level .task (line 73) runs once on launch (configures SubscriptionManager, restores persisted session, activates WatchSync). Put the cold-launch track() here. Note: dataStore is seeded at line 26 via DataStore.bootstrap()/makeMock(); MASO_SHOWCASE_SEED env guards demo data — guard analytics out of showcase mode if desired."
        },
        {
          "event": "app_foreground",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/MasoApp.swift",
          "symbol": "MasoApp.body — .onChange(of: scenePhase) { newPhase == .active }",
          "note": "Foreground transition (line 67-69). Already does subscriptions.refreshEntitlements(). RootView.swift line 248-256 has a SECOND scenePhase==.active handler (digest, HealthKit catch-up, AI refresh) — pick ONE site (MasoApp is the root-most) to avoid double-firing. Also fires .background/.inactive at line 60-65 for a backgrounded event."
        },
        {
          "event": "tab_switch",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/RootView.swift",
          "symbol": "RootView.body — TabView(selection: $tab)",
          "note": "Tab is @State private var tab: RootTab (line 46), bound to TabView at line 145. RootTab enum {plans, today, library, history} (line 9). Add .onChange(of: tab) at the TabView (around line 228) to track tab_switch with the new RootTab as a param. Programmatic switches also flow through here (router.requestedTab handler line 273, showcase line 81)."
        },
        {
          "event": "onboarding_step_advance",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Onboarding/OnboardingScreen.swift",
          "symbol": "OnboardingScreen.advance(to: Step)",
          "note": "Single funnel choke point for forward navigation (line 345). Every Next/auto-jump routes through advance(to:). Param = the destination Step (enum gender=1,goal,age,weight,days,focus,equipment, line 15). selectGender (line 356) and selectGoal (line 365) auto-call advance after a 0.18s delay; goBack() (line 350) is the reverse. Track the target step.rawValue here for step funnel."
        },
        {
          "event": "onboarding_complete",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Onboarding/OnboardingScreen.swift",
          "symbol": "OnboardingScreen.confirm()",
          "note": "Final 'Build My Routine' tap (line 382). Writes all 7 prefs into data.settings (gender/goal/age/weight/days/focus/equipment), flushSave, then kicks off the AIGeneratingView overlay + Task { generateFirstPlanViaAI() }. This is where onboarding profile is locked — track the full profile dict (gender, goalKind, age, weight, weeklyTrainingDays, wantStrengthen count, equipment count). Note: onboardingCompleted is actually set later in RootView.swift line 125-128 onDone closure when the AI-generating transition finishes — a second candidate for a 'reached_home' event."
        },
        {
          "event": "ai_routine_generate_start",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/AIWorkoutService.swift",
          "symbol": "AIWorkoutService.generateToday(payload:library:maxExercises:)",
          "note": "Today's single-plan generation. state = .generating is set at line 69 right after the isConfigured guard — the canonical 'start' marker. Callers: DataStore.refreshAIWorkoutIfNeeded (DataStore.swift:1048), forceRefreshAIWorkout (:1077), generateFirstPlanViaAI (:1096). For the multi-routine path use generateRoutines(payload:library:count:maxExercises:) (AIWorkoutService.swift:93), state=.generating at line 103, called by DataStore.generateAIRoutines (:1115)."
        },
        {
          "event": "ai_routine_generate_success",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/AIWorkoutService.swift",
          "symbol": "AIWorkoutService.generateToday(...) — state = .success(Date()) branch",
          "note": "generateToday success at line 79 (after parse + non-empty steps guard); generateRoutines success at line 115. These set state=.success and return the Plan(s). Track step count + whether source==.ai. Higher-level success is also observable in DataStore.refreshAIWorkoutIfNeeded line 1060 (if let plan) and generateAIRoutines line 1129 (returns usedFallback:false)."
        },
        {
          "event": "ai_routine_generate_fail",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/AIWorkoutService.swift",
          "symbol": "AIWorkoutService.generateToday(...) — state = .failure(...) branches",
          "note": "All failure exits set state=.failure: not-configured (line 66), empty-match (line 75), AIError catch (line 82), generic catch (line 85). Same shape in generateRoutines (lines 99/111/117/120). For a single high-level fail event, instrument DataStore.refreshAIWorkoutIfNeeded line 1065 (aiTodayFailed=true) and generateAIRoutines line 1131 (returns usedFallback:true). Track failure reason string from AIError.userMessage."
        },
        {
          "event": "tune_with_ai_send",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift",
          "symbol": "sendRefine() (PlanRationaleCard / AI page)",
          "note": "The 'tune with AI' chat send (line 208). Trimmed text guarded non-empty; Pro-gated (line 211 → paywallPresented for free users). On send it calls data.appendCoachNote(text) (line 216) then startGenerateRoutines(focusNote: text) (line 217). Track tune_with_ai_send with text length + whether it contained a URL (containsURL helper line 220). The paywall-bounce at line 211 is a good paywall_trigger source='tune_with_ai'."
        },
        {
          "event": "coach_note_append",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift",
          "symbol": "DataStore.appendCoachNote(_:)",
          "note": "Coaching-memory accumulation (line 119). Appends a '- bullet' to settings.coachMemory; early-returns on empty (line 121) or exact-duplicate-of-last-line (line 128). Only the non-skipped path actually mutates + saves (line 134). Track here to count real coach-note additions (deduped). Currently the only caller is sendRefine() above."
        },
        {
          "event": "routine_save",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift",
          "symbol": "DataStore.savePlan(_:) -> Bool",
          "note": "Adopt an AI/Classics plan into My Plans (line 906). Returns false when free cap hit (canSaveMorePlans, line 908) — that false is the paywall trigger. Idempotent if already saved (isPlanSaved, line 907). Track save with plan.resolvedSource (ai/classics/custom). Caller: PlansScreen.addToSaved (PlansScreen.swift:449) which bounces to paywall on false (line 452). createBlankPlan (:849) and seedStarterRoutines (:883) are separate 'new'/'seed' plan-creation sites."
        },
        {
          "event": "routine_delete",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift",
          "symbol": "DataStore.deletePlan(_:)",
          "note": "Explicit user delete from the My Plans long-press/swipe (line 949). Removes from plans + save; leaves sets/aiTodayPlan untouched. Single mutation choke point — both PlansScreen confirm paths (PlansScreen.swift:109 and :925) funnel here. Track plan source/age if useful."
        },
        {
          "event": "routine_adopt_niche_exercise",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift",
          "symbol": "DataStore.adoptNicheExercise(_:)",
          "note": "'Adopt' a rare/niche exercise into the user library (line 88). Guards against double-adopt (line 89). Mirror unadoptNicheExercise (:95). If 'adopt' in the prompt meant adopting a niche exercise, this is it; if it meant adopting a community/AI routine, see savePlan above. addCustomExercise (:102) and deleteCustomExercise (:111) are the custom-exercise equivalents."
        },
        {
          "event": "workout_start",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.start(planId:plan:segments:)",
          "note": "THE single workout-start entry (line 96). Sets up Session, starts Live Activity, resets watch. All UI start paths converge here via RootView.startTrainingNow (RootView.swift:738) ← startTraining (:569, which may first show the replace-confirm alert) ← Today/Plans onStart, startFreeWorkout (:534), center-tab quick start (:508), showcase. Track planId, source (recommended/ai/free/replay), step count = segments.filter(isExercise).count. NOTE: restorePersistedSession (TrainingSession.swift:235) is a cold-start RESUME, not a fresh start — track separately or skip."
        },
        {
          "event": "workout_pause",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.togglePlay()",
          "note": "Pause AND resume share one toggle (line 341). Branch on s.playing: the true→false branch (line 343) is pause, the else (line 349) is resume. Track the resulting state. Called from Controls onTogglePlay (PlanPlayerScreen.swift:977), MiniBar onTogglePlay (RootView.swift:472), handlePrimary for countdown segments (PlanPlayerScreen.swift:681), and WatchSyncManager.onTogglePlay (MasoApp.swift:95)."
        },
        {
          "event": "workout_resume",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.togglePlay() — else (resume) branch",
          "note": "Same function as pause (line 341); the else branch at line 349-355 (was paused → playing=true, restores endsAt from pausedRemaining). If you want distinct pause/resume events, branch inside togglePlay on the pre-toggle s.playing value before mutating."
        },
        {
          "event": "workout_complete_set",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.advance(record:)",
          "note": "The complete-a-set action (line 361). advance() is BOTH 'user tapped ✓' and 'countdown auto-finished'. A SetRecord is created + recorded and completedSets.insert happens at line 377-402, guarded so an already-completed (stepId,setN) is not double-counted. When no next landing index exists it flips completed=true (line 407-416) = workout_finish. Track complete_set on the line 401 insert; distinguish manual vs countdown via curWasStrength/seg.kind. Callers: handlePrimary (PlanPlayerScreen.swift:683), SessionTickerView auto-advance (TrainingSession.swift:1134), MiniBar onAdvance (RootView.swift:470), Watch onAdvance (MasoApp.swift:92)."
        },
        {
          "event": "workout_finish",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.advance(record:) — completed=true branch + finishEarly()",
          "note": "Natural finish: advance() line 407-416 (nextLandingIndex==nil → completed=true, Haptics.trainingComplete, LiveActivity.end). Early finish: finishEarly() (line 476) from the player End-confirm (PlanPlayerScreen.swift End button → endConfirmOpen). updateCurrentStep (:809) and deleteStep (:1000) can also flip completed when steps run out. checkAutoComplete (:184) is the 6h-idle silent finish. Track finish with totalSets, doneSets, duration, and finish_type (natural/early/auto_idle)."
        },
        {
          "event": "workout_skip_set",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.setIndex(_:) / jumpToStep(stepId:)",
          "note": "Skipping = jumping the playhead WITHOUT recording a set. setIndex (line 306) is the low-level seek (does NOT write completedSets, unlike advance). jumpToStep (line 328) lands on a step's next undone set, used when tapping a playlist row. There is no dedicated 'skip' button; skipping is implicit via these seeks. Track here if you want skip behavior; param = target stepId/setN."
        },
        {
          "event": "workout_undo_set",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.undoLastCompletedSet(removeRecord:)",
          "note": "Undo the most recent completed set of the current exercise (line 526). Removes the top (highest setN) from completedSets, flips completed=false, moves playhead back, and calls removeRecord closure → DataStore.removeLastSet (DataStore.swift:751) to delete the SetRecord. Returns Bool (false if nothing to undo). currentStepHasCompletedSet (:514) gates the UI. Note per CLAUDE.md the back button was later repointed to skipBackToPrevExercise, so verify whether undo is still wired in the player before relying on it."
        },
        {
          "event": "workout_replace_exercise",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.replaceStepExercise(_:newExerciseId:exById:defaultRest:defaultBetweenExerciseRest:)",
          "note": "In-session swap of one step's exercise, keeping sets/reps/weight (line 677). Sets planParamsDirty=true (line 738). Driven from the player playlist swipe→Replace → ExercisePickerSheet → store.replaceStepExercise (PlanPlayerScreen.swift:411). The Plans-tab (non-session) editor has its own Replace flow via stepToReplaceId (PlansScreen.swift:826). Track old→new exerciseId."
        },
        {
          "event": "workout_add_exercise",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/State/TrainingSession.swift",
          "symbol": "TrainingSessionStore.appendStep(exercise:settings:exById:defaultRest:defaultBetweenExerciseRest:)",
          "note": "Mid-session add-an-exercise (line 911), from the playlist '+ Add exercise' footer → ExercisePickerSheet → store.appendStep (PlanPlayerScreen.swift:438). Companion in-session mutators worth tracking: deleteStep (:978, swipe-delete a step), reorderSteps (:840, drag-reorder), updateStep (:602)/updateCurrentStep (:743, edit sets/reps/weight). All set planParamsDirty=true."
        },
        {
          "event": "workout_share",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/ShareImageButton.swift",
          "symbol": "ShareImageButton (rendered with UnifiedShareCard)",
          "note": "Shared share-image button used across surfaces. Call-sites: post-workout CompletedView (PlanPlayerScreen.swift ~line 2588 region, with data.setSessionPhoto), History session row (HistoryScreen.swift:491 and :1035), WorkoutCalendarScreen weekly-frequency share (:57). Add the track() inside ShareImageButton's tap/share-completion handler so all surfaces are covered once; param = share surface (workout_complete/history/calendar). Routine sharing (a link/QR, not a workout) is separate: PlansScreen.sharePlan via ShareImageRenderer.render (PlansScreen.swift:1053) + ShareActivityView (:2096)."
        },
        {
          "event": "image_import_start",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/TodayScreen.swift",
          "symbol": "PhotoImportModifier.body — .onChange(of: pickedImage)",
          "note": "Routine-from-image import. When a PhotoPicker (TodayScreen.swift:528) returns an image, .onChange (line 531) sets parsing=true and runs RoutineImageImporter.analyze (line 538). Track image_import_start at line 535. Outcomes switch at line 543-547: .deepLink (QR share card → ImportedPlanSheet, image_import_qr_success), .recognized (OCR candidates → RoutineReviewSheet, image_import_ocr_success), .empty (failed=true → alert, image_import_fail). The deep-link import via maso:// URL is a different path: RootView.onOpenURL (RootView.swift:319/132) → ImportedPlanSheet."
        },
        {
          "event": "image_import_result",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/TodayScreen.swift",
          "symbol": "PhotoImportModifier — switch result { .deepLink / .recognized / .empty }",
          "note": "Import outcome (lines 543-547). Track result type here; final 'imported into library' happens in the onAdd/onCommit closures (ImportedPlanSheet onAdd line 552, RoutineReviewSheet onCommit line 564) where data.plans.append + data.save run — a candidate image_import_commit event with recognized-exercise count."
        },
        {
          "event": "paywall_shown",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PaywallScreen.swift",
          "symbol": "PaywallScreen.body — .task { }",
          "note": "Paywall impression. PaywallScreen is presented via .sheet(isPresented:$paywallPresented) in RootView (RootView.swift:297) and locally in PlansScreen/PlanPlayer. Its .task (line 88) runs on present (loads products, computes intro-eligibility) — put paywall_shown there, or instrument each trigger that flips paywallPresented=true with a source param: handleNewPlan plan-cap (RootView.swift:443), addToSaved cap (PlansScreen.swift:452), sendRefine non-Pro (PlansScreen.swift:211), handleOptimize non-Pro (PlansScreen.swift:442)."
        },
        {
          "event": "paywall_purchase",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PaywallScreen.swift",
          "symbol": "PaywallScreen.handlePurchase()",
          "note": "Buy tap (line 282). Calls await subs.purchase(product) (line 286); on ok shows the confirm alert (line 288). Track purchase_attempt before the await with selectedPlan (.monthly/.yearly/.lifetime + introEligible flag), and purchase_success/_fail on the ok bool. Errors surface via subs.lastError → errorAlertShown (onChange line 83)."
        },
        {
          "event": "paywall_restore",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PaywallScreen.swift",
          "symbol": "PaywallScreen.handleRestore()",
          "note": "Restore Purchases tap (line 296, button at line 228). Calls await subs.restore() (line 299); success determined by subs.currentSubscription != nil (line 302) → confirm alert. Track restore_attempt + restore_result(restored:Bool)."
        },
        {
          "event": "settings_toggle_health",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/SettingsScreen.swift",
          "symbol": "ToggleRow 'Save workouts to Apple Health' — isOn custom Binding.set",
          "note": "Apple Health toggle (line 102-111). The Binding.set (line 107-112) writes settings.healthKitSyncEnabled and, when turned on, fires HealthKitService.requestAuthorization() (line 111). Track the new value + (optionally) auth grant result. This toggle is App-Review-critical per CLAUDE.md (Guideline 2.5.1)."
        },
        {
          "event": "settings_toggle_reminders",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/SettingsScreen.swift",
          "symbol": "ToggleRow 'Workout reminders' — isOn custom Binding.set",
          "note": "Comeback-reminder toggle (line 121-135). On-set optimistically sets workoutRemindersEnabled=true (line 128) then awaits WorkoutReminderScheduler.requestAuthorization() and reverts to the granted value if denied (line 130-131); off-set at line 135. Track new value + permission-granted result."
        },
        {
          "event": "settings_toggle_exercise_sync",
          "file": "/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/SettingsScreen.swift",
          "symbol": "ToggleRow 'globalExerciseParamSyncEnabled' — isOn: $data.settings.globalExerciseParamSyncEnabled",
          "note": "Global exercise-param sync toggle (line 145-148), a plain $binding (no side-effect closure) so to track you'd add .onChange(of: data.settings.globalExerciseParamSyncEnabled) or wrap in a custom Binding. Other settings worth tracking via the same pattern: weightUnit Choice (line 81), weekStartDay Choice (line 91). (debugProUnlock ToggleRow at line 224 is #if DEBUG only — never ships, do not instrument.)"
        }
      ]
    },
    "infra": {
      "networkLayer": "EXISTING HTTP/PROXY PATH — reusable as-is for an analytics endpoint.

File: /Users/yumowu/Projects/Maso-iOS/Maso/Data/AIWorkoutService.swift (@MainActor @Observable final class AIWorkoutService, singleton .shared).

Config read (xcconfig -> Info.plist -> Bundle):
- /Users/yumowu/Projects/Maso-iOS/Maso/Secrets.xcconfig (gitignored) defines `MASO_AI_PROXY_URL` and `MASO_CLIENT_TOKEN`. NOTE the xcconfig `//`-comment trap: URL is written `https:/$()/maso-ai.wuyumo.workers.dev` ($() breaks the // so it isn't truncated). Current value points at the Cloudflare Worker `maso-ai.wuyumo.workers.dev`.
- /Users/yumowu/Projects/Maso-iOS/Maso/Info.plist maps them: `MasoAIProxyURL` = `$(MASO_AI_PROXY_URL)`, `MasoClientToken` = `$(MASO_CLIENT_TOKEN)`.
- AIWorkoutService reads them via `Bundle.main.object(forInfoDictionaryKey:)`: `static var proxyURL` (line 42-44, key "MasoAIProxyURL") and `static var clientToken` (line 49-51, key "MasoClientToken"); `static var isConfigured` (line 54) = both non-empty.

Request build/send pattern (callDeepSeek, line 308; callDeepSeekForPicker 172; callDeepSeekRoutines 350 — all identical shape):
- `URL(string: "\\(Self.proxyURL)/v1/chat/completions")` — the path is hardcoded onto proxyURL.
- `var req = URLRequest(url:)`; httpMethod "POST"; timeoutInterval 45/60; header `Content-Type: application/json`; header `X-Maso-Client-Token: <clientToken>` (lightweight abuse-gate, not real auth — comment says reverse-engineerable).
- body via `JSONSerialization.data(withJSONObject:)`; transport `let (data, resp) = try await URLSession.shared.data(for: req)`; checks `resp as? HTTPURLResponse`, `(200...299).contains(http.statusCode)`. Errors via private enum AIError {network/api/parse}.

ANALYTICS FIT: Yes — this is a clean, proven template. The Cloudflare Worker proxy + URLSession.shared + X-Maso-Client-Token + Info.plist-injected base URL pattern can host an analytics endpoint directly. Cleanest approach: add a sibling path (e.g. `\\(proxyURL)/v1/events` or a separate `MasoAnalyticsURL` Info.plist key fed from a new xcconfig var) and a new `AnalyticsService` mirroring AIWorkoutService's static-config + URLSession POST shape. Reuse the same client token. Backend lives at /Users/yumowu/Projects/Maso-iOS/backend/ (cloudflare-worker, per AIWorkoutService comment). The Worker keeps real keys server-side, so analytics events are user-IP-visible to the Worker but no secret ships in the binary. A second, simpler in-app precedent exists at /Users/yumowu/Projects/Maso-iOS/Maso/Data/FeedbackTransport.swift (form-urlencoded POST to FormSubmit) — less suitable (3rd-party email forwarder) but confirms the URLSession POST idiom is used in two places already.",
      "persistence": "PERSISTENCE — two stores; both viable for buffering offline events.

(1) Primary app data: file-based JSON via /Users/yumowu/Projects/Maso-iOS/Maso/Data/PersistenceController.swift.
- Location: `var currentURL` (line 56-59) = `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("maso-data.json")` — i.e. `Documents/maso-data.json` (iCloud-Backup covered).
- `struct Snapshot: Codable` (version, plans, sets, settings, aiTodayPlan, lastAIRefreshAt, updatedAt). schemaVersion = 3 (line 40).
- `func save(_:)` (line 97): JSONEncoder iso8601, compact output, `data.write(to:options:[.atomic])`, failures swallowed. `func load()` (line 75) tolerant decode; version > current -> nil (mock fallback). Also export/import helpers (exportToTempFile, importFromFile) and `reset()`.
- Driven by /Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift (@MainActor @Observable final class DataStore). `func save()` (line 209) is true-debounced (0.8s coalesce via DispatchWorkItem); `func flushSave()` (line 219) writes immediately (called by RootView on scenePhase background/inactive); `writeSnapshotNow()` (line 226) builds Snapshot from DataStore state. UserSettings lives at `DataStore.settings` and is serialized inside this snapshot.

(2) Lightweight key-value: UserDefaults — used for small flags (LanguageManager storageKey, ExerciseImageCache `maso.imageCDNHostIndex`, @AppStorage `maso.hasSeenCenterTabHint` / `planStepCardLayout`).

EVENT-BUFFER FIT: The strongest existing analog is /Users/yumowu/Projects/Maso-iOS/Maso/Data/FeedbackStore.swift — a ready-made offline outbox pattern to copy verbatim for analytics: @MainActor @Observable singleton holding `private(set) var pending: [Item]` (Item is Codable: id UUID, date, body, appVersion, osVersion, language), persisted to UserDefaults keys `maso.feedback.pending.v1` / `maso.feedback.lastDigestSentAt.v1`. It enqueues on submit, opportunistically flushes, batch-sends a digest when >=24h since last success (digestInterval), removes sent ids on success, retries on next launch/foreground. An AnalyticsStore can mirror this exactly (swap email transport for the Worker POST). For larger event volumes, prefer a dedicated JSON file under Documents (same write-atomic pattern as PersistenceController) over UserDefaults. Device-info helpers already exist in FeedbackStore (appVersionString, osVersionString) for enriching events.",
      "anonymousId": "NO stable anonymous install/device ID exists today.

Grep across Maso + MasoWatch found zero use of `identifierForVendor`, `UIDevice`, `advertisingIdentifier`, `ASIdentifier`, `installId`, `deviceId`, or `anonymousId`. Every `UUID()` occurrence is ephemeral/per-record: plan ids (DataStore.swift 861/893/911, CommunityPlans.swift 4897/4922, PlanShareCodec.swift, ImportedPlanSheet.swift), custom-exercise ids (AddExerciseSheets.swift 405 "custom-<uuid>"), feedback item ids (FeedbackStore.swift 27/58), SetRecord ids (TrainingSession.swift 380), and SwiftUI Identifiable `let id = UUID()` view-model ids. None is persisted as a stable per-install identity.

CLEANEST PLACE TO MINT + STORE: add a field to `UserSettings` in /Users/yumowu/Projects/Maso-iOS/Maso/Models/Settings.swift (struct UserSettings: Codable, Sendable, ~line 81). It already persists inside the DataStore JSON snapshot (Documents/maso-data.json) and survives relaunch + iCloud Backup restore, and the file uses tolerant decoding so a new optional field is backward-safe. Recommended: `var anonymousId: String = UUID().uuidString` (or lazily minted in DataStore.bootstrap/freshInstall when empty), then `save()`. This gives a per-install (not per-device) id that resets on delete+reinstall — consistent with the existing privacy posture and avoids `identifierForVendor`/IDFA entirely. Alternative lighter location is a UserDefaults key (e.g. `maso.anonymousId`) mirroring FeedbackStore/ExerciseImageCache, but UserSettings keeps it co-located with the rest of user state and inside the single backed-up snapshot.",
      "privacyPosture": "PRIVACY POSTURE — currently a strict "no tracking / no collection" stance; adding analytics requires manifest + policy updates.

Privacy manifests (two, both declare NSPrivacyTracking false):
- /Users/yumowu/Projects/Maso-iOS/Maso/PrivacyInfo.xcprivacy: `NSPrivacyTracking` = false; `NSPrivacyTrackingDomains` = empty array; `NSPrivacyCollectedDataTypes` = EMPTY array (comment line 8-9 explicitly: "除 AI 流程外不收集任何数据; AI 数据通过 backend proxy 临时转发, 不构成 collection 定义"). NSPrivacyAccessedAPITypes declared: UserDefaults CA92.1, FileTimestamp C617.1, SystemBootTime 35F9.1.
- /Users/yumowu/Projects/Maso-iOS/MasoWatch/PrivacyInfo.xcprivacy (separate watch manifest).
IMPACT: shipping analytics likely requires adding a NSPrivacyCollectedDataTypes entry (e.g. Product Interaction / Other Usage Data, "not linked to identity, not used for tracking") and updating the App Store privacy questionnaire. NSPrivacyTracking can stay false as long as no cross-app/IDFA tracking is added (none planned).

No ATT / tracking framework: zero references to AppTrackingTransparency, ATTrackingManager, or advertisingIdentifier anywhere. No analytics SDK present (the only "analytics" hits are PaywallScreen.swift FeatureRow copy "Advanced analytics" = an in-app charts feature, and a SwipeableRow.swift comment).

Encryption flag: `ITSAppUsesNonExemptEncryption` = false in /Users/yumowu/Projects/Maso-iOS/Maso/Info.plist (line 41-42); CLAUDE.md notes it's set false across all three targets. Adding HTTPS analytics keeps standard-exemption (no change needed).

Privacy policy + terms URLs (live, in /Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PaywallScreen.swift line 34-35): termsURL = https://wuyumo.github.io/Maso/terms.html ; privacyURL = https://wuyumo.github.io/Maso/privacy-policy.html (markdown sources at docs/privacy-policy.md, docs/terms.md). Linked from PaywallScreen footer (line 231) and SettingsScreen. The privacy policy text would need an analytics/usage-data clause before shipping.

Privacy COPY in UI: searched for "stays on your device" / "本地" / "不会上传" — no marketing privacy claim string like "your data stays on your device" was found in Swift sources (the grep -l hits are files merely containing substrings like "on" or generic comments, not user-facing privacy promises). So there is no on-device-only promise in the UI that analytics would contradict, but the published privacy-policy.html is the binding statement to update. Other outbound network today: AI proxy (AIWorkoutService), feedback digest (FeedbackTransport -> formsubmit.co), and exercise image CDN (ExerciseImageCache) — all already leave the device, so analytics is consistent with existing network behavior but must be disclosed.",
      "flags": "FEATURE-FLAG PATTERN + DEBUG usage.

Flag enum: /Users/yumowu/Projects/Maso-iOS/Maso/Models/Settings.swift line 6-8:
```
enum MasoFlags {
    static let iapEnabled = true
}
```
A single file-scope enum of `static let` Bool constants — the established place to add a compile-time analytics flag (e.g. `static let analyticsEnabled = true`). Currently holds only `iapEnabled` (true as of this read; CLAUDE.md history shows it toggled false for the free-only launch and back). It gates Pro: `UserSettings.isPro` (line 128-134) returns true when `!MasoFlags.iapEnabled`, and SettingsScreen.proSection returns EmptyView when `!MasoFlags.iapEnabled` (SettingsScreen.swift line 263).

Runtime feature toggles (separate axis) live as Bool fields on `struct UserSettings` (Settings.swift), e.g. aiWorkoutEnabled (line 159, default true), healthKitSyncEnabled (139), workoutRemindersEnabled (152), globalExerciseParamSyncEnabled (185), debugProUnlock (124). A user-facing "share anonymous usage data" opt-out toggle would naturally go here (persisted in the snapshot), paired with the MasoFlags compile-time kill-switch.

#if DEBUG usage (relevant to gating analytics off in dev / debug-only UI):
- Settings.swift line 130-132: `isPro` reads `debugProUnlock` only inside `#if DEBUG` (Release never reads it).
- SettingsScreen.swift line 220-230: the entire "Debug" Section (Unlock Pro toggle) is wrapped in `#if DEBUG`, so it compiles only into Debug builds (install_iphone.sh ships Debug to device; Archive/Release strips it). This is the exact precedent for adding a debug-only analytics inspector or for `#if DEBUG`-suppressing event sends.
- Other #if DEBUG: LiveActivityManager.swift (37/54/59 logging), SpeechManager.swift (51 logging) — debug-only os_log/print, the pattern to follow if analytics should no-op or verbose-log in Debug.

RECOMMENDATION: combine a `MasoFlags.analyticsEnabled` compile-time gate + a `UserSettings.analyticsOptOut` (or opt-in) runtime field + `#if DEBUG` to disable real event transmission in dev builds."
    }
  },
  "workflowProgress": [
    {
      "type": "workflow_phase",
      "index": 1,
      "title": "Understand"
    },
    {
      "type": "workflow_phase",
      "index": 2,
      "title": "Synthesize"
    },
    {
      "type": "workflow_agent",
      "index": 1,
      "label": "map:screens",
      "phaseIndex": 1,
      "phaseTitle": "Understand",
      "agentId": "a13f5d93928ac7d98",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782822451500,
      "queuedAt": 1782822451491,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "promptPreview": "You are mapping the Maso iOS app (SwiftUI) at /Users/yumowu/Projects/Maso-iOS for an analytics design. Explore Maso/Views (Screens + Components) and Maso/Views/RootView.swift. Enumerate EVERY user-facing screen / tab / sheet and major interactive feature. For each: name, primary file, what the user DOES there (the concrete actions), and how they reach it (entry points). Also list notable cross-cut…",
      "lastProgressAt": 1782822640696,
      "tokens": 178424,
      "toolCalls": 24,
      "durationMs": 189195,
      "resultPreview": "{"screens":[{"name":"Onboarding (first-run wizard)","file":"/Users/yumowu/Projects/Maso-iOS/Maso/Views/Onboarding/OnboardingScreen.swift","whatUserDoes":"7-step one-question-per-screen wizard: pick gender, training goal, age (wheel), body weight (wheel, defaults to gender average), days/week (wheel, default 3), focus muscles (multi-select), available equipment (multi-select). Option-type steps (ge…"
    },
    {
      "type": "workflow_agent",
      "index": 2,
      "label": "map:funnel",
      "phaseIndex": 1,
      "phaseTitle": "Understand",
      "agentId": "a76a49084781eb0d8",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782822451506,
      "queuedAt": 1782822451491,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "promptPreview": "Map the core user journeys and natural funnel stages in the Maso iOS app at /Users/yumowu/Projects/Maso-iOS, for drop-off analysis. Trace the real code: first-launch onboarding (Maso/Views/Onboarding/OnboardingScreen.swift step machine) -> first AI plan generation (DataStore.generateFirstPlanViaAI / generateAIRoutines, AIWorkoutService) -> starting a workout (TrainingSessionStore / TrainingSession…",
      "lastProgressAt": 1782822569580,
      "tokens": 147498,
      "toolCalls": 11,
      "durationMs": 118074,
      "resultPreview": "{"funnelStages":[{"stage":"Install & cold start","represents":"App opened for the first time with no on-disk save. The store boots into the empty/fresh state (empty plans+sets) and routes the whole screen to onboarding.","codeLocation":"DataStore freshInstall path (DataStore.swift ~line 191-198: UserSettings() with onboardingCompleted=false, gender/age/weight=nil). RootView.body gate `if !data.set…"
    },
    {
      "type": "workflow_agent",
      "index": 3,
      "label": "map:callsites",
      "phaseIndex": 1,
      "phaseTitle": "Understand",
      "agentId": "a25c28c46112120e8",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782822451510,
      "queuedAt": 1782822451491,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "promptPreview": "Inventory the exact instrumentation call-sites for adding analytics to the Maso iOS app at /Users/yumowu/Projects/Maso-iOS. For each meaningful user action/event, give: a proposed snake_case event name, the file, the symbol/function where a track() call would go, and a short note. Cover at least: app launch / foreground, tab switches (RootView), onboarding step advance + complete (OnboardingScreen…",
      "lastProgressAt": 1782822630738,
      "tokens": 200108,
      "toolCalls": 23,
      "durationMs": 179228,
      "resultPreview": "{"callSites":[{"event":"app_launch","file":"/Users/yumowu/Projects/Maso-iOS/Maso/MasoApp.swift","symbol":"MasoApp.body — WindowGroup .task { } closure","note":"Cold-start init. The WindowGroup-level .task (line 73) runs once on launch (configures SubscriptionManager, restores persisted session, activates WatchSync). Put the cold-launch track() here. Note: dataStore is seeded at line 26 via DataSto…"
    },
    {
      "type": "workflow_agent",
      "index": 4,
      "label": "map:infra",
      "phaseIndex": 1,
      "phaseTitle": "Understand",
      "agentId": "a9bda4171631d324e",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782822451514,
      "queuedAt": 1782822451491,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "EXISTING HTTP/PROXY PATH — reusable as-is for an analytics …",
      "promptPreview": "Assess the Maso iOS app infrastructure for adding analytics, at /Users/yumowu/Projects/Maso-iOS. Report concretely: (1) networkLayer — the existing Cloudflare Worker / HTTP path (Data/AIWorkoutService.swift): how it reads MASO_AI_PROXY_URL + MASO_CLIENT_TOKEN from Secrets.xcconfig -> Info.plist (MasoAIProxyURL/MasoClientToken), how it builds + sends requests (URLSession), and whether that pattern …",
      "lastProgressAt": 1782822554368,
      "tokens": 130000,
      "toolCalls": 17,
      "durationMs": 102854,
      "resultPreview": "{"networkLayer":"EXISTING HTTP/PROXY PATH — reusable as-is for an analytics endpoint.\
\
File: /Users/yumowu/Projects/Maso-iOS/Maso/Data/AIWorkoutService.swift (@MainActor @Observable final class AIWorkoutService, singleton .shared).\
\
Config read (xcconfig -> Info.plist -> Bundle):\
- /Users/yumowu/Projects/Maso-iOS/Maso/Secrets.xcconfig (gitignored) defines `MASO_AI_PROXY_URL` and `MASO_CLIENT_…"
    },
    {
      "type": "workflow_agent",
      "index": 5,
      "label": "synthesize:design",
      "phaseIndex": 2,
      "phaseTitle": "Synthesize",
      "agentId": "ae40baf99cbca873f",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1782822640703,
      "queuedAt": 1782822640702,
      "attempt": 1,
      "promptPreview": "You are designing a product-analytics system for the Maso iOS app (SwiftUI, iOS 18, solo indie shipper, privacy-forward brand whose UI literally says training data 'stays on your device'). Goals the owner stated: (1) know which features users use, (2) find where users drop off / churn, (3) ongoing user-behavior monitoring for product optimization.

Inputs from the understanding phase (JSON):
SCREE…",
      "lastProgressAt": 1782822760726,
      "tokens": 56913,
      "toolCalls": 0,
      "durationMs": 120022,
      "resultPreview": "Output is the design doc only, no preamble.

# Maso Product Analytics — Build-Ready Design

Privacy-forward, solo-shipper-friendly product analytics for Maso-iOS. No PII, no IDFA/ATT, per-install anonymous id, offline-buffered, MasoFlags-gated, mirroring the existing `AIWorkoutService` / `FeedbackStore` patterns.

---

## 1. Event taxonomy

All events carry an implicit envelope (added by the servi…"
    }
  ],
  "totalTokens": 712943,
  "totalToolCalls": 75
