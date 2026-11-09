#!/usr/bin/env python3
"""Export the review batch from a running Studio production server.

Does not overwrite docs/store-plan-a-2026-11-08/exported.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
# EXPORT_DIR writes a side batch. The default path stays the previous review
# export so a partial rerun cannot replace that baseline by accident.
OUT = Path(os.environ["EXPORT_DIR"]).resolve() if os.environ.get("EXPORT_DIR") else ROOT / "docs/store-review-2026-11-09/exported/ios"
CHROME = "google-chrome"
BASE = "http://127.0.0.1:3456"
LOCALES = ["zh", "zh-Hant", "en", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"]
JOBS = [
    ("iphone", 1320, 2868, ["plan", "recovery", "training", "diet", "devices"]),
    ("ipad", 2064, 2752, ["plan", "recovery", "diet", "devices"]),
]
NAMES = {
    "plan": "01-plan.png",
    "recovery": "02-recovery.png",
    "training": "03-training.png",
    "diet": "04-diet.png",
    "devices": "05-devices.png",
}


def shot(url: str, dest: Path, w: int, h: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".raw.png")
    if tmp.exists():
        tmp.unlink()
    profile = Path(f"/tmp/cr-shot-{os.getpid()}-{dest.parent.name}-{dest.stem}")
    cmd = [
        CHROME, "--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage",
        "--hide-scrollbars", "--force-device-scale-factor=1", f"--window-size={w},{h}",
        f"--user-data-dir={profile}", "--remote-debugging-port=0",
        "--virtual-time-budget=10000", f"--screenshot={tmp}", url,
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 35
    stable = 0
    last = -1
    while time.time() < deadline:
        if tmp.exists():
            size = tmp.stat().st_size
            if size > 20000 and size == last:
                stable += 1
                if stable >= 2:
                    break
            else:
                stable = 0
            last = size
        if proc.poll() is not None and tmp.exists() and tmp.stat().st_size > 20000:
            break
        time.sleep(0.25)
    if proc.poll() is None:
        proc.kill()
        proc.wait(timeout=5)
    if not tmp.exists() or tmp.stat().st_size < 20000:
        raise SystemExit(f"screenshot failed for {url}")
    im = Image.open(tmp).convert("RGB")
    if im.size != (w, h):
        # Headless Chrome sometimes adds a scrollbar gutter. Keep the top-left canvas.
        if im.size[0] >= w and im.size[1] >= h:
            im = im.crop((0, 0, w, h))
        else:
            raise SystemExit(f"unexpected size {im.size} for {dest}")
    im.save(dest, format="PNG")
    tmp.unlink(missing_ok=True)
    shutil.rmtree(profile, ignore_errors=True)


def one(job):
    device, w, h, slide, locale = job
    name = NAMES[slide]
    dest = OUT / device / f"{w}x{h}" / locale / name
    url = f"{BASE}/render?device={device}&slide={slide}&locale={locale}"
    shot(url, dest, w, h)
    im = Image.open(dest)
    bright = badge_pixels(im)
    inner = inner_status(device, slide, locale)
    return {
        "file": f"{device}/{w}x{h}/{locale}/{name}",
        "width": im.size[0],
        "height": im.size[1],
        "mode": im.mode,
        "cornerBright": bright,
        "inner": inner,
        "uploadReady": False,
    }


PUB = ROOT / "design/app-store-studio-2026-10-29/public/screenshots/localized"


def have(family: str, locale: str, name: str) -> bool:
    return (PUB / family / locale / name).is_file()


def inner_status(device: str, slide: str, locale: str) -> str:
    # Page 01 is drawn chat, not a native capture. A partial page is not done.
    if slide == "plan":
        return "marketing-chat"
    if slide == "recovery":
        # iPhone uses iphone/muscle-selected. iPad asks for ipad/muscle-selected,
        # which is not part of the Mac capture set and is not filled from the phone.
        family = "iphone" if device == "iphone" else "ipad"
        return "native-captures-present" if have(family, locale, "muscle-selected.png") else "capture-missing"
    if slide == "training":
        phone = have("iphone", locale, "player-heart-warning.png")
        watch = have("watch", locale, "exercise-185.png")
        if phone and watch:
            return "native-captures-present"
        return "capture-partial" if phone or watch else "capture-missing"
    if slide == "diet":
        family = "ipad" if device == "ipad" else "iphone"
        if have(family, locale, "diet.png") and have(family, locale, "sleep.png"):
            return "native-captures-present"
        return "capture-missing"
    if slide == "devices":
        slots = [
            have("iphone", locale, "today.png"),
            have("ipad", locale, "insights.png"),
            have("duo", locale, "diet.png"),
            have("watch", locale, "rest-160.png"),
        ]
        if all(slots):
            return "native-captures-present"
        return "capture-partial" if any(slots) else "capture-missing"
    return "capture-missing"


def badge_pixels(im: Image.Image) -> int:
    w, h = im.size
    px = im.load()
    n = 0
    for y in range(h - 80, h):
        for x in range(0, 80):
            r, g, b = px[x, y]
            if r > 180 and g > 180 and b > 180:
                n += 1
    return n


def main() -> None:
    only_slides = set(os.environ.get("EXPORT_SLIDES", "").split()) - {""}
    only_locales = set(os.environ.get("EXPORT_LOCALES", "").split()) - {""}
    jobs = [
        (device, w, h, slide, locale)
        for device, w, h, slides in JOBS
        for locale in LOCALES
        for slide in slides
        if (not only_slides or slide in only_slides) and (not only_locales or locale in only_locales)
    ]
    rows = []
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(one, job) for job in jobs]
        for fut in as_completed(futures):
            row = fut.result()
            rows.append(row)
            print(row["file"], row["width"], row["height"], row["mode"], row["inner"], "corner", row["cornerBright"], flush=True)
    rows.sort(key=lambda row: row["file"])
    path = OUT.parent / "export-validation.json"
    if (only_slides or only_locales) and path.exists():
        previous = json.loads(path.read_text())
        by_file = {row["file"]: row for row in previous.get("files", [])}
        for row in rows:
            by_file[row["file"]] = row
        rows = sorted(by_file.values(), key=lambda row: row["file"])
    manifest = {
        "batch": os.environ.get("EXPORT_BATCH", "store-review-2026-11-09"),
        "status": "draft review, not upload-approved",
        "duoFrame": "neutral-black adaptation of the in-repo Night Sky bezel; not an official black SKU file",
        "counts": {
            "files": len(rows),
            "marketingChat": sum(r["inner"] == "marketing-chat" for r in rows),
            "nativeCapturesPresent": sum(r["inner"] == "native-captures-present" for r in rows),
            "capturePartial": sum(r["inner"] == "capture-partial" for r in rows),
            "captureMissing": sum(r["inner"] == "capture-missing" for r in rows),
        },
        "files": rows,
    }
    path = OUT.parent / "export-validation.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    bad = [r for r in rows if r["mode"] != "RGB" or r["cornerBright"] > 20 or (r["width"], r["height"]) not in ((1320, 2868), (2064, 2752))]
    print("files", len(rows), "problems", len(bad), flush=True)
    if bad:
        raise SystemExit(json.dumps(bad[:8], indent=2))


if __name__ == "__main__":
    main()
