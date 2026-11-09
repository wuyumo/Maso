import * as React from "react";
import { img } from "@/lib/image-cache";

// Preview reconstruction: layout follows RecordedMealCard / HistoryDaySummaryHeader.
// Photos and values are illustrative; this is not a native capture.
export function DietHistoryDemo() {
 const days = [
  {date:"Thu, Oct 29", percent:"57%", amount:"1,222", image:"/screenshots/apple/iphone/meal-demo-chicken.png", food:"Chicken, rice and broccoli", protein:"48 g", carbs:"82 g", fat:"20 g"},
  {date:"Wed, Oct 28", percent:"83%", amount:"1,776", image:"/screenshots/apple/iphone/meal-demo-salmon.png", food:"Salmon, sweet potato and greens", protein:"42 g", carbs:"63 g", fat:"24 g"},
 ];
 return <div aria-label="示意：每日饮食记录及餐食照片" style={{position:"absolute",inset:0,overflow:"hidden",background:"#101010",color:"#f5f5f5",fontFamily:"-apple-system, BlinkMacSystemFont, sans-serif",fontSize:"3.5cqw"}}>
  <div style={{height:"13cqw",padding:"3.5cqw 6cqw 0",display:"flex",justifyContent:"space-between",fontWeight:650,fontSize:"4cqw"}}><span>9:41</span><span>▰ ▰ ●</span></div>
  <div style={{padding:"2cqw 5cqw 0",fontSize:"7cqw",fontWeight:700}}>Diet</div>
  <div style={{padding:"6cqw 5cqw 3cqw",fontSize:"3.2cqw",fontWeight:700,letterSpacing:".3cqw",color:"#b1b1b4"}}>DIET HISTORY</div>
  <div style={{padding:"0 4cqw",display:"flex",flexDirection:"column",gap:"3cqw"}}>{days.map(day=><div key={day.date} style={{background:"#262628",border:"1px solid #414143",borderRadius:"4cqw",padding:"5cqw"}}>
   <div style={{display:"flex",alignItems:"baseline",justifyContent:"space-between",fontSize:"4cqw",fontWeight:650}}><span>{day.date}</span><span>{day.percent} <small style={{fontSize:"2.8cqw",fontWeight:400,color:"#aaa"}}>Calories</small></span></div>
   <div style={{marginTop:"1.5cqw",fontSize:"3.8cqw",fontWeight:600}}>{day.amount}<span style={{color:"#aaa",fontWeight:400}}> / 2,140 kcal</span></div>
   <div style={{height:".8cqw",background:"#48484a",borderRadius:99,marginTop:"2cqw"}}><div style={{width:day.percent,height:"100%",background:"#ffd60a",borderRadius:99}}/></div>
   <div style={{height:1,background:"#505052",margin:"3cqw 0"}}/>
   <div style={{display:"flex",justifyContent:"space-between",alignItems:"baseline"}}><strong style={{fontSize:"3.8cqw"}}>Meal 1</strong><span style={{fontSize:"2.7cqw",color:"#aaa"}}>12:30 PM · ≈ 610 kcal</span></div>
   <img src={img(day.image)} alt="" style={{width:"100%",height:"23cqw",objectFit:"cover",borderRadius:"2.5cqw",marginTop:"2.5cqw",display:"block"}}/>
   <div style={{fontSize:"3.1cqw",color:"#c5c5c7",marginTop:"2cqw"}}>{day.food}</div>
   <div style={{display:"flex",justifyContent:"space-between",fontSize:"2.8cqw",color:"#aaa",marginTop:"2cqw"}}><span>Protein <b style={{color:"#fff"}}>{day.protein}</b></span><span>Carbs <b style={{color:"#fff"}}>{day.carbs}</b></span><span>Fat <b style={{color:"#fff"}}>{day.fat}</b></span></div>
  </div>)}</div>
 </div>;
}
