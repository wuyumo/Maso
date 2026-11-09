"use client";

import * as React from "react";
import { themeById } from "@/lib/constants";
import { pickText } from "@/lib/locale";
import type { Slide } from "@/lib/types";
import { CoachChat } from "./coach-chat";
import { DeviceLineup, fitLineup } from "./device-lineup";
import { ScreenFill, Watch } from "./device-frames";
import { FittedCopy } from "./fitted-copy";
import { HighlightedHeadline } from "./headline-highlight";
import { marketingImage } from "@/lib/marketing-localized";

export type StoreDevice = "iphone" | "duo" | "ipad" | "watch";
export const STORE_DEVICES = {
  iphone: { label: "iPhone", w: 1320, h: 2868 },
  duo: { label: "iPhone Duo", w: 2007, h: 2853 },
  ipad: { label: "iPad 13″", w: 2064, h: 2752 },
  watch: { label: "Apple Watch", w: 416, h: 496 },
};

const pairedIds = ["diet"];

export function DeviceShowcase({ slide, device, locale }: { slide: Slide; device: StoreDevice; locale: string }) {
  const spec = STORE_DEVICES[device];
  const dark = slide.inverted;
  const family = device === "duo" ? "duo" : "ipad";
  const cw = spec.w / 2064;
  const copyInset = Math.round(140 * cw);
  const cjk = locale === "zh" || locale === "zh-Hant" || locale === "ja" || locale === "ko";
  const headSize = Math.round((cjk ? 168 : 150) * cw);
  const subSize = Math.round(68 * cw);
  const theme = themeById("masso-portfolio");
  const description = slide.textElements?.find((element) => element.id === "description");

  if (device === "watch") {
    const src = marketingImage(slide, "watch", locale) || slide.screenshot;
    return (
      <div style={{ width: 416, height: 496, background: "#000" }}>
        <ScreenFill src={src} alt="Masso watchOS screen" hideEmpty />
      </div>
    );
  }

  const copy = (
    <div
      dir={locale === "ar" ? "rtl" : "ltr"}
      style={{
        position: "absolute",
        left: copyInset,
        top: 188,
        right: copyInset,
        height: 600,
        fontFamily: locale === "ar" ? '"Noto Kufi Arabic","Noto Naskh Arabic",sans-serif' : undefined,
        zIndex: 8,
      }}
    >
      <FittedCopy>
        <div>
          <div
            style={{
              whiteSpace: "pre-line",
              textWrap: "balance",
              fontSize: headSize,
              fontWeight: 700,
              letterSpacing: locale === "ar" ? 0 : "-.035em",
              lineHeight: locale === "ar" ? 1.38 : cjk ? 1.2 : 1.12,
              overflowWrap: "break-word",
            }}
          >
            <HighlightedHeadline id={slide.id} locale={locale} text={pickText(slide.headline, locale)} />
          </div>
          {description && (
            <div
              style={{
                fontSize: subSize,
                fontWeight: 500,
                lineHeight: locale === "ar" ? 1.45 : 1.28,
                opacity: 0.92,
                textWrap: "pretty",
                whiteSpace: "pre-line",
                overflowWrap: "break-word",
                marginTop: 22,
              }}
            >
              {pickText(description.text, locale)}
            </div>
          )}
        </div>
      </FittedCopy>
    </div>
  );

  const poster: React.CSSProperties = {
    width: spec.w,
    height: spec.h,
    position: "relative",
    overflow: "hidden",
    background: dark ? "#212121" : "#EBECEC",
    color: dark ? "#EBECEC" : "#212121",
    fontFamily: "Manrope, sans-serif",
  };

  if (slide.chat) {
    const availH = spec.h - 960;
    const k = Math.min((spec.w - 180) / slide.chat.width, availH / (slide.chat.height || 2050));
    const shiftX = (spec.w - slide.chat.width * k) / 2 - slide.chat.x * k;
    const shiftY = 900 - slide.chat.y * k;
    return (
      <div style={poster}>
        {copy}
        <div style={{ position: "absolute", left: shiftX, top: shiftY, width: spec.w, height: spec.h }}>
          <CoachChat chat={slide.chat} cW={1320 * k} theme={theme} locale={locale} />
        </div>
      </div>
    );
  }

  return (
    <div style={poster}>
      {copy}
      {slide.lineup ? (
        <div style={{ position: "absolute", inset: 0, zIndex: 6 }}>
          <DeviceLineup
            lineup={slide.lineup}
            locale={locale}
            {...fitLineup(slide.lineup, { x: 80, y: 860, width: spec.w - 160, height: spec.h - 980 })}
          />
        </div>
      ) : slide.id === "watch" ? (
        <>
          <Watch
            src={marketingImage(slide, "watch", locale) || slide.screenshot}
            hideEmpty
            style={{ position: "absolute", left: 75, top: 810, width: 1150, height: 1807, transform: "rotate(-8deg)", zIndex: 3 }}
          />
          <Watch
            src={marketingImage(slide, "watch", locale, true) || slide.screenshotSecondary || slide.screenshot}
            hideEmpty
            style={{ position: "absolute", left: 970, top: 1100, width: 1050, height: 1650, transform: "rotate(8deg)", zIndex: 2 }}
          />
        </>
      ) : (
        (pairedIds.includes(slide.id) ? [0, 1] : [0]).map((index) => {
          const paired = pairedIds.includes(slide.id);
          const source = marketingImage(slide, family, locale, !!index);
          const aspect = device === "duo" ? 2853 / 2007 : 2752 / 2064;
          const width = paired ? (index ? spec.w * 0.475 : spec.w * 0.505) : Math.min(spec.w * 0.66, (spec.h * 0.94 - 860) / aspect);
          const height = width * aspect;
          const left = paired ? (index ? spec.w * 0.452 : spec.w * 0.055) : (spec.w - width) / 2;
          const top = paired ? (device === "duo" ? (index ? spec.h * 0.27 : spec.h * 0.44) : index ? spec.h * 0.315 : spec.h * 0.4) : 860;
          return (
            <div
              key={index}
              style={{
                position: "absolute",
                left,
                top,
                width,
                height,
                transform: paired ? `rotate(${index ? 4 : -4}deg)` : undefined,
                zIndex: index ? 2 : 3,
                border: "22px solid #171717",
                borderRadius: 65,
                overflow: "hidden",
                boxShadow: "0 24px 50px #0003",
                background: "black",
                containerType: "inline-size",
              }}
            >
              <ScreenFill
                src={source}
                hideEmpty
                alt={device === "duo" ? "Masso Duo native inner-screen capture" : "Masso iPad native capture"}
              />
            </div>
          );
        })
      )}
    </div>
  );
}

export function DeviceSheet({ slide, device, locale }: { slide: Slide; device: StoreDevice; locale: string }) {
  const ref = React.useRef<HTMLDivElement>(null);
  const [width, setWidth] = React.useState(560);
  const spec = STORE_DEVICES[device];
  React.useEffect(() => {
    if (!ref.current) return;
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);
  return (
    <div ref={ref} style={{ position: "relative", width: "100%", aspectRatio: `${spec.w}/${spec.h}`, overflow: "hidden", border: "1px solid #21212126" }}>
      <div style={{ position: "absolute", left: 0, top: 0, transform: `scale(${width / spec.w})`, transformOrigin: "top left" }}>
        <DeviceShowcase slide={slide} device={device} locale={locale} />
      </div>
    </div>
  );
}
