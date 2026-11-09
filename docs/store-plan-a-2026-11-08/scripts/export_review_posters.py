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
OUT = ROOT / "docs/store-review-2026-11-09/exported/ios"
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


def inner_status(device: str, slide: str, locale: str) -> str:
    # What this snapshot can honestly show. Page 01 is drawn copy, not a native capture.
    if slide == "plan":
        return "marketing-chat"
    have = {
        ("iphone", "diet", "en"), ("iphone", "diet", "zh"),
        ("ipad", "diet", "en"), ("ipad", "diet", "zh"),
        ("iphone", "devices", "en"), ("iphone", "devices", "zh"),
        ("ipad", "devices", "en"), ("ipad", "devices", "zh"),
    }
    if (device, slide, locale) in have:
        return "native-captures-present"
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
    jobs = [
        (device, w, h, slide, locale)
        for device, w, h, slides in JOBS
        for locale in LOCALES
        for slide in slides
    ]
    rows = []
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(one, job) for job in jobs]
        for fut in as_completed(futures):
            row = fut.result()
            rows.append(row)
            print(row["file"], row["width"], row["height"], row["mode"], row["inner"], "corner", row["cornerBright"], flush=True)
    rows.sort(key=lambda row: row["file"])
    manifest = {
        "batch": "store-review-2026-11-09",
        "status": "draft review, not upload-approved",
        "duoFrame": "neutral-black adaptation of the in-repo Night Sky bezel; not an official black SKU file",
        "counts": {
            "files": len(rows),
            "marketingChat": sum(r["inner"] == "marketing-chat" for r in rows),
            "nativeCapturesPresent": sum(r["inner"] == "native-captures-present" for r in rows),
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
