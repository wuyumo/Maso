import * as React from "react";
import { NATIVE_COACH_COPY } from "@/lib/candidate-native-coach-copy";

function Icon({kind,size}: {kind:"back"|"preferences"|"plus"|"send";size:number}) {
  const path={back:"M15 4L7 12L15 20",preferences:"M3 6H21M3 12H21M3 18H21M8 3V9M16 9V15M10 15V21",plus:"M12 4V20M4 12H20",send:"M12 20V4M5 11L12 4L19 11"}[kind];
  return <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d={path}/></svg>;
}

/** A is explicitly a mock: chrome follows native51, never claims to be a raw capture. */
export function CandidateNativeCoachChrome({locale,unit,topInset,visibleHeight}: {locale:string;unit:number;topInset:number;visibleHeight:number}) {
  const copy=NATIVE_COACH_COPY[locale as keyof typeof NATIVE_COACH_COPY] || NATIVE_COACH_COPY.en;
  const rtl=locale==="ar";
  const circle:React.CSSProperties={width:96*unit,height:96*unit,borderRadius:"50%",background:"#202020",border:`${1.5*unit}px solid #303030`,display:"flex",alignItems:"center",justifyContent:"center",flex:"none",color:"#eee"};
  return <div data-candidate-native-chrome="mock" dir={rtl?"rtl":"ltr"} style={{position:"absolute",inset:0,pointerEvents:"none",color:"#eee",fontFamily:"inherit"}}>
    <div data-native-mock-header="1" style={{position:"absolute",left:20*unit,right:20*unit,top:(topInset+64)*unit,height:108*unit,display:"flex",alignItems:"center",justifyContent:"space-between"}}>
      <span style={{...circle,transform:rtl?"scaleX(-1)":undefined}}><Icon kind="back" size={46*unit}/></span>
      <strong style={{fontSize:48*unit,fontWeight:700}}>{copy.title}</strong>
      <span style={circle}><Icon kind="preferences" size={42*unit}/></span>
    </div>
    <div data-native-mock-composer="1" style={{position:"absolute",left:18*unit,right:18*unit,top:visibleHeight-444*unit,height:420*unit}}>
      <div style={{display:"flex",gap:16*unit,height:84*unit,overflow:"hidden",alignItems:"center"}}>
        {copy.prompts.map((text,i)=><span key={i} style={{whiteSpace:"nowrap",fontSize:34*unit,padding:`${18*unit}px ${26*unit}px`,borderRadius:60*unit,background:"#202020",flex:"none"}}>{text}</span>)}
      </div>
      <div style={{position:"relative",height:300*unit,marginTop:18*unit,borderRadius:52*unit,border:`${1.5*unit}px solid #303030`,background:"#181818",boxSizing:"border-box",padding:30*unit}}>
        <div style={{fontSize:46*unit,lineHeight:1.3,color:"#656565"}}>{copy.placeholder}</div>
        <span style={{...circle,position:"absolute",insetInlineStart:30*unit,bottom:26*unit,background:"#303030"}}><Icon kind="plus" size={44*unit}/></span>
        <span style={{...circle,position:"absolute",insetInlineEnd:30*unit,bottom:26*unit,color:"#747474",background:"#242424"}}><Icon kind="send" size={48*unit}/></span>
      </div>
    </div>
  </div>;
}
