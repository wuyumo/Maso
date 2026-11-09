"use client";
import * as React from "react";
import JSZip from "jszip";
import { toPng } from "html-to-image";
import { Toaster, toast } from "sonner";
import {
  getExportSizes,
  hasTheme,
  supportsLandscape,
  themeById,
} from "@/lib/constants";
import { detectPlatform, nid } from "@/lib/defaults";
import { isBuiltInElementId, isTextElementId, textElementKey } from "@/lib/elements";
import { preloadImages } from "@/lib/image-cache";
import { lineupImage, marketingImage } from "@/lib/marketing-localized";
import { resolveScreenshot, writeLocalized } from "@/lib/locale";
import { useProject } from "@/lib/storage";
import type {
  BuiltInElementId,
  Device,
  ElementId,
  ElementTransform,
  SelectedElement,
  Slide,
} from "@/lib/types";
import { Inspector } from "./inspector";
import { PreviewStage, VerticalSheet } from "./preview-stage";
import { Sidebar } from "./sidebar";
import { DeckCanvas, getCanvas } from "./slide-canvas";
import { Toolbar } from "./toolbar";
import { DeviceSheet, DeviceShowcase, STORE_DEVICES, StoreDevice } from "./device-showcase";

export function ScreenshotEditor() {
  const { state, setState, hydrated, savedAt, saveError, reset, resetDevice, undo, redo } = useProject();
  const [vertical, setVertical] = React.useState(true);
  const [storeDevice, setStoreDevice] = React.useState<StoreDevice>("iphone");
  const [selectedLocales, setSelectedLocales] = React.useState<string[]>(["en"]);
  const [selectedDevices, setSelectedDevices] = React.useState<StoreDevice[]>(["iphone"]);
  const [activeSlideId, setActiveSlideId] = React.useState<string | null>(null);
  const [selectedElement, setSelectedElement] = React.useState<SelectedElement | null>(null);
  const [exporting, setExporting] = React.useState<string | null>(null);
  const [ready, setReady] = React.useState(false);
  const [exportLocaleOverride, setExportLocaleOverride] = React.useState<string | null>(null);
  const [exportSlideIndex, setExportSlideIndex] = React.useState(0);
  const exportRef = React.useRef<HTMLDivElement | null>(null);

  const phoneSlides = state.slidesByDevice[state.device] || [];
  const renderDevice = storeDevice;
  const currentSlides = renderDevice === "watch" ? [
    { id:"watch-exercise",layout:"hero" as const,label:{zh:"01 / 训练",en:"01 / WORKOUT"},headline:{zh:"完成这一组",en:"Log your set"},screenshot:"/screenshots/apple/iphone/watch-exercise-heart.png" },
    { id:"watch-rest",layout:"hero" as const,label:{zh:"02 / 休息",en:"02 / REST"},headline:{zh:"准备下一组",en:"Rest for the next set"},screenshot:"/screenshots/apple/iphone/watch-rest-heart.png" }
  ] : phoneSlides;
  const activeSlide =
    currentSlides.find((s) => s.id === activeSlideId) || currentSlides[0] || null;
  const theme = themeById(state.themeId);

  React.useEffect(() => {
    if (selectedElement && selectedElement.slideId !== activeSlide?.id) {
      setSelectedElement(null);
    }
  }, [activeSlide?.id, selectedElement]);

  React.useEffect(() => {
    if (!hydrated) return;
    if (!activeSlide && currentSlides.length > 0) {
      setActiveSlideId(currentSlides[0].id);
    }
  }, [hydrated, currentSlides, activeSlide]);

  React.useEffect(() => {
    if (!supportsLandscape(state.device) && state.orientation !== "portrait") {
      setState((p) => ({ ...p, orientation: "portrait" }));
    }
  }, [state.device, state.orientation, setState]);

  React.useEffect(() => {
    if (hydrated && state.themeId && !hasTheme(state.themeId)) {
      toast.warning("Using fallback theme", {
        description: `Theme "${state.themeId}" is not defined in src/lib/constants.ts.`,
        duration: 8000,
      });
    }
  }, [hydrated, state.themeId]);

  const assetPaths = React.useMemo(() => {
    const paths = new Set<string>();
    paths.add("/mockup.png");
    paths.add("/watch-frame.png");
    paths.add("/ipad-frame.png");
    paths.add("/duo-frame.png");
    paths.add("/screenshots/apple/iphone/today.png");
    paths.add("/screenshots/localized/iphone/zh/today.png?v=morning3");
    paths.add("/screenshots/localized/iphone/ar/today.png?v=review3");
    paths.add("/screenshots/localized/ipad/ar/today.png?v=review3");
    paths.add("/screenshots/localized/ipad/zh/today.png?v=morning3");
    paths.add("/screenshots/apple/iphone/coach-body-portrait.jpg");
    paths.add("/screenshots/apple/iphone/meal-demo-chicken.png");
    paths.add("/screenshots/apple/iphone/meal-demo-salmon.png");
    for (const name of ["today","coach_chat","coach_photo_after_yes","muscle_status","player","exercises","insights","diet","sleep"]) paths.add(`/screenshots/apple/ipad/${name}.png`);
    if (state.appIcon) paths.add(state.appIcon);
    // Preload every locale variant so bulk export doesn't race image loads.
    const allSlides: Slide[] = Object.values(state.slidesByDevice).flat();
    for (const s of allSlides) {
      for (const loc of state.locales) for (const family of ["iphone", "ipad", "watch", "duo"] as const) for (const second of [false,true]) { const path = marketingImage(s, family, loc, second); if (path) paths.add(path); }
      // Device portrait pages pull one screen per physical device instead of
      // one screen per slide, so their paths are collected separately.
      if (s.lineup) {
        for (const loc of state.locales) for (const slot of s.lineup.slots) { const path = lineupImage(slot.id, loc); if (path) paths.add(path); }
      }
      for (const raw of [s.screenshot, s.screenshotSecondary]) {
        if (!raw || raw.startsWith("data:")) continue;
        if (raw.includes("{locale}")) {
          for (const loc of state.locales) paths.add(resolveScreenshot(raw, loc));
        } else {
          paths.add(raw);
        }
      }
    }
    return Array.from(paths).sort();
  }, [state.slidesByDevice, state.appIcon, state.locales]);
  const assetSig = assetPaths.join("|");

  React.useEffect(() => {
    if (!hydrated) return;
    preloadImages(assetPaths).finally(() => setReady(true));
    // assetPaths is derived from assetSig; depending on the string keeps the
    // effect from re-firing when slidesByDevice churns without path changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hydrated, assetSig]);

  // Surface storage failures (quota exceeded etc.) so the user knows their work isn't safe.
  React.useEffect(() => {
    if (saveError) {
      toast.error("Couldn't load or save project file", {
        description: saveError,
        duration: 8000,
      });
    }
  }, [saveError]);

  // ---------- Mutations ----------

  const patchSlide = React.useCallback(
    (id: string, patch: Partial<Slide>) => {
      setState((prev) => ({
        ...prev,
        slidesByDevice: {
          ...prev.slidesByDevice,
          [prev.device]: (prev.slidesByDevice[prev.device] || []).map((s) =>
            s.id === id ? { ...s, ...patch } : s,
          ),
        },
      }));
    },
    [setState],
  );

  const reorderSlides = React.useCallback(
    (next: Slide[]) => {
      setState((prev) => ({
        ...prev,
        slidesByDevice: { ...prev.slidesByDevice, [prev.device]: next },
      }));
    },
    [setState],
  );

  const deleteSlide = React.useCallback(
    (id: string) => {
      const dev = state.device;
      const slides = state.slidesByDevice[dev] || [];
      const idx = slides.findIndex((s) => s.id === id);
      if (idx === -1) return;
      const snap = slides[idx];
      const fallback = slides[idx + 1] || slides[idx - 1] || null;

      setState((prev) => {
        const cur = prev.slidesByDevice[dev] || [];
        return {
          ...prev,
          slidesByDevice: { ...prev.slidesByDevice, [dev]: cur.filter((s) => s.id !== id) },
        };
      });
      setActiveSlideId((cur) => (cur === id ? fallback?.id || null : cur));

      toast("Screen deleted", {
        action: {
          label: "Undo",
          onClick: () => {
            setState((prev) => {
              const cur = prev.slidesByDevice[dev] || [];
              if (cur.some((s) => s.id === snap.id)) return prev;
              const restored = [...cur.slice(0, idx), snap, ...cur.slice(idx)];
              return {
                ...prev,
                slidesByDevice: { ...prev.slidesByDevice, [dev]: restored },
              };
            });
            setActiveSlideId(snap.id);
          },
        },
        duration: 6000,
      });
    },
    [setState, state.device, state.slidesByDevice],
  );

  const addSlide = React.useCallback(
    (slide: Slide) => {
      setState((prev) => ({
        ...prev,
        slidesByDevice: {
          ...prev.slidesByDevice,
          [prev.device]: [...(prev.slidesByDevice[prev.device] || []), slide],
        },
      }));
      setActiveSlideId(slide.id);
    },
    [setState],
  );

  const patchLocalized = React.useCallback(
    (slide: Slide, key: "label" | "headline", value: string) => {
      patchSlide(slide.id, {
        [key]: writeLocalized(slide[key], state.locale, value),
      } as Partial<Slide>);
    },
    [patchSlide, state.locale],
  );

  const patchElementTransform = React.useCallback(
    (slideId: string, elementId: ElementId, transform: ElementTransform) => {
      setState((prev) => ({
        ...prev,
        slidesByDevice: {
          ...prev.slidesByDevice,
          [prev.device]: (prev.slidesByDevice[prev.device] || []).map((slide) => {
            if (slide.id !== slideId) return slide;
            if (isTextElementId(elementId)) {
              const textId = textElementKey(elementId);
              return {
                ...slide,
                textElements: (slide.textElements || []).map((element) =>
                  element.id === textId ? { ...element, transform } : element,
                ),
              };
            }
            if (!isBuiltInElementId(elementId)) return slide;
            return {
              ...slide,
              transforms: {
                ...(slide.transforms || {}),
                [elementId]: transform,
              } as Partial<Record<BuiltInElementId, ElementTransform>>,
            };
          }),
        },
      }));
    },
    [setState],
  );

  const patchTextElementText = React.useCallback(
    (slideId: string, textId: string, value: string) => {
      setState((prev) => ({
        ...prev,
        slidesByDevice: {
          ...prev.slidesByDevice,
          [prev.device]: (prev.slidesByDevice[prev.device] || []).map((slide) =>
            slide.id === slideId
              ? {
                  ...slide,
                  textElements: (slide.textElements || []).map((element) =>
                    element.id === textId
                      ? { ...element, text: writeLocalized(element.text, prev.locale, value) }
                      : element,
                  ),
                }
              : slide,
          ),
        },
      }));
    },
    [setState],
  );

  const duplicateSlide = React.useCallback(
    (id: string) => {
      let newId: string | null = null;
      setState((prev) => {
        const slides = prev.slidesByDevice[prev.device] || [];
        const idx = slides.findIndex((s) => s.id === id);
        if (idx === -1) return prev;
        const src = slides[idx];
        newId = nid();
        const copy: Slide = {
          ...src,
          id: newId,
          label: { ...src.label },
          headline: { ...src.headline },
          transforms: src.transforms
            ? Object.fromEntries(
                Object.entries(src.transforms).map(([key, value]) => [key, { ...value }]),
              )
            : undefined,
          textElements: src.textElements?.map((element) => ({
            ...element,
            id: nid(),
            text: { ...element.text },
            transform: { ...element.transform },
          })),
        };
        const next = [...slides.slice(0, idx + 1), copy, ...slides.slice(idx + 1)];
        return {
          ...prev,
          slidesByDevice: { ...prev.slidesByDevice, [prev.device]: next },
        };
      });
      if (newId) setActiveSlideId(newId);
    },
    [setState],
  );

  // ---------- Keyboard shortcuts ----------

  React.useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const target = e.target as HTMLElement | null;
      const inEditable =
        target &&
        (target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          (target as HTMLElement).isContentEditable);
      if (exporting) return;

      if (e.key === "Escape") {
        setSelectedElement(null);
        if (target && "blur" in target && typeof target.blur === "function") target.blur();
        return;
      }

      // Let focused inputs and contenteditable text keep their native undo,
      // redo, selection, and deletion behavior.
      if (inEditable) return;

      if ((e.metaKey || e.ctrlKey) && (e.key === "z" || e.key === "Z")) {
        e.preventDefault();
        if (e.shiftKey) redo();
        else undo();
        return;
      }
      if ((e.metaKey || e.ctrlKey) && (e.key === "y" || e.key === "Y")) {
        e.preventDefault();
        redo();
        return;
      }
      if (!currentSlides.length) return;
      const idx = activeSlide ? currentSlides.findIndex((s) => s.id === activeSlide.id) : -1;
      if (e.key === "ArrowDown" || (e.key === "j" && !e.metaKey && !e.ctrlKey)) {
        e.preventDefault();
        const next = currentSlides[Math.min(currentSlides.length - 1, idx + 1)];
        if (next) setActiveSlideId(next.id);
      } else if (e.key === "ArrowUp" || (e.key === "k" && !e.metaKey && !e.ctrlKey)) {
        e.preventDefault();
        const next = currentSlides[Math.max(0, idx - 1)];
        if (next) setActiveSlideId(next.id);
      } else if ((e.key === "d" || e.key === "D") && (e.metaKey || e.ctrlKey)) {
        if (activeSlide) {
          e.preventDefault();
          duplicateSlide(activeSlide.id);
        }
      } else if ((e.key === "Backspace" || e.key === "Delete") && (e.metaKey || e.ctrlKey)) {
        if (activeSlide) {
          e.preventDefault();
          deleteSlide(activeSlide.id);
        }
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [activeSlide, currentSlides, duplicateSlide, deleteSlide, exporting, undo, redo]);

  // ---------- Export ----------

  // Wait two animation frames so React's render → browser layout/paint of the
  // off-screen container settles before html-to-image snapshots it. One frame
  // is occasionally not enough on slower machines.
  const waitForPaint = () =>
    new Promise<void>((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
    });

  async function exportAll() {
    if (!currentSlides.length) {
      toast.error("No screens to export");
      return;
    }

    const sizes = selectedDevices.map(device => ({...STORE_DEVICES[device], device}));
    if (!sizes.length) {
      toast.error("Nothing to export");
      return;
    }
    const locales = selectedLocales;
    if (!selectedDevices.length || !locales.length) { toast.error("请选择设备和语言"); return; }
    const readiness = await fetch("/api/capture-readiness", {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({locales,devices:selectedDevices})}).then(r=>r.json());
    if (!readiness.ready) { toast.error("素材尚未齐全：" + readiness.missing.join(", ")); return; }
    await document.fonts.ready;
    await preloadImages(assetPaths, { retryFailed: true });
    await waitForPaint();

    const missingScreens = currentSlides
      .map((slide, index) => ({ slide, index }))
      .filter(({ slide }) => slideNeedsScreenshot(state.device, slide) && !slide.screenshot);
    const reusedBackScreens = currentSlides
      .map((slide, index) => ({ slide, index }))
      .filter(
        ({ slide }) =>
          state.device !== "feature-graphic" &&
          slide.layout === "two-devices" &&
          slide.screenshot &&
          !slide.screenshotSecondary,
      );
    if (missingScreens.length > 0 || reusedBackScreens.length > 0) {
      const details = [
        missingScreens.length
          ? `${missingScreens.length} screen${missingScreens.length === 1 ? "" : "s"} will export with an empty device.`
          : null,
        reusedBackScreens.length
          ? `${reusedBackScreens.length} two-device screen${reusedBackScreens.length === 1 ? "" : "s"} will reuse the primary screenshot in back.`
          : null,
      ].filter(Boolean);
      toast.warning("Export includes placeholder screenshots", {
        description: details.join(" "),
        duration: 7000,
      });
    }

    // Make sure custom fonts are loaded before snapshot so typography in PNG
    // matches what's on screen.
    if (typeof document !== "undefined" && document.fonts && document.fonts.ready) {
      try {
        await document.fonts.ready;
      } catch {
        /* ignore */
      }
    }

    const { cW: baseW, cH: baseH } = getCanvas(state.device, state.orientation);
    const cW = storeDevice === "iphone" ? baseW : STORE_DEVICES[storeDevice].w;
    const cH = storeDevice === "iphone" ? baseH : STORE_DEVICES[storeDevice].h;
    const platform = detectPlatform(state.device);
    const zip = new JSZip();
    const totalUnits = locales.length * selectedDevices.reduce((sum, device) => sum + (device === "watch" ? 2 : phoneSlides.length), 0);
    const originalDevice = storeDevice;
    let unit = 0;
    let okCount = 0;
    let failed = 0;
    const errors: string[] = [];

    for (const locale of locales) {
      setExportLocaleOverride(locale);
      await waitForPaint();

      for (const size of sizes) {
        setStoreDevice(size.device);
        await waitForPaint();
        const slides = size.device === "watch" ? [
          {id:"watch-exercise", layout:"hero" as const}, {id:"watch-rest", layout:"hero" as const}
        ] : phoneSlides;
        const canvasW = size.device === "iphone" ? baseW : size.w;
        const canvasH = size.device === "iphone" ? baseH : size.h;
        for (let i = 0; i < slides.length; i++) {
          const slide = slides[i];
          unit += 1;
          setExporting(`${unit}/${totalUnits}`);
          setExportSlideIndex(i);
          await waitForPaint();
          const el = exportRef.current;
          if (!el) {
            failed += 1;
            errors.push(`${locale} ${size.w}×${size.h} screen ${i + 1}: render target missing`);
            continue;
          }
          try {
            const filename = `${String(i + 1).padStart(2, "0")}-${slide.id}.png`;
            const path = `${platform}/${size.device}/${size.w}x${size.h}/${locale}/${filename}`;
            const dataUrl = await captureSlide(el, canvasW, canvasH, size.w, size.h, path);
            const base64 = dataUrl.split(",")[1] || "";
            zip.file(path, base64, { base64: true });
            okCount += 1;
          } catch (e) {
            failed += 1;
            const msg = e instanceof Error ? e.message : String(e);
            errors.push(`${locale} ${size.w}×${size.h} screen ${i + 1}: ${msg}`);
            console.error("Export failed", { slideId: slide.id, locale, size }, e);
          }
        }
      }
    }

    setStoreDevice(originalDevice);
    setExportLocaleOverride(null);
    setExporting(null);

    if (okCount > 0) {
      try {
        zip.file("export-manifest.json", JSON.stringify({app:"Masso",locales,sizes,devices:selectedDevices,slides:phoneSlides.map(s=>({id:s.id,headline:s.headline})),format:"RGB PNG; no alpha",phone:"Apple iPhone 18 Pro / Black",watch:"Apple Watch Series 11 / 46mm"},null,2));
        const blob = await zip.generateAsync({ type: "blob" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = `${slugify(state.appName)}-${platform}-selection-${stamp()}.zip`;
        a.click();
        setTimeout(() => URL.revokeObjectURL(url), 5000);
      } catch (e) {
        toast.error("Couldn't bundle export");
        console.error(e);
        return;
      }
    }

    const summary = `${locales.length} locale${locales.length === 1 ? "" : "s"} × ${sizes.length} size${sizes.length === 1 ? "" : "s"}`;
    if (failed === 0) {
      toast.success(`Exported ${okCount} PNGs (${summary})`);
    } else if (okCount === 0) {
      toast.error(`All ${failed} renders failed`, {
        description: errors.slice(0, 3).join("\n"),
      });
    } else {
      toast.error(`${failed} of ${totalUnits} renders failed`, {
        description: errors.slice(0, 3).join("\n"),
      });
    }
  }

  async function captureSlide(
    el: HTMLElement,
    sourceW: number,
    sourceH: number,
    exportW: number,
    exportH: number,
    artifactPath: string,
  ) {
    // html-to-image needs the node at (0,0). Let the library scale the source
    // canvas into the requested output dimensions; CSS transforms leave
    // transparent gutters when export aspect ratios differ by a few pixels.
    const prev = {
      left: el.style.left,
      top: el.style.top,
      position: el.style.position,
      transform: el.style.transform,
      transformOrigin: el.style.transformOrigin,
      zIndex: el.style.zIndex,
    };
    el.style.left = "0px";
    el.style.top = "0px";
    el.style.position = "absolute";
    el.style.transform = "none";
    el.style.transformOrigin = "top left";
    el.style.zIndex = "-1";
    try {
      const dataUrl = await toPng(el, {
        width: sourceW,
        height: sourceH,
        canvasWidth: exportW,
        canvasHeight: exportH,
        pixelRatio: 1,
        cacheBust: false,
        backgroundColor: "#ffffff",
      });
      const response = await fetch("/api/export-image", {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({dataUrl,artifactPath})});
      if (!response.ok) throw new Error("RGB conversion failed");
      const result = await response.json();
      return result.dataUrl as string;
    } finally {
      el.style.left = prev.left || "-99999px";
      el.style.top = prev.top || "0px";
      el.style.position = prev.position || "absolute";
      el.style.transform = prev.transform;
      el.style.transformOrigin = prev.transformOrigin;
      el.style.zIndex = prev.zIndex;
    }
  }

  // ---------- Render ----------

  if (!hydrated || !ready) {
    return (
      <div className="flex h-screen items-center justify-center">
        <div className="flex flex-col items-center gap-2 text-muted-foreground">
          <div className="h-6 w-6 animate-spin rounded-full border-2 border-current border-t-transparent" />
          <p className="text-sm">Loading editor…</p>
        </div>
      </div>
    );
  }

  const { cW: baseW, cH: baseH } = getCanvas(state.device, state.orientation);
    const cW = storeDevice === "iphone" ? baseW : STORE_DEVICES[storeDevice].w;
    const cH = storeDevice === "iphone" ? baseH : STORE_DEVICES[storeDevice].h;
  const busy = !!exporting;

  return (
    <div className={vertical ? "studio-shell" : "flex h-screen flex-col overflow-hidden bg-background"}>
      <Toaster position="top-right" richColors closeButton />
      {vertical ? <>
        <header className="studio-header"><a className="studio-brand" href="#top"><img src="/mark.svg" alt=""/>MASSO <span>APP STORE STUDIO</span></a><div className="studio-actions">
          <select aria-label="Device category" value={storeDevice} onChange={e=>{setStoreDevice(e.target.value as StoreDevice);setExportSlideIndex(0)}} disabled={busy}>{Object.entries(STORE_DEVICES).map(([id,d])=><option key={id} value={id}>{d.label} · {d.w} × {d.h}</option>)}</select>
          <select aria-label="预览语言" value={state.locale} onChange={e=>setState(p=>({...p,locale:e.target.value}))} disabled={busy}>{state.locales.map(l=><option key={l} value={l}>{l}</option>)}</select>
          <button className="studio-export" onClick={exportAll} disabled={busy}>{busy ? `导出中 ${exporting}` : `一键导出 ${currentSlides.length} 页 ↓`}</button>
        </div></header>
        <aside className="studio-nav"><p>THE PRODUCT STORY</p>{currentSlides.map((slide,i)=><a key={slide.id} href={`#page-${slide.id}`}><span>{String(i+1).padStart(2,"0")}</span>{(slide.label[state.locale]||slide.label.en||"").split(" / ").slice(1).join(" / ")}</a>)}<div className="studio-save">{saveError?"保存失败，请保留当前页面":savedAt?"修改已保存到本机":"自动保存"}</div></aside>
        <main className="studio-feed" id="top"><details className="studio-selection"><summary>选择导出语言和设备</summary><p>按语言和设备检查真实截图完整性；缺失素材会阻止导出。</p><fieldset><legend>语言</legend>{state.locales.map(l=><label key={l}><input type="checkbox" checked={selectedLocales.includes(l)} onChange={e=>setSelectedLocales(prev=>e.target.checked?[...prev,l]:prev.filter(x=>x!==l))}/>{l}</label>)}</fieldset><fieldset><legend>设备</legend>{(Object.entries(STORE_DEVICES) as [StoreDevice, typeof STORE_DEVICES[StoreDevice]][]).map(([id,d])=><label key={id}><input type="checkbox" checked={selectedDevices.includes(id)} onChange={e=>setSelectedDevices(prev=>e.target.checked?[...prev,id]:prev.filter(x=>x!==id))}/>{d.label}</label>)}</fieldset><small>导出会按设备和语言分别整理到压缩包。</small></details><div className="studio-intro"><p>PORTFOLIO → APP STORE</p><h1>把 Masso 的故事<br/>一页页讲清楚<span>。</span></h1><div>Manrope · Masso green · iPhone · iPad · Apple Watch</div></div>
        {storeDevice === "iphone" && <section className="studio-strip"><p>横向预览 · 模拟截图间距</p><div className="studio-strip-scroll">{currentSlides.map(slide=><div key={slide.id} className="studio-strip-item"><VerticalSheet slide={slide} slides={currentSlides} theme={theme} locale={state.locale} connectedCanvas={state.connectedCanvas}/></div>)}</div></section>}
        {storeDevice === "duo" && <p className="studio-duo-notice">Duo 使用真实展开内屏截图；导出前核对 12 种语言素材与来源记录。</p>}
        {currentSlides.map((slide,i)=><section key={slide.id} id={`page-${slide.id}`} className="studio-page"><div className="studio-page-head"><span>{String(i+1).padStart(2,"0")} / {String(currentSlides.length).padStart(2,"0")}</span>{storeDevice === "iphone" && <button onClick={()=>{setActiveSlideId(slide.id);setVertical(false)}}>编辑这一页 ↗</button>}</div>{storeDevice === "iphone" ? <VerticalSheet slide={slide} theme={theme} locale={state.locale} slides={currentSlides} connectedCanvas={state.connectedCanvas}/> : <DeviceSheet slide={slide} device={storeDevice} locale={state.locale}/>}</section>)}
        <footer className="studio-footer"><p>每页一个卖点。原生截图使用演示数据；部分语言的界面截图仍回退英文，阿拉伯语部分动作名称仍为英文。iPhone 为 iOS 26.1、iPad 为 iOS 27.0，Duo 使用 iOS 27.1 原生内屏截图。</p><p>每类仅导出最大竖屏尺寸：iPhone 1320 × 2868 · Duo 2007 × 2853（原生内屏）· iPad 2064 × 2752 · Watch 416 × 496。Watch 导出原生界面，不含设备框。预览视频规格单独保留，不导出静态 PNG 冒充视频。 <a href="https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/" target="_blank" rel="noreferrer">Apple 截图规范 ↗</a></p></footer></main>
      </> : <>
      <button className="studio-back" onClick={()=>setVertical(true)}>← 返回全部页面</button>
      <Toolbar
        appName={state.appName}
        setAppName={(v) => setState((p) => ({ ...p, appName: v }))}
        connectedCanvas={state.connectedCanvas}
        setConnectedCanvas={(v) => setState((p) => ({ ...p, connectedCanvas: v }))}
        locale={state.locale}
        setLocale={(v) => setState((p) => ({ ...p, locale: v }))}
        locales={state.locales}
        device={state.device}
        setDevice={(v) => setState((p) => ({ ...p, device: v }))}
        orientation={state.orientation}
        setOrientation={(v) => setState((p) => ({ ...p, orientation: v }))}
        onExport={exportAll}
        onResetAll={() => {
          reset();
          setActiveSlideId(null);
          toast.success("Reset all devices to defaults");
        }}
        onResetDevice={() => {
          resetDevice(state.device);
          setActiveSlideId(null);
          toast.success(`Reset ${state.device} to defaults`);
        }}
        exporting={exporting}
        savedAt={savedAt}
        saveError={saveError}
        busy={busy}
      />

      <div className="flex flex-1 overflow-hidden md:flex-row flex-col">
        <aside className="md:w-72 w-full shrink-0 border-r bg-card md:max-h-none max-h-64 overflow-hidden">
          <Sidebar
            slides={currentSlides}
            activeId={activeSlide?.id || null}
            device={state.device}
            orientation={state.orientation}
            theme={theme}
            locale={state.locale}
            appName={state.appName}
            appIcon={state.appIcon}
            connectedCanvas={state.connectedCanvas}
            disabled={busy}
            onReorder={reorderSlides}
            onSelect={setActiveSlideId}
            onDelete={deleteSlide}
            onDuplicate={duplicateSlide}
            onAdd={addSlide}
          />
        </aside>

        <main className="flex flex-1 items-stretch overflow-hidden min-h-0">
          {activeSlide && currentSlides.length > 0 ? (
            <PreviewStage
              slides={currentSlides}
              activeSlideId={activeSlide.id}
              device={state.device}
              orientation={state.orientation}
              theme={theme}
              locale={state.locale}
              appName={state.appName}
              appIcon={state.appIcon}
              connectedCanvas={state.connectedCanvas}
              selectedElement={selectedElement}
              onActiveSlideChange={setActiveSlideId}
              onLabelChange={(slide, v) => patchLocalized(slide, "label", v)}
              onHeadlineChange={(slide, v) => patchLocalized(slide, "headline", v)}
              onTextElementTextChange={patchTextElementText}
              onElementChange={patchElementTransform}
              onSelectElement={setSelectedElement}
            />
          ) : (
            <div className="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center text-sm text-muted-foreground">
              <p className="font-medium text-foreground">No screen selected</p>
              <p>Add a screen on the left to get started.</p>
            </div>
          )}
        </main>

        <aside className="md:w-80 w-full shrink-0 border-l bg-card md:max-h-none max-h-96 overflow-hidden">
          {activeSlide ? (
            <Inspector
              slide={activeSlide}
              device={state.device}
              orientation={state.orientation}
              locale={state.locale}
              selectedElementId={
                selectedElement?.slideId === activeSlide.id ? selectedElement.elementId : null
              }
              onChange={(patch) => patchSlide(activeSlide.id, patch)}
              onSelectElement={(elementId) =>
                setSelectedElement(
                  elementId ? { slideId: activeSlide.id, elementId } : null,
                )
              }
            />
          ) : (
            <div className="flex h-full flex-col items-center justify-center gap-2 p-6 text-center text-sm text-muted-foreground">
              <p className="font-medium text-foreground">Nothing to inspect</p>
              <p className="text-xs">Screen settings will appear here once you add or select one.</p>
            </div>
          )}
        </aside>
      </div>

      </>}
      {/* Off-screen export container — full-resolution canvases for html-to-image. */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          left: -99999,
          top: 0,
          pointerEvents: "none",
        }}
      >
        {currentSlides.length > 0 && (
          <div
            ref={exportRef}
            style={{
              width: cW,
              height: cH,
              overflow: "hidden",
              position: "absolute",
              left: -99999,
              top: 0,
            }}
          >
            <div
              style={{
                position: "absolute",
                left: storeDevice === "iphone" ? -exportSlideIndex * cW : 0,
                top: 0,
                width: cW * currentSlides.length,
                height: cH,
              }}
            >
              {storeDevice !== "iphone" ? <DeviceShowcase slide={currentSlides[exportSlideIndex] || currentSlides[0]} device={storeDevice} locale={exportLocaleOverride ?? state.locale}/> : <DeckCanvas
                slides={currentSlides}
                device={state.device}
                orientation={state.orientation}
                theme={theme}
                locale={exportLocaleOverride ?? state.locale}
                appName={state.appName}
                appIcon={state.appIcon}
                connectedCanvas={state.connectedCanvas}
                hideEmpty
              />}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function slugify(s: string) {
  return (
    s
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "") || "screenshots"
  );
}

function slideNeedsScreenshot(device: Device, slide: Slide) {
  if (device === "feature-graphic") return false;
  return slide.layout !== "no-device" && slide.layout !== "feature-graphic";
}

function stamp() {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
}
