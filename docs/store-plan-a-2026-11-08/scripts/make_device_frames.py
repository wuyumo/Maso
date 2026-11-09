#!/usr/bin/env python3
"""Generate the photographic-style iPad and iPhone Duo bezel overlays used by page 05.

Why this exists
---------------
The iPhone (`public/mockup.png`) and the Apple Watch (`public/watch-frame.png`) are
bitmap bezels: the app screenshot sits *behind* them and the PNG punches the screen
out as transparent. The iPad and the Duo had no such asset, so
`src/components/editor/device-frames.tsx` drew them out of CSS gradients — which is
exactly what the owner asked to stop doing ("找个 mockup 把截图做在 mockup 上").

This script bakes the same treatment for those two devices, following the measured
anatomy of `mockup.png` (dark aluminium edge → 1 px bright rim light → black glass
bezel → screen), plus brushed micro-noise, side buttons, a front camera, and — for
the foldable — the centre crease. Everything is rendered with 4x supersampling and
a transparent screen hole, so it drops into the same overlay slot as mockup.png:

    python3 docs/store-plan-a-2026-11-08/scripts/make_device_frames.py

It prints the screen rectangle in percent of the frame; keep `IPAD_SCREEN` /
`DUO_SCREEN` in src/components/editor/device-frames.tsx in sync with that output.
"""
from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path("design/app-store-studio-2026-10-29/public")
SS = 2  # supersampling factor -> antialiased edges after the final downsample

DEVICES = {
    # 13" iPad Pro (2064 x 2752 screenshot). Bezels are thin on the real thing; the
    # frame keeps ~2.6 % of the width so the body still reads at poster scale.
    "ipad": dict(
        width=1500,
        aspect=2064 / 2752,
        bezel=0.026,
        radius_out=0.058,
        radius_in=0.043,
        camera="top-centre",
        crease=None,
        buttons=[("right", 0.045, 0.026, 0.075), ("right", 0.083, 0.026, 0.075)],
    ),
    # Foldable ("iPhone Duo"), 2007 x 2853 inner display.
    "duo": dict(
        width=1400,
        aspect=2007 / 2853,
        bezel=0.024,
        radius_out=0.062,
        radius_in=0.048,
        camera="top-centre",
        crease=0.052,
        buttons=[("right", 0.070, 0.050, 0.048), ("left", 0.058, 0.030, 0.070), ("left", 0.100, 0.030, 0.070)],
    ),
}


def rounded(w: int, h: int, box, radius: float) -> np.ndarray:
    """Antialiased rounded-rect coverage in [0, 1] (drawn 4x, box-filtered)."""
    k = 4
    img = Image.new("L", (w * k, h * k), 0)
    x0, y0, x1, y1 = (v * k for v in box)
    ImageDraw.Draw(img).rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=radius * k, fill=255)
    return np.asarray(img.resize((w, h), Image.LANCZOS), dtype=np.float32) / 255.0


