# Maso Routines — Training Preferences card + "Tune with AI" redesign

Design doc, grounded in real symbols. Targets: `PlansScreen.swift`, a new `PreferencesSheet`, `DataStore` coach-note helpers, `AISummaryCard`-parity styling.

---

## 0. Design thesis (from MARKET)

The winning pattern across ChatGPT Memory, Gemini Saved-info, and Fitbod is: **entry is a summonable pill, memory is discrete deletable items, and "manage what the AI knows" collapses into "edit your training profile."** Maso already has both halves — `TrainingSettingsSection` (the structured profile the AI consumes) and `coachMemory` (the free-text long-tail). Today they're a wall of inputs (`TextEditor` + an always-open `refineComposer`). The redesign hides both behind one lightweight entry, and re-presents `coachMemory`'s `"- bullet"` string as **deletable chips** (the ChatGPT-memory gold standard). No new source of truth — the chips *are* `settings.coachMemory`, parsed.

---

## 1. Restyled card (goal A) — `PlanRationaleCard` mimics `AISummaryCard`

`AISummaryCard` (`Maso/Views/Components/AISummaryCard.swift`) is the style target. Its DNA:

| Element | AISummaryCard spec |
|---|---|
| Shell | `.cardChrome()` — `padding(14)` + `.background(MasoColor.surface)` (#191919 **filled**, not outlined) + `.clipShape(RoundedRectangle(cornerRadius: cornerRadiusMedium=16))` |
| Header | `HStack(spacing: 8)`: `Image("sparkles")` size 12 `.bold` `accent` + `Text` size 14 `.bold` `MasoColor.text` + `Spacer()` + trailing icon button (`arrow.clockwise`, size 13 `.semibold`, `textDim`) |
| Body row | `recommendationRow`: leading `chevron.forward.circle.fill` size 13 `.bold` `accent`, title size 13 `.semibold` `text`, detail size 12 `textDim`, `.padding(.vertical, 6)`, top `Rectangle().fill(borderSoft).frame(height: 0.5)` hairline |
| Footer | size 11 `textFaint` "As of …" |

**Restyle `PlanRationaleCard` (`PlansScreen.swift` 568–656) to match:**

1. **Kill the outlined "hero" shell.** Drop the `.overlay(RoundedRectangle…stroke(borderHero…))` + `cardPadding` (20/18) treatment. Adopt `AISummaryCard`'s exact chrome: `padding(14)` + filled `MasoColor.surface` + `cornerRadiusMedium`. (Factor `cardChrome()` out of `AISummaryCard.swift`'s `private extension View` into a shared file so both cards call it — see Build plan.)

2. **Header row → sparkles + bold title.** Replace the current `figure.run` size-10 `.heavy` tracked kicker with the AISummary header idiom:
   - `Image(systemName: "slider.horizontal.3")` size 12 `.bold` `accent` (a preferences glyph; keep `sparkles` reserved for the AI-generated summary card so the two cards read as siblings, not twins). Title `Text("Training Preferences")` size **14 `.bold`** `MasoColor.text` (not the tracked all-caps kicker).
   - Trailing: replace the `chevron.right` 30×30 button with an `arrow.clockwise`-style affordance? No — this card's trailing action is *edit the structured profile*, so keep a `chevron.right` size 13 `.semibold` `textDim` (matches AISummary's trailing-icon weight/color). Whole header still `onTapGesture { showEditor = true }`.

3. **At-rest body = skimmable summary rows, not the one-liner + inline composer.** Today `prefSummary` is one gray `" · "`-joined string and `composer()` (the inline `refineComposer`) sits right under it. Replace with:
   - **Keep `prefSummary` as a single compact line** (size 12 `textDim`, `fixedSize(vertical)`) directly under the header — it's the skimmable "here's your profile" glance. This is fine as one line; it's a *summary*, not the editable surface.
   - **Remove `composer()` from the card entirely.** The inline `refineComposer` is deleted from this card (it moves into the sheet, §3d). The `Composer` generic slot on `PlanRationaleCard` is removed — the card no longer needs to be generic.
   - **Add the lightweight entry pill** (§2) as the last row of the card, replacing where the composer was.

Result at rest — three stacked elements, all skimmable:
```
[◧ slider] Training Preferences                    ›
3 days / week · Build muscle · 4 exercises · Dumbbells · Focus: Chest, Back
[ ✨ Tune with AI ]   ← pill, §2
```

---

## 2. The lightweight entry (B1)

**Affordance:** a single accent-tinted **pill button**, left-aligned, as the bottom row of the card:

```
Image("sparkles") size 12 .bold  +  Text("Tune with AI") size 13 .semibold
foreground: MasoColor.accent
padding: .horizontal 12, .vertical 8
background: Capsule().fill(MasoColor.accent.opacity(0.14))
overlay:    Capsule().stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5)
```

This is the exact "selected chip" idiom already in the codebase (`AddExerciseSheets.swift` 159–163: `accent.opacity(0.16)` fill + `accent.opacity(0.35)` stroke) — reuse it so it reads native. It sits **below** `prefSummary`, `Spacer()`-pushed to leading (pill hugs its content via intrinsic width, do **not** `maxWidth: .infinity`).

**Why a pill, not a field (MARKET):** "Lightweight, summonable ENTRY — never an always-open field." A tappable chip that opens a sheet on demand is the ChatGPT "Manage memories" link pattern; the always-open `refineComposer` is exactly the "always-open field cluttering the primary UI" pitfall.

**Pro-gated behavior:** the *entry* is always tappable (opening the sheet to *view* what the AI knows is free and builds trust — MARKET: locked teasers still show TL;DR). The **write actions inside the sheet** (send a tune / add-suggested-chip that triggers regenerate) carry the Pro gate, mirroring today's `sendRefine()` `guard data.settings.isPro else { paywallPresented = true; return }`. So: tap pill → sheet opens (free, read-only browse of profile + notes); tap Send / add / regenerate → if `!isPro`, dismiss-or-inline `paywallPresented = true`. Deleting a chip should be **free** even for non-Pro (users must always be able to prune what's stored — MARKET: "every stored item must be individually removable").

Header chevron and header tap still open the **structured editor** (`TrainingPreferencesSheet`, unchanged behavior). Two doors, cleanly labeled — Gemini's "facts I told it" vs "settings I set" separation:
- Header / chevron → structured prefs sheet (days/goal/equipment — the pickers).
- Pill → the new **Coaching sheet** (notes as chips + tune input). See §3.

*(Decision: keep them as two entries rather than merging into one sheet. The structured `TrainingPreferencesSheet` already exists, works, and ends in a "Generate routines" CTA. Overloading it with chip-management would bloat it. The new sheet is specifically the memory/tune surface.)*

---

## 3. The manage-your-preferences sheet (B2/B3/B4) — new `CoachingPreferencesSheet`

