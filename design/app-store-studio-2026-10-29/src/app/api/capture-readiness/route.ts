import { NextResponse } from 'next/server';
import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
const locales = ['zh','zh-Hant','en','ja','ko','es','fr','de','it','pt-BR','ru','ar'];
// Plan A deck (five pages): plan / recovery / training+watch / diet+sleep / devices.
// 'today' is the screen the "every supported device" page puts on the phone,
// tablet and Duo, so it is required for every export from now on.
const scenesByDevice: Record<string, string[]> = {
 iphone: ['plans','muscle-selected','player-heart-warning','diet','sleep','today'],
 ipad: ['plans','muscle-selected','training','insights','diet','sleep','today'],
 duo: ['plans','muscle-selected','training','insights','diet','sleep','today'],
 watch: ['exercise-185','rest-160'],
};
const watchScenes = ['exercise-185','rest-160'];
export async function POST(request: Request) {
 const body = await request.json();
 if (!Array.isArray(body.locales)||!Array.isArray(body.devices)||!body.locales.every((l:string)=>locales.includes(l))||!body.devices.every((d:string)=>['iphone','ipad','watch','duo'].includes(d))) return NextResponse.json({ready:false,missing:['invalid selection']},{status:400});
 const missing:string[]=[];
 for(const locale of body.locales) for(const device of body.devices) {
  if(device==='duo') {try {const proof=JSON.parse(await readFile(path.join(process.cwd(),'duo-capture-provenance.json'),'utf8'));if(proof.nativeInnerDisplay!==true||proof.width!==2007||proof.height!==2853) missing.push(locale+'/duo: native capture proof invalid');}catch{missing.push(locale+'/duo: native capture proof missing');}}
  if(device==='ipad') {try {const proof=JSON.parse(await readFile(path.join(process.cwd(),'ipad-capture-corrections.json'),'utf8'));if(proof.complete!==true) missing.push(locale+'/ipad: transition frames require recapture');}catch{missing.push(locale+'/ipad: capture corrections pending');}}
  for(const scene of scenesByDevice[device]||[]) try {await access(path.join(process.cwd(),'public/screenshots/localized',device,locale,scene+'.png'));} catch {missing.push(locale+'/'+device+'/'+scene);}
  if(device!=='watch') for(const scene of watchScenes) try {await access(path.join(process.cwd(),'public/screenshots/localized/watch',locale,scene+'.png'));} catch {missing.push(locale+'/watch/'+scene);}
 }
 return NextResponse.json({ready:missing.length===0,missing});
}
