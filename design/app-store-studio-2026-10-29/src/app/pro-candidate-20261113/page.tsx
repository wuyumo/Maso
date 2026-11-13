"use client";
import { CandidateHeadlineScope } from "@/lib/candidate-headline-emphasis";

/** Manual isolated candidate preview. Only the outer viewport scales.
 * Export captures the unscaled poster subtree at native pixel dimensions.
 * No canonical API, autosave, localStorage or network/service configuration.
 */

import * as React from "react";
import { toPng } from "html-to-image";
import { IPHONE_MEDIUM_CANVAS, themeById } from "@/lib/constants";
import type { Device } from "@/lib/types";
import { DeckCanvas, getCanvas, getElementTransform } from "@/components/editor/slide-canvas";
import { DeviceShowcase, STORE_DEVICES, type StoreDevice } from "@/components/editor/device-showcase";
import type { ProjectState } from "@/lib/types";
import { reviewBatchTargets, runReviewBatch } from "@/lib/candidate-batch";
import { candidateWatchSource } from "@/lib/candidate51-assets";
import { CANDIDATE_PLAN_CSS, candidatePlanUnit, candidatePlanNativeSource } from "@/lib/candidate-plan-presentation";

import { CandidatePlanMockup } from "@/components/editor/candidate-plan-mockup";

