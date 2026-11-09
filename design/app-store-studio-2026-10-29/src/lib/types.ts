export type Device =
  | "iphone"
  | "ipad"
  | "android"
  | "android-7"
  | "android-10"
  | "feature-graphic";

export type Orientation = "portrait" | "landscape";

export type Platform = "ios" | "android";

// Layouts the editor can render. Vary across slides for visual rhythm.
export type SlideLayout =
  | "hero"             // centered device, headline above
  | "device-bottom"    // headline top, device bottom-center
  | "device-top"       // device top, headline bottom (contrast)
  | "two-devices"      // back + front phones, headline above
  | "no-device"        // big headline + decorative blob, no device
  | "split-landscape"  // landscape tablets only: caption left + device right
  | "feature-graphic"; // 1024×500 banner with icon + name + tagline

// Per-element rect in canvas pixel space. Optional rotation in degrees and zIndex.
export type ElementTransform = {
  x: number;
  y: number;
  width: number;
  height: number;
  rotation?: number;
  zIndex?: number;
};

export type BuiltInElementId = "caption" | "device" | "deviceSecondary";
export type TextElementId = `text:${string}`;
export type ElementId = BuiltInElementId | TextElementId;

export type SelectedElement = {
  slideId: string;
  elementId: ElementId;
};

// Per-locale text keyed by locale code (e.g. "en", "de"). A locale is absent
// if the user hasn't typed anything for it; renderers fall back to en (see
// lib/locale.ts). The set of locales a project targets lives on
// ProjectState.locales.
export type LocalizedText = Partial<Record<string, string>>;

export type TextElement = {
  id: string;
  text: LocalizedText;
  transform: ElementTransform;
  fontSize?: number;
  fontWeight?: number;
  color?: string;
  align?: "left" | "center" | "right";
};

// Body-photo analysis block inside a coach bubble — mirrors the App's
// "Suggested focus" card (CoachScreen.bodyPhotoFocusMuscles): a front/back
// muscle diagram plus the muscles the plan will prioritise.
export type ChatReport = {
  /** Poster-level muscle groups (see lib/anatomy.ts MUSCLE_POLYGONS). */
  muscles: string[];
  /** Caption above the muscle names, e.g. "Suggested focus". */
  label: LocalizedText;
  /** Muscle names, one line each, accent coloured. */
  names: LocalizedText[];
  /** Optional one-line plan intent under the names. */
  note?: LocalizedText;
  /**
   * Skip the muscle diagram and lay the names out as accent chips instead.
   * Used by the "report + plan list" composition, where three day rows have to
   * fit under the analysis and the diagram would eat the space they need.
   */
  compact?: boolean;
};

/** One exercise chip on a routine card: muscle part + exercise name. */
export type ChatPlanPill = {
  part?: LocalizedText;
  name: LocalizedText;
};

// Routine card inside a coach bubble — mirrors the App's WorkoutCard as the
// Coach renders it (kicker row, title, count, muscle map, exercise pills).
export type ChatPlanCard = {
  kicker: LocalizedText;
  title: LocalizedText;
  /** "6 exercises · 21 sets" */
  meta: LocalizedText;
  /** Muscles highlighted in the card's diagram. */
  muscles: string[];
  pills: ChatPlanPill[];
  /** Optional trailing capsule, e.g. "Save to routines". */
  action?: LocalizedText;
};

// Chat-thread marketing composition: the demo area shows AI Coach conversation
// bubbles directly on the canvas instead of a device mockup.
export type ChatBubble = {
  role: "user" | "coach";
  text: LocalizedText;
  /** Smaller secondary line under the message, e.g. "3 days · 45 min each". */
  subtext?: LocalizedText;
  /** Path under /public, e.g. a photo the user attached. */
  photo?: string;
  /**
   * Several attached photos shown side by side (front + back body shots).
   * Takes precedence over `photo`.
   */
  photos?: string[];
  /** Small pill tags under the message (e.g. prescribed exercises). */
  chips?: LocalizedText[];
  /** Accent pill rendered under the message (e.g. "Start workout"). */
  cta?: LocalizedText;
  /** Body-photo analysis block (muscle diagram + focus muscles). */
  report?: ChatReport;
  /** Routine card with exercise chips. */
  plan?: ChatPlanCard;
  /**
   * Routine cards shown right under the message as a horizontal carousel.
   * The first card is fully visible and the rest run off the canvas edge, so
   * the crop itself says "there are more days to scroll".
   */
  plans?: ChatPlanCard[];
  /**
   * Render the routine cards as compact list rows (day badge, title, count)
   * instead of full WorkoutCards. Lets three days plus the analysis and the
   * save action share one poster without a horizontal carousel.
   */
  rowCards?: boolean;
  /** Put the accent action pill after the routine cards instead of above them. */
  ctaAfterCards?: boolean;
};

export type ChatThread = {
  // Placement in 1320-wide reference canvas px; scaled to the real canvas.
  x: number;
  y: number;
  width: number;
  /** Optional fixed height in reference px; footnotes sink to its bottom edge. */
  height?: number;
  bubbles: ChatBubble[];
  /** Dim pills below the thread that cover the remaining use cases. */
  footnotes?: LocalizedText[];
};

/** One device inside the "every supported device" portrait. */
export type LineupSlot = {
  id: "iphone" | "ipad" | "duo" | "watch";
  /** Placement in 1320-wide reference canvas px. Height follows the frame aspect. */
  x: number;
  y: number;
  width: number;
  rotation?: number;
  zIndex?: number;
};

/**
 * Device portrait: the demo area shows several supported devices at once
 * instead of one phone. Each slot pulls its own screen from the localized
 * capture set (see lib/marketing-localized.ts → lineupImage).
 */
export type DeviceLineup = {
  slots: LineupSlot[];
};

export type Slide = {
  id: string;
  layout: SlideLayout;
  label: LocalizedText;       // tiny uppercase caption above headline, per locale
  headline: LocalizedText;    // multi-line; newlines are intentional, per locale
  screenshot: string;         // path under /screenshots/ — may contain {locale}
  screenshotSecondary?: string; // for two-devices layout — may contain {locale}
  inverted?: boolean;         // dark background variant
  // Per-element overrides; when present, replaces layout default placement.
  transforms?: Partial<Record<BuiltInElementId, ElementTransform>>;
  textElements?: TextElement[];
  /** When present, the demo area renders this conversation instead of devices. */
  chat?: ChatThread;
  /** When present, the demo area renders several devices side by side. */
  lineup?: DeviceLineup;
};

export type ThemeId =
  | "clean-light"
  | "dark-bold"
  | "warm-editorial"
  | "ocean-fresh"
  | "bloom-roast";

export type Theme = {
  id: string;
  name: string;
  bg: string;          // primary background
  bgAlt: string;       // inverted background
  fg: string;          // text on bg
  fgAlt: string;       // text on bgAlt
  accent: string;
  muted: string;
};

export type ProjectState = {
  schemaVersion?: number;
  appName: string;
  themeId: string;
  // v1 projects render as isolated screens until the user opts into connected crops.
  connectedCanvas: boolean;
  // Locales this project targets. Drives the toolbar dropdown and bulk export.
  // Single-locale projects ship as ["en"] and hide the locale UI.
  locales: string[];
  locale: string;
  device: Device;
  orientation: Orientation;
  // Per-device slide decks so platform switching preserves work
  slidesByDevice: Record<Device, Slide[]>;
  appIcon?: string;    // path under /public (e.g. /app-icon.png)
};
