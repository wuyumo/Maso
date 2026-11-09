#!/usr/bin/env python3
"""Copy the five-page Plan A iPhone preview PNGs into docs/ and record provenance."""
import hashlib
import json
import pathlib
import shutil

from PIL import Image

# Newest pass last; any slide missing from the newest pass falls back to the pass before.
# badge-all: brand lockup removed, device glyphs moved to a feathered chip bottom-right,
# copy/art pulled up (that chip was retired again in final-chipoff below).
# planA-watch: page 3 warning state + matching watch.
PASSES = [pathlib.Path('/tmp/studio-out/planA-5p/ios/iphone/1320x2868'),
          pathlib.Path('/tmp/studio-out/planA-tilt/ios/iphone/1320x2868'),
          pathlib.Path('/tmp/studio-out/planA-chat/ios/iphone/1320x2868'),
          pathlib.Path('/tmp/studio-out/badge-all/ios/iphone/1320x2868'),
          pathlib.Path('/tmp/studio-out/planA-photo-report/ios/iphone/1320x2868'),
          # 2026-11-08: page 3 re-cut as the above-limit warning state (185 bpm vs a 155
          # personal limit) with a watch that mirrors the same set, reps and load.
          pathlib.Path('/tmp/studio-out/planA-watch/ios/iphone/1320x2868'),
          # 2026-11-08 (later): page 4 "Lift History" retired, nutrition promoted to 04 and
          # a new 05 device portrait added (iPhone + iPad + iPhone Duo + Apple Watch on one
          # canvas). This pass carries the final copy for all five pages.
          pathlib.Path('/tmp/studio-out/final-dev3/ios/iphone/1320x2868'),
          # 2026-11-08: page 05 first laid out as two tidy rows (the `grid` layout, kept as
          # an alternate in deck_devices_page.py); superseded by planA-fan below.
          pathlib.Path('/tmp/studio-out/final-dev4/ios/iphone/1320x2868'),
          # 2026-11-08 (poker fan): page 05 becomes one left-to-right fan — watch (smallest,
          # front, bottom-left, -16°) → duo (-6°) → iPhone (+5°) → iPad (+15°, back, top-right);
          # page 03 uses the same idea with the watch front-left (-9°) and the iPhone behind
          # right (+6°); page 01 drops the "Create a plan" CTA and runs the generated days as a
          # horizontal card row whose second card is cut by the canvas edge.
          # 2026-11-08 (message restyle): page 01 now draws the Coach conversation with the
          # App's own message shapes (photo over an accent bubble for the user turn, no bubble
          # for the coach turn), so the report, the body text and the plan cards all start on
          # the thread's left edge. Only 01-plan was re-rendered into this pass.
          pathlib.Path('/tmp/studio-out/planA-fan/ios/iphone/1320x2868'),
          # 2026-11-08 (final): the bottom-right device chip and its feathered shadow are gone
          # from every page (marketing-brand.tsx deleted); page 05 fan order is now
          # watch -> iPhone -> iPhone Duo -> iPad (iPhone second, Duo third) and both the iPad
          # and the Duo are real photographic bezel overlays (public/ipad-frame.png,
          # public/duo-frame.png) instead of CSS-drawn bodies.
          pathlib.Path('/tmp/studio-out/final-chipoff2/ios/iphone/1320x2868'),
          # 2026-11-09: zh-Hant rebuilt from zh-Hans (Taiwan wording) and every capture
          # re-taken, so page 03 shows 臥推 / 組數 / 次數 instead of the old machine
          # translation. Pages 01/02/04/05 are byte-identical to final-chipoff2.
          pathlib.Path('/tmp/studio-out/zhant-fix/ios/iphone/1320x2868'),
          # 2026-11-09 (later): pages 01/02/04/05 reuse the shared App scenes (`plans`,
          # `muscle-selected`, `diet`, `sleep`, `today`), which were still the 2026-11-06
          # captures from the old bundle — the page-01 Coach bubble was still 简体
          # 「周计划」. Those five scenes were re-taken with the current bundle and the
          # marketing fixture's demo copy now has a zh-Hant branch, so this pass carries
          # zh-Hant only and every other locale falls back to the pass above.
          pathlib.Path('/tmp/studio-out/zhant-scenes/ios/iphone/1320x2868'),
          # 2026-11-09 (owner revision): page 01 draws the three generated days as the App's
          # own WorkoutCard (kicker + AI badge, title row, count, muscle map, exercise pills,
          # per-card "save to plans" capsule) instead of the clipped carousel, and the batch
          # save pill follows the row; page 04 puts the diet screen front-left in the top
          # layer and the sleep screen behind it on the right; page 05 re-proportions the fan
          # (iPad 780 / Duo 540 / iPhone 345 / Watch 235 wide) so the tablet is finally the
          # largest silhouette. Pages 02 and 03 are byte-identical to the pass above.
          pathlib.Path('/tmp/studio-out/final-dev5/ios/iphone/1320x2868')]
DST = pathlib.Path('/Users/yumowu/Projects/Maso-iOS/docs/store-plan-a-2026-11-08/exported/ios/iphone/1320x2868')
# Same lineup geometry is reused on the 13" iPad canvas through fitLineup(); page 03 has no
# iPad counterpart (it is a two-device phone + watch composition), so the iPad deck carries
# four pages. -> iPad posters are newest pass only.
IPAD_PASSES = [pathlib.Path('/tmp/studio-out/final-ipad9/ios/ipad/2064x2752'),
               # 2026-11-09: the iPad poster scenes (plans / muscle-selected / diet / sleep /
               # today / insights) were re-taken from the current bundle, so the iPad deck no
               # longer shows the 2026-11-06 captures with 简体 copy and an empty Insights page.
               pathlib.Path('/tmp/studio-out/plan-a-ipad10/ios/ipad/2064x2752')]
