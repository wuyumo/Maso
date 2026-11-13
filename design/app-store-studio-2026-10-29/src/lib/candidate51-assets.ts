import type { Slide } from "./types";
export const READY_51_LOCALES=["zh","zh-Hant","en","ja","ko","es","fr","de","it","pt-BR","ru","ar"];
export const CANDIDATE_51_BASE="/candidate-assets/pro-20261113/native51";
export const CANDIDATE_51_REVISION="native51-20261113-1205";
export function candidatePageReady(device:string,slide:string,locale:string):boolean {
  if(!READY_51_LOCALES.includes(locale)) return false;
  if(device==="watch") return slide==="watch-rest"||(slide==="watch-exercise"&&locale!=="ru");
  if(!["iphone","iphone-medium","ipad","duo"].includes(device)) return false;
  return ["plan","recovery","diet","devices"].includes(slide)||(slide==="training"&&["iphone","iphone-medium","ipad"].includes(device)&&locale!=="ru");
}
export function candidateWatchSource(locale:string,slide:string):string|undefined {
  if(!READY_51_LOCALES.includes(locale)) return undefined;
  const scene=slide==="watch-exercise"?"exercise-185":slide==="watch-rest"?"rest-160":undefined;
  return scene?`${CANDIDATE_51_BASE}/watch/${locale}/watch-${scene}.png?v=${CANDIDATE_51_REVISION}`:undefined;
}
export function candidate51Override(slide:Slide,family:string,locale:string,secondary=false):string|undefined {
  if(slide.id!=="training"||!["iphone","ipad"].includes(family)||!READY_51_LOCALES.includes(locale)||!slide.screenshot?.startsWith(CANDIDATE_51_BASE+"/")) return undefined;
  return secondary?candidateWatchSource(locale,"watch-exercise"):`${CANDIDATE_51_BASE}/${family}/${locale}/player-heart-warning.png?v=${CANDIDATE_51_REVISION}`;
}
