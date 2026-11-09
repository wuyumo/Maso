import * as React from "react";
import { img } from "@/lib/image-cache";

// Preview mock based on the existing photo-report confirmation flow.
export function CoachPhotoDemo() {
 return <div aria-label="示意：照片分析与生成训练计划" style={{position:"absolute",inset:0,overflow:"hidden",background:"#101010",color:"#f5f5f5",fontFamily:"-apple-system, BlinkMacSystemFont, sans-serif",fontSize:"3.3cqw"}}>
  <div style={{height:"14cqw",padding:"3.5cqw 6cqw 0",display:"flex",justifyContent:"space-between",fontWeight:650,fontSize:"4cqw"}}><span>9:41</span><span>▰ ▰ ●</span></div>
  <div style={{padding:"3cqw 5cqw 4cqw",fontSize:"6.5cqw",fontWeight:700}}>AI Coach</div>
  <div style={{padding:"0 5cqw"}}>
   <div style={{marginLeft:"auto",width:"58%",padding:"2cqw",borderRadius:"4cqw",background:"#28282b"}}><img src={img('/screenshots/apple/iphone/coach-body-portrait.jpg')} alt="" style={{width:"100%",height:"43cqw",objectFit:"cover",objectPosition:"center 23%",borderRadius:"2.5cqw"}}/><div style={{padding:"2cqw 1cqw",fontSize:"3cqw"}}>Can you review my physique?</div></div>
   <div style={{marginTop:"6cqw",lineHeight:1.45,fontSize:"3.4cqw"}}><div style={{fontWeight:650,marginBottom:"2cqw"}}>Your physique report</div><div>Based on this photo, your upper body shows balanced development. A clear view of your back and legs would help complete the picture.</div><div style={{marginTop:"3cqw",color:"#a8a8ab"}}>Here is a plan based on your goals and the report.</div></div>
   <div style={{marginTop:"5cqw",border:"1px solid #464648",borderRadius:"4cqw",padding:"4cqw"}}><div style={{fontSize:"2.8cqw",fontWeight:700,color:"#1ed760",letterSpacing:".2cqw"}}>DAY 1 · AI</div><div style={{fontSize:"4.4cqw",fontWeight:700,marginTop:"1.5cqw"}}>Upper body strength</div><div style={{color:"#aaa",fontSize:"2.8cqw",marginTop:"1cqw"}}>4 exercises · 12 sets</div><div style={{display:"flex",gap:"2cqw",marginTop:"3cqw",fontSize:"2.6cqw"}}><span style={{background:"#242426",padding:"1.5cqw",borderRadius:99}}>Chest · Bench Press</span><span style={{background:"#242426",padding:"1.5cqw",borderRadius:99}}>Back · Row</span></div></div>
  </div>
 </div>;
}
