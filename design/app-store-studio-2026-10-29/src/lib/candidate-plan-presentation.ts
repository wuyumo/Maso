/** Candidate-only treatment of the existing chat; no new content or image pixels. */
export function candidatePlanUnit(canvas: { w: number; h: number }, phoneDeck: boolean, chat?: { width: number; height?: number }) {
  if (phoneDeck) return canvas.w / 1320;
  if (!chat) return 1;
  return Math.min((canvas.w - 180) / chat.width, (canvas.h - 960) / (chat.height || 2050));
}

/** Put only the device's empty right margin into the 2% poster bleed. */
export function candidatePlanShiftX(canvas: { w: number; h: number }, phoneDeck: boolean, chat?: { x?: number; width: number; height?: number }) {
  if (!chat) return 0;
  const unit = candidatePlanUnit(canvas, phoneDeck, chat);
  const left = phoneDeck ? (chat.x ?? 96) * unit : (canvas.w - chat.width * unit) / 2;
  return Math.max(0, canvas.w * 1.02 - left - chat.width * unit * 1.1);
}

// Match CoachChat's reference scale. Its existing measured fit includes the padding.
export const CANDIDATE_PLAN_CSS = `
#candidate-poster[data-candidate-plan-device="low-angle-split"] [data-candidate-original-layout] [data-chat-root="1"] {
  display: none;
}
#candidate-poster[data-candidate-plan-device="low-angle-split"] [data-candidate-plan-mockup] {
  position: absolute;
  filter: drop-shadow(0 calc(20px * var(--candidate-plan-unit)) calc(30px * var(--candidate-plan-unit)) rgba(0,0,0,.4));
  transform: translateX(var(--candidate-plan-shift-x)) perspective(calc(4500px * var(--candidate-plan-unit))) rotateX(10deg) skewX(-3deg) scale(1.1);
  transform-origin: left bottom;
}
#candidate-poster[data-candidate-plan-device="low-angle-split"] [data-candidate-plan-mockup] [data-chat-root="1"] > div {
  box-sizing: border-box;
  padding: calc(36px * var(--candidate-plan-unit)) calc(28px * var(--candidate-plan-unit));
}
#candidate-poster[data-candidate-plan-device="low-angle-split"] [data-chat-photos="1"] {
  display: grid !important;
  grid-template-columns: minmax(0,1fr) minmax(0,1fr);
  direction: ltr;
  gap: 0 !important;
  width: calc(598px * var(--candidate-plan-unit));
  height: calc(355px * var(--candidate-plan-unit));
  position: relative;
  overflow: hidden;
  border: 1.5px solid rgba(255,255,255,.16);
  border-radius: calc(24px * var(--candidate-plan-unit));
}
#candidate-poster[data-candidate-plan-device="low-angle-split"] [data-chat-photos="1"] > img {
  width: 100% !important;
  height: 100% !important;
  min-width: 0;
  border: 0 !important;
  border-radius: 0 !important;
}
#candidate-poster[data-candidate-plan-device="low-angle-split"] [data-chat-photos="1"]::after {
  content: "";
  position: absolute;
  left: 50%;
  top: 0;
  bottom: 0;
  width: max(1px, calc(2px * var(--candidate-plan-unit)));
  transform: translateX(-50%);
  background: rgba(255,255,255,.45);
  pointer-events: none;
}
`;
