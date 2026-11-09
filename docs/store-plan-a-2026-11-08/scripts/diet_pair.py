import json
import pathlib

P = pathlib.Path('/Users/yumowu/Projects/Maso-iOS/design/app-store-studio-2026-10-29/app-store-screenshots.json')
doc = json.loads(P.read_text())

ASPECT = 1350 / 2760


def box(x, y, w, rot, z):
    return {"x": x, "y": y, "width": w, "height": round(w / ASPECT, 2), "rotation": rot, "zIndex": z}


for slide in doc["slidesByDevice"]["iphone"]:
    if slide["id"] != "diet":
        continue
    # Owner order (2026-11-09): the diet screen is the front-left card in the top
    # layer, the sleep screen sits behind it on the right in the lower layer.
    #
    # Sizes are set so both screens stay recognisable inside 1320 px:
    #   * diet  800 wide at (-3°) → rotated bbox 884 × 1675, left edge 18, right 902,
    #           bottom 2651 (the frame's own height, 2.044× its width, is what makes
    #           it reach the bottom without any crop).
    #   * sleep 620 wide at (+3°) → bbox 685 × 1298, left 903 (just clear of the diet
    #           edge, so its "睡眠" title and the 7h34 number are never covered),
    #           right 1588 — the outer 268 px run off the canvas, the same
    #           bleed-off-edge convention the page used before.
    # Anything wider than 620 for the sleep pushes its title back under the diet;
    # anything wider than ~800 for the diet pushes the sleep past 40% off-canvas.
    slide["transforms"]["device"] = box(60, 1010, 800, -3, 3)
    slide["transforms"]["deviceSecondary"] = box(938, 1165, 620, 3, 2)
    slide["screenshot"], slide["screenshotSecondary"] = (
        "/screenshots/localized/iphone/{locale}/diet.png",
        "/screenshots/localized/iphone/{locale}/sleep.png",
    )
    print(json.dumps(slide["transforms"], ensure_ascii=False))

P.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
print("ok")
