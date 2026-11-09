"use client";
import * as React from "react";
import { PHONE_SCREEN } from "@/lib/constants";
import { img } from "@/lib/image-cache";
import { captureReady } from "@/lib/capture-inventory";

type FrameProps = {
  src: string;
  alt?: string;
  style?: React.CSSProperties;
  /** When true, a missing capture becomes an explicit gap plate instead of the editor placeholder. */
  hideEmpty?: boolean;
};

/** Real capture, or an obvious gap. Never substitutes another language's screenshot. */
export function ScreenFill({ src, alt = "", hideEmpty }: { src?: string; alt?: string; hideEmpty?: boolean }) {
  if (captureReady(src)) {
    return (
      <img
        src={img(src)}
        alt={alt}
        style={{ display: "block", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }}
        draggable={false}
      />
    );
  }
  if (!hideEmpty) return <EmptySlot />;
  const name = (src || "missing").split("?")[0].replace(/^\/screenshots\//, "");
  return (
    <div
      data-capture-missing="1"
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        textAlign: "center",
        padding: "6%",
        boxSizing: "border-box",
        color: "#EBECEC",
        background: "repeating-linear-gradient(135deg, #161616 0 12px, #242424 12px 24px)",
      }}
    >
      <div>
        <div style={{ fontSize: "7cqw", fontWeight: 800, color: "#1ED760", lineHeight: 1.1 }}>NO CAPTURE</div>
        <div style={{ fontSize: "3.1cqw", marginTop: "0.7em", opacity: 0.82, wordBreak: "break-all", lineHeight: 1.3 }}>{name}</div>
      </div>
    </div>
  );
}

// iPhone — uses pre-measured mockup.png overlay
export function Phone({ src, alt = "", style, hideEmpty }: FrameProps) {
  return (
    <div style={{ position: "relative", aspectRatio: "1350 / 2760", ...style }}>
      <img
        src={img("/mockup.png")}
        alt=""
        style={{ display: "block", width: "100%", height: "100%", position: "absolute", inset: 0, zIndex: 2, pointerEvents: "none" }}
        draggable={false}
      />
      <div
        style={{
          position: "absolute",
          zIndex: 1,
          overflow: "hidden",
          left: `${PHONE_SCREEN.L}%`,
          top: `${PHONE_SCREEN.T}%`,
          width: `${PHONE_SCREEN.W}%`,
          height: `${PHONE_SCREEN.H}%`,
          borderRadius: `${PHONE_SCREEN.RX}% / ${PHONE_SCREEN.RY}%`,
          background: "#111",
          containerType: "inline-size",
        }}
      >
        <ScreenFill src={src} alt={alt} hideEmpty={hideEmpty} />

      </div>
    </div>
  );
}

export function AndroidPhone({ src, alt = "", style, hideEmpty }: FrameProps) {
  const resolved = img(src);
  return (
    <div style={{ position: "relative", aspectRatio: "9 / 19.5", ...style }}>
      <div
        style={{
          width: "100%",
          height: "100%",
          borderRadius: "8% / 4%",
          background: "linear-gradient(160deg, #2a2a2e 0%, #18181b 100%)",
          boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08), 0 8px 40px rgba(0,0,0,0.55)",
          position: "relative",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            top: "1.5%",
            left: "50%",
            transform: "translateX(-50%)",
            width: "3%",
            height: "1.4%",
            borderRadius: "50%",
            background: "#0d0d0f",
            border: "1px solid rgba(255,255,255,0.06)",
            zIndex: 20,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: "3.5%",
            top: "2%",
            width: "93%",
            height: "96%",
            borderRadius: "5.5% / 2.6%",
            overflow: "hidden",
            background: "#000",
          }}
        >
          {resolved ? (
            <img
              src={resolved}
              alt={alt}
              style={{ display: "block", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }}
              draggable={false}
            />
          ) : hideEmpty ? null : (
            <EmptySlot />
          )}
        </div>
      </div>
    </div>
  );
}

export function AndroidTabletP({ src, alt = "", style, hideEmpty }: FrameProps) {
  const resolved = img(src);
  return (
    <div style={{ position: "relative", aspectRatio: "5 / 8", ...style }}>
      <div
        style={{
          width: "100%",
          height: "100%",
          borderRadius: "4.5% / 2.8%",
          background: "linear-gradient(160deg, #2a2a2e 0%, #18181b 100%)",
          boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08), 0 8px 48px rgba(0,0,0,0.6)",
          position: "relative",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            top: "1.2%",
            left: "50%",
            transform: "translateX(-50%)",
            width: "1.4%",
            height: "0.88%",
            borderRadius: "50%",
            background: "#0d0d0f",
            zIndex: 20,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: "3.5%",
            top: "2.2%",
            width: "93%",
            height: "95.6%",
            borderRadius: "2.5% / 1.6%",
            overflow: "hidden",
            background: "#000",
          }}
        >
          {resolved ? (
            <img
              src={resolved}
              alt={alt}
              style={{ display: "block", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }}
              draggable={false}
            />
          ) : hideEmpty ? null : (
            <EmptySlot />
          )}
        </div>
      </div>
    </div>
  );
}

