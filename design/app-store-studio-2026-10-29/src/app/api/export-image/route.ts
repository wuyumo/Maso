import { NextResponse } from 'next/server';
import sharp from 'sharp';
import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
export const runtime = 'nodejs';
export async function POST(request: Request) {
 try {
  const {dataUrl,artifactPath} = await request.json();
  if(typeof dataUrl!=='string'||!dataUrl.startsWith('data:image/png;base64,')||dataUrl.length>40_000_000) return NextResponse.json({error:'Invalid image'},{status:400});
  const bytes=Buffer.from(dataUrl.split(',')[1],'base64');
  const output=await sharp(bytes,{limitInputPixels:20_000_000}).flatten({background:'#ebecec'}).removeAlpha().png().toBuffer();
  if(artifactPath!==undefined) {
   if(typeof artifactPath!=='string'||!/^(ios|android)\/(iphone|ipad|duo|watch)\/\d{3,4}x\d{3,4}\/(zh|zh-Hant|en|ja|ko|es|fr|de|it|pt-BR|ru|ar)\/[0-9]{2}-[a-z][a-z0-9-]*\.png$/.test(artifactPath)) return NextResponse.json({error:'Invalid artifact path'},{status:400});
   const file=path.join(process.cwd(),'exports/latest',artifactPath);
   await mkdir(path.dirname(file),{recursive:true});await writeFile(file,output);
  }
  return NextResponse.json({dataUrl:'data:image/png;base64,'+output.toString('base64')});
 } catch { return NextResponse.json({error:'Image conversion failed'},{status:400}); }
}
