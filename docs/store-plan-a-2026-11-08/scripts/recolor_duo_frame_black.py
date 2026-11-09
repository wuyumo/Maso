#!/usr/bin/env python3
"""Neutral-black adaptation of the Duo bezel already in this repo.

The snapshot only contains Apple's "iPhone Duo - Night Sky" product bezel
(`public/duo-frame.png`, blue-gray metal). There is no official black Duo
frame file in the tree, and this script does not invent one or fetch one.

It recolors bezel pixels only:
  * alpha is copied unchanged, so the screen hole stays transparent
  * chroma is removed (the Night Sky blue cast)
  * body luminance is lowered toward black metal
  * specular highlights above L=190 keep their brightness

Do not describe the result as an official Apple colorway.
Re-running on the already-adapted file is a no-op.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
FRAME = ROOT / "design/app-store-studio-2026-10-29/public/duo-frame.png"
NOTE = ROOT / "design/app-store-studio-2026-10-29/public/duo-frame-black.json"
NIGHT_SKY_SHA = "11eb961aad1a0766ace80f0433e4008fd5d67c19222df8e73ce90de47311dda4"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def map_luma(luma: float) -> float:
    # Body (the Night Sky face sits around L=43) drops toward black.
    # Highlights above 190 stay, so the rim light and buttons still read.
    t = luma / 255.0
    body = (t ** 1.65) * 255.0 * 0.90
    if luma <= 90:
        out = body
    elif luma >= 190:
        out = luma * 0.94
    else:
        u = (luma - 90) / 100.0
        out = body * (1 - u) + (luma * 0.94) * u
    return max(0.0, min(255.0, out))


def adapt(src: Image.Image) -> Image.Image:
    out = src.copy()
    pix = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a == 0:
                continue
            luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            n = int(map_luma(luma) + 0.5)
            pix[x, y] = (n, n, n, a)
    return out


def main() -> None:
    digest = sha256(FRAME)
    if NOTE.exists():
        note = json.loads(NOTE.read_text())
        if note.get("outputSha256") == digest:
            print("already black-adapted", digest)
            return
    if digest != NIGHT_SKY_SHA:
        raise SystemExit(f"refusing to recolor unexpected duo-frame.png sha {digest}")
    src = Image.open(FRAME).convert("RGBA")
    out = adapt(src)
    # Alpha must be identical so the screen hole is not painted black.
    sp, op = src.load(), out.load()
    w, h = src.size
    for y in range(0, h, 3):
        for x in range(0, w, 3):
            if sp[x, y][3] != op[x, y][3]:
                raise SystemExit("alpha changed; aborting")
    out.save(FRAME, format="PNG")
    output = sha256(FRAME)
    NOTE.write_text(json.dumps({
        "source": "public/duo-frame.png",
        "sourceName": "iPhone Duo - Night Sky - Inner Open Portrait (already cropped in this repo)",
        "sourceSha256": NIGHT_SKY_SHA,
        "outputSha256": output,
        "method": "neutral luminance curve on bezel pixels only; alpha copied; no screen pixels",
        "claim": "Not an official Apple black Duo bezel file. Black adaptation of the Night Sky asset in this snapshot.",
    }, indent=2) + "\n")
    print("wrote", FRAME, output)


if __name__ == "__main__":
    main()
