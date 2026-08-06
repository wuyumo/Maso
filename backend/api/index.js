// Vercel Edge Function 入口 — 逻辑全在 ../shared/handler.mjs (跟 Cloudflare 入口共用同一份).
//
// 为什么有这个: `*.workers.dev` 在中国大陆被 DNS 污染, 大陆用户连不上 Cloudflare 那个 endpoint.
// Vercel 的 *.vercel.app 目前大陆可达 (Nuze 的 AI 就跑在 Vercel, 大陆用户能用).
//
// 部署: Vercel 项目 **Root Directory 设为 `backend`**, 环境变量要配:
//   ANTHROPIC_API_KEY / MASO_CLIENT_TOKEN / POLAR_TOKEN / POLAR_ORG_ID
// (跟 Cloudflare 那边 wrangler secret 的值完全一样.)
import { handleRequest } from "../shared/handler.mjs";

export const config = { runtime: "edge" };

export default async function handler(request) {
  // Worker 拿 env 参数, Vercel 走 process.env — 这里把形状抹平.
  return handleRequest(request, process.env);
}
