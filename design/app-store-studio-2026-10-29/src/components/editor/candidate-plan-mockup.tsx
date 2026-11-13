"use client";
import * as React from "react";
import { PHONE_SCREEN } from "@/lib/constants";
import type { ChatThread, Theme } from "@/lib/types";
import { candidatePlanUnit, candidatePlanShiftX } from "@/lib/candidate-plan-presentation";
import { IPAD_SCREEN, DUO_SCREEN, IPAD_FRAME_ASPECT, DUO_FRAME_ASPECT } from "./device-frames";
import { CoachChat } from "./coach-chat";

export function candidatePlanFrame(device: string) {
  if (device === "iphone" || device === "iphone-medium") return { src: "/mockup.png", aspect: 1350 / 2760, screen: PHONE_SCREEN, topInset: 80 };
  if (device === "ipad") return { src: "/ipad-frame.png", aspect: IPAD_FRAME_ASPECT, screen: IPAD_SCREEN, topInset: 24 };
  if (device === "duo") return { src: "/duo-frame.png", aspect: DUO_FRAME_ASPECT, screen: DUO_SCREEN, topInset: 24 };
  return null;
}

export function candidatePlanMockupGeometry(device: string, canvas: { w: number; h: number }, chat: ChatThread) {
  const frame = candidatePlanFrame(device);
  if (!frame) return null;
  const phone = device === "iphone" || device === "iphone-medium";
  const unit = candidatePlanUnit(canvas, phone, chat);
  const height = (chat.height || 2050) * unit;
  const width = height * frame.aspect;
  const left = phone ? chat.x * unit : (canvas.w - width) / 2;
  const top = phone ? chat.y * unit : 900;
  const shift = candidatePlanShiftX(canvas, phone, { ...chat, width: width / unit });
  const content: ChatThread = { ...chat, x: 16, y: frame.topInset,
    width: width * frame.screen.W / 100 / unit - 32,
    height: height * frame.screen.H / 100 / unit - frame.topInset - 36 };
  return { frame, unit, width, height, left, top, shift, content };
}

/** Existing photographed bezel and aperture, containing the unchanged real chat. */
export function CandidatePlanMockup({ device, canvas, chat, theme, locale }: {
  device: string; canvas: { w: number; h: number }; chat: ChatThread; theme: Theme; locale: string;
}) {
  const g = candidatePlanMockupGeometry(device, canvas, chat);
  if (!g) return null;
  const { frame, unit } = g;
  return <div data-candidate-plan-mockup={device} style={{ left: g.left, top: g.top, width: g.width, height: g.height,
    "--candidate-plan-shift-x": `${g.shift}px` } as React.CSSProperties}>
    <div data-candidate-chat-aperture="1" style={{ position: "absolute", left: `${frame.screen.L}%`, top: `${frame.screen.T}%`,
      width: `${frame.screen.W}%`, height: `${frame.screen.H}%`, borderRadius: `${frame.screen.RX}% / ${frame.screen.RY}%`,
      overflow: "hidden", background: "#111317", zIndex: 1 }}>
      <CoachChat chat={g.content} cW={1320 * unit} theme={theme} locale={locale} />
    </div>
    <img data-candidate-device-bezel="1" src={frame.src} alt="" draggable={false}
      style={{ position: "absolute", inset: 0, width: "100%", height: "100%", zIndex: 2, pointerEvents: "none" }} />
  </div>;
}