def ramp(w: int, h: int, angle_deg: float = 150.0) -> np.ndarray:
    """0..1 ramp along `angle_deg` (light comes from the top-left)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = np.deg2rad(angle_deg)
    t = np.cos(a) * xx / w + np.sin(a) * yy / h
    t -= t.min()
    return t / max(float(t.max()), 1e-6)


def build(name: str, spec: dict) -> tuple[pathlib.Path, dict]:
    W = spec["width"]
    H = int(round(W / spec["aspect"]))
    w, h = W * SS, H * SS
    px = W * SS / 1500.0  # geometry below is written for a 1500 px reference width

    bezel = spec["bezel"] * w
    r_out = spec["radius_out"] * w
    r_in = spec["radius_in"] * w
    edge = 3.0 * SS * px        # dark aluminium shoulder, outside the rim light
    rim = 1.1 * SS * px         # the bright rim hairline itself (native px)

    body = rounded(w, h, (0, 0, w, h), r_out)
    glass = rounded(w, h, (edge, edge, w - edge, h - edge), r_out - edge * 0.4)
    screen = rounded(w, h, (bezel, bezel, w - bezel, h - bezel), r_in)

    light = 1.0 - ramp(w, h, 150)          # 1 at top-left, 0 at bottom-right
    rgb = np.zeros((h, w, 3), dtype=np.float32)
    alpha = np.zeros((h, w), dtype=np.float32)

    # --- 1. aluminium shoulder: dark graphite, lit from the top-left ---------------
    alu = np.array([0.055, 0.055, 0.057], dtype=np.float32) + light[..., None] * np.array([0.10, 0.10, 0.105], dtype=np.float32)
    rgb[:] = alu
    alpha[:] = body

    # --- 2. black glass bezel with an inner bevel --------------------------------
    glass_body = np.clip(glass, 0, 1)
    inner = np.clip(1.0 - (bezel + 0.004 * w) / (0.004 * w) * (1 - screen), 0, 1)  # soft falloff into the screen
    bezel_tone = 0.032 + 0.070 * np.clip(1 - inner, 0, 1) * light
    glass_rgb = np.stack([bezel_tone * 1.0, bezel_tone * 1.0, bezel_tone * 1.04], axis=-1)
    rgb = rgb * (1 - glass_body[..., None]) + glass_rgb * glass_body[..., None]

    # --- 3. rim light: bright line on the outer aluminium edge -------------------
    rim_ring = np.clip(
        rounded(w, h, (edge - rim, edge - rim, w - edge + rim, h - edge + rim), r_out - edge * 0.2) - glass,
        0, 1,
    )
    # soft, directional edge light: bright where the key light hits, almost gone
    # in the shadow side, and blurred so it never reads as a drawn white outline
    rim_soft = np.asarray(
        Image.fromarray((rim_ring * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.1 * SS)),
        dtype=np.float32,
    ) / 255.0
    rim_tone = 0.05 + 0.42 * light
    rgb += rim_soft[..., None] * rim_tone[..., None] * np.array([0.58, 0.59, 0.61], dtype=np.float32)

    # --- 4. brushed micro noise on the metal only --------------------------------
    rng = np.random.default_rng(11)
    metal_mask = np.clip(alpha - glass, 0, 1)
    rgb += rng.normal(0.0, 0.016, size=(h, w, 1)).astype(np.float32) * metal_mask[..., None]

    # --- 5. screen: vignette + specular streak + crease, as a translucent overlay -
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx, ny = (xx / w - 0.5) * 2, (yy / h - 0.5) * 2
    vig = np.clip(np.sqrt(nx * nx + ny * ny) / np.sqrt(2.0), 0, 1) ** 2 * 0.26
    ang = ramp(w, h, 122)
    streak = np.clip((ang - 0.40) * 7.0, 0, 1) * np.clip((0.60 - ang) * 7.0, 0, 1) * 0.09
    dark_a = screen * vig
    light_a = screen * streak

    if spec["crease"]:
        dx = np.abs(xx - w / 2.0) / (spec["crease"] * w)
        band = np.clip(1.0 - dx, 0, 1) ** 1.5 * screen
        dark_a = np.maximum(dark_a, band * 0.09)
        light_a = np.maximum(light_a, band * band * 0.05)

    # --- 6. camera ---------------------------------------------------------------
    cw = 0.019 * w * px
    if spec["camera"] == "top-centre":
        cx, cy = w / 2.0, (edge + bezel) / 2.0
        lens_a = 1.0
    else:  # punch-hole inside the display, like the iPhone's baked-in island
        cx, cy = w / 2.0 + 0.17 * w, bezel + cw * 0.95
        lens_a = 1.0
    cam = rounded(w, h, (cx - cw * 0.62, cy - cw * 0.62, cx + cw * 0.62, cy + cw * 0.62), cw * 0.62)
    cam_ring = rounded(w, h, (cx - cw * 0.50, cy - cw * 0.50, cx + cw * 0.50, cy + cw * 0.50), cw * 0.50)
    cam_lens = rounded(w, h, (cx - cw * 0.34, cy - cw * 0.34, cx + cw * 0.34, cy + cw * 0.34), cw * 0.34)
    cam_glint = rounded(w, h, (cx - cw * 0.13, cy - cw * 0.20, cx - cw * 0.02, cy - cw * 0.09), cw * 0.1)
    rgb = rgb * (1 - cam[..., None]) + cam[..., None] * np.array([0.02, 0.02, 0.024], dtype=np.float32)
    rgb = rgb * (1 - cam_ring[..., None]) + cam_ring[..., None] * np.array([0.13, 0.13, 0.145], dtype=np.float32)
    rgb = rgb * (1 - cam_lens[..., None]) + cam_lens[..., None] * np.array([0.05, 0.055, 0.08], dtype=np.float32)
    rgb = rgb * (1 - cam_glint[..., None]) + cam_glint[..., None] * np.array([0.30, 0.32, 0.40], dtype=np.float32)
    alpha = np.clip(alpha + cam * lens_a, 0, 1)

    # --- 7. side buttons ---------------------------------------------------------
    for side, y0, bw, bh in spec["buttons"]:
        bwpx, bhpx = bw * w, bh * w
        y = y0 * h
        box = (w - bwpx * 0.5, y, w + bwpx * 0.5, y + bhpx) if side == "right" else (-bwpx * 0.5, y, bwpx * 0.5, y + bhpx)
        btn = rounded(w, h, box, bwpx * 0.45)
        btn_rgb = np.array([0.055, 0.055, 0.058], dtype=np.float32) + light[..., None] * np.array([0.13, 0.13, 0.14], dtype=np.float32)
        rgb = rgb * (1 - btn[..., None]) + btn_rgb * btn[..., None]
        alpha = np.clip(alpha + btn, 0, 1)

    # --- composite: keep the screen hole transparent, but let glass tint through ---
    out_a = alpha * (1 - screen) + screen * np.clip(dark_a + light_a, 0, 0.42)
    out_rgb = rgb.copy()
    lit = np.clip(dark_a + light_a, 1e-6, 1)
    out_rgb = out_rgb * (1 - screen[..., None]) + (
        (light_a[..., None] * 1.0 + dark_a[..., None] * 0.0) / lit[..., None]
    ) * screen[..., None]
    out_rgb = np.clip(out_rgb, 0, 1)

    out = np.dstack([(out_rgb * 255).round(), (out_a * 255).round()]).astype(np.uint8)
    img = Image.fromarray(out).resize((W, H), Image.LANCZOS)
    path = OUT / f"{name}-frame.png"
    img.save(path)

    pct = dict(
        L=round(bezel / w * 100, 3),
        T=round(bezel / h * 100, 3),
        W=round((w - 2 * bezel) / w * 100, 3),
        H=round((h - 2 * bezel) / h * 100, 3),
        RX=round(r_in / w * 100, 3),
        RY=round(r_in / h * 100, 3),
    )
    return path, dict(size=(W, H), screen=pct)


if __name__ == "__main__":
    for device, spec in DEVICES.items():
        path, info = build(device, spec)
        print(f"{path}  {info['size'][0]}x{info['size'][1]}  screen% {info['screen']}")
