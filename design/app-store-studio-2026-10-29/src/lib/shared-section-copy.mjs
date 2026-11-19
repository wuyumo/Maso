import { createHash } from "node:crypto";

export const SECTION_ORDER = ["plan", "recovery", "training", "diet", "devices"];
export const LOCALES = ["zh", "zh-Hant", "en", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"];

function stable(value) {
  return JSON.stringify(value);
}

export function canonicalRows(sections) {
  const byId = new Map(sections.map((section) => [section.id, section]));
  const rows = [];
  for (const id of SECTION_ORDER) {
    const section = byId.get(id);
    if (!section) throw new Error(`Missing shared section ${id}`);
    for (const locale of LOCALES) {
      rows.push([id, locale, section.label[locale], section.title[locale], section.subtitle[locale]]);
    }
  }
  return rows;
}

export function copyRevision(sections) {
  return createHash("sha256").update(stable(canonicalRows(sections)), "utf8").digest("hex");
}

export function storeSlides(project) {
  const byId = new Map(project.sharedSections.map((section) => [section.id, section]));
  const slidesByDevice = {};
  for (const [family, slides] of Object.entries(project.slidesByDevice)) {
    slidesByDevice[family] = slides.map((slide) => {
      const section = byId.get(slide.id);
      if (!section) return slide;
      const textElements = (slide.textElements || []).map((element) => (
        element.id === "description" ? { ...element, text: section.subtitle } : element
      ));
      return { ...slide, label: section.label, headline: section.title, textElements };
    });
  }
  return slidesByDevice;
}

export function webDocument(project) {
  return {
    contract: "masso-shared-sections-v1",
    authoring: "candidates/pro-20261113/project.json#sharedSections",
    revision: copyRevision(project.sharedSections),
    sections: SECTION_ORDER.map((id) => {
      const section = project.sharedSections.find((item) => item.id === id);
      return {
        id,
        copyApproval: section.copyApproval,
        mediaCapture: section.mediaCapture,
        label: section.label,
        title: section.title,
        subtitle: section.subtitle,
        websiteBody: section.websiteBody || {},
      };
    }),
  };
}

/// Status, long body, and screenshot refs. Short copy stays in copyRevision only.
export function payloadDocument(project) {
  const slidesByDevice = project.slidesByDevice || {};
  return {
    contract: "masso-shared-sections-v1",
    authoring: "candidates/pro-20261113/project.json#sharedSections",
    shortCopyRevision: copyRevision(project.sharedSections),
    sections: SECTION_ORDER.map((id) => {
      const section = project.sharedSections.find((item) => item.id === id);
      const mediaRefs = [];
      for (const [family, slides] of Object.entries(slidesByDevice)) {
        for (const slide of slides) {
          if (slide.id !== id) continue;
          mediaRefs.push({
            family,
            layout: slide.layout ?? null,
            screenshot: slide.screenshot ?? null,
          });
        }
      }
      return {
        id,
        copyApproval: section.copyApproval,
        mediaCapture: section.mediaCapture,
        websiteBody: section.websiteBody || {},
        mediaRefs,
      };
    }),
  };
}

export function payloadSHA(project) {
  return createHash("sha256").update(stable(payloadDocument(project)), "utf8").digest("hex");
}

export function projectCandidate(project) {
  if (!Array.isArray(project.sharedSections) || project.sharedSections.length !== 5) {
    throw new Error("Candidate is missing the five shared section records");
  }
  const store = { ...project, slidesByDevice: storeSlides(project) };
  const web = webDocument(project);
  return { revision: web.revision, store, web };
}
