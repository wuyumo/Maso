"use client";

/**
 * Isolated manual candidate surface. Existing poster and html-to-image chain.
 * No canonical project/export API calls, autosave or localStorage.
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
import { toPng } from "html-to-image";
import { IPHONE_MEDIUM_CANVAS, themeById } from "@/lib/constants";
import type { Device } from "@/lib/types";
import { DeckCanvas, getCanvas } from "@/components/editor/slide-canvas";
import { DeviceShowcase, STORE_DEVICES, type StoreDevice } from "@/components/editor/device-showcase";
import type { ProjectState } from "@/lib/types";

type RenderDevice = StoreDevice | "iphone-medium";
type Target = { device: RenderDevice; slide: string; locale: string };

const PHONE_CANVAS: Record<StoreDevice, { w: number; h: number }> = {
  iphone: { w: getCanvas("iphone", "portrait").cW, h: getCanvas("iphone", "portrait").cH },
  ipad: { w: STORE_DEVICES.ipad.w, h: STORE_DEVICES.ipad.h },
  duo: { w: STORE_DEVICES.duo.w, h: STORE_DEVICES.duo.h },
  watch: { w: STORE_DEVICES.watch.w, h: STORE_DEVICES.watch.h },
};

function parseTarget(): Target {
  const q = new URLSearchParams(window.location.search);
  const raw = q.get("device") || "iphone";
  const device: RenderDevice =
    raw === "iphone-medium" || raw === "iphone" || raw === "ipad" || raw === "duo" || raw === "watch"
      ? raw
      : "iphone";
  return {
    device,
    slide: q.get("slide") || "diet",
    locale: q.get("locale") || "zh",
  };
}

function canvasFor(device: RenderDevice) {
  if (device === "iphone-medium") return { w: IPHONE_MEDIUM_CANVAS.w, h: IPHONE_MEDIUM_CANVAS.h };
  return PHONE_CANVAS[device];
}

function deckDevice(device: RenderDevice): Device | null {
  if (device === "iphone" || device === "iphone-medium") return device;
  return null;
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
        const resp = await fetch("/api/pro-candidate-20261113/project", { cache: "no-store" });
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

  // Settle: fonts + every image decoded, then announce. requestAnimationFrame is
  // not the only gate — headless Mac Chrome can fail CVDisplayLink and never
  // fire a frame. A short timeout still flips the flag; the exporter must
  // reject a solid bitmap, because the flag is not itself a painted poster.
  React.useEffect(() => {
    if (!state || !target) return;
    let cancelled = false;
    const root = document.documentElement;
    root.dataset.ready = "0";
    root.dataset.device = target.device;
    root.dataset.slide = target.slide;
    root.dataset.locale = target.locale;
    root.dataset.status = "loading";
    const found = (state.slidesByDevice.iphone || []).find((s) => s.id === target.slide);
    if (!found) {
      root.dataset.ready = "error";
      root.dataset.status = "missing-slide";
      setError(`missing slide ${target.slide}`);
      return () => {
        cancelled = true;
        root.dataset.ready = "0";
      };
    }
    void (async () => {
      try {
        await Promise.race([
          document.fonts.ready,
          new Promise((_, reject) => setTimeout(() => reject(new Error("fonts-timeout")), 8000)),
        ]);
      } catch {
        if (!cancelled) {
          root.dataset.ready = "error";
          root.dataset.status = "fonts-timeout";
          setError("fonts-timeout");
        }
        return;
      }
      const imgs = Array.from(document.images);
      await Promise.all(imgs.map((image) => (image.decode ? image.decode().catch(() => undefined) : Promise.resolve())));
      await new Promise<void>((resolve) => {
        let settled = false;
        const finish = () => {
          if (settled) return;
          settled = true;
          resolve();
        };
        requestAnimationFrame(() => requestAnimationFrame(finish));
        setTimeout(finish, 50);
      });
      if (cancelled) return;
      root.dataset.status = "ready";
      root.dataset.ready = "1";
    })();
    return () => {
      cancelled = true;
      root.dataset.ready = "0";
    };
  }, [state, target]);

  if (error) {
    return <div style={{ padding: 24, fontFamily: "monospace", color: "#b00" }}>render error: {error}</div>;
  }
  if (!state || !target) return null;

  const canvas = canvasFor(target.device);
  const phoneDeck = deckDevice(target.device);
  const theme = themeById(state.themeId);
  const slides = state.slidesByDevice.iphone || [];
  // Exact id only. Falling back to slides[0] exported a different poster
  // under the requested slide name.
  const slide = slides.find((s) => s.id === target.slide);

  async function saveCandidatePoster() {
    if (!target || !["plan", "recovery"].includes(target.slide)) { alert("Only pages 01/02 are approved for this export batch. Page 03 awaits authentic corrected captures."); return; }
    const main = document.getElementById("candidate-poster");
    if (!main || document.documentElement.dataset.ready !== "1" || Array.from(main.querySelectorAll("img")).some(image => !image.complete || image.naturalWidth === 0)) { alert("Fonts/images not ready; no PNG saved."); return; }
    try {
      await document.fonts.ready;
      const dataUrl = await toPng(main, { width: canvas.w, height: canvas.h, canvasWidth: canvas.w, canvasHeight: canvas.h, pixelRatio: 1, style: { position: "static", inset: "auto" } });
      const name = (target.slide === "plan" ? "01" : "02") + "-" + target.slide + ".png";
      const artifactPath = `ios/${target.device}/${canvas.w}x${canvas.h}/${target.locale}/${name}`;
      const response = await fetch("/api/pro-candidate-20261113/export", {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({dataUrl,artifactPath})});
      const result = await response.json();
      if (!response.ok || !result.dataUrl) throw new Error(result.error || "PNG export failed");
      const a = document.createElement("a"); a.href = result.dataUrl; a.download = `CANDIDATE-${target.locale}-${target.device}-${name}`; a.click();
      alert("Saved candidate only: " + result.savedPath + "\nNot uploaded. Visual review required.");
    } catch (e) { alert(String(e)); }
  }
  return (
    <>
    <aside style={{position:"fixed",right:8,top:8,zIndex:99999,maxWidth:330,padding:12,background:"#fff",color:"#111",fontFamily:"system-ui",fontSize:14,border:"2px solid #a50"}}>
      <strong>截图候选 / 未验收，未上传</strong>
      <p>文案候选；内屏保留43演示素材。03待真实重截。原工程与latest不会被此入口写入。</p>
      <div>{["plan","recovery","training","diet","devices"].map((id,i)=><a key={id} style={{marginRight:10}} href={`?device=${target.device}&slide=${id}&locale=${target.locale}`}>{i+1}</a>)}</div>
      <p><a href={`?device=${target.device}&slide=${target.slide}&locale=zh`}>中文</a> · <a href={`?device=${target.device}&slide=${target.slide}&locale=en`}>English</a></p>
      <button onClick={saveCandidatePoster} disabled={!["plan","recovery"].includes(target.slide)} style={{padding:12,background:"#164",color:"#fff",border:0}}>保存本页候选 PNG（仅01/02）</button>
      <p>导出仅捕获下方海报，不包含此控制卡。</p>
    </aside>
    <main id="candidate-poster"
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
      {!slide || !phoneDeck ? (
        !slide ? null : (
          <DeviceShowcase slide={slide} device={target.device as StoreDevice} locale={target.locale} />
        )
      ) : (
        <DeckCanvas
          slides={[slide]}
          device={phoneDeck}
          orientation="portrait"
          theme={theme}
          locale={target.locale}
          connectedCanvas={false}
          previewScale={1}
          hideEmpty
        />
      )}
    </main>
    </>
  );
}
