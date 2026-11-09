"use client";

/**
 * Headless render surface.
 *
 * The editor is a full app shell (sidebar, inspector, zoom chrome) — fine for
 * hand editing, useless for a deterministic screenshot. This route draws one
 * poster at its exact native pixel size with nothing else on the page, then
 * flips `document.documentElement.dataset.ready` once fonts and every <img>
 * have decoded, so an external headless Chrome can wait on that flag and grab
 * a pixel-exact PNG.
 *
 *   /render?device=iphone&slide=diet&locale=zh
 *
 * It reads the same git-tracked `app-store-screenshots.json` as the editor
 * (via /api/project), so what you see here is what the editor would export.
 */

import * as React from "react";
import { themeById } from "@/lib/constants";
import { DeckCanvas, getCanvas } from "@/components/editor/slide-canvas";
import { DeviceShowcase, STORE_DEVICES, type StoreDevice } from "@/components/editor/device-showcase";
import type { ProjectState } from "@/lib/types";

type Target = { device: StoreDevice; slide: string; locale: string };

const CANVAS: Record<StoreDevice, { w: number; h: number }> = {
  iphone: { w: getCanvas("iphone", "portrait").cW, h: getCanvas("iphone", "portrait").cH },
  ipad: { w: STORE_DEVICES.ipad.w, h: STORE_DEVICES.ipad.h },
  duo: { w: STORE_DEVICES.duo.w, h: STORE_DEVICES.duo.h },
  watch: { w: STORE_DEVICES.watch.w, h: STORE_DEVICES.watch.h },
};

function parseTarget(): Target {
  const q = new URLSearchParams(window.location.search);
  const device = (q.get("device") || "iphone") as StoreDevice;
  return {
    device: device in CANVAS ? device : "iphone",
    slide: q.get("slide") || "diet",
    locale: q.get("locale") || "zh",
  };
}

export default function RenderPage() {
  const [target, setTarget] = React.useState<Target | null>(null);
  const [state, setState] = React.useState<ProjectState | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    setTarget(parseTarget());
  }, []);

  React.useEffect(() => {
    if (!target) return;
    let cancelled = false;
    void (async () => {
      try {
        const resp = await fetch("/api/project", { cache: "no-store" });
        const json = (await resp.json()) as { ok: boolean; state: ProjectState | null };
        if (cancelled) return;
        if (!json.ok || !json.state) throw new Error(json.ok ? "no project file" : "project read failed");
        setState(json.state);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [target]);

  // Settle: fonts + every image decoded + two frames of layout, then announce.
  React.useEffect(() => {
    if (!state || !target) return;
    let cancelled = false;
    void (async () => {
      try {
        await document.fonts.ready;
      } catch {
        /* ignore */
      }
      const imgs = Array.from(document.images);
      await Promise.all(imgs.map((image) => (image.decode ? image.decode().catch(() => undefined) : Promise.resolve())));
      await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
      if (!cancelled) document.documentElement.dataset.ready = "1";
    })();
    return () => {
      cancelled = true;
    };
  }, [state, target]);

  if (error) {
    return <div style={{ padding: 24, fontFamily: "monospace", color: "#b00" }}>render error: {error}</div>;
  }
  if (!state || !target) return null;

  const canvas = CANVAS[target.device];
  const theme = themeById(state.themeId);
  const slides = state.slidesByDevice.iphone || [];
  const slide = slides.find((s) => s.id === target.slide) || slides[0];

  return (
    <main
      style={{
        position: "fixed",
        inset: 0,
        width: canvas.w,
        height: canvas.h,
        overflow: "hidden",
        margin: 0,
        background: slide?.inverted ? "#212121" : "#EBECEC",
      }}
    >
      {!slide ? null : target.device === "iphone" ? (
        <DeckCanvas
          slides={[slide]}
          device="iphone"
          orientation="portrait"
          theme={theme}
          locale={target.locale}
          connectedCanvas={false}
          previewScale={1}
          hideEmpty
        />
      ) : (
        <DeviceShowcase slide={slide} device={target.device} locale={target.locale} />
      )}
    </main>
  );
}
