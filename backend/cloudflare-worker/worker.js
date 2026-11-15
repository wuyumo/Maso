// Cloudflare Worker 入口 — 逻辑全在 ../shared/handler.mjs (跟 Vercel 入口共用同一份).
// 改行为改那边, 不要在这里加分支, 否则两个 endpoint 会漂移.
import { handleRequest, sendFeedbackDigest } from "../shared/handler.mjs";
import { expireDemoJobs } from "../demo/service.mjs";

export default {
  async fetch(request, env) {
    return handleRequest(request, env);
  },
  async scheduled(_controller, env, ctx) {
    if (_controller.cron === "0 1 * * 1") ctx.waitUntil(sendFeedbackDigest(env));
    ctx.waitUntil(expireDemoJobs(env));
  },
};
