# Isolated Pro candidate — manual browser export

Prepared 2026-11-13 Asia/Shanghai. Not visually verified, uploaded, or submitted.

## Existing local browser only
The already-running Mac studio process uses `127.0.0.1:8802` in this exact project. No server was started/restarted or reconfigured. This route was added as source files; no HTTP/browser request was made to verify the running route.

In your own existing Mac browser, open:
`http://127.0.0.1:8802/pro-candidate-20261113?device=iphone&slide=plan&locale=zh`

1. Inspect the poster (browser zoom-out can help see the whole poster). This is new candidate caption data over retained 43 source captures, NOT a new native-app capture.
2. Click **保存本页候选 PNG（仅01/02）**. Wait for saved-path alert; the actual PNG is downloaded and also saved in the isolated output directory below.
3. Click **2**, inspect and save; click **English**, inspect and save; click **1**, inspect and save. This yields Chinese/English pages01/02 for first visual acceptance. No bulk export is triggered.
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
Only 22 recovery leaves now differ from canonical; all transforms/chat/native asset references unchanged.

03: `slidesByDevice.iphone[2].screenshot` is `/screenshots/localized/iphone/{locale}/player-heart-warning.png`; its actual native exercise label/media must be verified before any asset replacement. Phone/watch heart-rate values live inside native captures, not editable caption fields. Never paint over them. DeviceShowcase uses its own capture mapping for other families; obtain genuine corrected source before updating those references.

## Validation / limitations
`node candidates/pro-20261113/test-isolation.cjs`:14checks pass; tests invoke handlers directly with no network. Generated synthetic test PNG exists only in a temporary sandbox removed after the test; it is not a poster or candidate export.
Tests: readonly candidate GET, output containment, RGB/no-alpha, exact dimensions, rejection of path traversal/wrong family/size/locale/page, no canonical writes, TSX syntax.
Source-only TypeScript checking has3pre-existing `iphone-medium` missing-record errors in constants/defaults; no candidate-source errors. Full tsc also encounters generated `.next` route-type synchronization errors. A full green build/browser acceptance is NOT claimed.

The broader pre-existing studio directory was untracked at task start. Only these6task-owned candidate files are intended for this change; do not bulk-stage the rest of studio, its assets, exports, or unrelated native work.