export function AndroidTabletL({ src, alt = "", style, hideEmpty }: FrameProps) {
  const resolved = img(src);
  return (
    <div style={{ position: "relative", aspectRatio: "8 / 5", ...style }}>
      <div
        style={{
          width: "100%",
          height: "100%",
          borderRadius: "2.8% / 4.5%",
          background: "linear-gradient(160deg, #2a2a2e 0%, #18181b 100%)",
          boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08), 0 8px 48px rgba(0,0,0,0.6)",
          position: "relative",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            left: "1.2%",
            top: "50%",
            transform: "translateY(-50%)",
            width: "0.88%",
            height: "1.4%",
            borderRadius: "50%",
            background: "#0d0d0f",
            zIndex: 20,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: "2.2%",
            top: "3.5%",
            width: "95.6%",
            height: "93%",
            borderRadius: "1.6% / 2.5%",
            overflow: "hidden",
            background: "#000",
          }}
        >
          {resolved ? (
            <img
              src={resolved}
              alt={alt}
              style={{ display: "block", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }}
              draggable={false}
            />
          ) : hideEmpty ? null : (
            <EmptySlot />
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * Screen rectangles of the two bezel PNGs (percent of the frame body).
 *
 * Both `public/ipad-frame.png` and `public/duo-frame.png` are now cropped straight
 * out of Apple's official **Product Bezels** package
 * (developer.apple.com/design/resources → Bezel-iPad-Pro-(M5).dmg /
 * Bezel-iPhone-Duo.dmg), so the body is a photographic render rather than the
 * CSS-gradient approximation the earlier `make_device_frames.py` produced.
 *
 * The percentages below were measured off the alpha bounding box of each asset and
 * double-checked against the App Store's required pixel sizes — the punched-out
 * screen hole comes out at exactly 2064 × 2752 (iPad Pro 13″) and 2007 × 2853
 * (iPhone Duo inner display), i.e. one asset pixel per App Store pixel.
 */
export const IPAD_SCREEN = { L: 4.002, T: 3.202, W: 91.774, H: 93.733, RX: 4.3, RY: 3.225 };
export const DUO_SCREEN = { L: 3.273, T: 2.345, W: 93.829, H: 95.578, RX: 4.8, RY: 3.377 };

/** Body aspect ratios of the two bezel PNGs — keep in sync with `ASPECT` in device-lineup.tsx. */
export const IPAD_FRAME_ASPECT = 1600 / 2089;
export const DUO_FRAME_ASPECT = 1600 / 2233;

const FRAME_SHADOW =
  "drop-shadow(0 26px 34px rgba(0,0,0,0.5)) drop-shadow(0 4px 10px rgba(0,0,0,0.35))";

function BezelFrame({
  src,
  alt,
  style,
  hideEmpty,
  aspect,
  screen,
  overlay,
}: FrameProps & { aspect: string; screen: typeof IPAD_SCREEN; overlay: string }) {
  return (
    <div style={{ position: "relative", aspectRatio: aspect, filter: FRAME_SHADOW, ...style }}>
      <div
        style={{
          position: "absolute",
          left: `${screen.L}%`,
          top: `${screen.T}%`,
          width: `${screen.W}%`,
          height: `${screen.H}%`,
          borderRadius: `${screen.RX}% / ${screen.RY}%`,
          overflow: "hidden",
          background: "#000",
          containerType: "inline-size",
        }}
      >
        <ScreenFill src={src} alt={alt} hideEmpty={hideEmpty} />
      </div>
      <img
        src={img(overlay)}
        alt=""
        style={{ position: "absolute", inset: 0, width: "100%", height: "100%", zIndex: 2, pointerEvents: "none" }}
        draggable={false}
      />
    </div>
  );
}

/** 13" iPad Pro — official photographic bezel asset (`public/ipad-frame.png`). */
export function IPad(props: FrameProps) {
  return (
    <BezelFrame
      {...props}
      aspect="1600 / 2089"
      screen={IPAD_SCREEN}
      overlay="/ipad-frame.png"
    />
  );
}

/**
 * iPhone Duo — inner display. The bezel PNG is a neutral-black adaptation of the
 * Night Sky product bezel that shipped in this repo (see duo-frame-black.json).
 * It is not a separate official black colorway. The screen hole stays transparent,
 * so the capture drawn underneath is not tinted.
 */
export function Duo(props: FrameProps) {
  return (
    <BezelFrame
      {...props}
      aspect="1600 / 2233"
      screen={DUO_SCREEN}
      overlay="/duo-frame.png"
    />
  );
}

function EmptySlot() {
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color: "rgba(255,255,255,0.4)",
        fontSize: "min(2vw, 14px)",
        background: "linear-gradient(135deg, #1a1a1a 0%, #0a0a0a 100%)",
        textAlign: "center",
        padding: "4%",
      }}
    >
      Drop a screenshot here
    </div>
  );
}

export function Watch({ src, style, hideEmpty }: FrameProps) {
 return <div style={{position:"relative",aspectRatio:"560 / 880",filter:"drop-shadow(0 30px 35px #0003)",...style}}>
  <div style={{position:"absolute",left:"12.8571429%",top:"21.8181818%",width:"74.2857143%",height:"56.3636364%",borderRadius:"25% / 21%",overflow:"hidden",background:"#000",containerType:"inline-size"}}><ScreenFill src={src} alt="Masso Apple Watch" hideEmpty={hideEmpty} /></div>
  <img src={img("/watch-frame.png")} alt="" style={{position:"absolute",inset:0,width:"100%",height:"100%",zIndex:2,pointerEvents:"none"}} />
 </div>;
}
