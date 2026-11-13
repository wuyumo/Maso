# t376 actual rendered poster review

## Current evidence (Asia/Shanghai)
Air connected; existing listener59892 on127.0.0.1:8802, selectedApageHTTP200. Git source remains15b3b66a6d3f7478cd5312e64b7ec0a7d02d9858. Ten real zh/en iPhone1320×2868posters were already exported16:51:47–16:51:49, discovered17:18. They are NOT old43assets. All10copied through officialCopyToBox, Mac/boxSHA match, allRGB1320×2868, individually Read. No alternative transfer/browser route used.

## Actual per-page verdict
-01zh/en: actual selectedA2.1-card mock; real front-left/back-right joined photos, original dialogue, same page02phone placement. Full poster exists. Ready to show user as draft, not accepted/uploaded. Small native-style card text should be checked at actual storefront size by parent/user; no design changes made.
-02zh/en: new marketing estimate headline, Pro qualification removed, source09:41recovery/49%visible, no marketing truncation; shared lower phone bleed is intentional. Ready to show user as draft.
-03zh/en: REJECT. Both phone andWatch contain visible NO CAPTURE panels.03precision copy separately still unapproved.
-04zh/en: real diet/sleep screens, titles/nutrition/sleep values visible, intended device overlap; ready to show user as draft.
-05zh/en: REJECT. Watch contains NO CAPTURE, other three native devices visible.

## Confirmed renderer integration defect, not missing original assets
`src/components/editor/device-frames.tsx:16–25` calls `captureReady(src)` before renderingimg. `src/lib/capture-inventory.ts:512–515` only matches the original localized screenshot inventory, rejecting candidate-assets URLs. Six exact zh/enphone-warning/watch-exercise/watch-restURLs all exist, returnHTTP200, but actualcaptureReady returnsfalse. Thus files/SHA/component source assertions missed the rendered placeholder. Correct Watch filenames include `watch-exercise-185.png` / `watch-rest-160.png`, not bare scene names. The exported PNGs themselves now prove this failure.

Do not repeat export yet: it would reproduce placeholders. Narrow next fix must correctly recognize verified candidate source identities while preserving canonical behavior, Duo/Russian gates and unknown-source rejection; exporter must reject `[data-capture-missing="1"]` rather than treating a font/image-ready placeholder as finished. Then original officialDOMre-export03/05 and inspect actual PNGs again. No new renderer/asset relocation or simulator needed. Both affected generic source modules are historical UNTRACKED local dependencies; do not blindly stage full files as new history. This stage records exact diagnosis, does not modify them.

## Actual deliverables on box
`/workspace/masso-store-A-selected-20261113/user-preview-01-02-04-six-pages.jpg` (6drafts)
`/workspace/masso-store-A-selected-20261113/review-contact-10-WITH-HOLDS.jpg` (all10, holds labeled)
`/workspace/masso-store-A-selected-20261113/{zh,en}/{01-plan-A,02-recovery,03-training,04-diet,05-devices}.png` (untouched full PNGs)
`/workspace/masso-store-A-selected-20261113/six-pages-for-user-review.zip`
`/workspace/masso-store-A-selected-20261113/REVIEW-MANIFEST.json` (SHA/dimensions/verdicts)

A selected/B historical,03pending/Duolock remain. acceptedImages empty; no upload/submission, simulator/data operations or design iteration. Only these10actualposterPNGs were reviewed, not all264. Earlier248sourceeligible count is NOT rendered readiness:03/05candidate interfaces can currently resolve to placeholders.
