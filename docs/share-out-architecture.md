# Maso "SHARE OUT" Architecture — Design Doc (for approval)

**Scope:** app-wide shareable share-out cards, anchored to the existing 3-layer pipeline in `Maso/Views/Components/Share/`. Grounded in real symbols: `ShareImageRenderer`, `ShareImageButton`, `ShareCustomizeSheet`, `ShareCardFooter`/`ShareQR`, `UnifiedShareCard`, `AISummaryCard`, `HistoryScreen`, `InsightsChartsView`.

---

## 1. The level decision (the owner's core question)

**Recommendation: ONE reusable per-object share affordance — `ShareImageButton` — applied consistently on each accomplishment surface. No share hub. Add exactly ONE milestone trigger (PR) later, and DEFER any "recap/Wrapped" hub until aggregate data earns it.**

This is precisely what `MARKET.levelRecommendation` converges on (Strava/Hevy/Strong/Nike/Gentler/Apple Fitness all attach the entry to the object), and it's what Maso already half-does: `ShareImageButton` is the object-level affordance, already routed through the native iOS Share sheet via `ActivityViewController`. We are not inventing a level; we are **finishing the one we chose** and fixing the two places where it drifted.

Rationale specific to this codebase:
- **The reusable affordance already exists and is battle-tested.** `ShareImageButton` + `ShareCustomizeSheet` handle the whole "tap → customize → render PNG at scale 3.0 → native sheet → analytics" loop, including the two subtle bugs the code comments document (sheet-from-sheet race, PNG colorspace normalization). Every new surface should ride this, never re-implement it.
- **A hub would sit empty and is anti-pattern for a solo dev.** `MARKET.pitfalls`: "A dedicated share HUB with nothing to celebrate." Maso has no annual aggregate ritual yet. Building a Wrapped surface now = maintenance cost with no payoff.
- **Avoid the other extreme too.** Do NOT put a share icon on every `SessionCard` row, every `InsightCard`, or every history week. `MARKET.pitfalls`: "Share buttons EVERYWHERE = noise." One prominent entry per genuine accomplishment screen.

**The model in one sentence:** *`ShareImageButton` is the universal "share this thing" component; each shareable surface owns exactly one entry that hands it the right card view; the segment-level entry on Progress is the one exception, because Progress hosts two different shareable objects (Insights vs History) behind a segmented control.*

---

## 2. Share-out section map

