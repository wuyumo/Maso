// Maso DeepSeek API Proxy — Cloudflare Worker
//
// 把 DeepSeek API key 从 iOS app binary 移到这里 — 客户端再也不嵌 key, App Store 审核员
// 反编译扫不到. 同时这个 proxy 给你加一层抗滥用控制 (rate limit / origin check).
//
// 部署:
//   1. 装 wrangler:           npm i -g wrangler
//   2. 登录:                  wrangler login
//   3. 设 secret:             wrangler secret put DEEPSEEK_API_KEY
//   4. 部署:                  wrangler deploy
//
// iOS 端调用:
//   POST https://maso-ai.<your-subdomain>.workers.dev/v1/chat/completions
//   Headers:
//     Content-Type: application/json
//     X-Maso-Client-Token: <baked-in build token>  (轻量防滥用, 不是真 auth)
//   Body: 跟 DeepSeek API 一样的 JSON (model, messages, temperature, ...)
//
// 实现说明:
//   - DeepSeek API 兼容 OpenAI Chat Completions 格式, 直接 passthrough.
//   - 不存 prompt / response (request 生命周期外没数据). 隐私政策已声明.
//   - rate limit 用 Cloudflare 自带的 (50 req/min/IP) — 简单粗暴够用.
//     真上线想严格点可以加 Durable Objects token bucket.
//   - 只允许 POST /v1/chat/completions — 其他 path 直接 404, 防扫描.

const ALLOWED_PATH = "/v1/chat/completions";
const UPSTREAM = "https://api.deepseek.com/v1/chat/completions";

// iOS app 里 baked 的客户端 token. 不是真 auth — 任何人解 binary 都能拿到 — 但能挡住
// "随手测试 endpoint" 的 abuse. 真严格需要 StoreKit receipt verification.
// 必须跟 iOS app 端 Maso/Data/AIWorkoutService.swift 的 clientToken 保持一致.
const CLIENT_TOKEN_HEADER = "X-Maso-Client-Token";

export default {
  async fetch(request, env, ctx) {
    // 仅 POST + 正确 path
    if (request.method === "OPTIONS") {
      // CORS preflight (虽然 native app 不走 CORS, 留着方便 web debug)
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, X-Maso-Client-Token",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== ALLOWED_PATH) {
      return new Response("Not Found", { status: 404 });
    }

    // 校验 client token — 简单防滥用
    const clientToken = request.headers.get(CLIENT_TOKEN_HEADER);
    if (!clientToken || clientToken !== env.MASO_CLIENT_TOKEN) {
      return new Response("Unauthorized", { status: 401 });
    }

    // 读 body
    let body;
    try {
      body = await request.json();
    } catch (e) {
      return new Response("Invalid JSON", { status: 400 });
    }

    // 限制 body 大小 (防止有人 abuse 发巨型 prompt 烧我们 quota)
    const bodyStr = JSON.stringify(body);
    if (bodyStr.length > 50_000) {
      return new Response("Request too large", { status: 413 });
    }

    // 强制限制 model — 只允许 DeepSeek 系列, 不让客户端调 deepseek-r1 之类贵 model.
    // (你想开放更多 model 改这里就行)
    const allowedModels = ["deepseek-chat", "deepseek-coder"];
    if (!body.model || !allowedModels.includes(body.model)) {
      body.model = "deepseek-chat";  // 强制兜底
    }

    // 强制 max_tokens 上限 (再防滥用)
    if (typeof body.max_tokens === "number") {
      body.max_tokens = Math.min(body.max_tokens, 4000);
    } else {
      body.max_tokens = 2000;
    }

    // 转发给 DeepSeek
    const upstreamRes = await fetch(UPSTREAM, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify(body),
    });

    // 把 response 透传回 iOS — 包含 status, headers, body
    // (DeepSeek 返回 OpenAI 兼容 JSON, iOS 端不用改解析逻辑)
    const responseBody = await upstreamRes.text();
    return new Response(responseBody, {
      status: upstreamRes.status,
      headers: {
        "Content-Type": upstreamRes.headers.get("Content-Type") || "application/json",
        // CORS (debug 用)
        "Access-Control-Allow-Origin": "*",
      },
    });
  },
};
