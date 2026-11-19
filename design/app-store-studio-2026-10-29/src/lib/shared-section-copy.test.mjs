import assert from "node:assert/strict";
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
