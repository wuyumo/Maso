"use client";
import * as React from "react";
import { PHONE_SCREEN } from "@/lib/constants";
import type { ChatThread, Theme } from "@/lib/types";
import { candidatePlanUnit, candidatePlanShiftX, candidateChatFit } from "@/lib/candidate-plan-presentation";
import { IPAD_SCREEN, DUO_SCREEN, IPAD_FRAME_ASPECT, DUO_FRAME_ASPECT } from "./device-frames";
import { CoachChat } from "./coach-chat";

export function candidatePlanFrame(device: string) {
  if (device === "iphone" || device === "iphone-medium") return { src: "/mockup.png", aspect: 1350 / 2760, screen: PHONE_SCREEN, topInset: 80 };
  if (device === "ipad") return { src: "/ipad-frame.png", aspect: IPAD_FRAME_ASPECT, screen: IPAD_SCREEN, topInset: 24 };
  if (device === "duo") return { src: "/duo-frame.png", aspect: DUO_FRAME_ASPECT, screen: DUO_SCREEN, topInset: 24 };
  return null;
}

export type CandidatePhoneRect = { x: number; y: number; width: number; height: number; rotation?: number; zIndex?: number };

export function candidatePlanMockupGeometry(device: string, canvas: { w: number; h: number }, chat: ChatThread, phoneRect?: CandidatePhoneRect) {
  const frame = candidatePlanFrame(device);
  if (!frame) return null;
  const phone = device === "iphone" || device === "iphone-medium";
  if (phone && !phoneRect) return null;
  const unit = phoneRect && phone ? phoneRect.width / chat.width : candidatePlanUnit(canvas, phone, chat);
  const height = phoneRect && phone ? phoneRect.height : (chat.height || 2050) * unit;
  const width = phoneRect && phone ? phoneRect.width : height * frame.aspect;
  const left = phoneRect && phone ? phoneRect.x : (canvas.w - width) / 2;
  const top = phoneRect && phone ? phoneRect.y : 900;
  const shift = phone ? 0 : candidatePlanShiftX(canvas, phone, { ...chat, width: width / unit });
  const fullScreenHeight = height * frame.screen.H / 100;
  const visibleScreenHeight = phone ? Math.min(fullScreenHeight, canvas.h - top - height * frame.screen.T / 100) : fullScreenHeight;
  const content: ChatThread = { ...chat, x: 16, y: frame.topInset,
    width: width * frame.screen.W / 100 / unit - 32,
    height: visibleScreenHeight / unit - frame.topInset - 36 };
  return { frame, unit, width, height, left, top, shift, content, phone };
}

/** Uniform height fitting must compensate its layout width, not leave a blank right strip. */
function CandidateFittedChat(props: React.ComponentProps<typeof CoachChat>) {
  const ref = React.useRef<HTMLDivElement>(null);
  React.useLayoutEffect(() => {
    const inner = ref.current?.querySelector<HTMLElement>('[data-chat-root="1"] > div');
    if (!inner) return;
    let floor = 1;
    const fit = () => {
      floor = candidateChatFit(floor, inner.dataset.chatFit);
      inner.style.setProperty("--candidate-thread-fit", String(floor));
    };
    fit();
    const observer = new MutationObserver(fit);
    observer.observe(inner, { attributes: true, attributeFilter: ["data-chat-fit"] });
    return () => observer.disconnect();
  }, [props.locale, props.cW, props.chat.width, props.chat.height]);
  return <div ref={ref} style={{position:"absolute",inset:0}}><CoachChat {...props} /></div>;
}

/** Existing photographed bezel and aperture, containing the unchanged real chat. */
export function CandidatePlanMockup({ device, canvas, chat, theme, locale, phoneRect, variant = "A", nativeSource }: {
  device: string; canvas: { w: number; h: number }; chat: ChatThread; theme: Theme; locale: string;
  phoneRect?: CandidatePhoneRect; variant?: "A" | "B"; nativeSource?: string | null;
}) {
  const g = candidatePlanMockupGeometry(device, canvas, chat, phoneRect);
  if (!g || (variant === "B" && !nativeSource)) return null;
  const { frame, unit } = g;
  return <div data-candidate-plan-mockup={device} data-phone-layout={g.phone ? "recovery" : undefined} data-plan-variant={variant} style={{ left: g.left, top: g.top, width: g.width, height: g.height, zIndex: phoneRect?.zIndex ?? 6,
    "--candidate-plan-unit": unit,
    "--candidate-plan-shift-x": `${g.shift}px` } as React.CSSProperties}>
    <div data-candidate-chat-aperture="1" style={{ position: "absolute", left: `${frame.screen.L}%`, top: `${frame.screen.T}%`,
      width: `${frame.screen.W}%`, height: `${frame.screen.H}%`, borderRadius: `${frame.screen.RX}% / ${frame.screen.RY}%`,
      overflow: "hidden", background: "#111317", zIndex: 1 }}>
      {variant === "B" ? <img data-native-app-viewport="1" src={nativeSource!} alt="原生App演示截图" draggable={false}
        style={{ display: "block", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }} /> :
        <CandidateFittedChat chat={g.content} cW={1320 * unit} theme={theme} locale={locale} />}
    </div>
    <img data-candidate-device-bezel="1" src={frame.src} alt="" draggable={false}
      style={{ position: "absolute", inset: 0, width: "100%", height: "100%", zIndex: 2, pointerEvents: "none" }} />
  </div>;
}
