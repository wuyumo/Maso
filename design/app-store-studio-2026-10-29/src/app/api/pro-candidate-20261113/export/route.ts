import { NextResponse } from "next/server";
import sharp from "sharp";
import { candidatePageReady } from "../../../../lib/candidate51-assets";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
export const runtime = "nodejs";
const sizes: Record<string,string> = {iphone:"1320x2868", "iphone-medium":"1206x2622", ipad:"2064x2752", duo:"2007x2853",watch:"416x496"};
export async function POST(request: Request) {
  try {
    const {dataUrl,artifactPath} = await request.json();
    const match = typeof artifactPath === "string" && /^ios\/(iphone|iphone-medium|ipad|duo|watch)\/(\d{3,4}x\d{3,4})\/(zh|zh-Hant|en|ja|ko|es|fr|de|it|pt-BR|ru|ar)\/(01-plan|02-recovery|03-training|04-diet|05-devices|01-exercise-185|02-rest-160)\.png$/.exec(artifactPath);
    if (!match || sizes[match[1]] !== match[2] || typeof dataUrl !== "string" || !dataUrl.startsWith("data:image/png;base64,") || dataUrl.length > 40_000_000) return NextResponse.json({error:"Invalid candidate image/path"},{status:400});
    const pageByName:Record<string,string>={"01-plan":"plan","02-recovery":"recovery","03-training":"training","04-diet":"diet","05-devices":"devices","01-exercise-185":"watch-exercise","02-rest-160":"watch-rest"};
    const allowed=candidatePageReady(match[1],pageByName[match[4]],match[3]);
    if(!allowed) return NextResponse.json({error:"Native source not ready for this locale/device/page"},{status:400});
    const bytes = Buffer.from(dataUrl.split(",")[1],"base64");
    const meta = await sharp(bytes,{limitInputPixels:20_000_000}).metadata();
    const [w,h] = match[2].split("x").map(Number);
    if (meta.format !== "png" || meta.width !== w || meta.height !== h) return NextResponse.json({error:"Candidate PNG dimensions do not match target"},{status:400});
    const output = await sharp(bytes,{limitInputPixels:20_000_000}).flatten({background:"#ebecec"}).removeAlpha().png().toBuffer();
    const savedPath = path.join("exports/candidates/pro-20261113",artifactPath);
    const file = path.join(process.cwd(),savedPath);
    await mkdir(path.dirname(file),{recursive:true}); await writeFile(file,output);
    return NextResponse.json({dataUrl:"data:image/png;base64,"+output.toString("base64"),savedPath});
  } catch { return NextResponse.json({error:"Candidate export failed"},{status:400}); }
}
