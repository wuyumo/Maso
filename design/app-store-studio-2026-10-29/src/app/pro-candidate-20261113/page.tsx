"use client";

/** Manual isolated candidate preview. Only the outer viewport scales.
 * Export captures the unscaled poster subtree at native pixel dimensions.
 * No canonical API, autosave, localStorage or network/service configuration.
 */

import * as React from "react";
import { toPng } from "html-to-image";
import { IPHONE_MEDIUM_CANVAS, themeById } from "@/lib/constants";
import type { Device } from "@/lib/types";
import { DeckCanvas, getCanvas } from "@/components/editor/slide-canvas";
import { DeviceShowcase, STORE_DEVICES, type StoreDevice } from "@/components/editor/device-showcase";
import type { ProjectState } from "@/lib/types";

import { CandidatePreviewControls, parsePreviewTarget, targetSearch, fitScale, canExportPage, exportCaptureOptions, type PreviewTarget as Target, type PreviewDevice as RenderDevice } from "@/components/editor/candidate-preview-controls";

const PHONE_CANVAS: Record<StoreDevice, { w: number; h: number }> = {
  iphone: { w: getCanvas("iphone", "portrait").cW, h: getCanvas("iphone", "portrait").cH },
  ipad: { w: STORE_DEVICES.ipad.w, h: STORE_DEVICES.ipad.h },
  duo: { w: STORE_DEVICES.duo.w, h: STORE_DEVICES.duo.h },
  watch: { w: STORE_DEVICES.watch.w, h: STORE_DEVICES.watch.h },
};

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

  const [mode,setMode] = React.useState<"fit"|"actual">("fit");
  const [ready,setReady] = React.useState(false);
  const [busy,setBusy] = React.useState(false);
  const [viewport,setViewport] = React.useState({w:320,h:640});
  const stageRef = React.useRef<HTMLElement | null>(null);
  React.useEffect(() => {
    const sync=()=>{setReady(false);document.documentElement.dataset.ready="0";setTarget(parsePreviewTarget(window.location.search));};
    sync(); window.addEventListener("popstate",sync);
    return ()=>window.removeEventListener("popstate",sync);
  }, []);
  React.useEffect(()=>{
    const stage=stageRef.current; if(!stage) return;
    const measure=()=>setViewport({w:stage.clientWidth,h:stage.clientHeight});
    measure(); const observer=new ResizeObserver(measure); observer.observe(stage);
    return ()=>observer.disconnect();
  },[state,target]);
  function navigate(next:Target) {
    if(busy) return;
    setReady(false);setError(null);document.documentElement.dataset.ready="0";
    window.history.pushState(null,"",window.location.pathname+targetSearch(next));setTarget(next);
    stageRef.current?.scrollTo({left:0,top:0});
  }

  React.useEffect(() => {
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
  }, []);

  // Settle: fonts + every image decoded, then announce. requestAnimationFrame is
  // not the only gate — headless Mac Chrome can fail CVDisplayLink and never
  // fire a frame. A short timeout still flips the flag; the exporter must
  // reject a solid bitmap, because the flag is not itself a painted poster.
  React.useEffect(() => {
    if (!state || !target) return;
    let cancelled = false;
    const root = document.documentElement;
    setReady(false);setError(null);
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
      const imgs = Array.from(document.getElementById("candidate-poster")?.querySelectorAll("img") || []);
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
      if(imgs.some(image=>!image.complete||image.naturalWidth===0)) { root.dataset.ready="error";root.dataset.status="missing-image";setError("图片未完整加载；请切换页面或刷新重试。");return; }
      setReady(true);
      root.dataset.status = "ready";
      root.dataset.ready = "1";
    })();
    return () => {
      cancelled = true;
      root.dataset.ready = "0";
    };
  }, [state, target]);

  if (!state || !target) return <div style={{padding:24,fontFamily:"system-ui"}}>{error || "正在载入截图候选…"}</div>;

  const canvas = canvasFor(target.device);
  const phoneDeck = deckDevice(target.device);
  const theme = themeById(state.themeId);
  const slides = state.slidesByDevice.iphone || [];
  // Exact id only. Falling back to slides[0] exported a different poster
  // under the requested slide name.
  const slide = slides.find((s) => s.id === target.slide);

  async function saveCandidatePoster() {
    if (busy || !ready || !target || !canExportPage(target)) { alert("Only pages 01/02 are approved for this export batch. Page 03 awaits authentic corrected captures."); return; }
    const main = document.getElementById("candidate-poster");
    if (!main || document.documentElement.dataset.ready !== "1" || Array.from(main.querySelectorAll("img")).some(image => !image.complete || image.naturalWidth === 0)) { alert("Fonts/images not ready; no PNG saved."); return; }
    setBusy(true);
    try {
      await document.fonts.ready;
      const dataUrl = await toPng(main, exportCaptureOptions(canvas));
      const name = (target.slide === "plan" ? "01" : "02") + "-" + target.slide + ".png";
      const artifactPath = `ios/${target.device}/${canvas.w}x${canvas.h}/${target.locale}/${name}`;
      const response = await fetch("/api/pro-candidate-20261113/export", {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({dataUrl,artifactPath})});
      const result = await response.json();
      if (!response.ok || !result.dataUrl) throw new Error(result.error || "PNG export failed");
      const a = document.createElement("a"); a.href = result.dataUrl; a.download = `CANDIDATE-${target.locale}-${target.device}-${name}`; a.click();
      alert("Saved candidate only: " + result.savedPath + "\nNot uploaded. Visual review required.");
    } catch (e) { alert(String(e)); } finally {setBusy(false);}
  }
  const scale=mode==="fit" ? fitScale(viewport,canvas) : 1;
  return (
    <div style={{position:"fixed",inset:0,height:"100dvh",display:"flex",flexDirection:"column",background:"#e8ebf0",color:"#172233",fontFamily:"system-ui,-apple-system,sans-serif"}}>
    <CandidatePreviewControls target={target} mode={mode} scale={scale} ready={ready} busy={busy} error={error} onTarget={navigate} onMode={setMode} onExport={saveCandidatePoster}/>
    <section ref={stageRef} aria-label="海报预览区域" style={{flex:1,minHeight:0,overflow:"auto",overscrollBehavior:"contain"}}>
    <div style={{width:canvas.w*scale,height:canvas.h*scale,margin:"16px auto"}}>
    <div data-preview-scale={scale} style={{width:canvas.w,height:canvas.h,position:"relative",transform:`scale(${scale})`,transformOrigin:"top left"}}>
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
    </div>
    </div>
    </section>
    </div>
  );
}
