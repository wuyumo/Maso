import { candidate51Override } from "./candidate51-assets";
import type { Slide } from './types';
// Plan A deck (2026-11-08, revised): plan → recovery → training(+watch) → diet(+sleep) → devices.
// The heart-rate card lives inside the training screen (player with a live bpm card),
// so the Apple Watch sits beside the phone on the training page, and the final page
// shows the whole supported device family (iPhone / iPad / iPhone Duo / Apple Watch).
// Each entry is [primary screen, secondary screen?] drawn from the localized
// native captures in public/screenshots/localized/<family>/<locale>/.
const scenes: Record<string, [string, string?]> = {
  plan: ['plans'],
  recovery: ['muscle-selected'],
  // Warning state: the phone shows the above-limit heart card and the watch the same
  // reading, so the page 3 copy and the pixels describe one moment.
  training: ['player-heart-warning', 'exercise-185'],
  // Nutrition leads: the diet screen is the front (larger) device, sleep sits behind it.
  diet: ['diet', 'sleep'],
  // The device portrait shows the same home screen on phone, tablet and Duo so the
  // page reads as one library travelling across screens (the lineup itself draws
  // each family from `lineupImage`; this entry keeps posters/fallbacks honest).
  devices: ['today'],
  watch: ['exercise', 'rest'],
  'watch-exercise': ['exercise-185'],
  'watch-rest': ['rest-160'],
};
// Scenes that only exist as an iPhone capture. Pad/Duo fall back to the closest
// captured screen of the same story beat until their own capture ships.
// Their training-heart-card still shows the retired 193 bpm card, so it is never used.
const familyFallback: Record<string, Partial<Record<'ipad' | 'duo', string>>> = {};
const WATCH_SCENES = new Set(['exercise', 'exercise-160', 'exercise-185', 'rest', 'rest-160', 'watch-exercise', 'watch-rest']);
export const LOCALIZED_LOCALES = ['zh','zh-Hant','en','ja','ko','es','fr','de','it','pt-BR','ru','ar'];
/** Asset cache-buster for the localized capture set. */
const ASSET_VERSION = 'release43-20261112';
// Screen shown on each device of the "every supported device" page. Each family
// gets the screen that reads best at its print size: the home screen on phone and
// tablet, the wider insights layout on the Duo, and the rest state on the watch
// (so the page doesn't repeat the training screen shown on page 3).
const lineupScenes: Record<'iphone' | 'ipad' | 'duo' | 'watch', string> = {
  iphone: 'today',
  ipad: 'insights',
  duo: 'diet',
  watch: 'rest-160',
};
export function marketingImage(slide: Slide, family: 'iphone'|'ipad'|'watch'|'duo', locale: string, secondary = false): string | undefined {
  const candidate = candidate51Override(slide, family, locale, secondary);
  if (candidate) return candidate;
  if (!LOCALIZED_LOCALES.includes(locale)) return undefined;
  if (family === 'watch' && !['watch','watch-exercise','watch-rest'].includes(slide.id)) return undefined;
  let scene = scenes[slide.id]?.[secondary ? 1 : 0];
  if (!scene) return undefined;
  // A watch scene is always served from the watch capture set, whichever deck shows it.
  const sourceFamily = slide.id === 'watch' || WATCH_SCENES.has(scene) ? 'watch' : family;
  if ((sourceFamily === 'ipad' || sourceFamily === 'duo') && familyFallback[slide.id]?.[sourceFamily]) {
    scene = familyFallback[slide.id]![sourceFamily]!;
  }
  return `/screenshots/localized/${sourceFamily}/${locale}/${scene}.png?v=${ASSET_VERSION}`;
}

/**
 * Screen for one device of the supported-device portrait. Kept separate from
 * `marketingImage` because that helper is keyed by slide story (one screen per
 * slide) while this page needs one screen per physical device.
 */
export function lineupImage(family: 'iphone' | 'ipad' | 'duo' | 'watch', locale: string): string | undefined {
  if (!LOCALIZED_LOCALES.includes(locale)) return undefined;
  const scene = lineupScenes[family];
  if (!scene) return undefined;
  return `/screenshots/localized/${family}/${locale}/${scene}.png?v=${ASSET_VERSION}`;
}
