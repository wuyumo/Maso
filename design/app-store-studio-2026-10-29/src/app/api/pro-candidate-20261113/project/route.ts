import { promises as fs } from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";
import { projectCandidate } from "../../../../lib/shared-section-copy.mjs";
export const dynamic = "force-dynamic";
export async function GET() {
  try {
    const raw = await fs.readFile(path.join(process.cwd(), "candidates/pro-20261113/project.json"), "utf8");
    const projected = projectCandidate(JSON.parse(raw));
    return NextResponse.json({ ok: true, revision: projected.revision, state: projected.store, web: projected.web });
  } catch {
    return NextResponse.json({ ok: false, error: "Candidate project unavailable" }, { status: 500 });
  }
}
// Deliberately no POST: candidate surface cannot autosave to canonical project.
