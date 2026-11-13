import { pagesForDevice,canExportPage,type PreviewTarget,type PreviewDevice } from "../components/editor/candidate-preview-controls";
export function reviewBatchTargets(device:PreviewDevice):PreviewTarget[] {
  return ["zh","en"].flatMap(locale=>pagesForDevice(device).map(page=>({device,locale,slide:page.id})).filter(canExportPage));
}
export type BatchDriver={show:(target:PreviewTarget)=>Promise<void>;ready:(target:PreviewTarget)=>Promise<void>;capture:(target:PreviewTarget)=>Promise<string>;cancelled:()=>boolean;progress:(saved:readonly string[],total:number,target:PreviewTarget)=>void};
export async function runReviewBatch(targets:readonly PreviewTarget[],driver:BatchDriver) {
  const saved:string[]=[];
  if(targets.some(target=>!canExportPage(target))) throw new Error("Batch contains a blocked source variant");
  for(const target of targets){
    if(driver.cancelled()) return {status:"stopped" as const,saved};
    await driver.show(target);await driver.ready(target);
    if(driver.cancelled()) return {status:"stopped" as const,saved};
    if(!canExportPage(target)) throw new Error("Source gate changed");
    saved.push(await driver.capture(target));driver.progress([...saved],targets.length,target);
  }
  return {status:"complete" as const,saved};
}
