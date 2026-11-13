import { promises as fs } from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";
export const dynamic = "force-dynamic";
export async function GET() {
  try { const raw = await fs.readFile(path.join(process.cwd(), "candidates/pro-20261113/project.json"), "utf8"); return NextResponse.json({ok:true,state:JSON.parse(raw)}); }
  catch { return NextResponse.json({ok:false,error:"Candidate project unavailable"},{status:500}); }
}
// Deliberately no POST: candidate surface cannot autosave to canonical project.
