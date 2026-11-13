/** Candidate-only treatment of the existing chat; no new content or image pixels. */
export function candidatePlanUnit(canvas: { w: number; h: number }, phoneDeck: boolean, chat?: { width: number; height?: number }) {
  if (phoneDeck) return canvas.w / 1320;
  if (!chat) return 1;
  return Math.min((canvas.w - 180) / chat.width, (canvas.h - 960) / (chat.height || 2050));
}

// Match CoachChat's reference scale. Its existing measured fit includes the padding.
export const CANDIDATE_PLAN_CSS = `
#candidate-poster[data-candidate-plan-device="low-angle-split"] [data-chat-root="1"] {
  box-sizing: border-box;
  border: calc(18px * var(--candidate-plan-unit)) solid #343c46;
  border-radius: calc(64px * var(--candidate-plan-unit));
  background: #141a20;
  box-shadow: 0 calc(12px * var(--candidate-plan-unit)) 0 #252d36,
    0 calc(30px * var(--candidate-plan-unit)) calc(46px * var(--candidate-plan-unit)) rgba(0,0,0,.32),
    inset 0 0 0 calc(2px * var(--candidate-plan-unit)) rgba(255,255,255,.12);
  transform: perspective(calc(7000px * var(--candidate-plan-unit))) rotateX(4deg) skewX(-1deg) scale(.95);
  transform-origin: center center;
}
#candidate-poster[data-candidate-plan-device="low-angle-split"] [data-chat-root="1"] > div {
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
