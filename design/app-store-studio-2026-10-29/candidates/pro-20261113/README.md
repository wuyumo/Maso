# Isolated Pro candidate — manual browser export

Prepared 2026-11-13 Asia/Shanghai. Not visually verified, uploaded, or submitted.

## Existing local browser only
The already-running Mac studio process uses `127.0.0.1:8802` in this exact project. No server was started/restarted or reconfigured. This route was added as source files; no HTTP/browser request was made to verify the running route.

In your own existing Mac browser, open:
`http://127.0.0.1:8802/pro-candidate-20261113?device=iphone&slide=plan&locale=zh`

1. The poster defaults to **适配 Fit**, showing the whole poster inside the remaining window. Use **100%** only when you want native-size scrolling. Inspect the poster. This is new candidate caption data over retained 43 source captures, NOT a new native-app capture.
2. Click **保存本页候选 PNG（仅01/02）**. Wait for saved-path alert; the actual PNG is downloaded and also saved in the isolated output directory below.
3. Use the fixed01–05tabs or 上一张/下一张. Save Chinese02, choose **English** in the language selector and save02, then choose01and save. Device selection stays in the same fixed toolbar. This yields Chinese/English pages01/02 for first visual acceptance. No bulk export is triggered.
4. Stop and report any render error, font/image warning, missing photos, dark/blank inner screen, clipped/overlapping copy, or a failed export. Do not change ports/proxies/network settings. The source route is implemented but browser reachability/paint/export are still unverified until these real actions succeed.

Pages1–5 are navigable. 03 export is deliberately disabled pending actual corrected native captures. 04/05 are unchanged reference-content previews, not accepted latest-native UI proof. No screenshot upload or review action exists in this route.

## Protection boundary
- Candidate project: `candidates/pro-20261113/project.json` (same schema as original).
- Read-only API: `/api/pro-candidate-20261113/project`, no POST handler.
- Export API: `/api/pro-candidate-20261113/export` (strict fixed locale/device/size/page allowlist; decoded dimensions checked).
- Output only: `exports/candidates/pro-20261113/ios/<device>/<dimensions>/<locale>/<01-plan|02-recovery>.png`.
- No canonical `/api/project`, `/api/export-image`, `useProject`, autosave or localStorage is invoked.
- The control card is a sibling outside the poster DOM captured by html-to-image.
- The original poster main subtree is byte-identical except for an ID used to target it.
- Original `app-store-screenshots.json`, original renderer/API files and `exports/latest` are unchanged.461 protected files were rehashed after tests with zero differences.
- Uses existing html-to-image and Sharp, no replacement rendering engine. No browser automation or alternate service.

## Exact fields and pending real capture
`slidesByDevice.iphone[0].textElements[0].text`: t318 restores all12 plan descriptions to their original days/duration/focus wording; no Pro sentence.
`slidesByDevice.iphone[1].headline` :12locale estimated-recovery wording.
`slidesByDevice.iphone[1].textElements[0].text`: t319 removes all12 detailed-recovery Pro sentences; retains each existing 3D-map sentence.
At t319,22recovery leaves differed from canonical; t324terminal-period changes are recorded below; all transforms/chat/native asset references unchanged.

03: `slidesByDevice.iphone[2].screenshot` is `/screenshots/localized/iphone/{locale}/player-heart-warning.png`; its actual native exercise label/media must be verified before any asset replacement. Phone/watch heart-rate values live inside native captures, not editable caption fields. Never paint over them. DeviceShowcase uses its own capture mapping for other families; obtain genuine corrected source before updating those references.

## Validation / limitations
`node candidates/pro-20261113/test-isolation.cjs`:15checks pass; tests invoke handlers directly with no network. Generated synthetic test PNG exists only in a temporary sandbox removed after the test; it is not a poster or candidate export.
Tests: readonly candidate GET, output containment, RGB/no-alpha, exact dimensions, rejection of path traversal/wrong family/size/locale/page, no canonical writes, TSX syntax.
Source-only TypeScript checking has3pre-existing `iphone-medium` missing-record errors in constants/defaults; no candidate-source errors. Full tsc also encounters generated `.next` route-type synchronization errors. A full green build/browser acceptance is NOT claimed.

The broader pre-existing studio directory was untracked at task start. Only these6task-owned candidate files are intended for this change; do not bulk-stage the rest of studio, its assets, exports, or unrelated native work.

