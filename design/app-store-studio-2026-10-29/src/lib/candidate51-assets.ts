import type { Slide } from "./types";
export const READY_51_LOCALES=["zh","en","zh-Hant"];
export const CANDIDATE_51_BASE="/candidate-assets/pro-20261113/native51";
export function candidateWatchSource(locale:string,slide:string):string|undefined {
  if(!READY_51_LOCALES.includes(locale)) return undefined;
  const scene=slide==="watch-exercise"?"exercise-185":slide==="watch-rest"?"rest-160":undefined;
  return scene?`${CANDIDATE_51_BASE}/watch/${locale}/watch-${scene}.png`:undefined;
}
export function candidate51Override(slide:Slide,family:string,locale:string,secondary=false):string|undefined {
  if(slide.id!=="training"||family!=="iphone"||!READY_51_LOCALES.includes(locale)||!slide.screenshot?.startsWith(CANDIDATE_51_BASE+"/")) return undefined;
  return secondary?candidateWatchSource(locale,"watch-exercise"):`${CANDIDATE_51_BASE}/iphone/${locale}/player-heart-warning.png`;
}
