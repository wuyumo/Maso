// Files that actually exist under public/screenshots after the 2026-11-09
// snapshot. A locale/scene not listed here must render as a gap, not as English.
export const PRESENT_CAPTURES: readonly string[] = [
  "localized/duo/en/diet.png",
  "localized/duo/en/insights.png",
  "localized/duo/en/sleep.png",
  "localized/duo/en/today.png",
  "localized/duo/zh/diet.png",
  "localized/duo/zh/insights.png",
  "localized/duo/zh/sleep.png",
  "localized/duo/zh/today.png",
  "localized/ipad/en/diet.png",
  "localized/ipad/en/insights.png",
  "localized/ipad/en/sleep.png",
  "localized/ipad/en/today.png",
  "localized/ipad/zh/diet.png",
  "localized/ipad/zh/insights.png",
  "localized/ipad/zh/sleep.png",
  "localized/ipad/zh/today.png",
  "localized/iphone/en/diet.png",
  "localized/iphone/en/insights.png",
  "localized/iphone/en/sleep.png",
  "localized/iphone/en/today.png",
  "localized/iphone/zh/diet.png",
  "localized/iphone/zh/insights.png",
  "localized/iphone/zh/sleep.png",
  "localized/iphone/zh/today.png",
  "localized/watch/en/rest-160.png",
  "localized/watch/zh/rest-160.png",
];

const PRESENT = new Set(PRESENT_CAPTURES);

export function captureReady(src: string | undefined): boolean {
  if (!src) return false;
  const path = src.split("?")[0].replace(/^\/screenshots\//, "");
  return PRESENT.has(path);
}
