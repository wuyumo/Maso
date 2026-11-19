"use client";
import * as React from "react";
import { ANTERIOR, ANATOMY_H, ANATOMY_W, POSTERIOR, expandMuscles } from "@/lib/anatomy";
import type { AnatomyPoly } from "@/lib/anatomy";

// Front/back muscle diagram for the marketing poster.
//
// Mirrors Maso/Views/Components/BodyHint.swift + MuscleVisualBlock.swift:
//   - square slot of `side` px, body drawn at `side * 0.82` tall (MuscleVisualBlock's bodyHintHeight)
//   - front and back panels sit flush (panelSpacing 0), each locked square, centred in its panel
//   - idle muscle = white @22%, hit muscle = accent, hairline #1F1F1F separators
//   - every polygon gets the App's 2.5-unit corner rounding
// Polygon data comes from Anatomy.swift via scripts/port_anatomy.py.

function parsePoints(raw: string): number[][] {
  const nums = raw.split(/[ ,]+/).filter(Boolean).map(Number);
  const out: number[][] = [];
  for (let i = 0; i + 1 < nums.length; i += 2) out.push([nums[i], nums[i + 1]]);
  return out;
}

/** Same corner rounding as `roundedPolygonPath` in BodyHint.swift. */
function roundedPath(pts: number[][], radius: number): string {
  const n = pts.length;
  if (n < 3) return "";
  const enter: number[][] = [];
  const exit: number[][] = [];
  for (let i = 0; i < n; i++) {
    const prev = pts[(i + n - 1) % n];
    const cur = pts[i];
    const next = pts[(i + 1) % n];
    const dxPrev = prev[0] - cur[0];
    const dyPrev = prev[1] - cur[1];
    const dxNext = next[0] - cur[0];
    const dyNext = next[1] - cur[1];
    const lenPrev = Math.max(0.0001, Math.hypot(dxPrev, dyPrev));
    const lenNext = Math.max(0.0001, Math.hypot(dxNext, dyNext));
    const r = Math.min(radius, Math.min(lenPrev, lenNext) * 0.5);
    enter.push([cur[0] + (dxPrev / lenPrev) * r, cur[1] + (dyPrev / lenPrev) * r]);
    exit.push([cur[0] + (dxNext / lenNext) * r, cur[1] + (dyNext / lenNext) * r]);
  }
  let d = `M${exit[0][0]} ${exit[0][1]}`;
  for (let i = 0; i < n; i++) {
    const next = (i + 1) % n;
    d += `L${enter[next][0]} ${enter[next][1]}`;
    d += `Q${pts[next][0]} ${pts[next][1]} ${exit[next][0]} ${exit[next][1]}`;
  }
  return d + "Z";
}

function panel(
  polys: AnatomyPoly[],
  dx: number,
  scale: number,
  hit: Set<string>,
  accent: string,
  stroke: number,
) {
  return polys.map((poly, index) => {
    const pts = parsePoints(poly.p);
    if (pts.length < 3) return null;
    const scaled = pts.map(([x, y]) => [dx + x * scale, y * scale]);
    const fill = hit.has(poly.m) ? accent : "rgba(255, 255, 255, 0.22)";
    return (
      <path
        key={`${poly.m}-${index}`}
        d={roundedPath(scaled, 2.5 * scale)}
        fill={fill}
        stroke={stroke > 0 ? `rgb(31, 31, 31)` : "none"}
        strokeWidth={stroke}
        strokeLinejoin="round"
      />
    );
  });
}

export function MuscleMap({
  muscles,
  side,
  accent,
  stroke = 0.6,
}: {
  muscles: string[];
  /** Square slot size in canvas px — same role as MuscleVisualBlock.sideLength. */
  side: number;
  accent: string;
  stroke?: number;
}) {
  const hit = React.useMemo(() => expandMuscles(muscles), [muscles]);
  // BodyHint.square == false: panel width = height * (viewBox.width / viewBox.height)
  // = height / 2, so the two flush panels are 0.82 * side wide in total and the
  // whole diagram is aspect-fit and centred inside the square slot.
  const h = side * 0.82; // MuscleVisualBlock.bodyHintHeight
  const scale = h / ANATOMY_H;
  const panelW = ANATOMY_W * scale;
  const top = (side - h) / 2;
  const left = (side - panelW * 2) / 2;

  return (
    <svg
      width={side}
      height={side}
      viewBox={`0 0 ${side} ${side}`}
      style={{ display: "block", overflow: "visible" }}
      aria-hidden
    >
      <g transform={`translate(${left}, ${top})`}>
        {panel(ANTERIOR, 0, scale, hit, accent, stroke)}
        {panel(POSTERIOR, panelW, scale, hit, accent, stroke)}
      </g>
    </svg>
  );
}
