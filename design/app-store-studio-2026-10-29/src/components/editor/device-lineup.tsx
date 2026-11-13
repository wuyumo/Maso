"use client";
import * as React from "react";
import type { DeviceLineup as Lineup } from "@/lib/types";
import { lineupImage } from "@/lib/marketing-localized";
import { Duo, IPad, Phone, Watch } from "./device-frames";

/**
 * "Every supported device" portrait.
 *
 * The deck's other pages show one story on one device (plus a watch on the
 * training page). This page has to prove the opposite: the same app runs on an
 * iPhone, an iPad, an iPhone Duo and an Apple Watch.
 *
 * Composition (owner brief 2026-11-09): the four devices fan open like a hand of
 * cards — Apple Watch at the bottom-left, then the iPhone, then the Duo, then the
 * iPad at the top-right. Every device both *moves* along that bottom-left →
 * top-right diagonal and *tilts further clockwise* than the one before it, so the
 * eye gets one continuous gradient instead of four unrelated placements.
 *
 * Placement comes from the slide (`slide.lineup.slots`) in 1320-wide reference
 * px so it can be nudged without touching code; heights always follow each
 * frame's own aspect ratio so no device is ever stretched.
 */
const ASPECT: Record<string, number> = {
  iphone: 1350 / 2760,
  // Body aspect of the photographic bezel PNGs, not of their screen holes.
  ipad: 1600 / 2089,
  duo: 1600 / 2233,
  watch: 560 / 880,
};

/**
 * Bounding box of the cascade in reference px, with a little slop for the
 * rotations (a rotated frame pokes out of its unrotated rect).
 */
export function lineupBounds(lineup: Lineup) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const slot of lineup.slots) {
    const height = slot.width / (ASPECT[slot.id] ?? 1);
    const slop = Math.max(slot.width, height) * 0.04;
    minX = Math.min(minX, slot.x - slop);
    minY = Math.min(minY, slot.y - slop);
    maxX = Math.max(maxX, slot.x + slot.width + slop);
    maxY = Math.max(maxY, slot.y + height + slop);
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

/**
 * Fit the same cascade into another canvas (the iPad / Duo posters are wider and
 * shorter than the 1320 × 2868 phone canvas, so the phone page's raw scale would
 * push the watch off the bottom). Returns the scale plus the offsets that centre
 * the cluster inside `box`.
 */
export function fitLineup(lineup: Lineup, box: { x: number; y: number; width: number; height: number }) {
  const bounds = lineupBounds(lineup);
  const scale = Math.min(box.width / bounds.width, box.height / bounds.height);
  return {
    scale,
    offsetX: box.x + (box.width - bounds.width * scale) / 2 - bounds.x * scale,
    offsetY: box.y + (box.height - bounds.height * scale) / 2 - bounds.y * scale,
  };
}

export function DeviceLineup({
  lineup,
  locale,
  scale = 1,
  offsetX = 0,
  offsetY = 0,
}: {
  lineup: Lineup;
  locale: string;
  scale?: number;
  offsetX?: number;
  offsetY?: number;
}) {
  return (
    <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
      {lineup.slots.map((slot, index) => {
        const candidateNative51=(lineup as Lineup & {candidateSourceSet?:string}).candidateSourceSet==="native51-20261113";
        const src = lineupImage(slot.id, locale, candidateNative51);
        if (!src) return null;
        const width = slot.width * scale;
        const height = width / (ASPECT[slot.id] ?? 1);
        const rotation = slot.rotation ?? 0;
        const style: React.CSSProperties = {
          position: "absolute",
          left: slot.x * scale + offsetX,
          top: slot.y * scale + offsetY,
          width,
          height,
          transform: rotation ? `rotate(${rotation}deg)` : undefined,
          zIndex: slot.zIndex ?? index + 1,
        };
        const alt =
          slot.id === "watch"
            ? "Masso on Apple Watch"
            : slot.id === "ipad"
              ? "Masso on iPad"
              : slot.id === "duo"
                ? "Masso on iPhone Duo"
                : "Masso on iPhone";
        const Frame = slot.id === "watch" ? Watch : slot.id === "ipad" ? IPad : slot.id === "duo" ? Duo : Phone;
        return <Frame key={slot.id} src={src} alt={alt} style={style} hideEmpty />;
      })}
    </div>
  );
}