Priorities: **P0 = this cycle** (owner's two asks), **P1 = next**, **P2 = later/triggered**.

| # | Surface / board | Card it produces | Entry location | Trigger | Status | Priority |
|---|---|---|---|---|---|---|
| 1 | Post-workout complete | `WorkoutCompleteShareCard` | Finish-workout screen (existing Share button) | User taps after finishing | **Exists** | — |
| 2 | History → session detail | `UnifiedShareCard` (workout default on) | `SessionDetailSheet` toolbar `.topBarLeading` (existing `ShareImageButton`) | User taps in session sheet | **Exists** | — |
| 3 | Routine / plan | `UnifiedShareCard` / routine card | Plan detail (existing) | User taps | **Exists** | — |
| 4 | **Progress → History overview** | `UnifiedShareCard` (todayStatus+workout+muscle+calendar) | **Per-segment**: header share button, active only on History segment | User taps when on History | Exists but **misplaced** — relocate (§3) | **P0** |
| 5 | **Progress → Insights segment** | **`InsightsSummaryShareCard` (new)** — headline stats roll-up (delta, weekly volume trend, top-lift e1RM, PR count, consistency) | **Per-segment**: header share button, active on Insights segment | User taps when on Insights | **New** | **P0** |
| 6 | **AI Insight Summary** | **`AISummaryShareCard` (new)** — TL;DR + 2 key numbers, on-brand + QR | Small share glyph on the `AISummaryCard` header row (next to Refresh) | User taps on the AI card | **New** | **P0** |
| 7 | Muscle Status | `MuscleStatusShareCard` (exists) | Share glyph on `MuscleStatusOverviewCard` (Today tab) | User taps | Card exists, **entry missing** | **P1** |
| 8 | Individual insight charts (volume / e1RM / MEV-MAV / PR-timeline) | **`ChartShareCard<Chart>` (new, generic wrapper)** | Small share glyph in each `InsightCard`'s `cardHeader` | User taps a specific chart | **New** | **P1** |
| 9 | PR milestone | Reuse `SessionShareCard` or a lean PR card | **Triggered** — surfaced at the moment a new PR is logged (Duolingo-style) | App-initiated at PR write | **New** | **P2** |
| 10 | Weekly recap / streak | Weekly roll-up card | Triggered weekly, or a single "share my week" entry on History | Weekly trigger | **New** | **P2** |

Notes:
- Rows 4–6 are the P0 cut = the owner's two asks (relocate Progress share; make AI Insight shareable).
- Row 8 is deliberately a **generic wrapper**, not one card per chart — a solo dev can't maintain 8 bespoke chart cards (`MARKET.pitfalls`: "Over-building for a solo dev").
- Row 9 (PR) is the one milestone trigger `MARKET.levelRecommendation` explicitly recommends adding; `data.isPR(_:)` already exists, so the detection is free.

---

## 3. Progress tab share relocation

**Two problems today** (both in `HistoryScreen.swift`):
1. The share button `historyShareButton` (lines 537–572) lives in `.screenHeader("Progress")`'s trailing closure (lines 202–212). It is **always** the History overview card (`UnifiedShareCard` with all 4 sections), regardless of which segment (`historyTab`) is active. On the Insights segment it shares the wrong thing.
2. It sits awkwardly in the nav-bar trailing group next to the gear, disconnected from the segment content it represents.

**Fix — make the header share button segment-aware.** Keep it in the `screenHeader` trailing slot (that's the correct iOS home for a screen-level share, and it stays out of the scroll content), but branch its card by `historyTab`:

```swift
// HistoryScreen.body, .screenHeader trailing closure (replaces bare `historyShareButton`)
.screenHeader("Progress") {
    if !groupedSessions().isEmpty {          // no data → no share entry at all
        switch historyTab {
        case .insights: insightsShareButton   // NEW → InsightsSummaryShareCard
        case .records:  historyShareButton    // EXISTING → UnifiedShareCard
        }
    }
    Button(action: onOpenSettings) { Image(systemName: "gearshape") ... }
}
```

- **On History segment** → existing `historyShareButton` unchanged (rows 4). `shareSurface: "history"`.
- **On Insights segment** → new `insightsShareButton`, built with the same `ShareImageButton` API, producing `InsightsSummaryShareCard` (§4-adjacent, defined below). `shareSurface: "insights"`.

Why keep it in the header rather than move it inline under the `Picker`:
- The `Picker` (lines 140–145) is inside the `ScrollView` content; an inline share button there would scroll away and dilute into the card list — exactly the "share icon on every card" noise we're avoiding.
- The header slot is persistent, discoverable, and already the pattern for `SessionDetailSheet`.
- Empty-state guard: when `groupedSessions().isEmpty`, render no share entry (nothing to share) — mirrors how the sections themselves guard on data.

Both branches reuse `ShareImageButton` with the identical `editing`/`rendering` closure shape already in `historyShareButton`. The only new code is the Insights card view and a small `insightsShareButton` computed property.

---

## 4. AI Insight Summary share card (`AISummaryShareCard` — new)

### What it renders
The card renders the **cached** summary — never triggers an LLM call. Data source is already on `DataStore`:
- `data.cachedSummary` (`DataStore.swift:1616`) → `AISummary.tldr` + `recommendations`.
- `data.settings.aiSummaryGeneratedAt` (`Settings.swift:268`) → "As of <date>" footer line, matching the on-card footer at `AISummaryCard.footer(generatedAt:)`.
- 2 key numbers pulled from the same deterministic helpers `InsightsChartsView` already uses (so the share card can't contradict the on-screen card): e.g. `consistencyScore()`-equivalent adherence and `weekDeltas().volume` %, or top-lift name + e1RM. These come from `DataStore`, not the LLM (`AISummary.swift` header rule: "LLM 从不自己算/编数字").

### Layout (on-brand, Wrapped-style, celebration-only)
```
┌─────────────────────────────┐
│  ✨ AI COACH SUMMARY  (kicker, accent)   │
│                                          │
│  “<TL;DR one-liner>”   (big, 22pt bold)  │  ← the hero: the coach's read
│                                          │
│  [ +14%      ]  [  92%        ]          │  ← 2 ShareStat tiles (reuse `ShareStat`)
│  VOLUME WoW     ADHERENCE                 │
│                                          │
│  (optional) 1 top recommendation title   │
│                                          │
│  ShareCardFooter(qrPayload: appStore)    │  ← MASSO wordmark + real QR
└─────────────────────────────┘
```
- Reuse `ShareStat` (from `WorkoutCompleteShareCard.swift:85`) for the two number tiles — no new stat component.
- Reuse `ShareCardFooter()` with `MasoLinks.appStore` as the QR payload (the growth loop-back; `MARKET.bestPractices` "build the growth loop into the pixels"). This is the standard payload all cards use today.
- Follow `SessionShareCard`'s exact chrome: `VStack { … }.padding(.horizontal, 24).background(MasoColor.background)` + trailing `ShareCardFooter()`. Optional top `SharePhotoBanner(photo:onTapToAdd:)` so users can overlay on a gym selfie (`MARKET.bestPractices` transparent/photo overlay) — reuse, don't rebuild.
- **Celebration-only:** if the TL;DR is a "signal thin / hedge" message (the `AISummaryPayload.Signal.thin` case), the share entry is **hidden** — never let the user broadcast a "not enough data / you slacked" card (`MARKET.pitfalls`: "Judgmental or shaming content").

### How it plugs into the pipeline
Identical to every other card — zero new plumbing:
```swift
// AISummaryCard.header(showRefresh:), add before Refresh button:
ShareImageButton(
    previewTitle: NSLocalizedString("My AI Summary", comment: ""),
    defaultSections: ShareSections(),          // sections unused here; pass a no-op set
    shareSurface: "ai_summary",
    shareContent: { photo, onTapAdd, _ in
        AISummaryShareCard(summary: shown, generatedAt: data.settings.aiSummaryGeneratedAt,
                           keyStats: data.summaryKeyStats(), userPhoto: photo, onTapAddPhoto: onTapAdd)
    },
    label: { Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MasoColor.textDim) }
)
```
- `ShareImageButton`'s closure is called twice (editing/rendering) by `ShareCustomizeSheet`; since this card has no toggleable sections, both branches return the same `AISummaryShareCard` (photo overlay is the only "customization"). This is a legit degenerate use of the existing API — no changes to `ShareImageButton` needed.
- Rendering flows through `ShareImageRenderer.render` (width 390, scale 3 → ~1170px) → PNG normalization → `ActivityViewController` → analytics `workout_share` with `surface: "ai_summary"`. All existing.
- **Entry sits on the `AISummaryCard` itself** (header row, left of Refresh), only in the Pro/cached state where a real summary exists. Insufficient-data and locked states show **no** share glyph (nothing real to share; don't let a non-Pro broadcast the blurred teaser).

`InsightsSummaryShareCard` (§3, the Insights-segment card) is the same card family — it's `AISummaryShareCard` widened to a stats roll-up: it may reuse the TL;DR headline plus 3–4 `ShareStat` tiles sourced from `InsightsChartsView`'s existing helpers (`weekDeltas`, `topLiftSeries`, `prTimeline().count`, `consistencyScore`). To avoid duplicating those private helpers, lift the handful needed into small `DataStore` methods (see §5).

---

## 5. Reuse vs new

**Reuse (no changes):**
- `ShareImageRenderer` — unchanged. Every new card renders through it.
- `ShareImageButton` + `ShareCustomizeSheet` + `ActivityViewController` — unchanged. All new entries are just new callers.
- `ShareCardFooter` / `ShareQR` / `MasoLinks.appStore` — unchanged; new cards pass the App Store payload.
- `SharePhotoBanner` — reuse for photo overlay on the new cards.
- `ShareStat` (in `WorkoutCompleteShareCard.swift`) — reuse for all stat tiles.

**New (minimal):**
1. `Share/AISummaryShareCard.swift` — the AI TL;DR + 2 stats card (P0).
2. `Share/InsightsSummaryShareCard.swift` — the Insights-segment roll-up (P0). Can start as a thin config over the same layout primitives; if near-identical, make it one card with a `variant` enum rather than two files.
3. `Share/ChartShareCard.swift` — generic `ChartShareCard<Content: View>(title:subtitle:chart:)` wrapper: kicker + a passed-in `Chart` snapshot + footer (P1). One wrapper serves all four insight charts.
4. Small `DataStore` accessors so share cards don't reach into `InsightsChartsView`'s private helpers, e.g. `func summaryKeyStats() -> (volumeWoW: Int?, adherencePct: Int, topLift: (name: String, e1rm: Int)?)`. This centralizes the "numbers are computed deterministically, never by the card" rule already stated in `AISummary.swift`.

**Shared pattern (recommended, lightweight):** a `ShareableCard` marker protocol is *not* worth it — SwiftUI cards don't share behavior, only visual chrome. Instead codify chrome as a `ViewModifier`:
```swift
struct ShareCardChrome: ViewModifier {  // background + footer slot
    func body(content: Content) -> some View {
        VStack(spacing: 0) { content; ShareCardFooter() }.background(MasoColor.background)
    }
}
```
Every card ends `.modifier(ShareCardChrome())` instead of hand-writing the footer + background. This is the reuse win; a protocol is over-engineering here.

**xcodegen note:** new files under `Maso/Views/Components/Share/` are picked up by the existing glob in `project.yml` — no `project.yml` edit needed, just `xcodegen generate` if the group globbing requires it (verify; the Share dir is already a source path).

---

## 6. Phased build plan

### P0 — Owner's two asks (this cycle)
Ordered files to add/edit:
1. **Add** `Maso/Views/Components/Share/AISummaryShareCard.swift` — new card (§4), using `ShareStat` + `ShareCardFooter` + optional `SharePhotoBanner`.
2. **Add** `Maso/Views/Components/Share/InsightsSummaryShareCard.swift` — new card (§3/§4). (Or fold into #1 with a variant.)
3. **Edit** `Maso/Data/DataStore.swift` — add `summaryKeyStats()` (and any small stat accessor the Insights card needs), pulling from existing helpers. No new data collection.
4. **Edit** `Maso/Views/Components/AISummaryCard.swift` — add the share glyph in `header(showRefresh:)`, gated to the cached/Pro state; skip when summary is a thin-signal/insufficient/locked teaser.
5. **Edit** `Maso/Views/Screens/HistoryScreen.swift` — (a) add `insightsShareButton` computed property mirroring `historyShareButton`; (b) make the `screenHeader` trailing branch on `historyTab` and guard on non-empty sessions (§3).
6. Localizable.strings (en + zh): "My AI Summary", "My Insights", card labels.
7. `xcodegen generate` (if needed) → simulator build verify → `verify-app` smoke → `install_iphone.sh`.

### P1 — Broaden coverage
1. **Add** `Share/ChartShareCard.swift` generic wrapper.
2. **Edit** `InsightsChartsView.swift` — add a small share glyph into `cardHeader(icon:title:subtitle:)` for the four "worth sharing" charts (volume, e1RM/`perLift`, `mevMav`, `prTimeline`); each hands its `Chart` to `ChartShareCard`. Not on the small/utility cards (heatmap legend, delta tiles) — keep it one entry per genuinely brag-worthy chart.
3. **Edit** `MuscleStatusOverviewCard.swift` (Today tab) — add a `ShareImageButton` entry producing the existing `MuscleStatusShareCard` (card exists; only the entry is missing).

### P2 — Triggered / recap
1. **PR milestone trigger** — at the SetRecord write path where `data.isPR(_:)` flips true, surface the share sheet (or a subtle "🏆 New PR — share it?" affordance) with `SessionShareCard`/a lean PR card. This is the one high-ROI trigger from `MARKET.bestPractices` ("Milestone-TRIGGER the share").
2. **Weekly recap / streak** — a single "share my week" card sourced from the weekly stats already computed in `HistoryScreen` (`currentWeekStreak`, `setsThisWeekCount`). Still object-level, not a hub.
3. Re-evaluate a seasonal recap **only** once there's ≥ a few months of aggregate data to make it non-empty.

### Cross-cutting flags
- **Privacy of stats on a share card** (`MARKET.pitfalls` "Ignoring privacy"): the AI/insights cards expose adherence %, tonnage, e1RM, PR names. Bodyweight is not on these cards (good). Recommendation: keep the per-section toggles for the History card (already there via `ShareSections`), and for the new AI/Insights cards give a sane default that omits anything a user might not want public (no absolute dates — reuse the "As of <date>" only; no location data exists in this app). Celebration-only: never render a shame framing (thin-signal/low-adherence → hide the share entry, don't produce a card).
- **Parallel-edit conflict warning:** `AISummaryCard.swift` and `PlansScreen` are being edited in parallel for an unrelated change (per the owner). The P0 edit to `AISummaryCard.header(showRefresh:)` (step 4) is a small, localized insertion — coordinate/rebase so the share-glyph insertion and the unrelated change don't collide on that same header function. `HistoryScreen` also routes AI Apply into Plans via `AppRouter`; the share relocation touches only `screenHeader`/`historyShareButton`, not the Apply path, so no conflict there.

---

**Files referenced (all absolute):**
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/ShareImageButton.swift`
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/ShareImageRenderer.swift`
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/ShareCardFooter.swift`
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/SessionShareCard.swift`
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/WorkoutCompleteShareCard.swift` (defines `ShareStat`)
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/UnifiedShareCard.swift`
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/MuscleStatusShareCard.swift`
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/AISummaryCard.swift` (edit: header share glyph)
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/InsightsChartsView.swift` (P1 edit: per-chart glyph)
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/HistoryScreen.swift` (edit: `historyShareButton` L537, `screenHeader` L202)
- `/Users/yumowu/Projects/Maso-iOS/Maso/Models/AISummary.swift`, `/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift` (`cachedSummary` L1616, `summaryMinDataMet` L1296), `/Users/yumowu/Projects/Maso-iOS/Maso/Models/Settings.swift` (`aiSummaryGeneratedAt` L268)",
    "market": {
      "apps": [
        {
          "name": "Strava",
          "shareable": "Individual activity (run/ride) with distance, pace, time and a mini route map; segment achievements (KOM/QOM, PRs, top-10s); the route map itself. Cards auto-generate stats+map; users can also drop the stat sticker over their own photo.",
          "entryPattern": "Per-item share icon. A share icon lives on each activity — both inline in the feed and on the activity detail screen. Tap it → native Share sheet → 'Share to Instagram Stories' generates the stat/map card as a sticker on the IG canvas. No dedicated share hub; entry is attached to the object being shared.",
          "cardStyle": "Utilitarian-athletic: dark or photo background, orange accents, a route-map line as the hero graphic, stats in a clean monospace-ish grid. The map silhouette is the recognizable signature; stat sticker can overlay the user's own photo.",
          "driver": "Brag/proof-of-effort + the route map as identity. People share because the distance/pace is an accomplishment and the map is a unique visual fingerprint of where they went. Segment achievements add competitive brag."
        },
        {
          "name": "WHOOP",
          "shareable": "Daily recovery score, workout/strain summaries, sleep milestones; historically the Weekly Performance Assessment. Teams feature lets you share recovery/strain/sleep into a private group.",
          "entryPattern": "Per-metric share, a few taps from the relevant detail screen, plus a social/Teams layer. Not a single hub. Note: the in-app Weekly/Monthly Performance Assessment tab was removed (May 2025); monthly recaps now go out by email, so the recap-card surface has shrunk to per-metric shares.",
          "cardStyle": "Clinical, data-forward: dark background, the color-coded recovery ring (green/yellow/red) as the hero, big single number, minimal chrome. Reads as a 'health readout,' more informational than celebratory.",
          "driver": "Identity of the optimizer + data brag ('99% recovered'). Weaker mass-virality than Strava/Whoop's audience is smaller and stats are private-feeling; the recovery color is the one instantly legible flex."
        },
        {
          "name": "Apple Fitness",
          "shareable": "Closed Activity rings, individual workout summaries, and awards/badges (challenge medals, monthly and special-event awards). Special events also grant animated Messages stickers/badges.",
          "entryPattern": "Per-object share from the detail view, routed through the system Share sheet. In Fitness you tap an award (or a workout/ring summary), then the Share button → Messages / social / any Share-sheet extension. Deeply integrated with iMessage rather than a bespoke share studio.",
          "cardStyle": "Rings as the universal hero graphic; awards are glossy 3D medallions with metallic finishes and dates. Celebratory, tightly on-brand with Apple's gradient/dark aesthetic. Animated stickers for events add a playful layer.",
          "driver": "Milestone/streak + collection. Closing all three rings and rare limited-edition awards (e.g. anniversary, special challenges) create a completionist brag; iMessage sharing is 1:1 social nudging rather than broadcast."
        },
        {
          "name": "Hevy",
          "shareable": "Per completed workout, MULTIPLE auto-generated assets: workout summary (duration, volume, sets), exercise list, personal records, muscle-distribution chart, and playful 'real-world comparison' cards ('13,264 kg = a truck'). Plus monthly report (PRs, consistency calendar, exercise frequency).",
          "entryPattern": "Two entries: (1) 'Stories' button surfaced right after finishing a workout; (2) three-dots menu next to any past workout on the Profile tab → 'Share Workout' → pick which asset. Monthly report shared from Profile > Statistics. User picks from a carousel of assets — not forced to share all.",
          "cardStyle": "Clean, modern, fitness-native. Each asset is a focused card (one stat theme per card). Background toggle: light / dark / transparent — transparent is explicitly for overlaying on a gym selfie or lifting clip. Strong system for turning dry log data into legible bragging cards.",
          "driver": "Volume/PR brag + gym-selfie culture. The 'lifted a truck' comparison injects humor/shareability into otherwise dry numbers; transparent overlay lets the flex ride on top of the user's own gym content (identity)."
        },
        {
          "name": "Strong",
          "shareable": "Workout summary cards — total volume, sets, duration, exercises, PRs — generated per logged session. Comparable to Hevy but a leaner, more no-frills asset set.",
          "entryPattern": "Per-workout share from the completed-workout / history detail via a share action into the native Share sheet. No dedicated hub; entry is attached to the individual workout record.",
          "cardStyle": "Minimal, dark, data-first — a tidy stat block with the Strong wordmark. Less templated variety than Hevy; prioritizes a single clean summary over a carousel of themed assets.",
          "driver": "Proof-of-work / PR brag among serious lifters. Utility-over-aesthetics: the audience shares numbers, not art. Lower viral surface than Hevy because there's less visual novelty per card."
        },
        {
          "name": "Nike Run Club",
          "shareable": "A finished run rendered as a shareable post OR a more dynamic Story: your own photo or a Nike poster with run-data stickers (distance, pace, time) overlaid, plus captions/emoji/hashtags.",
          "entryPattern": "Segment/tab-level entry into a share studio. Activity tab → select the run → 'Share your run' → opens a customizer where you choose photo vs poster, place data stickers, then pick the channel. It's a mini editor, not just a one-tap sticker drop.",
          "cardStyle": "Bold Nike brand: heavy type, high-contrast, motivational-poster energy. Stats as stickers over the user's photo or a Nike-designed poster background. Editorial and aspirational rather than clinical.",
          "driver": "Identity/aspiration + brand halo. Sharing associates the runner with the Nike brand and its 'athlete' identity; the poster templates make an ordinary jog look editorial (aesthetics), and milestone runs (first 5K/10K) add brag."
        },
        {
          "name": "Gentler Streak",
          "shareable": "Beautifully composed workout summaries — map, photos, stats, charts in one clean journal-style card — and the signature Activity Path (the gentle 'go/rest' wave). Custom titles, notes, added photos turn each workout into a shareable journal entry.",
          "entryPattern": "Per-workout share from the summary/detail screen. The share affordance is attached to the individual beautifully-rendered summary rather than a global hub. Design-led product, so the object itself is the share unit.",
          "cardStyle": "The most explicitly aesthetic of the fitness set: colorful, soft, approachable HealthKit data; big bold friendly numbers; the mascot 'Yorhart'; smooth gradients. Kindness-branded — non-judgmental, no shame for rest days.",
          "driver": "Aesthetics + gentle identity (the anti-hustle 'kind to yourself' crowd). People share because the card is gorgeous and expresses a values-identity (balance, self-compassion), not raw performance brag."
        },
        {
          "name": "Duolingo",
          "shareable": "Streak count and streak-milestone cards (7/30/100/365 days etc.), achievements, and the annual Year-in-Review recap (top stats + a personality 'learner style' archetype).",
          "entryPattern": "Per-achievement share: tap the streak counter / milestone pop-up → Share → generates a card and posts without leaving the app. Year-in-Review is a seasonal segment-level recap flow. Milestone-TRIGGERED — the app proactively surfaces the share moment when you hit the number.",
          "cardStyle": "Premium artifacts, not screenshots: custom illustrations (Duo the owl, flames), bold brand color, built at Instagram AND Twitter aspect ratios so no cropping. Playful, characterful, instantly recognizable.",
          "driver": "Streak brag + identity/personality. The milestone-triggered, gorgeously-illustrated cards reportedly drove a ~5–10x jump in organic sharing (millions of daily streak shares; #Duolingo365 trends yearly). Year-in-Review's 'learner style' archetype democratized sharing beyond top-10% performers by giving everyone an identity token to post."
        },
        {
          "name": "Spotify Wrapped",
          "shareable": "An annual, multi-slide personalized recap — top artists, songs, genres, minutes listened, and identity-flavored labels — each slide a discrete shareable card.",
          "entryPattern": "Dedicated seasonal share HUB: a guided, swipeable story deck where every slide has its own share button pre-wired to IG Stories / TikTok / etc. Not per-screen scattered — it's a purpose-built recap experience released once a year (scarcity/ritual).",
          "cardStyle": "The gold standard: 9:16 vertical sized exactly for Stories/TikTok (zero cropping/friction), bold vibrant color blocks, clean modern layout, one big stat per slide. Feels like a premium designed product, not a data dump.",
          "driver": "Identity + celebration + FOMO. It showcases the USER, not the brand ('this is who I am'), never judges ('celebration not critique'), and its once-a-year scarcity builds ritual and social momentum — generating more organic reach than paid ads could buy."
        },
        {
          "name": "BeReal",
          "shareable": "Your daily dual-camera BeReal post (unfiltered front+back photo). Sharing is the whole product, not a stats recap.",
          "entryPattern": "Share-to-external is a deliberate outbound step, and every externally shared image carries a 'bere.al/username' watermark — a built-in growth loop-back. Screenshotting a friend's post surfaces a screenshot count icon (share-aware social pressure) rather than push notifications.",
          "cardStyle": "Anti-aesthetic by design: no filters, no beautification, dual-camera framing. The 'card' is the raw authentic moment; the only chrome is the username watermark that turns every share into an acquisition link.",
          "driver": "Authenticity/identity + the watermark growth loop. The lesson for a fitness app is mechanical, not visual: every outbound image should carry a branded, tappable path back to the app (handle/QR/link)."
        }
      ],
      "levelRecommendation": "Use a MIX, but anchor on the PER-OBJECT (per-card / per-detail) share affordance as the primary level, and add ONE milestone-triggered moment plus ONE optional seasonal recap. Concretely, for a solo fitness app: (1) PRIMARY — put a single share action on each shareable object's detail screen: the finished-workout summary, a PR, and a completed-streak/milestone. This is what Strava, Hevy, Strong, Nike, Gentler Streak and Apple Fitness all converge on — the entry lives ON the thing being shared, routed through the native iOS Share sheet. It's discoverable exactly when the user feels the accomplishment, and it costs one button per screen, not a button everywhere. (2) TRIGGERED — proactively surface the share sheet at emotional peaks (first workout, a new PR, a round-number streak), Duolingo-style; milestone-triggered sharing massively outperforms a passive icon because you catch the brag impulse at its peak. (3) OPTIONAL HUB — reserve a dedicated 'recap/Wrapped' surface only for a periodic (monthly/yearly) roll-up; a full share-hub is worth it ONLY when there's genuinely rich aggregate data to celebrate, otherwise it sits empty. AVOID the two extremes: do NOT scatter a share icon on every card/row in feeds and lists (noise, dilutes the signal, nobody shares a single set), and do NOT hide sharing behind a three-dots menu on the primary moment. Rule of thumb: one prominent share entry per genuine 'accomplishment' screen, the native Share sheet for the how, and a milestone trigger for the when — that gives you Strava-grade coverage without Strava-grade clutter, which matters more for a solo dev who can't maintain many bespoke share editors."",
      "bestPractices": [
        "Gorgeous, opinionated DEFAULT card — the auto-generated card must look finished with zero editing. Spotify Wrapped, Duolingo and Gentler Streak win because the default IS the shareable; treat the card as a designed product, not a screenshot of your UI.",
        "One tap from impulse to posted. Route through the native iOS/Android Share sheet so the user shares to whatever app they already have (Strava/Hevy/Nike all do this). Never build a bespoke list of network buttons; the OS sheet is faster and always current.",
        "Size cards to the destination: 9:16 / 1080x1920 for Stories & TikTok (Spotify) and provide a square variant (Duolingo ships both IG and Twitter ratios) so users never have to crop — cropping friction kills shares.",
        "Milestone-TRIGGER the share, don't just expose an icon. Proactively surface the share prompt at PRs, first-workout, and round-number streaks. Duolingo's milestone-triggered cards reportedly drove ~5–10x more organic sharing than a passive share button.",
        "Make it about the USER, not the app. The card should read as 'this is who I am / what I did' (Wrapped, Nike posters, Gentler's values-identity). Celebration only — never scold rest days or low numbers ('celebration not critique').",
        "Give one HERO visual as identity signature: Strava's route map, Apple's rings, WHOOP's recovery color, Duolingo's flame/owl. A single instantly-legible graphic per card beats a table of numbers.",
        "Build the growth loop INTO the pixels: every outbound image carries a small branded, tappable path back — app handle + QR code or short link (BeReal's bere.al/username watermark, Wrapped's Spotify mark). This is how a share becomes an install.",
        "Offer light/dark/transparent backgrounds so users can overlay the stat card on their own gym selfie or clip (Hevy). Riding on the user's own photo massively increases willingness to post.",
        "Let the user pick which asset to share (Hevy's carousel) — auto-generate a few themed cards (summary, PR, comparison) but don't force an all-or-nothing dump.",
        "Add tasteful, brand-appropriate humor/novelty where it fits (Hevy's 'you lifted a truck') — a delightful comparison is more shareable than a raw kg total."
      ],
      "pitfalls": [
        "Share buttons EVERYWHERE = noise. A share icon on every feed row, list item, and sub-screen dilutes the signal and trains users to ignore it. Reserve prominent share entries for genuine accomplishment moments.",
        "Ugly data-dump cards. If the card is just a screenshot of your stats table (dense numbers, app chrome, no hero visual), nobody posts it. WHOOP/Strong's clinical cards share far less than Wrapped/Duolingo's designed artifacts — invest in the default aesthetic.",
        "Burying the entry in a three-dots / overflow menu on the PRIMARY moment. The finish-workout and milestone screens must have a first-class, visible share action; hiding it behind a menu tanks share rate even when the card is beautiful.",
        "Ignoring privacy of stats. Fitness data is sensitive — route maps reveal home/gym locations, weight/body metrics are personal. Give per-share control (hide precise location, hide bodyweight, choose which metrics appear) and sane defaults; never auto-broadcast.",
        "Wrong aspect ratio / forcing a crop. A card that isn't pre-sized for Stories/TikTok forces the user to crop or reformat — that friction is where most abandoned shares die.",
        "Over-building for a solo dev. Don't ship many bespoke share editors (Nike-style full customizer) you can't maintain; a great auto-default card + native Share sheet gets ~90% of the value at a fraction of the effort. Scope to one card system, reused.",
        "A dedicated share HUB with nothing to celebrate. A 'Wrapped'-style recap surface only works with rich aggregate data and a scarcity/ritual cadence; shipped early or with thin data it sits empty and feels sad. Earn the hub before building it.",
        "Judgmental or shaming content. Surfacing 'you skipped 4 days' or low numbers as shareable kills sharing and hurts retention — Gentler Streak's non-judgmental framing and Wrapped's celebration-only rule exist for this reason.",
        "No loop-back to the app. A card with zero branding/handle/QR gets reshared but drives no installs — you gave away the reach and captured none of the growth. Every share must be able to convert a viewer into a visitor."
      ]
    },
    "current": {
      "shareInfra": "The share pipeline is a 3-layer stack under /Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/, all card-image based (never text/URL — it always shares a rendered PNG).

1) RENDER — ShareImageRenderer.swift (/Users/.../Share/ShareImageRenderer.swift). A single @MainActor enum with `render<Content: View>(width: 390, content) -> UIImage?`. Uses Apple's iOS16+ `ImageRenderer` (not UIHostingController snapshot, which flakes). Frames the card at width 390, forces MasoColor.background so no transparency, sets `renderer.scale = 3.0` → ~1170px-wide crisp output for IG/Twitter/WeChat. Height auto-sizes from the card.

2) TRIGGER + CUSTOMIZE — ShareImageButton.swift (/Users/.../Share/ShareImageButton.swift). This one file holds four pieces:
  - ShareSections (Equatable): 4 bool toggles — todayStatus(photo)/workout/muscleStatus/calendar — for UnifiedShareCard's per-section on/off.
  - ShareCardMode enum: `.editing(Binding<ShareSections>)` for the live preview (draws inline toggles), `.rendering(ShareSections)` for the final image (no toggles, only on-sections drawn).
  - ShareImageButton<ShareContent, Label>: the reusable trigger. Takes previewTitle, defaultSections, optional initialPhoto, a `shareContent: (UIImage?, (()->Void)?, ShareCardMode) -> View` closure (caller builds the card twice — one branch per mode), optional `onPersistPhoto`, and a `shareSurface` string for analytics. Tapping it presents ShareCustomizeSheet.
  - ShareCustomizeSheet: the customize UI. ScrollView with the live card preview (`.editing($sections)`); tapping the card's photo area opens a system confirmationDialog (Take Photo / Choose from Library / Remove) that drives a PhotoPicker via `sheet(item: activePicker)`; `onPersistPhoto` writes the chosen photo back to DataStore (per-session). The "Share" toolbar button calls `renderAndShare()`: it snapshots `sections`, calls ShareImageRenderer.render with `.rendering(snap)` + nil add-photo callback (so no placeholder UI leaks in), then does a PNG round-trip normalization (`img.pngData()` → `UIImage(data:)`) to strip odd colorspace/scale metadata that made UIActivityViewController render a blank preview. The normalized image drives `renderedImage`, which presents ActivityViewController.
  - ActivityViewController: a UIViewControllerRepresentable wrapping UIActivityViewController (system share sheet → AirDrop/Messages/Instagram/etc). Its completionHandler fires `Analytics.shared.track("workout_share", ["surface": shareSurface])` only when the user actually completed a share, then auto-dismisses the whole customize sheet after 0.35s.

3) FOOTER + QR + PHOTO BANNER — ShareCardFooter.swift (/Users/.../Share/ShareCardFooter.swift). Shared by every card. Contains:
  - MasoLinks.appStore = "https://apps.apple.com/app/id6776689750" (the App Store product page; NOTE: memory says the QR 404s until the app is live).
  - SharePhotoBanner: the top 1:1 user-photo banner (photo shown center-cropped; dashed "Add a photo" placeholder in preview mode; EmptyView in render mode). Used by WorkoutDetailShareCard/RoutineShareCard (UnifiedShareCard has its own inline TodayStatus photo section instead).
  - ShareCardFooter: bottom brand strip — MASSO wordmark + "My Personal AI Trainer" tagline on the left, and on the right a REAL QR only when `qrPayload != nil` (drawn via ShareQR). A deliberate design rule: no fake placeholder QR ("scan → nothing" is misleading), so cards without a payload draw no QR.
  - ShareQR: CoreImage `CIFilter.qrCodeGenerator()`, correctionLevel M, nearest-neighbor upscale → crisp black/white UIImage.
  QR PAYLOAD SEMANTICS: today the QR always encodes the App Store download link (MasoLinks.appStore) — RoutineShareCard, WorkoutDetailShareCard, and UnifiedShareCard all pass MasoLinks.appStore. Import-back is handled by OCR of the on-card exercise list (each card lists full exercise names + "N × M · W kg" in an OCR-friendly format), NOT the QR anymore (the codebase comments note the QR used to carry a maso:// deep-linked Plan via PlanShareCodec, but was switched to the App Store link).",
      "cardTypes": [],
      "existingEntries": [],
      "progressShareToday": "placeholder",
      "shareableSurfaces": []
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
      "agentId": "a5b1810495d8cb972",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1783060261826,
      "queuedAt": 1783060261819,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "Use a MIX, but anchor on the PER-OBJECT (per-card / per-det…",
      "promptPreview": "You are a growth/product analyst. Research how leading fitness & consumer apps do "SHARE OUT" of stats/achievements/cards, to inform an app-wide share strategy for a solo fitness app. Use WebSearch/WebFetch (load via ToolSearch) + your own knowledge (through early 2026).

Cover: Strava (activity/segment/achievement share cards + the share flow), WHOOP (weekly performance / recovery share), Apple F…",
      "lastProgressAt": 1783060468710,
      "tokens": 52417,
      "toolCalls": 17,
      "durationMs": 206884,
      "resultPreview": "{"apps":[{"name":"Strava","shareable":"Individual activity (run/ride) with distance, pace, time and a mini route map; segment achievements (KOM/QOM, PRs, top-10s); the route map itself. Cards auto-generate stats+map; users can also drop the stat sticker over their own photo.","entryPattern":"Per-item share icon. A share icon lives on each activity — both inline in the feed and on the activity deta…"
    },
    {
      "type": "workflow_agent",
      "index": 2,
      "label": "research:current",
      "phaseIndex": 1,
      "phaseTitle": "Research",
      "agentId": "a2c5d49da5c69750b",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1783060261833,
      "queuedAt": 1783060261819,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "The share pipeline is a 3-layer stack under /Users/yumowu/P…",
      "promptPreview": "Inventory the Maso iOS app's CURRENT share infrastructure + every surface that could be shared, at /Users/yumowu/Projects/Maso-iOS. Read the real files (share family lives in Maso/Views/Components/Share/ — ShareImageRenderer / ShareImageButton / ShareCustomizeSheet, plus UnifiedShareCard / WorkoutDetailShareCard / RoutineShareCard). Report:
- shareInfra: how the share pipeline works — ShareImageRe…",
      "lastProgressAt": 1783060395690,
      "tokens": 147183,
      "toolCalls": 25,
      "durationMs": 133857,
      "resultPreview": "{"shareInfra":"The share pipeline is a 3-layer stack under /Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/Share/, all card-image based (never text/URL — it always shares a rendered PNG).\
\
1) RENDER — ShareImageRenderer.swift (/Users/.../Share/ShareImageRenderer.swift). A single @MainActor enum with `render<Content: View>(width: 390, content) -> UIImage?`. Uses Apple's iOS16+ `ImageRendere…"
    },
    {
      "type": "workflow_agent",
      "index": 3,
      "label": "synthesize:design",
      "phaseIndex": 2,
      "phaseTitle": "Synthesize",
      "agentId": "ac722f0090c5076ea",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1783060468713,
      "queuedAt": 1783060468712,
      "attempt": 1,
      "lastToolName": "Bash",
      "lastToolSummary": "cd /Users/yumowu/Projects/Maso-iOS/Maso && grep -rn "func s…",
      "promptPreview": "Design an app-wide "SHARE OUT" architecture for the Maso iOS app (SwiftUI, solo indie fitness app with a live paywall; already has a share-card pipeline). The owner wants MANY things in the app to be shareable as beautiful share-out cards (Strava/Wrapped style), and specifically: (1) the new AI training-data interpretation (AI Insight Summary) should be shareable; (2) the Progress tab's share butt…",
      "lastProgressAt": 1783060615902,
      "tokens": 127778,
      "toolCalls": 10,
      "durationMs": 147188,
      "resultPreview": "I have everything needed. Here is the design doc.

---

# Maso "SHARE OUT" Architecture — Design Doc (for approval)

**Scope:** app-wide shareable share-out cards, anchored to the existing 3-layer pipeline in `Maso/Views/Components/Share/`. Grounded in real symbols: `ShareImageRenderer`, `ShareImageButton`, `ShareCustomizeSheet`, `ShareCardFooter`/`ShareQR`, `UnifiedShareCard`, `AISummaryCard`, `H…"
    }
  ],
  "totalTokens": 327378,
  "totalToolCalls": 52
