import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { LOCALES, SECTION_ORDER, canonicalRows, copyRevision, payloadDocument, payloadSHA, projectCandidate, webDocument } from "./shared-section-copy.mjs";

const file = new URL("../../candidates/pro-20261113/project.json", import.meta.url);
const originalRows = "f33f436ef6aca6c390458f6be87342b1f8514c8337e6f57739f802983ce14570";

function load() {
  return JSON.parse(readFileSync(file, "utf8"));
}

test("studio authoring is five shared records and every device family matches them", () => {
  const project = load();
  assert.deepEqual(project.sharedSections.map((section) => section.id), SECTION_ORDER);
  assert.equal(canonicalRows(project.sharedSections).length, 60);
  assert.equal(canonicalRows(project.sharedSections).flatMap((row) => row.slice(2)).length, 180);
  assert.equal(copyRevision(project.sharedSections), originalRows);
  const projected = projectCandidate(project);
  assert.equal(projected.revision, projected.web.revision);
  assert.equal(projected.store.slidesByDevice.iphone.length, 5);
  assert.deepEqual(Object.keys(projected.store.slidesByDevice), ["iphone", "android", "ipad", "android-7", "android-10", "feature-graphic"]);
  for (const slides of Object.values(projected.store.slidesByDevice)) {
    for (const slide of slides) {
      const section = project.sharedSections.find((item) => item.id === slide.id);
      assert.deepEqual(slide.label, section.label);
      assert.deepEqual(slide.headline, section.title);
      const description = slide.textElements.find((element) => element.id === "description");
      assert.deepEqual(description.text, section.subtitle);
    }
  }
  for (const [id, locale, label, title, subtitle] of canonicalRows(project.sharedSections)) {
    for (const value of [label, title, subtitle]) {
      assert.equal(value.endsWith("."), false, `${id} ${locale}`);
      assert.equal(value.endsWith("。"), false, `${id} ${locale}`);
    }
  }
  assert.equal(LOCALES.length, 12);
});

test("a shared short title changes the store and website projections together", () => {
  const project = load();
  project.sharedSections = project.sharedSections.map((section) => (
    section.id === "plan" ? { ...section, title: { ...section.title, en: "Fixture title" } } : section
  ));
  const projected = projectCandidate(project);
  assert.equal(projected.store.slidesByDevice.iphone.find((slide) => slide.id === "plan").headline.en, "Fixture title");
  for (const slides of Object.values(projected.store.slidesByDevice)) {
    const plan = slides.find((slide) => slide.id === "plan");
    if (plan) assert.equal(plan.headline.en, "Fixture title");
  }
  assert.equal(projected.web.sections.find((section) => section.id === "plan").title.en, "Fixture title");
  assert.notEqual(projected.revision, originalRows);
});

test("the committed web projection is the same revision as the five author records", () => {
  const project = load();
  const committed = JSON.parse(readFileSync(new URL("../../candidates/pro-20261113/web-projection.json", import.meta.url), "utf8"));
  assert.deepEqual(committed, webDocument(project));
  assert.equal(committed.revision, originalRows);
});

test("a website body does not change the store short copy", () => {
  const project = load();
  const before = copyRevision(project.sharedSections);
  project.sharedSections = project.sharedSections.map((section) => (
    section.id === "plan" ? { ...section, websiteBody: { en: "Long website paragraph." } } : section
  ));
  const projected = projectCandidate(project);
  assert.equal(copyRevision(project.sharedSections), before);
  assert.equal(projected.store.slidesByDevice.iphone[0].headline.en, "One photo in,\na week planned out");
  assert.equal(projected.web.sections[0].websiteBody.en, "Long website paragraph.");
  assert.equal(projected.web.sections[0].copyApproval, "approved");
  assert.equal(projected.web.sections.find((section) => section.id === "training").copyApproval, "unapproved");
  assert.equal(projected.web.sections.find((section) => section.id === "devices").copyApproval, "unapproved");
  assert.equal(projected.web.sections.find((section) => section.id === "devices").mediaCapture, "no-capture");
});

