# Anatomy Sub-Muscle Highlight — Research Report

## Background

Maso's current anatomy diagram (`Maso/Data/Anatomy.swift` + `Maso/Views/Components/BodyHint.swift`) reuses polygon data verbatim from `react-body-highlighter` (MIT). The upstream only ships major-muscle polygons (~17 distinct: chest, back, shoulders, arms, legs, core, calves, etc.) — there is no separate polygon for `upperChest`, `frontDelts`, `tricepsLong`, `gluteusMedius`, or 23 of the other 27 sub-muscles in the plan §0.2. The code "lies" about this with `proxyAnatomy` (Anatomy.swift L106–138): pick `Upper Chest` and the whole chest polygon lights up, identical to picking `Chest`.

User wants to extend BodyHint to 27 sub-muscle granularity for the exercise-db overhaul (so e.g. selecting "Incline Bench Press" lights up *upper* chest, not the whole chest). User has tried 4 hand-redraws of the anatomy and rejected each as "完全不能用" — bar for visual quality is high, anatomical correctness matters, and ad-hoc polygon splits (the `splitHorizontalY` helper at Anatomy.swift L179) yielded the rejected results. **The previous failure mode was visual quality**: hand-drawn 5–12-vertex polygons cut into thirds along a horizontal line produced rectangular blocks that didn't look like muscle bellies — they looked like flat stacked bricks.

Three approaches researched below. **Recommendation: Approach 1 (MuscleMap SwiftUI SDK)** — drop-in, MIT, ~36 muscle groups, 14 already-correct sub-groups, anatomical fidelity that already matches "Spotify-dark minimalism".

---

## Approach 1: Adopt MuscleMap SwiftUI SDK (recommended)

### Source