import { CandidatePreviewControls, parsePreviewTarget, targetSearch, fitScale, canExportPage, exportName, exportCaptureOptions, type PreviewTarget as Target, type PreviewDevice as RenderDevice } from "@/components/editor/candidate-preview-controls";

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

  const [variant,setVariant] = React.useState<"A"|"B">("A");
  const [mode,setMode] = React.useState<"fit"|"actual">("fit");
  const [ready,setReady] = React.useState(false);
  const [busy,setBusy] = React.useState(false);
  const [viewport,setViewport] = React.useState({w:320,h:640});
  const [batchRunning,setBatchRunning]=React.useState(false);
  const [batchStatus,setBatchStatus]=React.useState("");
  const batchRef=React.useRef(false);
  const cancelBatchRef=React.useRef(false);
  const exportInFlightRef=React.useRef(false);
  const stageRef = React.useRef<HTMLElement | null>(null);
  React.useEffect(() => {
    const sync=()=>{setReady(false);document.documentElement.dataset.ready="0";setTarget(parsePreviewTarget(window.location.search));setVariant(new URLSearchParams(window.location.search).get("variant")==="B"?"B":"A");};
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
    if(busy||batchRef.current) return;
    setReady(false);setError(null);setBatchStatus("");document.documentElement.dataset.ready="0";
    window.history.pushState(null,"",window.location.pathname+targetSearch(next)+`&variant=${variant}`);setTarget(next);
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
    root.dataset.variant = variant;
    if(target.slide === "plan" && variant === "B" && !candidatePlanNativeSource(target.device,target.locale)){setError("B版等待该设备/语言的真实51截图，不用旧图代替");root.dataset.ready="error";root.dataset.status="native-plan-missing";return;}
    root.dataset.status = "loading";
    const found = target.device==="watch" || (state.slidesByDevice.iphone || []).find((s) => s.id === target.slide);
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
  }, [state, target, variant]);

  if (!state || !target) return <div style={{padding:24,fontFamily:"system-ui"}}>{error || "正在载入截图候选…"}</div>;

  const canvas = canvasFor(target.device);
  const phoneDeck = deckDevice(target.device);
  const theme = themeById(state.themeId);
  const slides = state.slidesByDevice.iphone || [];
  // Exact id only. Falling back to slides[0] exported a different poster
  // under the requested slide name.
  const slide = slides.find((s) => s.id === target.slide);
  const recoverySlide = slides.find((s) => s.id === "recovery");
  const phoneRect = phoneDeck && recoverySlide ? getElementTransform(recoverySlide, phoneDeck, "portrait", "device") : undefined;
  function changeVariant(next:"A"|"B") {
    if(busy || batchRunning) return;
    setReady(false);setError(null);document.documentElement.dataset.ready="0";
    const url=new URL(window.location.href);url.searchParams.set("variant",next);window.history.replaceState(null,"",url.pathname+url.search);setVariant(next);
  }

  async function captureCandidatePoster(exportTarget:Target,download=true,planVariant:"A"|"B"=variant):Promise<string> {
    if(exportTarget.slide==="plan"&&planVariant==="B"&&!candidatePlanNativeSource(exportTarget.device,exportTarget.locale)) throw new Error("Native plan source missing");
    if(exportInFlightRef.current||!canExportPage(exportTarget)) throw new Error("Blocked or concurrent candidate capture");
    const main=document.getElementById("candidate-poster"),root=document.documentElement;
    if(!main||root.dataset.ready!=="1"||root.dataset.device!==exportTarget.device||root.dataset.slide!==exportTarget.slide||root.dataset.locale!==exportTarget.locale||root.dataset.variant!==planVariant||Array.from(main.querySelectorAll("img")).some(image=>!image.complete||image.naturalWidth===0)) throw new Error("Target/fonts/images not ready; no PNG saved");
    exportInFlightRef.current=true;
    try {
      await document.fonts.ready;
      const canvas=canvasFor(exportTarget.device);
      const dataUrl=await toPng(main, exportCaptureOptions(canvas));
      if(root.dataset.ready!=="1"||root.dataset.device!==exportTarget.device||root.dataset.slide!==exportTarget.slide||root.dataset.locale!==exportTarget.locale||root.dataset.variant!==planVariant) throw new Error("Target changed during capture; PNG discarded");
      const name=exportTarget.slide==="plan" ? exportName(exportTarget).replace(".png",`-${planVariant}.png`) : exportName(exportTarget);
      const artifactPath=`ios/${exportTarget.device}/${canvas.w}x${canvas.h}/${exportTarget.locale}/${name}`;
      const response=await fetch("/api/pro-candidate-20261113/export",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({dataUrl,artifactPath})});
      const result=await response.json();if(!response.ok||!result.dataUrl) throw new Error(result.error||"PNG export failed");
      if(download){const a=document.createElement("a");a.href=result.dataUrl;a.download=`CANDIDATE-${exportTarget.locale}-${exportTarget.device}-${name}`;a.click();}
      return result.savedPath as string;
    } finally {exportInFlightRef.current=false;}
  }
  async function saveCandidatePoster() {
    if(busy||batchRef.current||!ready||!target) return;
    setBusy(true);try{const saved=await captureCandidatePoster(target);alert("Saved candidate only: "+saved+"\nNot uploaded. Visual review required.");}catch(e){alert(String(e));}finally{setBusy(false);}
  }
  async function startReviewBatch() {
    if(!target||busy||batchRef.current) return;
    batchRef.current=true;cancelBatchRef.current=false;setBatchRunning(true);setBatchStatus("中英候选批量导出准备中；不上传");
    const targets=reviewBatchTargets(target.device);
    const batchVariant = "A" as const; // User-selected design; historical B must not leak into batch captures.
    try {
      const result=await runReviewBatch(targets,{
        cancelled:()=>cancelBatchRef.current,
        show:async next=>{setVariant(batchVariant);setError(null);setReady(false);document.documentElement.dataset.ready="0";window.history.replaceState(null,"",window.location.pathname+targetSearch(next)+`&variant=${batchVariant}`);setTarget({...next});},
        ready:async next=>{
          const start=Date.now();
          while(Date.now()-start<20000){
            if(cancelBatchRef.current)return;
            const root=document.documentElement;
            const matching=root.dataset.device===next.device&&root.dataset.slide===next.slide&&root.dataset.locale===next.locale&&root.dataset.variant===batchVariant;
            if(matching&&root.dataset.ready==="1")return;
            if(matching&&root.dataset.ready==="error")throw new Error(root.dataset.status||"Candidate readiness failed");
            await new Promise(resolve=>window.setTimeout(resolve,50));
          }
          throw new Error("Candidate fonts/images readiness timed out; batch stopped");
        },
        capture:next=>captureCandidatePoster(next,false,batchVariant),
        progress:(saved,total,next)=>setBatchStatus(`已保存 ${saved.length}/${total} · ${next.locale} ${exportName(next)} · 仅候选，待逐页目检`),
      });
      setBatchStatus(`${result.status==="complete"?"中英候选已导出":"已停止"} ${result.saved.length}/${targets.length} 张 · exports/candidates/pro-20261113 · 未上传，待目检/用户确认`);
    }catch(e){setError(String(e));setBatchStatus("批量导出已停止："+String(e));}finally{batchRef.current=false;setBatchRunning(false);}
  }
  async function saveComparison() {
    if(!target||target.slide!=="plan"||busy||batchRef.current||!candidatePlanNativeSource(target.device,target.locale)) return;
    batchRef.current=true;cancelBatchRef.current=false;setBatchRunning(true);setBatchStatus("A/B候选准备中；不上传");
    try {
      for(const next of ["A","B"] as const){
        if(cancelBatchRef.current) break;
        const root=document.documentElement;
        if(root.dataset.variant!==next || root.dataset.ready!=="1"){
          root.dataset.ready="0";setReady(false);setVariant(next);
          const url=new URL(window.location.href);url.searchParams.set("variant",next);window.history.replaceState(null,"",url.pathname+url.search);
        }
        const deadline=Date.now()+20000;
        while(root.dataset.ready!=="1"||root.dataset.variant!==next){
          if(root.dataset.ready==="error"||Date.now()>deadline) throw new Error(root.dataset.status||"A/B准备超时");
          if(cancelBatchRef.current) return;
          await new Promise(resolve=>window.setTimeout(resolve,50));
        }
        const saved=await captureCandidatePoster(target,false,next);setBatchStatus(`已保存${next}版：${saved}；未上传`);
      }
    }catch(e){setError(String(e));}finally{batchRef.current=false;setBatchRunning(false);}
  }
  const scale=mode==="fit" ? fitScale(viewport,canvas) : 1;
  return (
    <div style={{position:"fixed",inset:0,height:"100dvh",display:"flex",flexDirection:"column",background:"#e8ebf0",color:"#172233",fontFamily:"system-ui,-apple-system,sans-serif"}}>
    <CandidatePreviewControls target={target} mode={mode} scale={scale} ready={ready} busy={busy||batchRunning} error={error} onTarget={navigate} onMode={setMode} onExport={saveCandidatePoster} onBatch={startReviewBatch} batchRunning={batchRunning} batchStatus={batchStatus} onBatchCancel={()=>{cancelBatchRef.current=true;setBatchStatus("完成当前页后停止；已保存的候选保留，不上传");}}/>
    {target.slide === "plan" && target.device !== "watch" ? <div aria-label="第一页A/B对照" style={{display:"flex",gap:8,alignItems:"center",flexWrap:"wrap",padding:"8px 12px",background:"#fff",borderBottom:"1px solid #cbd2da"}}>
      <button type="button" aria-pressed={variant==="A"} disabled={busy||batchRunning} onClick={()=>changeVariant("A")}>A · 原生UI风格 Mock</button>
      <button type="button" aria-pressed={variant==="B"} disabled={busy||batchRunning||!candidatePlanNativeSource(target.device,target.locale)} onClick={()=>changeVariant("B")}>B · 原生计划完成态</button>
      <button type="button" disabled={busy||batchRunning||!ready||!candidatePlanNativeSource(target.device,target.locale)} onClick={saveComparison}>一次保存 A/B 两版 PNG</button>
      <span style={{fontSize:12}}>同设备框、同位置尺寸 · A为Mock，B为真实51演示计划完成态 · 均待海报目检</span>
    </div> : null}
    <section ref={stageRef} aria-label="海报预览区域" style={{flex:1,minHeight:0,overflow:"auto",overscrollBehavior:"contain"}}>
    <div style={{width:canvas.w*scale,height:canvas.h*scale,margin:"16px auto"}}>
    <div data-preview-scale={scale} style={{width:canvas.w,height:canvas.h,position:"relative",transform:`scale(${scale})`,transformOrigin:"top left"}}>
    <CandidateHeadlineScope.Provider value={true}><main id="candidate-poster"
      data-candidate-plan-device={slide?.id === "plan" && slide.chat && target.device !== "watch" ? "low-angle-split" : undefined}
      style={{
        "--candidate-plan-unit": candidatePlanUnit(canvas, !!phoneDeck, slide?.chat),
        position: "fixed",
        inset: 0,
        width: canvas.w,
        height: canvas.h,
        overflow: "hidden",
        margin: 0,
        background: slide?.inverted ? "#212121" : "#EBECEC",
      } as React.CSSProperties}
    >
      <style>{CANDIDATE_PLAN_CSS}</style>
      <div data-candidate-original-layout="1">
      {target.device==="watch" ? <img alt="Watch独立原生演示截图" src={candidateWatchSource(target.locale,target.slide)||`/screenshots/localized/watch/${target.locale}/${target.slide==="watch-exercise"?"exercise-185":"rest-160"}.png`} width={canvas.w} height={canvas.h} style={{display:"block",width:canvas.w,height:canvas.h}}/> : !slide || !phoneDeck ? (
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
      </div>
      {slide?.id === "plan" && slide.chat && target.device !== "watch" ? <CandidatePlanMockup device={target.device} canvas={canvas} chat={slide.chat} theme={theme} locale={target.locale} phoneRect={phoneRect} variant={variant} nativeSource={candidatePlanNativeSource(target.device,target.locale)} /> : null}
    </main></CandidateHeadlineScope.Provider>
    </div>
    </div>
    </section>
    </div>
  );
}
