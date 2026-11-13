import * as React from "react";
export const PAGES = [
  {id:"plan",label:"照片计划"}, {id:"recovery",label:"恢复估算"},
  {id:"training",label:"训练心率"}, {id:"diet",label:"饮食睡眠"}, {id:"devices",label:"多设备"},
] as const;
export const WATCH_PAGES=[{id:"watch-exercise",label:"Watch训练"},{id:"watch-rest",label:"Watch休息"}] as const;
export function pagesForDevice(device:string):readonly {id:string;label:string}[] {return device==="watch"?WATCH_PAGES:PAGES;}
export const DEVICES = [
  {id:"iphone",label:"iPhone · 1320×2868"}, {id:"iphone-medium",label:"iPhone · 1206×2622"},
  {id:"ipad",label:"iPad · 2064×2752"}, {id:"duo",label:"Duo · 2007×2853"}, {id:"watch",label:"Watch · 416×496"},
] as const;
export const LOCALES = [
  ["zh","简体中文"],["zh-Hant","繁體中文"],["en","English"],["ja","日本語"],
  ["ko","한국어"],["es","Español"],["fr","Français"],["de","Deutsch"],
  ["it","Italiano"],["pt-BR","Português"],["ru","Русский"],["ar","العربية"],
] as const;
export type PreviewDevice = typeof DEVICES[number]["id"];
export type PreviewTarget = {device:PreviewDevice;slide:string;locale:string};
export function parsePreviewTarget(search:string): PreviewTarget {
  const q=new URLSearchParams(search);
  const device=DEVICES.find(d=>d.id===q.get("device"))?.id || "iphone";const pages=pagesForDevice(device);
  return {device,slide:pages.find(p=>p.id===q.get("slide"))?.id || pages[0].id,locale:LOCALES.find(l=>l[0]===q.get("locale"))?.[0] || "zh"};
}
export function targetSearch(target:PreviewTarget) { return "?"+new URLSearchParams(target).toString(); }
export function pageIndex(target:PreviewTarget) { return Math.max(0,pagesForDevice(target.device).findIndex(p=>p.id===target.slide)); }
export function adjacentTarget(target:PreviewTarget,direction:number):PreviewTarget { const pages=pagesForDevice(target.device);return {...target,slide:pages[Math.max(0,Math.min(pages.length-1,pageIndex(target)+direction))].id}; }
export function canExportPage(target:PreviewTarget) {
  const ready=["zh","en","zh-Hant"].includes(target.locale);
  if(target.device==="watch") return ready&&["watch-exercise","watch-rest"].includes(target.slide);
  return ["plan","recovery"].includes(target.slide)||(target.slide==="training"&&ready&&["iphone","iphone-medium"].includes(target.device));
}
export function exportName(target:PreviewTarget) {return target.device==="watch"?(target.slide==="watch-exercise"?"01-exercise-185.png":"02-rest-160.png"):target.slide==="training"?"03-training.png":target.slide==="plan"?"01-plan.png":"02-recovery.png";}