A new private view in `PlansScreen.swift` (or its own file `Maso/Views/Components/CoachingPreferencesSheet.swift`), presented from the pill via `.sheet(isPresented: $showCoaching)`, `.presentationDetents([.large])`, drag indicator, nav title **"Coaching"**, top-left **Done**. `ScrollView` body, `VStack(alignment: .leading, spacing: 20)`.

### (a) Header — "what the AI uses"

Honest-use framing (MARKET best practice #7). A short block at top:
```
Image("sparkles") accent size 12 .bold + Text("What your AI coach knows") size 14 .bold text
Text("Your plans are built from your training profile below, plus the notes you add here. Edit or remove anything anytime.") size 12 textDim
```

### (b) Structured prefs — compact, reuse `TrainingSettingsSection`

MARKET: "collapse 'manage what the AI knows' into 'edit your training profile.'" Don't duplicate the pickers here — show a **compact read-only glance + one edit affordance** that jumps to the existing structured editor:

- A single row: leading `slider.horizontal.3` accent, `Text("Training profile")` size 13 `.semibold`, then `prefSummary` reused as a size-12 `textDim` second line, trailing `chevron.right` `textDim`. Wrapped in a `Button` → sets `showEditor = true` to present the **existing `TrainingPreferencesSheet`** (which wraps `TrainingSettingsSection()` and ends in the "Generate routines" CTA). Zero new structured-prefs code; it's a launcher.

*(This keeps a single source for the pickers — `TrainingSettingsSection` — exactly as the CURRENT notes say it's shared across Settings + both sheets.)*

Hairline `Rectangle().fill(borderSoft).frame(height:0.5)` divider below.

### (c) Coaching Memory as **deletable chips** (the core)

This is the ChatGPT-memory surface. Header:
```
Image("brain.head.profile") accent size 11 .heavy + Text("Coaching notes") size 12 .bold tracking 0.5
Spacer + [Clear all] size 12 .semibold textDim   ← only when non-empty; confirm alert
```
(Mirrors the existing `coachMemorySection` kicker in `TrainingSettingsSection.swift` 262–311 — same icon, same "Clear" affordance — but the `TextEditor` is replaced by chips.)

**Chips:** a `FlowLayout` (already defined in `OnboardingScreen.swift`, reused app-wide per CLAUDE.md — "全 app 复用, 勿移") of removable chips, one per parsed bullet:
```
HStack(spacing: 6):
  Text(noteText) size 13 text, lineLimit 2
  Image("xmark") size 9 .bold textDim   ← tap target = whole chip's trailing 28pt
padding .horizontal 12 .vertical 8
background Capsule().fill(MasoColor.surfaceHi)   (#262626)
overlay    Capsule().stroke(borderSoft, lineWidth 0.5)
```
Tapping the ✕ removes **that** bullet from `coachMemory` and persists (§4). Delete-only, no inline text edit (MARKET: "delete-and-re-teach is simpler … text-edit-only correction with no delete is fiddly"). Full-width notes that would be awkward as short chips still render fine with `lineLimit(2)` + `fixedSize(vertical)`; chips can be tall.

**Empty state:** if no notes, show a faint one-liner instead of an empty flow: size 12 `textFaint` — *"No notes yet. Tell your coach a preference below — e.g. 'bad shoulder, no overhead'."*

**Data mapping (exact):**
- `coachMemory: String` → `[CoachNote]` where each line is split on `\
`, trimmed, leading `"- "` stripped, empty lines dropped. Index-stable `id` = array index (or a hash of text) so ForEach is stable within a render.
- Delete note at index `i` → rebuild the string from the array minus `i`, each re-prefixed `"- "`, joined `"\
"`, write back to `settings.coachMemory`, `save()`. New DataStore helpers, §5.

### (d) Lightweight ADD — the tune input, relocated here

The old `refineComposer` moves here, at the **bottom of the sheet** (thumb-reachable), as a `safeAreaInset(edge: .bottom)` so it's pinned while the chip list scrolls. Same construction as today's `refineComposer` (`PlansScreen.swift` 206–243): multi-line `TextField` (`axis: .vertical`, `lineLimit(1...4)`, size 14) in `surface` fill + `borderSoft` stroke corner 16, + circular `arrow.up` send button (36×36, `accent` when `canRefine` else `surfaceHi`). Placeholder unchanged: *"Tell the AI a preference or change in plain words — e.g. 'bad shoulder, no overhead'. It remembers."* Keep the URL hint conditional.

**Suggested-chip adders (habit-friendly, MARKET #6):** above the text field, a small row of tappable "Add:" chips for the common long-tail that isn't in the structured pickers, e.g. *"Add: bad knee"*, *"Add: hate burpees"*, *"Add: train early mornings"*, *"Add: home gym only"*. Tap → same as sending that text (`appendCoachNote` + optional regenerate). Style = the accent entry-pill from §2 (accent.opacity(0.14) fill). These make growing the profile a tap, not typing.

### (e) AISummary recommendation points as interactive chips (optional, phase 2)

MARKET (e): surface previously-summarized points and let the user interact. `AISummaryCard` already produces `AIRecommendation`s with an `.addCoachNote` action and an "Add to notes" apply button (`AISummaryCard.swift` 278–279). Surface the same `data.cachedSummary?.recommendations` here as a **"Suggested from your data"** row of chips: each chip = the rec's `title`, tapping "adds to preferences" → `appendCoachNote(rec.detail or title)` (same path as the AISummary "Add to notes" button), then the chip animates into the Coaching-notes flow above. A dismiss ✕ just hides it for the session. This closes the loop: the coach's own observations become one-tap standing preferences. **Defer to v1.1** — v1 ships (a)–(d); the cached summary may be nil on the Routines tab and wiring it is extra surface. Flag as a fast-follow.

---

## 4. Interaction & flow

**Send a tune (text field or suggested-add chip):** preserve today's exact dual behavior from `sendRefine()`:
1. Pro gate first (`guard isPro else paywall`).
2. `data.appendCoachNote(text)` — persists the bullet (a new chip appears in §3c with a spring insert + `Haptics.tap()`).
3. `startGenerateRoutines(focusNote: text, surface: "tune")` — immediate regenerate driven by that sentence (the existing focusNote path stays intact).
4. Analytics `tune_with_ai_send` unchanged.

So: **typed tune = append note + regenerate now.** This is the strong "moment of learning is visible" pattern — the note becomes a chip *and* the plan updates, matching ChatGPT's ambient "Memory updated" confirmation.

**Add via suggested chip (§3d):** same as send — append + regenerate. (Decision: suggested chips regenerate too, because they express a real constraint the user wants reflected. If perf/token cost is a worry, downgrade to append-only + a subtle "Regenerate" affordance; but default = regenerate for the "it just learned X" payoff.)

**Delete a chip (§3c):** remove bullet + `save()` only. **Do NOT auto-regenerate** on delete — deletion is pruning, often batched; regenerating on every ✕ is jarring and token-wasteful. Instead, when the notes set has changed since the sheet opened, show a small footer affordance *"Notes changed — regenerate routines"* (accent capsule, the §2 pill style) that the user taps once to apply, calling `startGenerateRoutines(focusNote: nil, surface: "coaching_edit")`. Undo: after a delete, a brief inline "Removed · Undo" (size 12, 4s) that re-inserts the bullet — cheap trust win (MARKET: reversible in-context).

**Clear all:** confirm alert ("Clear all coaching notes?"), then `settings.coachMemory = ""` + `save()` (matches existing `coachMemorySection` Clear). Offer the same "regenerate" footer after.

**Empty states:** covered in §3c (notes) and §3b (structured always has values). Non-Pro: sheet fully browsable; text field + send + suggested-adds route to paywall; delete/clear stay free.

**No regenerate on structured edits from here** — those go through `TrainingPreferencesSheet`'s own "Generate routines" CTA, unchanged.

---

## 5. Data model changes

**Recommendation: no schema change for v1.** Keep `coachMemory: String` of `"- bullet"` lines. Add three thin helpers to `DataStore` (next to `appendCoachNote`, DataStore.swift ~122):

```swift
/// Parse coachMemory into display lines (leading "- " stripped, empties dropped).
var coachNotes: [String] {
    settings.coachMemory
        .split(separator: "\
", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
        .filter { !$0.isEmpty }
}

/// Remove the note at display index; rebuild + save.
func removeCoachNote(at index: Int) {
    var notes = coachNotes
    guard notes.indices.contains(index) else { return }
    notes.remove(at: index)
    settings.coachMemory = notes.map { "- \\($0)" }.joined(separator: "\
")
    Analytics.shared.track("coach_note_delete", ["note_count": .int(notes.count)])
    save()
}

func clearCoachNotes() { settings.coachMemory = ""; save() }   // or reuse existing Clear
```

`appendCoachNote` is reused as-is (its consecutive-dedupe is fine).

**Is a richer model (array of `{id, text, createdAt}`) worth it?** Not for v1. The string is already the single source of truth injected into generation (`buildAIPayload` → `coachMemoryBlock`, capped to last ~1200 chars). A struct array would mean a migration + changing that injection path for zero user-visible gain — index-based delete on the parsed array is sufficient because edits happen one sheet-session at a time. **Only** revisit if v1.1 wants per-note provenance ("added by you" vs "from AI summary") or timestamps for the ~1200-char recency cap — then a `[CoachNote]` with `Codable` migration from the legacy string is clean. Note it as a future option, don't build it now.

---

## 6. Build plan (ordered)

Concurrency note: **PlansScreen.swift is being edited in parallel for a frosted-header change.** Keep this work surgical and away from the header/scroll region: touch only `PlanRationaleCard` (568–656), the `refineComposer`/`sendRefine` block (206–266), and `aiPage` wiring (183–199). Land the *new* sheet as its **own file** so it doesn't collide, and prefer additive edits over reflowing existing lines. Rebase-friendly.

1. **Extract shared card chrome.** Move `cardChrome()` out of the `private extension View` at the bottom of `AISummaryCard.swift` (301–309) into a shared file (e.g. `Maso/Theme/CardChrome.swift`) as `internal`. Verify `AISummaryCard` still compiles.

2. **New file `Maso/Views/Components/CoachingPreferencesSheet.swift`** — the §3 sheet: header, structured-profile launcher row, chip flow (reuse `FlowLayout`), pinned bottom composer (port `refineComposer` + `canRefine` + URL hint), suggested-add chips, all wired to new DataStore helpers. Owns `@State showEditor` for the nested structured sheet and `@State refineInput`.

3. **DataStore helpers** (§5): `coachNotes`, `removeCoachNote(at:)`, `clearCoachNotes` (or reuse Clear) in `DataStore.swift` near `appendCoachNote`. Add `coach_note_delete` analytics.

4. **Restyle `PlanRationaleCard`** (`PlansScreen.swift` 568–656): swap shell to `cardChrome()`; header → `slider.horizontal.3` + size-14 bold title + `chevron.right`; keep `prefSummary`; **remove the `Composer` generic + `composer()` call**; add the §2 "Tune with AI" pill (accent.opacity 0.14 capsule) whose action sets a new `@State showCoaching = true`.

5. **Wire `aiPage`** (`PlansScreen.swift` 183–199): drop the trailing-closure `{ refineComposer }` from the `PlanRationaleCard(...)` call (no longer generic). Add `.sheet(isPresented: $showCoaching) { CoachingPreferencesSheet(...) }` passing the Pro gate + `startGenerateRoutines` + `paywallPresented` bindings. Keep the existing `.sheet($showEditor) { TrainingPreferencesSheet(...) }` for the structured door.

6. **Delete dead code:** the inline `refineComposer` / `canRefine` / `sendRefine` / `containsURL` from `PlansScreen` **once ported** into the sheet (or keep them on `PlansScreen` and have the sheet call back — simpler for the parallel-edit risk is to leave `sendRefine` on `PlansScreen` and pass it into the sheet as a closure, so the Pro-gate + regenerate logic stays in one place). **Recommend: pass `onSend: (String) -> Void` and `onDelete: (Int) -> Void` closures into the sheet; keep the gate/regenerate logic in `PlansScreen`.** Minimizes what moves.

7. **Localizable.strings (en + zh-Hans):** new keys — "Tune with AI"/"用 AI 调整", "Coaching"/"教练", "What your AI coach knows"/…, the honest-use subtitle, "Training profile", "Coaching notes" (exists), "Clear all", suggested-add chip labels, "Removed"/"Undo", "Notes changed — regenerate routines". Reuse existing placeholder + "Clear" keys.

8. **Verify:** simulator build + run the `verify-app` smoke skill (exercises.json 938, 4 showcase pages distinct), then per user preference auto-run `./scripts/install_iphone.sh` after build verify. Manually check: pill opens sheet; chips render from a seeded multi-line `coachMemory`; ✕ removes + persists (kill/relaunch survives); Send appends chip + regenerates; non-Pro Send → paywall, delete still works.

**Files touched:** `AISummaryCard.swift` (extract), new `CoachingPreferencesSheet.swift`, `DataStore.swift` (helpers), `PlansScreen.swift` (card restyle + wiring, surgical), `Localizable.strings` ×2. No `project.yml` change unless the new file needs registering — it does: add `CoachingPreferencesSheet.swift` under the Maso target sources and `xcodegen generate` (per CLAUDE.md, new .swift files go through project.yml).",
    "market": {
      "apps": [
        {
          "name": "ChatGPT Memory (OpenAI)",
          "memoryFeature": "Two layers: (1) 'Saved memories' — discrete, user-inspectable facts the model chose to store ('User is training for a marathon in October'); (2) 'Reference chat history' — an opaque, always-on synthesis of all past chats with no item list. The gold-standard editable surface is the Saved-memories list. As of GPT-5.5 (late 2025) responses that use a memory now show an inline 'Sources' section citing which stored fact was pulled, with a per-source 'Make a correction' action.",
          "entryPattern": "Two entry points, deliberately lightweight. (1) Ambient: a small 'Memory updated' chip/pill appears inline in the chat the moment ChatGPT saves something — tappable to review, so you never have to go hunting. (2) Deep: Settings > Personalization > Manage memories opens a sheet/modal. Entry is a link, not an always-open field — memory management stays out of the way until you summon it.",
          "editPattern": "'Manage memories' opens a scrollable modal where each memory is ONE discrete row of plain-English text with a trash icon on the right. Delete is per-row, one tap + confirm. No inline editing of a row's text (you delete and re-teach), which keeps rows read-only-simple. A 'Clear ChatGPT's memory' button sits at the bottom of the list for nuke-all. Newer inline path: under an answer, three-dot menu on a cited source > 'Make a correction' edits the fact without leaving the chat.",
          "addPattern": "Almost entirely implicit — you just talk ('I'm vegetarian', 'remember I lift on Mon/Wed/Fri') and the model decides to save it, confirming via the 'Memory updated' chip. You can also explicitly command 'Remember that…'. There is NO free-text box to type a memory directly into the list; adding is conversational, removing is UI. You can undo a bad save inline with 'Forget that'.",
          "notes": "The canonical reference design. Key wins: (a) the ambient save-confirmation chip makes an invisible action visible and reversible in-context; (b) memories are discrete human-readable sentences, not a JSON blob; (c) entry is a summonable link, never an open form. Key criticism (Simon Willison, May 2025): the opaque 'reference chat history' layer feels like a creepy hidden dossier precisely because it's NOT shown as editable items — reinforcing that the *inspectable list* is what earns trust. Also: turning memory off does not delete existing memories, a subtle trust gap."
        },
        {
          "name": "Claude Memory / Projects (Anthropic)",
          "memoryFeature": "Account-level memory (rolled out to all users March 2026) plus project-scoped memory — each Project keeps its own separate memory so work contexts don't bleed together. Claude distills long-term-worthy facts (profession, tools, recurring context, working style) roughly every 24h rather than saving instantly per message. Users get a full view-and-edit surface of what's stored.",
          "entryPattern": "Settings > Memory in claude.ai. Plus 'Incognito chat' as a first-class, always-available toggle at the point of conversation for chats that must NOT touch memory — entry to *not being remembered* is as easy as entry to reviewing memory. Project memory is reached from inside each Project.",
          "editPattern": "Settings > Memory shows the stored memory which you can view, edit, and delete individual items or clear everything. Because synthesis is batched (~24h) rather than a live chip on every message, the edit surface is the settings view rather than an inline per-message affordance — quieter than ChatGPT's chip, at the cost of less immediate 'it just learned X' feedback.",
          "addPattern": "Implicit/automatic from conversations; users steer by talking and by editing/deleting after the fact. Project instructions and Project knowledge act as an explicit, structured 'here's what you should know' field that complements the auto-memory. No suggested-chip adder.",
          "notes": "Two design lessons for fitness: (1) SCOPED memory (per-project) maps cleanly to a fitness app's 'this plan / this goal-block' — memory tied to a context is less creepy than one global blob. (2) Incognito-as-a-peer-to-memory is a strong trust signal: give users an obvious 'don't remember this session' escape hatch. Downside vs ChatGPT: no ambient save chip means the moment-of-learning is less transparent."
        },
        {
          "name": "Google Gemini 'Saved info' + Personal Intelligence",
          "memoryFeature": "'Saved info' = an explicit long-term-memory store of user-authored facts and standing instructions (name, profession, hobbies, dietary prefs, how-I-like-answers, ongoing projects). Separate 'Personal Intelligence' layer connects Google apps (Gmail, Photos, etc.) as an implicit context source. Clean separation between what YOU wrote (Saved info) and what it INFERRED from your data (connected apps).",
          "entryPattern": "A dedicated destination — gemini.google.com/saved-info — reachable from Settings > Personalization. App connections are a separate, explicit opt-in surface (off by default; you pick each app). So there are two clearly labeled doors: 'facts I told it' vs 'data sources I connected'.",
          "editPattern": "Saved info is a managed list of individual entries you can view, edit, and delete one by one — closest to a true CRUD list (you can edit an item's text, not just delete it). Connected apps are managed as per-app on/off toggles, and Gemini tries to cite which source it used so you can verify. Correcting an inferred fact is done by telling Gemini in-chat with Memory on.",
          "addPattern": "The most explicit ADD of the group: an 'Add' affordance lets you type a new fact/instruction directly into the Saved-info list — a genuine free-text entry box, not just conversational capture. This makes the list feel like a settings panel you author, complementing implicit learning.",
          "notes": "Best model for a fitness app that wants a USER-AUTHORED profile: Gemini proves that an explicit 'type a fact and it's saved' list can coexist with implicit learning without feeling like a chore, *if* it's a summonable page rather than a wall you face on every screen. The app-connection toggles are a good template for 'the AI uses your workout log / Apple Health — here's the switch and here's what it pulls.' Off-by-default connections = strong consent framing."
        },
        {
          "name": "Notion AI",
          "memoryFeature": "No consumer-style personal 'memory dossier.' Personalization is workspace-context-driven: Notion AI reads the pages, databases, and docs you point it at, plus optional connected sources (Slack, Drive, etc.). 'What the AI knows' = your workspace content + custom instructions, not a list of remembered facts about you as a person.",
          "entryPattern": "Two surfaces: (1) admin/workspace-level connectors and AI settings (which sources AI may read); (2) at point-of-use, an @-mention / context picker where you scope exactly which pages the AI should consider for THIS task. Context is chosen per-invocation rather than persistently remembered.",
          "editPattern": "You 'edit what it knows' by editing the underlying pages/databases (single source of truth) and by toggling which connectors are enabled. There is no separate memory list to prune — the content IS the memory. Custom AI instructions are an editable text field.",
          "addPattern": "Add knowledge = create/edit a page or connect a source; add behavior = write a custom instruction. Explicit and structured; nothing implicit or chip-based.",
          "notes": "The 'content is the memory, no separate dossier' philosophy is relevant if the fitness app already HAS structured user data (logged workouts, equipment, goals). Rather than a parallel memory blob, the AI can be framed as reading your existing profile + logs — which the user already edits — so 'manage what the AI knows' collapses into 'edit your profile', minimizing a whole extra surface. Trust comes from 'it only reads what I gave it', not from a memory-management UI."
        },
        {
          "name": "Perplexity",
          "memoryFeature": "Lighter memory than the chatbots. Personalization centers on an 'AI Profile' / 'Introduce yourself' free-text field (tell it about you, your interests, how to answer) plus optional memory that references prior threads for continuity. Spaces (collections) act as scoped context with their own instructions/sources.",
          "entryPattern": "Settings > Account/Personalization for the AI Profile field; Spaces are entered from the sidebar and carry their own context. Entry is a settings page, not ambient — there's no in-answer 'memory saved' chip in the ChatGPT sense.",
          "editPattern": "The AI Profile is a single editable free-text box (edit the text, save). Memory/history can be toggled and cleared. Space instructions and attached sources are editable per Space. Less granular than ChatGPT's per-item rows — it's a paragraph you own rather than a list of atomized facts.",
          "addPattern": "Primarily one free-text box you author ('Introduce yourself'), plus per-Space instructions. Implicit thread-continuity memory can be turned on. No suggested chips.",
          "notes": "Represents the 'single free-text self-description' end of the spectrum — lowest-friction to set up, but least transparent about WHICH fact drove a given answer (no per-item list, no citation of the used memory). Good lesson: a short free-text 'about me' is a fine MVP, but pair it with structured, deletable items if you want users to feel in control of granular things (an injury, a disliked exercise)."
        },
        {
          "name": "Replika",
          "memoryFeature": "Persistent companion memory: stores personal facts, tracks mood, remembers milestones/past conversations. Surfaces via a 'Memory' / diary + facts area and a Persona/backstory the user can edit. Learns continuously and mostly automatically.",
          "entryPattern": "Reached from the companion's profile / Memory tab — a dedicated section, not ambient chips during chat. Diary entries are generated and browsable; the facts area lists things it 'knows'.",
          "editPattern": "Memory/diary functions let users review and correct what the companion remembers, and edit persona facts. But critics note the memory is largely automatic and somewhat OPAQUE — users don't get a fully transparent, prune-every-item wheel the way Kindroid/Gemini give; correction is possible but the mechanism is partly hidden.",
          "addPattern": "Mostly implicit (learns as you chat) plus explicit persona/backstory fields you write. Free-text persona editing; facts accrue automatically.",
          "notes": "Cautionary case for a fitness app: emotionally 'sticky' automatic memory drives attachment but the opacity ('keeps the wheel hidden') is exactly the creepiness pitfall. Take the persistence, reject the opacity — always show the discrete items and make correction obvious. Relevant emotional lesson: 'it remembers my milestones' is a retention lever, but only feels good when the user believes they could delete any item."
        },
        {
          "name": "Character.AI ('About You' persona)",
          "memoryFeature": "Notably does NOT persist true cross-session memory of the user by default. Personalization is via a user-authored Persona ('About You') and per-character Pinned memories / character definition — notes YOU write for the AI to read, rather than facts it independently remembers. Some pinned-memory features let you force-keep specific facts.",
          "entryPattern": "Persona is set in settings/profile; pinned memories and character notes are attached from the chat/character screen. Entry is explicit authoring surfaces, no ambient save chip.",
          "editPattern": "Persona and pinned memories are directly editable text you own — fully transparent because YOU wrote every word; nothing hidden accrues. Pinned items can be removed. The tradeoff: because the AI 'reads your notes' rather than 'remembers you', continuity is weak and maintenance is manual.",
          "addPattern": "100% explicit free-text: write your Persona, pin a memory. No implicit capture, no suggested chips.",
          "notes": "The pure 'user writes notes the AI reads' model — maximally transparent, zero creepiness, but high friction and weak continuity (open a new chat, it's forgotten). Lesson for fitness: fully manual authoring is great for TRUST but bad for HABIT — users won't keep a profile current by hand. The sweet spot is auto-capture (ChatGPT-style) presented as discrete, user-owned, deletable items (Character-style transparency)."
        },
        {
          "name": "Fitbod (fitness — implicit AI profile via structured settings)",
          "memoryFeature": "No 'AI memory list' UI — instead a structured, editable profile is the AI's memory: available equipment, workout goal, experience level, session length, and a live 'muscle recovery state' derived from your logged sessions. The recommendation engine reads these fields directly. 'What the AI knows about you' = your explicit settings + your workout log.",
          "entryPattern": "Standard Settings / profile screens and a fast 'gym mode ↔ home mode' equipment toggle right where it matters. Equipment-aware substitutions and travel mode are reachable inline without re-onboarding. No memory-management sheet because there's no separate memory to manage.",
          "editPattern": "Structured controls: equipment as a selectable/deselectable set (chip-like on/off), goal and experience as pickers, session length as a value. The muscle-recovery model is auto-computed and shown as a body-map visualization the user reads (and implicitly edits by logging). Everything the AI uses is a real, tweakable setting.",
          "addPattern": "Explicit and structured — add equipment by selecting it, change a goal via picker. Implicit signal (fatigue) is added automatically by logging workouts. No free-text 'tell the AI about you' box.",
          "notes": "Most directly relevant to the user's app. Proves the strongest fitness pattern: don't build a chatbot-style memory dossier — expose the exact structured fields the AI consumes (equipment, goals, injuries/restrictions, defaults) as normal editable settings, so 'manage what the AI knows' == 'edit your training preferences'. The muscle-recovery body map is a great model for making an AUTO-derived signal transparent and legible without asking the user to manage it. Gap: no free-text escape hatch for the weird stuff (a nagging shoulder, 'I hate burpees') — which is exactly where a lightweight ChatGPT-style deletable-chip layer would complement the structured fields."
        },
        {
          "name": "WHOOP / Oura + AI coach layer (fitness — wearable-derived context)",
          "memoryFeature": "The 'memory' is auto-synced biometric context (HRV, sleep stages, strain/recovery, training load) that an AI coach layer reads to modify plans in real time. Increasingly paired with a chat coach (WHOOP Coach) that also holds some conversational profile of goals.",
          "entryPattern": "Data-source connections via OAuth (Strava/Garmin/Oura/WHOOP) managed in settings, plus per-metric visibility on dashboards. The 'what it knows' is surfaced as daily scores/insights rather than an editable fact list.",
          "editPattern": "Users manage which sources are connected (toggles) and can enter context (goals, whether they're sick/injured) that overrides the auto-signal. The biometric facts themselves aren't 'edited' — they're measured — but the user can correct interpretation ('I'm not fatigued, that was a late night').",
          "addPattern": "Mostly automatic ingestion; explicit additions are goal-setting and situational flags ('feeling sore', 'traveling'). Some coaches let you tell the chat coach standing preferences.",
          "notes": "Reinforces the consent-toggle pattern (Gemini-style) for data the AI pulls, and the idea that AUTO signals need a user override, not just display. For the fitness app: if the AI leans on Apple Health / logged data, show a plain 'the AI uses: your workout history, equipment, and goals' line with per-source toggles, and let users add corrective free-text ('bad knee — avoid deep squats') that visibly outranks the inferred data."
        }
      ],
      "bestPractices": [
        "Lightweight, summonable ENTRY — never an always-open field. The winning pattern is a small chip/link/toast (ChatGPT's 'Memory updated' pill; a 'What the AI knows' link in settings) that opens a sheet on demand. The memory surface should be invisible until summoned, so the main flow stays clean.",
        "Show memory as DISCRETE, human-readable items — one short plain-English sentence per row/chip — not a paragraph blob or JSON. Atomized items are what let users trust and prune granularly ('avoid overhead press — shoulder', 'trains Mon/Wed/Fri'). This is the single biggest driver of the 'transparent + controllable' feeling.",
        "Make the moment of learning VISIBLE and reversible in-context. ChatGPT's ambient 'Memory updated' chip + inline 'Forget that' is the gold standard: the user sees exactly what was captured the instant it happens and can undo it without opening settings. For a fitness app, a small 'Saved: prefers dumbbells' toast after onboarding answers or a chat reply.",
        "One-tap DELETE per item (trash icon / removable chip) + a clearly separated 'Clear all' at the bottom. Deletion should never require editing text — delete-and-re-teach is simpler and less error-prone than inline text editing for the average user.",
        "Blend STRUCTURED settings with a FREE-TEXT layer. Structured fields (equipment chips, goal picker, injury/restriction toggles — the Fitbod model) cover the common, high-signal stuff cheaply and legibly; a short free-text 'anything else the coach should know?' box (Gemini/Perplexity model) catches the long tail ('nagging left knee', 'I hate burpees') without forcing everything into rigid fields.",
        "One-tap ADD via suggested chips, not just an empty box. Offer tappable candidate facts ('Add: home gym', 'Add: training for a 10K') so adding is a tap, not typing. Reserve free text for the unusual. This is the habit-friendly move — low friction to grow the profile.",
        "For a fitness app specifically, collapse 'manage what the AI knows' into 'edit your training profile.' Expose the exact fields the AI consumes as normal editable settings (equipment, goals, defaults, restrictions). No separate parallel 'memory dossier' to maintain — the profile IS the memory (Fitbod / Notion philosophy). Less to build, less to feel creepy.",
        "Honest 'the AI uses this' framing + source visibility. State plainly which data the coach draws on ('Your plan uses: equipment, goals, and recent workouts') and, ideally, cite the specific item behind a recommendation with an inline 'correct this' (GPT-5.5 source-citation pattern). Transparency about USE, not just storage, is what defuses creepiness.",
        "Consent-first toggles for any AUTO/inferred data source (Apple Health, workout log, wearables), off-by-default or clearly opt-in, each individually switchable (Gemini connected-apps / WHOOP-Oura model). Pair with a user override so explicit free-text ('bad knee') visibly outranks inferred signals.",
        "Scope memory to a context where possible (per-plan / per-goal-block), mirroring Claude project memory — scoped facts feel purposeful and less like one all-knowing global profile.",
        "Give an obvious 'don't remember this' escape hatch (Claude incognito). Even a simple 'this was a one-off, don't save it' on a captured item builds trust that the user, not the app, is in control."
      ],
      "pitfalls": [
        "Overwhelming wall of text: dumping memory as one long synthesized paragraph or an unstructured 'dossier' (the exact complaint about ChatGPT's opaque 'reference chat history' layer). Users can't tell what's in there or prune one thing — it reads as surveillance, not a tool.",
        "Hidden / hard-to-find controls: burying memory management several taps deep with no ambient signal that anything was ever saved. If users don't KNOW the AI remembered something, or can't find where to change it, the feature feels sneaky even when the intent is benign.",
        "Uneditable or opaque memory (the Replika criticism — 'keeps the wheel hidden'). Auto-learning that the user can view but can't confidently delete/correct item-by-item is the core creepiness trigger. Every stored item must be individually removable.",
        "Creepy over-personalization: surfacing inferred-and-stored facts the user never volunteered (especially sensitive health/body/emotional inferences), or referencing them without explaining the source. In a fitness/health context this is acute — weight, injuries, mood inferences must be handled with visible provenance and easy deletion.",
        "High friction to ADD or maintain: a manual, free-text-only profile that users must hand-curate (Character.AI persona model) goes stale immediately — people won't keep it current, so the AI stays dumb. Auto-capture + one-tap chips are what make it habit-friendly.",
        "An always-open memory field / form cluttering the primary UI. Memory management competing for attention on every screen creates friction and anxiety; it belongs behind a summonable, lightweight entry.",
        "Text-edit-only correction with no delete: forcing users to rewrite a fact's wording to fix it (instead of a simple remove) is fiddly and error-prone for the common case of 'this is just wrong, kill it.'",
        "Nuke-all buttons mixed in with per-item deletes without separation, risking accidental full wipes — or the opposite, only offering 'clear everything' with no granular control.",
        "The subtle trust gap where turning memory OFF doesn't delete what's already stored (a real ChatGPT confusion). If you offer a master switch, be explicit that existing items persist and give a paired 'delete existing' action.",
        "Building a second, parallel 'AI memory' store that duplicates and can drift from the app's real profile/settings — two sources of truth the user must reconcile. Prefer making the AI read the profile the user already edits."
      ]
    },
    "current": {
      "trainingPrefCard": "**File:** /Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift — `struct PlanRationaleCard<Composer: View>` (lines 568–656), used in `aiPage` (lines 183–199).

**What it is:** The "TRAINING PREFERENCES" card at the top of the Routines→AI page. It is generic over a `Composer` view slot so the parent injects the Tune-with-AI input inside the same card. Instantiated as:
`PlanRationaleCard(onApplyPreferences: { startGenerateRoutines() }) { refineComposer }` (line 188–190).

**Structure (top → bottom), outer `VStack(alignment: .leading, spacing: 12)`:**
1. A tappable header block — inner `VStack(alignment: .leading, spacing: 12)` wrapped in `.contentShape(Rectangle()).onTapGesture { showEditor = true }`:
   - **Top row** `HStack(alignment: .center, spacing: 6)`: `figure.run` SF Symbol (size 10, weight .heavy, accent) + kicker `Text("TRAINING PREFERENCES")` (size 10, weight .heavy, `.tracking(1.5)`, accent, lineLimit 1, minimumScaleFactor 0.85) + `Spacer()` + a chevron button (`chevron.right`, size 12, weight .heavy, `textFaint`, 30×30 hit area) whose action is `showEditor = true`.
   - **`Text(prefSummary)`** — plain gray one-liner (size 12, `textDim`, `.fixedSize(vertical)`). NOT chips. `prefSummary` (lines 634–655) joins with " · ": `"{N} days / week"` · goal displayName · `"{N} exercises"` · `"{N} sets"` · equipment (first 2 category names + " +K", or "Any equipment") · `"Focus: {muscles}"` (first 3 major sections + " +K", omitted if none). Example: `"3 days / week · Build muscle · 4 exercises · 3 sets · Dumbbells, Barbell · Focus: Chest, Back"`.
2. **`composer()`** — the injected Tune-with-AI slot, rendered directly below the summary with NO divider (comment says main chat entry lives inside this card).

**Layout/styling of the card shell:** `.padding(.horizontal, MasoMetrics.cardPadding)` (20) + `.padding(.vertical, cardPadding - 2)` (18); `.frame(maxWidth: .infinity, alignment: .leading)`; **no fill** — only an `.overlay` `RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium=16).stroke(MasoColor.borderHero=white 0.18, lineWidth: 0.5)` (a "hero" outlined card that lets the page background show through).

**Edit sheet:** `.sheet(isPresented: $showEditor) { TrainingPreferencesSheet(onConfirm: onApplyPreferences) }` — private sheet (lines 662–719), `.presentationDetents([.large])`, drag indicator, nav title "Training Preferences", `Cancel` (top-left, rolls back to a `UserSettings` snapshot taken onAppear), and a bottom `safeAreaInset` accent Capsule CTA `sparkles + "Generate routines"` → `confirm()` → `data.save()` + dismiss + `onConfirm()` (= startGenerateRoutines). The sheet body is just `TrainingSettingsSection()`.",
      "tuneComposer": "**File:** /Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift — `refineComposer` (lines 206–243), `canRefine` (245–247), `sendRefine()` (249–266), `containsURL()` (268–273). State: `@State refineInput` and `lastRefineNote` (referenced around line 42, 261).

**What the view is:** an inline chat-style input, injected as the `composer` slot of `PlanRationaleCard`. `VStack(alignment: .leading, spacing: 8)`:
- `HStack(spacing: 10)`: a multi-line `TextField` (`axis: .vertical`, `lineLimit(1...4)`, size 14, `text` color) bound to `$refineInput`; padding H14/V10; fill `MasoColor.surface`; overlay `RoundedRectangle(cornerRadius: 16).stroke(borderSoft=white 0.08, 0.5)`; `.submitLabel(.send)`; `.onSubmit { sendRefine() }`. Next to it a circular send button: `arrow.up` (size 15, .heavy, black glyph) in a 36×36 `Circle` filled `accent` when `canRefine` else `surfaceHi`; disabled when `!canRefine`.
- Conditional hint: if `containsURL(refineInput)`, a gray size-11 note "I can't watch the video yet — paste the key moves...". (TODO(backend) fetch transcript.)

**Placeholder (localized):** `"Tell the AI a preference or change in plain words — e.g. 'bad shoulder, no overhead'. It remembers."`

**`canRefine`:** `!aiGenerating && !refineInput.trimmed.isEmpty`.

**`sendRefine()` flow:** trims text; guards non-empty & not generating; fires analytics `tune_with_ai_send` (text_len / contained_url / is_pro, no PII). **Pro gate:** `guard data.settings.isPro else { paywallPresented = true; return }` — non-Pro taps open the paywall (nothing is written to memory). Pro path: clears `refineInput`, sets `lastRefineNote = text`, then does BOTH:
  1. `data.appendCoachNote(text)` — the sentence is persisted long-term into Coaching Memory (every future generation carries it).
  2. `startGenerateRoutines(focusNote: text, surface: "tune")` — the sentence drives an immediate regenerate.

**`startGenerateRoutines(focusNote:surface:)`** (lines 451–467): sets `aiGenerating`, awaits `data.generateAIRoutines(focusNote:surface:)`, populates `aiPlans` + fallback flag. So one sentence = immediate `focusNote` regenerate + permanent coach-memory append. This is the exact dual behavior (focusNote regenerate + appendCoachNote) to preserve in any redesign.",
      "coachMemory": "**Storage format — YES, a single String of "- bullet" lines.** `UserSettings.coachMemory: String = ""` in /Users/yumowu/Projects/Maso-iOS/Maso/Models/Settings.swift (line 113). It is one flat `String` where each user note is a line prefixed with `"- "`, joined by `\
`. There is no array/struct; the bullet convention is purely textual.

**Append/dedupe — `DataStore.appendCoachNote(_:)`** in /Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift (lines 122–142):
- trims; ignores empty.
- forms `bullet = "- \\(trimmed)"`.
- dedupe is ONLY against the immediately-previous line: splits `coachMemory` on `\
`, takes `.last`, trims, and `guard lastLine != bullet` — so it only blocks consecutive exact duplicates (user double-sending the same sentence). Non-adjacent duplicates and near-duplicates are NOT deduped.
- if memory is currently empty → `coachMemory = bullet`; else `coachMemory += "\
" + bullet` (append at end).
- analytics `coach_note_append` with `note_count` = number of non-empty lines (no text). Then `save()`.

**Injection into generation — two hops:**
1. `DataStore.buildAIPayload()` (DataStore.swift ~1643–1720): sets `AIPayload.coachMemory` = `settings.coachMemory.trimmed`, or **nil when empty** so the prompt block is omitted (lines 1715–1718).
2. `AIPayload.coachMemory` / `coachMemoryBlock` in /Users/yumowu/Projects/Maso-iOS/Maso/Data/AIWorkoutService.swift (lines 893, 904–908): `coachMemoryBlock` returns "" when nil/empty, else caps to the **last ~1200 chars** (keeps most-recent) and wraps as `"\
\
COACH NOTES — the user's standing preferences/constraints, ALWAYS respect these unless they conflict with safety:\
{capped}"`. This block is concatenated into both prompts right after the equipment line (`buildPrompt` line 612, `buildRoutinesPrompt` line 674).

**Existing editor — `coachMemorySection`** in /Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/TrainingSettingsSection.swift (lines 262–311), the LAST row of TrainingSettingsSection: accent kicker `HStack` with `brain.head.profile` icon (size 10 .heavy) + `Text("Coaching memory")` (size 12 .bold, tracking 0.5) + a `Clear` button (size 12 .semibold textDim) shown only when non-empty (sets `coachMemory = ""`, `save()`). Below: a multi-line `TextEditor` live-bound to `settings.coachMemory` (font 14, text color, `.scrollContentBackground(.hidden)`, `minHeight: 96`, padded H10/V6, `surfaceHi` background, `borderSoft` 0.5 stroke, corner radius 12). Then help text (size 11, textFaint): "Notes the AI uses every time it builds your routines — edit or clear anytime." Editing is live (writes settings directly, no dirty-mark, no regen) — the raw "- bullet" text is shown/edited as-is, so users see and can edit the bullet lines directly.",
      "structuredPrefs": "**File:** /Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/TrainingSettingsSection.swift — `struct TrainingSettingsSection` (lines 23–332). It is the SINGLE SOURCE for training prefs: rendered both in the Settings screen (`Section_(title:"Training")`) and in the two prefs sheets (`TrainingPreferencesSheet` in PlansScreen and `TrainingSettingsSheet` in this file). No outer chrome/padding — caller decides. Body is `VStack(spacing: 0)` of rows separated by `Divider().background(borderSoft)`.

**Fields, in order:**
1. **Days per week** — `IntStepperContent` range 1...7, binding writes `settings.weeklyTrainingDays` + `markRecommendedPlansDirty()`.
2. **Muscles to focus** — a `Button` row → sets `showMusclePicker = true`; right side shows `musclesSummaryText` (folded to 6 major sections: "None" / "Chest" / "Chest, Back" / "Chest, Back +2") + chevron.right. Opens `MusclesPickerSheet` (medium/large detents) bound to `settings.wantStrengthen`.
3. **Gym equipment** — a `Button` row → `showEquipmentPicker`; right side `equipmentSummaryText` ("All equipment" if empty, else 2 category names + "+N") + chevron. Opens `EquipmentPickerSheet` (multi-select category grid with icon tiles + checkmarks; lines 488–566) bound to `settings.availableEquipment`.
4. **Exercises per plan** — `IntStepperContent` range 1...8 → `settings.exercisesPerSession`.
5. **Default sets** — `IntStepperContent` range 1...6 → `settings.defaultSetsPerExercise`.
6. **Training goal** — a `Menu` listing `TrainingGoalKind.allCases` (writes `settings.trainingGoalKind`, whose didSet cascades trainingGoal + defaultRestSeconds); label shows displayName + up/down chevron; below it a faint subtitle (size 11) explaining the goal's rep/rest range.
7. **Set rest** — `IntStepperContent` 15...300 step 15 suffix "s" → `settings.defaultRestSeconds`.
8. **Exercise rest** — `IntStepperContent` 0...600 step 15 suffix "s" → `settings.defaultBetweenExerciseRestSeconds`.
9. **Prefer community plans** — `ToggleRow` → `settings.preferCommunityPlans`.
Then a scope footnote (size 11 textFaint): "These apply to recommended routines and exercises you add — your custom routines aren't changed." Then the **Coaching memory** section (see coachMemory).

**Dirty/regen model:** stepper/toggle/picker edits only call `markRecommendedPlansDirty()`; the actual regenerate is deferred to `.onDisappear { data.commitRecommendedPlansIfDirty() }` (loading refresh on leaving), so it doesn't recompute on every tap.

**The sheet:** `TrainingSettingsSheet` (lines 340–483, this file) and `TrainingPreferencesSheet` (PlansScreen 662–719) both wrap `TrainingSettingsSection()` in a NavigationStack/ScrollView with nav title "Training Preferences", a snapshot `original: UserSettings` for rollback, a `changed` diff computed field-by-field (UserSettings isn't Equatable), a bottom accent Capsule CTA `sparkles + "Generate routines"` (disabled/greyed until `changed`), Close/Cancel → Discard alert, and (TrainingSettingsSheet only) an "Update your saved routines?" alert when per-step params (rest/sets) changed → `applyDefaultParamsToAllRoutines`.",
      "aiSummaryCardStyle": "(see aiSummaryCardStyle field above)",
      "aiSummaryPoints": "(see aiSummaryPoints field above)"
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
      "agentId": "adbfca08a0557ad37",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1783010370467,
      "queuedAt": 1783010370460,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "promptPreview": "You are a product/UX analyst. Research how the best AI & consumer apps let users SEE and MANAGE "what the AI knows / remembers about me" and their preferences, so we can design a lightweight, habit-friendly version for a fitness app. Use WebSearch/WebFetch (load via ToolSearch) + your own knowledge (through early 2026).

Cover: ChatGPT Memory (the saved-memories list, per-item delete, "Manage memo…",
      "lastProgressAt": 1783010541478,
      "tokens": 45195,
      "toolCalls": 8,
      "durationMs": 171011,
      "resultPreview": "{"apps":[{"name":"ChatGPT Memory (OpenAI)","memoryFeature":"Two layers: (1) 'Saved memories' — discrete, user-inspectable facts the model chose to store ('User is training for a marathon in October'); (2) 'Reference chat history' — an opaque, always-on synthesis of all past chats with no item list. The gold-standard editable surface is the Saved-memories list. As of GPT-5.5 (late 2025) responses t…"
    },
    {
      "type": "workflow_agent",
      "index": 2,
      "label": "research:current",
      "phaseIndex": 1,
      "phaseTitle": "Research",
      "agentId": "addf82e8d8e6bfbf9",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1783010370472,
      "queuedAt": 1783010370460,
      "attempt": 1,
      "lastToolName": "StructuredOutput",
      "lastToolSummary": "**File:** /Users/yumowu/Projects/Maso-iOS/Maso/Views/Screen…",
      "promptPreview": "Inventory the Maso iOS pieces relevant to redesigning the Routines "Training Preferences" card + its "Tune with AI" input, at /Users/yumowu/Projects/Maso-iOS. Read the real files. Report:
- trainingPrefCard: the current "TRAINING PREFERENCES" card — struct PlanRationaleCard in Maso/Views/Screens/PlansScreen.swift: what it shows (kicker + plain-text prefSummary + the composer slot + chevron→edit sh…",
      "lastProgressAt": 1783010498021,
      "tokens": 88073,
      "toolCalls": 14,
      "durationMs": 127549,
      "resultPreview": "{"trainingPrefCard":"**File:** /Users/yumowu/Projects/Maso-iOS/Maso/Views/Screens/PlansScreen.swift — `struct PlanRationaleCard<Composer: View>` (lines 568–656), used in `aiPage` (lines 183–199).\
\
**What it is:** The \\"TRAINING PREFERENCES\\" card at the top of the Routines→AI page. It is generic over a `Composer` view slot so the parent injects the Tune-with-AI input inside the same card. Instan…"
    },
    {
      "type": "workflow_agent",
      "index": 3,
      "label": "synthesize:design",
      "phaseIndex": 2,
      "phaseTitle": "Synthesize",
      "agentId": "add2e2637ca2efc69",
      "model": "claude-opus-4-8[1m]",
      "state": "done",
      "startedAt": 1783010541484,
      "queuedAt": 1783010541483,
      "attempt": 1,
      "lastToolName": "Read",
      "lastToolSummary": "/Users/yumowu/Projects/Maso-iOS/Maso/Data/DataStore.swift",
      "promptPreview": "Design a build-ready redesign of the Maso iOS Routines tab's "Training Preferences" card + its "Tune with AI" input. Two goals from the owner:
(A) Restyle the whole Training Preferences card to MIMIC the Progress tab's "AI Coach Summary" card style (icons + text style).
(B) Redesign the AI input per the owner's ideas: (1) lightweight ENTRY (a button/chip, not an always-open input field on the page…",
      "lastProgressAt": 1783010672150,
      "tokens": 76957,
      "toolCalls": 5,
      "durationMs": 130665,
      "resultPreview": "I now have all the concrete symbols confirmed. Here is the design doc.

---

# Maso Routines — Training Preferences card + "Tune with AI" redesign

Design doc, grounded in real symbols. Targets: `PlansScreen.swift`, a new `PreferencesSheet`, `DataStore` coach-note helpers, `AISummaryCard`-parity styling.

---

## 0. Design thesis (from MARKET)

The winning pattern across ChatGPT Memory, Gemini Sav…"
    }
  ],
  "totalTokens": 210225,
  "totalToolCalls": 27
