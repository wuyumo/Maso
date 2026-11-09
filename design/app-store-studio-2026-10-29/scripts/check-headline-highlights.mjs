#!/usr/bin/env node
// Verifies every accent phrase in src/components/editor/headline-highlight.tsx
// is an exact substring of the matching localized headline in
// app-store-screenshots.json. Exits non-zero on any drift.
//
// Default run only enforces the locales whose copy is approved
// (app-store-screenshots.json → approvedLocales). `--all` enforces every locale
// and is required before a twelve-locale export.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");

const src = fs.readFileSync(path.join(root, "src/components/editor/headline-highlight.tsx"), "utf8");
const start = src.indexOf("const highlights");
const open = src.indexOf("{", start);
const end = src.indexOf("\n};", open);
if (start < 0 || open < 0 || end < 0) throw new Error("cannot locate highlights map");
const highlights = new Function("return (" + src.slice(open, end + 2) + ")")();

const project = JSON.parse(fs.readFileSync(path.join(root, "app-store-screenshots.json"), "utf8"));
const slides = project.slidesByDevice.iphone;
const allLocales = project.locales;
const approved = project.approvedLocales || allLocales;
const enforceAll = process.argv.includes("--all");
const enforce = enforceAll ? allLocales : approved;
const pending = allLocales.filter((l) => !enforce.includes(l));

let fail = 0;
const rows = [];
for (const slide of slides) {
  const table = highlights[slide.id];
  if (!table) {
    console.log(`MISSING slide table: ${slide.id}`);
    fail++;
    continue;
  }
  for (const locale of enforce) {
    const headline = slide.headline?.[locale] || slide.headline?.en || "";
    const phrase = table[locale];
    if (!phrase) {
      console.log(`MISSING ${slide.id} ${locale}: no accent phrase`);
      fail++;
      continue;
    }
    const hit = headline.toLocaleLowerCase().indexOf(phrase.toLocaleLowerCase());
    if (hit < 0) {
      console.log(`MISMATCH ${slide.id} ${locale}: "${phrase}" not inside "${headline}"`);
      fail++;
    } else {
      rows.push(`  ${slide.id.padEnd(9)} ${locale.padEnd(8)} "${phrase}"`);
    }
  }
}

if (process.argv.includes("--list")) console.log(rows.join("\n"));
const scope = enforceAll ? `${slides.length} slides x ${allLocales.length} locales` : `${slides.length} slides x ${enforce.length} approved locales`;
console.log(fail === 0 ? `OK ${scope}` : `FAILED ${fail}`);
if (pending.length && !enforceAll) console.log(`pending (not enforced): ${pending.join(", ")} — run with --all before the 12-locale export`);
process.exit(fail === 0 ? 0 : 1);
