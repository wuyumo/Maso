#!/usr/bin/env python3
"""Port the App's anatomy polygons into the Store Studio (React) poster.

Maso/Data/Anatomy.swift is the single source of truth for the BodyHint
silhouette (react-body-highlighter, MIT). The 01 plan poster draws the same
muscle diagram behind the AI Coach report bubble, so instead of eyeballing a
lookalike we regenerate the polygon table from the Swift source.

Usage:
    python3 docs/store-plan-a-2026-11-08/scripts/port_anatomy.py

Writes: design/app-store-studio-2026-10-29/src/lib/anatomy.ts
"""

from __future__ import annotations

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3]
SWIFT = ROOT / "Maso/Data/Anatomy.swift"
OUT = ROOT / "design/app-store-studio-2026-10-29/src/lib/anatomy.ts"

POSTERIOR_SCALE = 200.0 / 220.0


def parse_points(raw: str) -> list[list[float]]:
    nums = [float(t) for t in raw.replace(",", " ").split()]
    return [[nums[i], nums[i + 1]] for i in range(0, len(nums) - 1, 2)]


def main() -> None:
    src = SWIFT.read_text()
    raw = dict(re.findall(r'static let (\w+) = "([^"]*)"', src))

    def entries(start: str, end: str) -> list[tuple[str, str]]:
        body = src[src.index(start) : src.index(end)]
        pat = (
            r"AnatomyPolygon\(muscle: \.(\w+), points: (?:scaleY\()?parse\(R\.(\w+)\)"
            r"(?:, posteriorScale\))?\)"
        )
        return re.findall(pat, body)

    anterior = entries("let ANTERIOR: [AnatomyPolygon] = [", "let POSTERIOR: [AnatomyPolygon] = [")
    posterior = entries("let POSTERIOR: [AnatomyPolygon] = [", "// MARK: - 视图尺寸常量")

    def build(items, scale=1.0):
        out = []
        for muscle, key in items:
            pts = parse_points(raw[key])
            if scale != 1.0:
                pts = [[x, y * scale] for x, y in pts]
            out.append({"m": muscle, "p": [[round(x, 2), round(y, 2)] for x, y in pts]})
        return out

    data = {
        "anterior": build(anterior),
        "posterior": build(posterior, POSTERIOR_SCALE),
    }

    def fmt(polys, name):
        lines = [f"export const {name}: AnatomyPoly[] = ["]
        for poly in polys:
            pts = ",".join(f"{x} {y}" for x, y in poly["p"])
            lines.append(f'  {{ m: "{poly["m"]}", p: "{pts}" }},')
        lines.append("];")
        return "\n".join(lines)

    header = """// Anatomy polygon data — ported 1:1 from Maso/Data/Anatomy.swift
// (react-body-highlighter, MIT, https://github.com/giavinh79/react-body-highlighter).
//
// Source of truth for the App's BodyHint silhouette; the marketing poster renders
// the same polygons as SVG so the muscle diagram matches the App exactly.
// Coordinate space: 100 wide x 200 tall. Posterior polygons were already scaled by
// 200/220 in Anatomy.swift, so both sets share one coordinate system.
//
// Generated from the Swift source — do not hand-edit; re-run
// docs/store-plan-a-2026-11-08/scripts/port_anatomy.py after changing Anatomy.swift.

export type AnatomyPoly = {
  /** Muscle id used by Anatomy.swift (chest, upperLats, lowerBack, ...). */
  m: string;
  /** Flat "x y x y ..." point list. */
  p: string;
};

/** Anatomy viewBox — matches AnatomyView.width / .height in the App. */
export const ANATOMY_W = 100;
export const ANATOMY_H = 200;

"""

    groups = """
/**
 * Poster-level muscle groups -> the polygon ids that light up, mirroring
 * `expandAnatomyMuscles` in Anatomy.swift (e.g. `.back` lights trapezius,
 * lats and lower back; `.chest` lights both pec polygons).
 */
export const MUSCLE_POLYGONS: Record<string, string[]> = {
  chest: ["chest"],
  back: ["upperTraps", "upperLats", "lowerBack"],
  shoulders: ["frontDelts", "rearDelts"],
  delts: ["frontDelts", "rearDelts"],
  biceps: ["biceps"],
  triceps: ["triceps"],
  arms: ["biceps", "triceps", "forearms"],
  forearms: ["forearms"],
  abs: ["abs"],
  core: ["abs", "obliques"],
  obliques: ["obliques"],
  traps: ["upperTraps"],
  lats: ["upperLats"],
  lowerBack: ["lowerBack"],
  glutes: ["glutes", "gluteusMedius"],
  hamstrings: ["hamstrings"],
  quads: ["quads"],
  adductors: ["adductors"],
  legs: ["quads", "hamstrings", "glutes", "gluteusMedius", "adductors", "calves", "soleus", "tibialisAnterior"],
  calves: ["calves", "soleus", "tibialisAnterior"],
  tibialisAnterior: ["tibialisAnterior"],
  neck: ["neck"],
};

/** Expand poster-level groups into the polygon ids that render highlighted. */
export function expandMuscles(muscles: string[]): Set<string> {
  const out = new Set<string>();
  for (const g of muscles) {
    const polys = MUSCLE_POLYGONS[g];
    if (polys) polys.forEach((p) => out.add(p));
    else out.add(g);
  }
  return out;
}
"""

    ts = header + fmt(data["anterior"], "ANTERIOR") + "\n\n" + fmt(data["posterior"], "POSTERIOR") + "\n" + groups
    OUT.write_text(ts)
    print(f"wrote {OUT.relative_to(ROOT)} — {len(data['anterior'])} anterior, {len(data['posterior'])} posterior polys")


if __name__ == "__main__":
    main()