export function fitScale(viewport:{w:number;h:number},canvas:{w:number;h:number}) {
  return Math.max(0.01,Math.min(1,Math.max(1,viewport.w-32)/canvas.w,Math.max(1,viewport.h-32)/canvas.h));
}
export function exportCaptureOptions(canvas:{w:number;h:number}) {
  return {width:canvas.w,height:canvas.h,canvasWidth:canvas.w,canvasHeight:canvas.h,pixelRatio:1,style:{position:"static",inset:"auto",transform:"none",transformOrigin:"top left"}};
}
type Props = {
  target:PreviewTarget; mode:"fit"|"actual"; scale:number; ready:boolean; busy:boolean; error:string|null;
  onTarget:(target:PreviewTarget)=>void; onMode:(mode:"fit"|"actual")=>void; onExport:()=>void;
};
const button:React.CSSProperties={minHeight:40,padding:"8px 12px",border:"1px solid #ccd2dc",borderRadius:8,background:"#fff",color:"#172233",fontSize:14,cursor:"pointer"};
export function CandidatePreviewControls({target,mode,scale,ready,busy,error,onTarget,onMode,onExport}:Props) {
  const index=pageIndex(target); const allowed=canExportPage(target);const pages=pagesForDevice(target.device);
  const status=error?error:!allowed?(target.slide==="training"||target.device==="watch"?"当前语言/设备51素材未齐 · 不能导出":"保留参考页 · 不在本批导出"):busy?"正在保存原尺寸 PNG…":ready?"源素材已核对 · 可导出候选，整张待验收":"正在加载字体与图片…";
  return <header aria-label="截图预览控制栏" style={{flexShrink:0,maxHeight:"46dvh",overflowY:"auto",background:"#fff",borderBottom:"1px solid #cdd3dd",padding:"10px 16px",boxShadow:"0 2px 10px #17223312",zIndex:10}}>
    <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",gap:8,flexWrap:"wrap",marginBottom:8}}>
      <strong>截图预览 · {index+1}/{pages.length} · {pages[index].label}</strong>
      <span style={{fontSize:12,color:"#596578"}}>{DEVICES.find(d=>d.id===target.device)?.label} · {LOCALES.find(l=>l[0]===target.locale)?.[1]}</span>
    </div>
    <nav aria-label="截图页面" style={{display:"grid",gridTemplateColumns:`repeat(${pages.length},minmax(0,1fr))`,gap:6,marginBottom:8}}>
      {pages.map((page,i)=><button key={page.id} type="button" data-page={page.id} aria-current={page.id===target.slide ? "page" : undefined} disabled={busy} onClick={()=>onTarget({...target,slide:page.id})} style={{...button,padding:"8px 3px",fontSize:12,background:page.id===target.slide?"#164e35":"#f5f7fa",color:page.id===target.slide?"#fff":"#172233",borderColor:page.id===target.slide?"#164e35":"#d5dae2"}}>{String(i+1).padStart(2,"0")}<br/>{page.label}{page.id==="training"&&!canExportPage({...target,slide:page.id})?" · 待补":""}</button>)}
    </nav>
    <div style={{display:"flex",alignItems:"center",gap:8,flexWrap:"wrap"}}>
      <button type="button" aria-label="上一张" disabled={busy||index===0} onClick={()=>onTarget(adjacentTarget(target,-1))} style={button}>← 上一张</button>
      <button type="button" aria-label="下一张" disabled={busy||index===pages.length-1} onClick={()=>onTarget(adjacentTarget(target,1))} style={button}>下一张 →</button>
      <label style={{fontSize:12}}>语言 <select aria-label="语言" value={target.locale} disabled={busy} onChange={e=>onTarget({...target,locale:e.target.value})} style={{...button,maxWidth:150}}>{LOCALES.map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label>
      <label style={{fontSize:12}}>设备 <select aria-label="设备" value={target.device} disabled={busy} onChange={e=>onTarget(parsePreviewTarget(targetSearch({...target,device:e.target.value as PreviewDevice})))} style={{...button,maxWidth:205}}>{DEVICES.map(d=><option key={d.id} value={d.id}>{d.label}</option>)}</select></label>
      <div role="group" aria-label="预览缩放" style={{display:"flex",gap:4}}>
        <button type="button" aria-pressed={mode==="fit"} onClick={()=>onMode("fit")} style={{...button,background:mode==="fit"?"#e5f3eb":"#fff"}}>适配 Fit</button>
        <button type="button" aria-pressed={mode==="actual"} onClick={()=>onMode("actual")} style={{...button,background:mode==="actual"?"#e5f3eb":"#fff"}}>100%</button>
      </div>
      <span style={{fontSize:12,color:"#596578"}}>{Math.round(scale*100)}% · 导出尺寸不变</span>
      <button type="button" data-export="candidate" disabled={!allowed||!ready||busy||!!error} onClick={onExport} style={{...button,background:!allowed||!ready||busy||error?"#e8ebee":"#164e35",color:!allowed||!ready||busy||error?"#596578":"#fff"}}>{busy?"保存中…":"保存本页 PNG"}</button>
    </div>
    <div role="status" aria-live="polite" style={{fontSize:12,color:error?"#a21d20":target.slide==="training"?"#895300":"#596578",marginTop:8}}>{status} · 控制栏不入图；模拟器独立演示，手机/Watch时钟不同，不代表真机同步。</div>
  </header>;
}