IPAD_DST = pathlib.Path('/Users/yumowu/Projects/Maso-iOS/docs/store-plan-a-2026-11-08/exported/ios/ipad/2064x2752')
IPAD_SLIDES = ['01-plan', '02-recovery', '04-diet', '05-devices']
LOCALES = ['zh', 'zh-Hant', 'en', 'ja']
SLIDES = ['01-plan', '02-recovery', '03-training', '04-diet', '05-devices']
STALE = ['04-heart.png', '06-watch.png', '04-progress.png', '05-diet.png']

for locale in LOCALES:
    (DST / locale).mkdir(parents=True, exist_ok=True)
    for slug in STALE:  # the merged heart page and the retired watch page
        (DST / locale / slug).unlink(missing_ok=True)
    for slug in SLIDES:
        src = next(p / locale / f'{slug}.png' for p in reversed(PASSES) if (p / locale / f'{slug}.png').exists())
        shutil.copy2(src, DST / locale / f'{slug}.png')

files = []
for locale in LOCALES:
    for slug in SLIDES:
        path = DST / locale / f'{slug}.png'
        raw = path.read_bytes()
        with Image.open(path) as im:
            mode, size = im.mode, im.size
        files.append({
            'file': f'iphone/1320x2868/{locale}/{slug}.png',
            'locale': locale,
            'slide': slug,
            'sha256': hashlib.sha256(raw).hexdigest(),
            'bytes': len(raw),
            'width': size[0],
            'height': size[1],
            'mode': mode,
        })

ipad_files = []
for locale in LOCALES:
    (IPAD_DST / locale).mkdir(parents=True, exist_ok=True)
    for slug in IPAD_SLIDES:
        src = next(p / locale / f'{slug}.png' for p in reversed(IPAD_PASSES) if (p / locale / f'{slug}.png').exists())
        shutil.copy2(src, IPAD_DST / locale / f'{slug}.png')
for locale in LOCALES:
    for slug in IPAD_SLIDES:
        path = IPAD_DST / locale / f'{slug}.png'
        raw = path.read_bytes()
        with Image.open(path) as im:
            mode, size = im.mode, im.size
        ipad_files.append({
            'file': f'ipad/2064x2752/{locale}/{slug}.png',
            'locale': locale,
            'slide': slug,
            'sha256': hashlib.sha256(raw).hexdigest(),
            'bytes': len(raw),
            'width': size[0],
            'height': size[1],
            'mode': mode,
        })

bad = [f for f in files if f['mode'] != 'RGB' or (f['width'], f['height']) != (1320, 2868)]
bad += [f for f in ipad_files if f['mode'] != 'RGB' or (f['width'], f['height']) != (2064, 2752)]
report = {
    'batch': 'store-plan-a-2026-11-08',
    'scope': 'iPhone 6.9in (5 pages) + iPad 13in (4 pages) previews — 4 approved locales; the other 8 locales and the Duo/Watch exports are pending',
    'studioProject': 'design/app-store-studio-2026-10-29/app-store-screenshots.json',
    'exportedAt': '2026-11-09T02:10+08:00',
    'locales': LOCALES,
    'slides': [
        {'id': 'plan', 'file': '01-plan', 'scene': 'AI Coach chat: front+back body photos -> body report -> the three generated days as App WorkoutCards (muscle map + exercise pills + per-card save capsule) -> batch save pill', 'headline': '一张照片，就有一周计划'},
        {'id': 'recovery', 'file': '02-recovery', 'scene': 'iphone/muscle-selected', 'headline': '肌肉恢复，一眼看清'},
        {'id': 'training', 'file': '03-training', 'scene': 'iphone/player-heart-warning-185 + watch/exercise-185', 'headline': '心率过高，立刻提醒'},
        {'id': 'diet', 'file': '04-diet', 'scene': 'iphone/diet (front, left, top layer) + iphone/sleep (back, right, cropped by the canvas edge)', 'headline': '饮食与睡眠，一起照顾'},
        {'id': 'devices', 'file': '05-devices',
         'scene': 'device fan: watch/rest (235 wide, front, bottom-left, -16deg) -> iphone/today (345, -6deg) -> duo/diet (540, +5deg) -> ipad/insights (780, back, top-right); widths follow each frame\'s real proportions so the iPad is the largest silhouette; iPad and Duo use photographic bezel overlays (ipad-frame.png / duo-frame.png)',
         'headline': '每一块屏幕，都在一个 App 里'},
    ],
    'verified': len(files) + len(ipad_files),
    'expected': len(LOCALES) * (len(SLIDES) + len(IPAD_SLIDES)),
    'format': 'RGB PNG; no alpha; 1320x2868 (iPhone) / 2064x2752 (iPad); no brand lockup, no bottom-right device chip or its shadow; caption top y=150',
    'failures': bad,
    'files': files,
    'ipadFiles': ipad_files,
}
out = pathlib.Path('/Users/yumowu/Projects/Maso-iOS/docs/store-plan-a-2026-11-08/exported/export-validation.json')
out.write_text(json.dumps(report, ensure_ascii=False, indent=1) + '\n')
print('files', len(files), 'ipad', len(ipad_files), 'failures', len(bad))