test("the store and website projections read one website body without changing short copy", () => {
  const project = load();
  const projected = projectCandidate(project);
  assert.equal(projected.revision, originalRows);
  assert.equal(copyRevision(project.sharedSections), originalRows);
  assert.deepEqual(projected.web, webDocument(project));
  for (const id of SECTION_ORDER) {
    const section = project.sharedSections.find((item) => item.id === id);
    assert.deepEqual(projected.web.sections.find((item) => item.id === id).websiteBody, section.websiteBody);
  }
  const plan = projected.store.slidesByDevice.iphone.find((slide) => slide.id === "plan");
  assert.equal(JSON.stringify(plan.headline), JSON.stringify(project.sharedSections[0].title));
  assert.equal(JSON.stringify(plan).includes("Free AI tasks"), false);
  for (const [family, slides] of Object.entries(projected.store.slidesByDevice)) {
    if (family !== "iphone") assert.deepEqual(slides, []);
  }
  assert.equal(projected.web.sections.find((section) => section.id === "training").copyApproval, "unapproved");
  assert.equal(projected.web.sections.find((section) => section.id === "training").mediaCapture, "no-capture");
  assert.equal(projected.web.sections.find((section) => section.id === "training").websiteBody.publication, "withheld");
  assert.equal(projected.web.sections.find((section) => section.id === "devices").websiteBody.publication, "withheld");
  const before = payloadSHA(project);
  project.sharedSections[0].websiteBody = { ...project.sharedSections[0].websiteBody, publication: "fixture" };
  assert.equal(copyRevision(project.sharedSections), originalRows);
  assert.notEqual(payloadSHA(project), before);
  const payload = JSON.parse(readFileSync(new URL("../../candidates/pro-20261113/payload.json", import.meta.url), "utf8"));
  const fresh = load();
  assert.equal(payload.payloadSHA, payloadSHA(fresh));
  assert.deepEqual(payload.document, payloadDocument(fresh));
  assert.equal(payload.shortCopyRevision, originalRows);
  assert.equal(payload.document.sections.find((section) => section.id === "training").mediaRefs[0].screenshot.includes("player-heart-warning"), true);
});

test("website demo captions stay bound to the four file hashes", () => {
  const project = load();
  const bodies = JSON.stringify(project.sharedSections.map((section) => section.websiteBody));
  assert.equal(createHash("sha256").update(bodies).digest("hex"), "cab1c9c77f86e9de60139309ce59b821620a16373a8e87ae026097a979fee486");
  const projected = projectCandidate(project);
  const bySection = Object.fromEntries(projected.web.sections.map((section) => [section.id, section]));
  assert.deepEqual(bySection.recovery.mediaAnnotations, project.sharedSections.find((section) => section.id === "recovery").mediaAnnotations);
  assert.deepEqual(bySection.training.mediaAnnotations, project.sharedSections.find((section) => section.id === "training").mediaAnnotations);
  assert.deepEqual(bySection.plan.mediaAnnotations, []);
  assert.equal(bySection.training.copyApproval, "unapproved");
  assert.equal(bySection.training.mediaCapture, "no-capture");
  assert.equal(bySection.devices.copyApproval, "unapproved");
  const recoveryBody = JSON.stringify(bySection.recovery.websiteBody);
  assert.equal(recoveryBody.includes("49"), false);
  for (const note of bySection.recovery.mediaAnnotations) {
    assert.equal(note.websiteDemoOnly, true);
    assert.equal(note.release, false);
    assert.equal(note.caption.includes("49"), true);
  }
  const trainingBody = bySection.training.websiteBody.candidate.en.body;
  assert.equal(trainingBody.includes("128"), false);
  assert.match(trainingBody, /No heart-rate sample/);
  const enWatch = bySection.training.mediaAnnotations.find((note) => note.locale === "en");
  const zhWatch = bySection.training.mediaAnnotations.find((note) => note.locale === "zh");
  assert.equal(enWatch.pairsWithBody, false);
  assert.equal(enWatch.sha256, "9c0ebb80249563d9d805184fd031b2c0f95ab648dc5b5b0e6a016f7d4bacd73c");
  assert.equal(enWatch.caption.includes("128"), true);
  assert.equal(zhWatch.pairsWithBody, true);
  assert.equal(zhWatch.sha256, "c3da92be94dc89c25b728875650ed3fdc7ea4422128d9442c523c81302e13f1e");
  assert.equal(zhWatch.caption.includes("128"), false);
  const root = new URL("../../candidates/pro-20261113/", import.meta.url);
  for (const note of [...bySection.recovery.mediaAnnotations, ...bySection.training.mediaAnnotations]) {
    const bytes = readFileSync(new URL(note.file, root));
    assert.equal(createHash("sha256").update(bytes).digest("hex"), note.sha256);
    assert.equal(note.websiteDemoOnly, true);
    assert.equal(note.release, false);
  }
  const payload = payloadDocument(project);
  assert.deepEqual(payload.sections.find((section) => section.id === "training").mediaAnnotations, bySection.training.mediaAnnotations);
});