## t320/t321 full marketing-copy audit
`marketing-audit.json` lists24removed locale sentences,264source-mapped variants, no additional added marketing Pro/unlock/free-limit prompts, and explicit pixel-review limits. The preview workflow card now says “截图候选”, not “PRO CANDIDATE”; this card is never exported. Proper hardware names/in-app native pixels are not erased.

## t322 preview usability
The same route now has a fixed responsive toolbar, persistent current page/device/language labels,01–05tabs, previous/next, all12languages, all4poster devices, Fit/100%, and explicit blocked/loading/export states. Only the outer preview wrapper scales; the exact native poster subtree is unchanged. Export calls `exportCaptureOptions(canvas)` on the poster node only, forces transform:none, and retains native width/height/canvasWidth/canvasHeight and pixelRatio1. 03remains blocked;04/05remain reference previews outside the current01/02export batch.

`node candidates/pro-20261113/test-preview.cjs`:15group checks;240query roundtrips,16fit cases including narrow viewports, component current-state/navigation/selector/disabled-export callbacks, and4actual handler dimension/RGB/isolation tests using temporary synthetic fixtures. Existing15isolation checks also pass. These are source/component/handler tests, NOT browser visual acceptance or actual DOM export proof.
Refresh the same existing8802URL to load this UI. No browser was driven and no server/network configuration changed. A real current-candidate PNG still needs user-browser export and image inspection.

## Native51source audit /03 remains blocked
`native51-source-audit.json` identifies3authentic native1206×2622phone fixtures (zh/en/zh-Hant),185bpm,3×8×50kg, Chest Press Machine / 推胸（器械）. Raw bytes staged under `public/candidate-assets/pro-20261113/native51/iphone/<locale>/player-heart-warning.png`, hashes match the native executor originals. No pixels resized/edited, no original source overwritten, not activated in the poster.

The handoff explicitly says **no new Watch capture was executed**. OldWatchzh/zh-Hantstill says卧推/臥推; all3sampledWatchcaptures use60kg, vs51phone50kg.03must remain blocked until matching genuine Watch fixture and remaining locale/family sources exist. Same185bpm alone does not make these a consistent pair and proves no production synchronization. StandaloneWatch01Chinese naming likewise needs replacement. SampledWatchrest160has no wrong exercise label; standardize it through real capture only if a uniform50kgdeckfixture is intended.04/05have no further specific new51conflict established, but are not certified against fresh51captures.

Native51source regression also checks all3staged PNG hashes/dimensions and ensures03remains locked; preview grouped checks now15.

## t324 terminal punctuation
All12languages share the same candidate text across4poster sizes. Removed exactly56terminal description sentence periods (224poster variants),0headlines needed changing;4device-page descriptions already had no final period. Interior punctuation, decimal points, chat/native UI and original image pixels are unchanged. StandaloneWatch24rawcaptures have no added editable marketing captions and were not pixel-edited. Full per-language/per-page before/after/field audit: `punctuation-audit.json`.
The same preview/export project endpoint reads this updated file with no-store. Refresh the existing route; previously exported changed pages require re-export.03remains locked. No new PNG render or upload is claimed. Isolation checks16;preview grouped checks16including exact one-character deletion regression.

## Native51paired assets connected (supersedes previous03blocked notes)
Parent-approved three-language Watch originals are now paired with the3native51phone captures. Candidate-only screenshot paths activate the override in marketing-localized; canonical43slides retain their exact original resolved paths.03candidate export is enabled only for zh/en/zh-Hant×iPhone/iphone-medium(6variants). Other9localesandiPad/Duo03remain disabled in UI and API. Use the same route, select03and the target; no service/port changes.

Device selector now also offers Watch416×496 with2raw-native pages. Its三语01exercise185/02rest160can export (6variants); other9languagesremainblocked. Watch10:11andphone09:41clocks are unaltered independentdemonstrations, never production synchronization proof. Original43screens/latest/canonical are unchanged.

`material-readiness51.json` is the exact page-change/ready/blocked manifest; `watch51-source-map.json` carries6native hashes. `test-mapping51.cjs`:7checks,6eligible03variants/42blocked,6eligibleWatchvariants/18blocked,exactrawsourcehash/dimensionsandAPIgates. Existing16isolation+16previewgroupspass;264URLroundtrips. Browserpaint/fullposteracceptanceisstillpending. Re-exportold01/02;onlyoldzh02currentlyobserved.