[`melihcolpan/MuscleMap`](https://github.com/melihcolpan/MuscleMap) — native SwiftUI SDK, MIT, 174 stars, last update 2026-05-21, iOS 17+ / macOS 14+, zero dependencies, available via SwiftPM (`from: "1.6.4"`) and CocoaPods.

What it ships:
- **Male and Female** body models, **Front and Back** views (4 path files)
- **36 muscle groups** = 22 base + 14 sub-groups, declared in `Sources/MuscleMap/Data/Muscle.swift`
- Sub-groups already present in the path data: `upperChest`, `lowerChest`, `frontDeltoid`, `rearDeltoid`, `upperTrapezius`, `lowerTrapezius`, `innerQuad`, `outerQuad`, `hipFlexors`, `upperAbs`, `lowerAbs`, `serratus`, `ankles`, `adductors`, `neck`
- Polygon data is **bezier-path SVG strings** (M/C/Q/Z commands), not 5–12-vertex coarse polygons. Verified by reading `Sources/MuscleMap/Data/MaleFrontPaths.swift` — each muscle has anatomically-shaped curves, not boxy outlines.
- Rendered via SwiftUI **Canvas + Path** (same primitive Maso already uses). Self-contained SVG path parser (`Core/SVGPathParser.swift`), no UIKit/external dep.
- Built-in features Maso could opt into or ignore: heatmap, gradient fills, multi-select, drag-to-select, pinch-zoom, undo/redo, 4 preset styles (`default`, `minimal`, `neon`, `medical`), VoiceOver accessibility, localization (11 languages incl. ZH).

Mapping to Maso's 27-sub-muscle list:

| Maso target | MuscleMap coverage | Notes |
|---|---|---|
| upper_chest, middle_chest, lower_chest | ✅ `upperChest`, `chest`, `lowerChest` | "middle" = the main `chest` polygon (anatomically the sternocostal head) |
| front_delt, side_delt, rear_delt | 🟡 `frontDeltoid`, `deltoids`, `rearDeltoid` (back side only) | "side delt" missing as separate path — would need to be derived as `deltoids` minus front/rear, or accept proxy (deltoids → side_delt visually) |
| traps_upper, traps_middle, traps_lower | 🟡 Front: `upperTrapezius`, `lowerTrapezius` (no middle); Back: only `trapezius` aggregate | Back view needs trap split — degraded but acceptable |
| lats | ❌ Only `upperBack` aggregate | No lats / rhomboids split — same gap as current Maso |
| rhomboids | ❌ Not split out | Same gap as current |
| lower_back | ✅ `lowerBack` | |
| biceps, triceps, forearms, brachialis | 🟡 `biceps`, `triceps`, `forearm` — no brachialis, no triceps-head split | Brachialis is anatomically a strip between biceps & brachioradialis — can proxy to biceps |
| quads | ✅ `quadriceps` + `innerQuad`, `outerQuad`, `hipFlexors` | RF/VL/VM mapping: VL → outerQuad, VM → innerQuad, RF → quadriceps |
| hamstrings, glutes, calves, adductors, tibialis | ✅ all present | |
| glutes_med, abductors | ❌ Aggregated into `gluteal` | Gap |
| abs_upper, abs_lower, obliques, serratus | ✅ all present | |
| transverse (deep core) | ❌ Not visualizable | Drop from visual; show as label only |

**Net coverage: ~21 of 27 sub-muscles with dedicated polygons. The remaining 6 (side_delt, traps_middle, lats, rhomboids, glutes_med, abductors, transverse, brachialis, triceps heads) get the same proxy-to-parent treatment Maso already has** — but instead of *all* 23 sub-muscles being proxied, only ~6–8 are. That's a 70 %+ improvement.

### Visual

See `/tmp/musclemap_front.png` and `/tmp/musclemap_neon.png` (downloaded during research). Style is:
- Anatomically-shaped muscle bellies with smooth curves (chest is rounded pec-shape, not a hexagon; biceps is a peaked teardrop; abs are a proper 6-pack with serratus arcs)
- Front/back symmetric, head as a stylized silhouette (not a circle)
- `default` style: light gray idle (#3f3f3f), red/orange/yellow highlight. Background light.
- **`neon` style: black background, dark gray idle, red+cyan glow highlight — already matches Spotify-dark + accent green if you swap the highlight color.** Drop-in fit.
- Edge: anti-aliased bezier paths, no jagged edges.

Compared to current Maso BodyHint: this is a *qualitative leap*. Current polygons are visibly low-poly (chest is two 5-vertex blobs); MuscleMap polygons read as actual muscles even at 80pt thumbnail size.

### Effort

| Task | Time |
|---|---|
| Add SPM dep `MuscleMap 1.6.4`, audit license, write a `MuscleMapping.swift` translating `Maso.MuscleGroup` ↔ `MuscleMap.Muscle` | 0.5 d |
| Rewrite `BodyHint.swift` to embed `BodyView(gender: .male, side: .front)` and `.back` side-by-side, mapping current `opacityFor` callback into `.highlight(_:color:opacity:)` modifiers | 0.5 d |
| Replicate current behaviors: `region.viewBox` upper/lower crop (use SwiftUI `.clipped()` + scale), `synergists` (different opacity), `coarseOnly` (toggle `hideSubGroups`), `onMuscleTap` (use `.onMuscleSelected`) | 1 d |
| Visual QA on all the call sites that currently use BodyHint (HistoryScreen SessionCard, ExerciseDetailScreen, MuscleSelector, TrainingMiniBar thumbnail, etc.) — adjust colors, sizes, ensure dark theme | 1 d |
| **Total** | **3 days** |

Existing `proxyAnatomy` table in Anatomy.swift becomes a shorter, justified table (only the 6–8 muscles MuscleMap doesn't ship) — net code reduction.

### Risk

**This is genuinely different from the 4 prior failures.** The prior attempts were *hand-drawn polygons by Claude*, where the failure mode was "5–12 vertex hand-drawn shapes can't represent a muscle without looking blocky / fake". MuscleMap was drawn by a human designer using a vector tool, with 30–80 control points per muscle, anatomically referenced. The output is visibly *correct anatomy*, not approximation.

Remaining risks:
1. **Style mismatch.** MuscleMap's `default` style has a light head/skin tone that may clash with Maso's `#121212` background. Mitigation: use the `neon` preset or a custom `BodyViewStyle` with `headColor: idleGray, hairColor: idleGray` to neutralize. Verified the API supports this.
2. **Side-by-side panel layout.** Current Maso draws anterior + posterior in one Canvas at fixed aspect. MuscleMap renders one `BodyView` per side; we wrap two in an HStack. Aspect-fit math is straightforward (each panel is 727×1280 viewport).
3. **Hit-testing precision changes.** MuscleMap's tap recognition uses its own point-in-path; means `onMuscleTap` is now bezier-precise (not ray-cast on coarse polygons). Should be a strict improvement.
4. **SPM transitive bloat.** MuscleMap has zero external deps — safe.
5. **Drift if MuscleMap is abandoned.** Mitigation: vendor the path data files (4 swift files, ~120 KB total) into Maso. They're MIT, just include the license. Even if upstream dies, Maso owns a frozen copy of the polygons.

### Sample code

```swift
// MuscleMapping.swift — new file, ~80 lines
import MuscleMap

extension Maso.MuscleGroup {
    var mmMuscle: MuscleMap.Muscle? {
        switch self {
        case .chest:        return .chest
        case .upperChest:   return .upperChest
        case .midChest:     return .chest          // sternocostal head = main chest
        case .lowerChest:   return .lowerChest
        case .frontDelts:   return .frontDeltoid
        case .sideDelts:    return .deltoids       // proxy: middle delt unrendered
        case .rearDelts:    return .rearDeltoid
        case .upperTraps:   return .upperTrapezius
        case .midTraps:     return .trapezius      // proxy
        case .lowerTraps:   return .lowerTrapezius
        case .quads:        return .quadriceps
        case .rectusFemoris:    return .quadriceps  // central head — uses main polygon
        case .vastusLateralis:  return .outerQuad
        case .vastusMedialis:   return .innerQuad
        // ... rest of the mapping
        default: return nil
        }
    }
}

// BodyHint.swift — replaces current Canvas-draw loop
struct BodyHint: View {
    let muscles: [MuscleGroup]
    var synergists: [MuscleGroup] = []
    var color: Color = MasoColor.accent
    var height: CGFloat = 110
    var region: BodyRegion = .full
    var opacityFor: ((MuscleGroup) -> Double?)? = nil
    var onMuscleTap: ((MuscleGroup) -> Void)? = nil

    private var style: BodyViewStyle {
        BodyViewStyle(
            defaultFillColor: Color(red: 0.165, green: 0.165, blue: 0.165),
            strokeColor: .clear,
            strokeWidth: 0,
            selectionColor: color,
            selectionStrokeColor: .clear,
            selectionStrokeWidth: 0,
            headColor: Color(red: 0.165, green: 0.165, blue: 0.165),
            hairColor: Color(red: 0.122, green: 0.122, blue: 0.122),
            shadowColor: .clear, shadowRadius: 0, shadowOffset: .zero
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            panel(side: .front)
            panel(side: .back)
        }
        .frame(maxHeight: height)
        // .clipped() + custom offset for region == .upper / .lower (crop to upper half)
    }

    @ViewBuilder
    private func panel(side: BodySide) -> some View {
        BodyView(gender: .male, side: side)
            .bodyStyle(style)
            .applyHighlights(muscles: muscles, synergists: synergists,
                             opacityFor: opacityFor, color: color)
            .onMuscleSelected { m, _ in
                if let mg = MuscleGroup(mmMuscle: m) { onMuscleTap?(mg) }
            }
    }
}
```

---

## Approach 2: Vendor MuscleMap's path data only, keep Maso's custom renderer

### Source

Same as Approach 1, but instead of `.package(url:)` we copy `MaleFrontPaths.swift`, `MaleBackPaths.swift`, the `BodyPathData` / `BodySlug` / `Muscle` types, and `Core/SVGPathParser.swift` + `Core/PathBuilder.swift` into `Maso/Data/`. Keep the existing `BodyHint.swift` Canvas-draw loop, swap the polygon source from `ANTERIOR` / `POSTERIOR` arrays to the new SVG-path-parsed `Path` objects.

### Visual

Identical to Approach 1 *if* Maso's renderer is updated to handle bezier paths (not just polygons). The current `roundedPolygonPath()` helper at BodyHint.swift L266 only handles vertex lists; MuscleMap path data is already curved, so feeding parsed `Path` directly into `ctx.fill(path)` works without the rounding step.

Slight regression vs Approach 1: lose the gestures (zoom, drag-select, undo), the 4 preset styles, and accessibility/localization — Maso has to re-implement any of these it wants. But Maso doesn't use most of those anyway; the relevant features (highlight color, opacity, tap, hit-test) are simple to keep in BodyHint.

### Effort

| Task | Time |
|---|---|
| Copy 6 source files from MuscleMap, add MIT license header attribution, prune unused types | 0.5 d |
| Replace `AnatomyPolygon` array with `BodyPartPathData` array; rewrite `drawAnatomy` to use parsed `Path`s instead of polygon-fill helper | 1 d |
| Re-do hit-testing: replace `pointInPolygon` (ray-casting) with `Path.contains(point)` (SwiftUI built-in for `Path`) | 0.5 d |
| Same QA + region cropping work as Approach 1 | 1 d |
| **Total** | **3 days** (same as Approach 1, no win) |

### Risk

- No real win over Approach 1 unless you want to avoid the SPM dep. License headers still required.
- Same prior-failure differentiation as Approach 1: the polygons themselves are anatomically correct.
- Slightly more code to maintain (you own the parser + path data, instead of letting the package handle it).
- If you ever want gestures or heatmap later, you re-implement what's already in MuscleMap.

**Use this only if you have a strong objection to SwiftPM dependencies.** Otherwise Approach 1 is strictly better.

---

## Approach 3: Keep current polygons + add label/badge overlay for sub-muscle disambiguation

### Source

No new data. Use existing `react-body-highlighter` polygons for major muscles. When a sub-muscle is selected (e.g. `upperChest`), light up the parent `.chest` polygon (current behavior via `proxyAnatomy`), AND overlay a small text badge or arrow indicator on top of the polygon pointing to the relevant region. E.g. for `upperChest`, draw a small "↑" or "upper" chip overlaid on the upper third of the chest polygon.

### Visual

Body diagram looks identical to today. Adds:
- A small (8–10pt) caption chip overlaid in the upper/middle/lower third of the parent polygon, with the sub-muscle name. Like a map label.
- Or: an arrow glyph + faint shading gradient in the parent polygon (upper third tinted slightly brighter for `upperChest`).
- Or: a tiny inset badge in the corner of the body diagram listing the active sub-muscle names as chips.

Honestly admits "we don't have the polygon detail" and uses text/icons to convey precision. This is what Apple Fitness+ does — it shows muscle group icons next to the activity name, no detailed sub-muscle diagram.

### Effort

| Task | Time |
|---|---|
| Compute per-sub-muscle anchor point (center of upper/middle/lower third of parent polygon) | 0.5 d |
| Draw small `Text(label).font(.caption2).background(.ultraThinMaterial)` overlay at the anchor inside BodyHint's Canvas | 0.5 d |
| Visual QA — make sure labels don't clash, support both color modes | 0.5 d |
| **Total** | **1.5 days** |

### Risk

- **High risk of looking cluttered at 80pt thumbnail sizes** (SessionCard, MiniBar). Captions get unreadable below ~12pt.
- Doesn't solve the actual product problem ("the diagram should show *visually* that upper chest was worked, not just say it"). User intent for sub-muscle granularity is the visual signal.
- However: this is **the safe fallback if Approaches 1/2 are deemed too risky.** It's an honest disambiguation, not a fake-anatomy attempt — explicitly differs from the 4 prior failures because it doesn't pretend to redraw the body, it just adds text labels.
- Compatible with Approach 1: a label overlay layer can be added on top of MuscleMap rendering too.

---

## Recommendation

**Adopt Approach 1 (MuscleMap SwiftUI SDK)** with the `neon` style customized to Maso's accent green.

Why this matters and why it's not the 5th failure:

1. **The 4 previous failures were all "Claude redraws polygons by hand"** — that's a fundamentally hard problem, and the polygons looked low-poly because they *were* low-poly. MuscleMap's polygons were drawn by a human illustrator with vector tools, not in 5–12 vertex chunks. The visual quality is *categorically different*.

2. **It already supports 21 of 27 target sub-muscles natively** with anatomically-correct polygons (incl. `upperChest`/`lowerChest`, `frontDeltoid`/`rearDeltoid`, `upperAbs`/`lowerAbs`, `serratus`, `innerQuad`/`outerQuad`, `hipFlexors`). The current code already gracefully handles the remaining 6 via `proxyAnatomy` — that fallback shrinks from 23 entries to ~6.

3. **It's SwiftUI Canvas-native**, MIT, zero deps, iOS 17+ — same baseline Maso targets. Drop-in replacement for `BodyHint.swift`.

4. **The `neon` preset** already renders on a black background with a glow effect — that's Maso's Spotify-dark aesthetic out of the box. Swap the highlight color to `MasoColor.accent` (#1ED760) and it looks bespoke.

5. **Effort is bounded at ~3 days**, mostly QA. The data is not Claude-generated, so the failure mode of "Claude can't draw" is not in play.

6. **Vendor the path data** (drop MuscleMap's 4 path files into Maso/Data/ alongside the existing Anatomy.swift) so the dep can be eventually removed if upstream stops being maintained. License compliance: include the MIT notice.

If user wants extra safety: stage as a Settings toggle for the first release. Add `Settings.useDetailedAnatomy: Bool` (default `false`), let early users opt in, gather feedback before flipping default. The current BodyHint stays as the fallback path.

**Do NOT recommend Approach 3 alone** — labels on top of fake polygons is what Apple Fitness+ does, but Maso is more anatomically focused (per the exercise-db overhaul plan §0.2 itself). Users who care about upper-vs-lower-chest *want to see* upper-vs-lower-chest highlighted. A text label is a UX surrender.

If Approach 1 fails QA: fall back to Approach 3 (1.5 d) rather than retry hand-redraw. Hand-redraw is a known failure mode.

---

## Sources / Links

- [`melihcolpan/MuscleMap`](https://github.com/melihcolpan/MuscleMap) — primary recommendation. MIT, SwiftUI, 174 stars, iOS 17+. Has the 14 sub-muscle paths Maso needs.
- [`HichamELBSI/react-native-body-highlighter`](https://github.com/HichamELBSI/react-native-body-highlighter) — RN version, 226 stars, same polygon source as MuscleMap (verified by reading both path files; same SVG strings). MIT. Useful as a reference for the SVG path data.
- [`giavinh79/react-body-highlighter`](https://github.com/giavinh79/react-body-highlighter) — current Maso source. Last release v2.0.5 in 2021, **no sub-muscle polygons in v1.x or v2.x**. Maso has already extracted everything available.
- [`soroojshehryar/react-muscle-highlighter`](https://github.com/soroojshehryar/react-muscle-highlighter) — newer (May 2026) React port. Has Male/Female + Front/Back but only major muscles (~17), no sub-muscle granularity. Not useful for Maso.
- [`gossamr/swift-body-highlighter`](https://github.com/gossamr/swift-body-highlighter) — small Swift port (2 stars). Outdated, no sub-muscles.
- [`Obaloluwa-Obidoyin/bodychart_heatmap`](https://github.com/Obaloluwa-Obidoyin/bodychart_heatmap) — Flutter, very coarse (~8 body regions), not useful.

Files in this repo touched/relevant:
- `/Users/yumowu/Projects/Maso-iOS/Maso/Data/Anatomy.swift` — current polygon data + `proxyAnatomy` fallback
- `/Users/yumowu/Projects/Maso-iOS/Maso/Views/Components/BodyHint.swift` — current Canvas renderer
- `/Users/yumowu/Projects/Maso-iOS/Maso/Models/MuscleGroup.swift` — Maso's enum (target of new mapping table)
- `/Users/yumowu/Projects/Maso-iOS/docs/exercise-db-overhaul-plan.md` §0.2 — 27 sub-muscle taxonomy
- `/Users/yumowu/Projects/Maso-iOS/docs/session-memory-2026-05-22.md` L57-60, L197-201 — context on the 4 prior rejections
