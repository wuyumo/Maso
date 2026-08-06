// Cloudflare Worker 入口 — 逻辑全在 ../shared/handler.mjs (跟 Vercel 入口共用同一份).
// 改行为改那边, 不要在这里加分支, 否则两个 endpoint 会漂移.
import { handleRequest } from "../shared/handler.mjs";

export default {
  async fetch(request, env) {
    return handleRequest(request, env);
  },
};
