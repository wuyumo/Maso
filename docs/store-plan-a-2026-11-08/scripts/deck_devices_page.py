#!/usr/bin/env python3
"""Rebuild the iPhone deck as five pages: plan → recovery → training → diet → devices.

2026-11-08 revision (owner request):
  * The old page 4 ("Lift History" / progress, insights) is removed.
  * The nutrition page moves from 05 to 04.
  * A new page 5 shows every supported device at once: Apple Watch, iPhone,
    iPad and iPhone Duo.

Run from the repository root:
    python3 docs/store-plan-a-2026-11-08/scripts/deck_devices_page.py
"""
import copy
import json
import os
import shutil
import sys

P = "design/app-store-studio-2026-10-29/app-store-screenshots.json"
BACKUP = P + ".before-devices-page-20261108"

LOCALES = ["zh", "zh-Hant", "en", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"]
APPROVED = ["zh", "zh-Hant", "en", "ja"]

CAPTION = {"x": 112, "y": 150, "width": 1096, "height": 545, "zIndex": 4}
DESC = {"x": 96, "y": 595, "width": 1128, "height": 140, "zIndex": 5}

# Device placement, in 1320-wide reference px. Heights follow each frame's own
# aspect ratio (see src/components/editor/device-lineup.tsx), so no width here is
# also a height. Two interchangeable compositions of the same four frames:
#
#   fan  — shipped. One card fanned from bottom-left to top-right: smallest first
#          (watch, most in front) and every next frame larger, tilted further right
#          and further back. Drama comes from the overlapping, so the copy above it
#          has to stay on two lines to keep the iPad's top edge clear.
#   grid — alternate. 2 x 2, baseline-aligned rows, 80 px gutters, tilts kept under
#          2° so all four screens stay upright and fully readable.
#
# Switch with: python3 deck_devices_page.py grid   (default is fan)
LAYOUTS = {
    "fan": {
        # Owner order (2026-11-08): Apple Watch → iPhone → iPhone Duo → iPad, i.e.
        # the phone must be the second card and the Duo the third. Every card tilts
        # ~10° further clockwise than the one in front of it.
        #
        # Widths are physical proportions (owner request 2026-11-09): the old
        # 310 / 450 / 520 / 590 made the iPad the shortest silhouette of the four
        # (590 wide → only 787 tall against the iPhone's 920), so the tablet read
        # as the smallest screen. Widths now follow each device's real width — a 13"
        # iPad is ~2.3× an iPhone, a Duo inner display ~1.55×, an Apple Watch case
        # ~0.7× (enlarged for legibility) — and heights come from each frame's own
        # aspect ratio: iPad 1040, Duo 768, iPhone 705, Watch 369. The tablet is
        # finally the tallest silhouette, and the cascade still fills 790 → 2790.
        "slots": [
            {"id": "watch", "x": 115, "y": 2244, "width": 270, "rotation": -14, "zIndex": 4},
            {"id": "iphone", "x": 210, "y": 1705, "width": 420, "rotation": -4, "zIndex": 3},
            {"id": "duo", "x": 355, "y": 1348, "width": 560, "rotation": 6, "zIndex": 2},
            {"id": "ipad", "x": 390, "y": 868, "width": 780, "rotation": 13, "zIndex": 1},
        ]
    },
    "grid": {
        "slots": [
            {"id": "ipad", "x": 75, "y": 860, "width": 640, "rotation": -2, "zIndex": 1},
            {"id": "duo", "x": 795, "y": 1051, "width": 450, "rotation": 2, "zIndex": 2},
            {"id": "iphone", "x": 285, "y": 1881, "width": 420, "rotation": -1.5, "zIndex": 3},
            {"id": "watch", "x": 785, "y": 2347, "width": 250, "rotation": 2, "zIndex": 4},
        ]
    },
}

DEVICES = {
    "id": "devices",
    "layout": "no-device",
    "label": {
        "zh": "05 / 全设备",
        "zh-Hant": "05 / 全裝置",
        "en": "05 / EVERY DEVICE",
        "ja": "05 / すべてのデバイス",
    },
    "headline": {
        "en": "One app,\nfor these screens",
        "zh": "每一块屏幕，\n都在一个 App 里",
        "zh-Hant": "每一塊螢幕，\n都在一個 App 裡",
        "ja": "iPhone も iPad も\nApple Watch も",
        # Untranslated locales keep the English placeholder until their copy is
        # approved (see pendingLocales).
        "ko": "One app,\nevery Apple screen",
        "es": "One app,\nevery Apple screen",
        "fr": "One app,\nevery Apple screen",
        "de": "One app,\nevery Apple screen",
        "it": "One app,\nevery Apple screen",
        "pt-BR": "One app,\nevery Apple screen",
        "ru": "One app,\nevery Apple screen",
        "ar": "One app,\nevery Apple screen",
    },
    "screenshot": "/screenshots/localized/iphone/{locale}/today.png",
    "inverted": True,
    "transforms": {"caption": CAPTION},
    "textElements": [
        {
            "id": "description",
            # Explicit break so the four device names stay on one line at 41 px.
            # Two lines only: the box is 140 px tall, so a third line would spill.
            # No sync claim — Masso has no iCloud multi-device sync (only the
            # iPhone↔Watch bridge), so the copy states app availability only.
            "text": {
                "en": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
                "zh": "iPhone、iPad、iPhone Duo、\nApple Watch 都支持，随时开练。",
                "zh-Hant": "iPhone、iPad、iPhone Duo、\nApple Watch 都已支援，隨時開練。",
                "ja": "iPhone・iPad・iPhone Duo・\nApple Watch にも対応しています。",
                "ko": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
                "es": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
                "fr": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
                "de": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
                "it": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
                "pt-BR": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
                "ru": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
                "ar": "Now on iPhone, iPad, iPhone Duo\nand Apple Watch.",
            },
            "transform": DESC,
            "fontSize": 41,
            "fontWeight": 400,
            "color": "#60625C",
            "align": "left",
        }
    ],
}

# Page 4 takes over the nutrition page, so its numbering follows.
DIET_LABEL = {
    "zh": "04 / 饮食与睡眠",
    "zh-Hant": "04 / 飲食與睡眠",
    "en": "04 / NUTRITION & SLEEP",
    "ja": "04 / 食事と睡眠",
}


def main() -> None:
    layout = sys.argv[1] if len(sys.argv) > 1 else "fan"
    if layout not in LAYOUTS:
        raise SystemExit(f"unknown layout {layout!r}; pick one of {sorted(LAYOUTS)}")

    if not os.path.exists(BACKUP):
        shutil.copy(P, BACKUP)
    with open(P) as f:
        doc = json.load(f)

    slides = doc["slidesByDevice"]["iphone"]
    # Idempotent: drop the retired progress page and any earlier devices page, so
    # re-running this script only refreshes the lineup coordinates.
    kept = [s for s in slides if s["id"] not in ("progress", "devices")]
    if [s["id"] for s in kept] != ["plan", "recovery", "training", "diet"]:
        raise SystemExit(f"unexpected deck order: {[s['id'] for s in kept]}")

    for slide in kept:
        if slide["id"] == "diet":
            slide["label"] = DIET_LABEL

    devices = copy.deepcopy(DEVICES)
    devices["lineup"] = LAYOUTS[layout]
    if "--rebuild-copy" in sys.argv:
        kept.append(devices)
    else:
        current = next((slide for slide in slides if slide["id"] == "devices"), None)
        if current is None:
            kept.append(devices)
        else:
            current["lineup"] = LAYOUTS[layout]
            kept.append(current)

    doc["slidesByDevice"]["iphone"] = kept
    doc["approvedLocales"] = APPROVED
    doc["pendingLocales"] = [locale for locale in LOCALES if locale not in APPROVED]

    with open(P, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print("deck:", " → ".join(s["id"] for s in kept), f"[layout {layout}]")


if __name__ == "__main__":
    main()
