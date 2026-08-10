// Vercel 函数入口 — 逻辑全在 ../shared/handler.mjs (跟 Cloudflare 入口共用同一份).
//
// 为什么有这个: `*.workers.dev` 在中国大陆被 DNS 污染, 大陆用户连不上 Cloudflare 那个 endpoint.
// 自有域名 ai.replai.sh 指到这个项目 (replai.sh 的 DNS 也托管在 Vercel), 国内 DNS 不投毒.
//
// ⚠️ **不能用 Edge runtime** (2026-08-10 踩到): Edge Function 有硬性执行上限, 而生成整周
//    routine 的那次调用要跑 40-60s → 直接 504 `FUNCTION_INVOCATION_TIMEOUT`, app 侧表现成
//    "Couldn't reach the AI coach"。Cloudflare Worker 没这个限制, 所以只在切到 Vercel 作主
//    endpoint 之后才暴露。改用 Node runtime + maxDuration。
//
// Node runtime 是 (req, res) 签名, 而 handler.mjs 是 Web 标准 Request/Response (要跟 Worker 共用),
// 所以这里做一层薄适配。Node 18+ 全局有 Request/Response/fetch, 不用额外依赖。
//
// 部署: Vercel 项目 **Root Directory 设为 `backend`**, 环境变量要配:
//   ANTHROPIC_API_KEY / MASO_CLIENT_TOKEN / POLAR_TOKEN / POLAR_ORG_ID
// (跟 Cloudflare 那边 wrangler secret 的值完全一样.)
import { handleRequest } from "../shared/handler.mjs";

// ⚠️ 文件必须是 .mjs: backend/ 下没有 package.json, Node runtime 默认按 CommonJS 解析
//    `import` 会直接 FUNCTION_INVOCATION_FAILED (2026-08-10 踩过, 1.9s 就 500)。
//    runtime 不写 —— Node 是默认值, 写 "nodejs" 反而多一处会漂的字面量。
export const config = {
  maxDuration: 300,   // 秒. Pro 计划上限远高于此; 客户端自己的超时是 120s, 这里给足余量.
};

/** 把 Node 的 IncomingMessage 读成 Buffer (GET/HEAD 无 body). */
function readBody(req) {
  if (req.method === "GET" || req.method === "HEAD") return Promise.resolve(undefined);
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

export default async function handler(req, res) {
  try {
    const proto = req.headers["x-forwarded-proto"] || "https";
    const host = req.headers["x-forwarded-host"] || req.headers.host;
    const url = `${proto}://${host}${req.url}`;

    const request = new Request(url, {
      method: req.method,
      headers: req.headers,
      body: await readBody(req),
    });

    const out = await handleRequest(request, process.env);

    res.statusCode = out.status;
    out.headers.forEach((v, k) => res.setHeader(k, v));
    const buf = Buffer.from(await out.arrayBuffer());
    res.end(buf);
  } catch (e) {
    // 不要静默 500 —— app 侧现在会把这段原样显示给用户/开发者, 写清楚是哪一层挂的.
    res.statusCode = 500;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ error: { message: `vercel entry: ${e?.message || e}` } }));
  }
}
