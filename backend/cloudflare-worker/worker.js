// Maso Cloudflare Worker — 多路由
//
// 两条职责:
//   1. POST /v1/chat/completions  → DeepSeek AI 代理 (把 API key 从 app binary 里挪出来)
//   2. POST /pro/validate         → Polar license key 校验 (把 Polar org token 藏在这里)
//   3. GET  /pro/return           → Polar 结账成功后的回跳页: 查出 license key → 深链回 app
//
// 部署:
//   wrangler secret put DEEPSEEK_API_KEY
//   wrangler secret put MASO_CLIENT_TOKEN
//   wrangler secret put POLAR_TOKEN       ← Polar Organization Access Token
//   wrangler secret put POLAR_ORG_ID      ← Polar organization UUID
//   wrangler deploy
//
// Pro 变现说明 (2026-07): 账号身份签不了美国 Paid Apps 协议 → 不走 Apple IAP, 改走
//   Polar 网页结账 (merchant of record, 代收税). 仅美区显示购买 (Epic v. Apple 判决后
//   美区 app 内可放外链付费, 0 抽成). Polar 发 license key 当无账号的可携带凭证,
//   app 拿 key 走这个 Worker 校验 (org token 不进 binary).

const AI_PATH = "/v1/chat/completions";
const UPSTREAM = "https://api.deepseek.com/v1/chat/completions";
const CLIENT_TOKEN_HEADER = "X-Maso-Client-Token";

const POLAR_VALIDATE = "https://api.polar.sh/v1/license-keys/validate";
const POLAR_CHECKOUT = "https://api.polar.sh/v1/checkouts/";
const POLAR_LICENSE_KEYS = "https://api.polar.sh/v1/license-keys";
// 结账成功后深链回 app 的 scheme (Info.plist CFBundleURLSchemes 里已有 maso).
const APP_ACTIVATE_SCHEME = "maso://activate";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Maso-Client-Token",
  "Access-Control-Max-Age": "86400",
};

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "POST" && path === AI_PATH) {
      return handleAI(request, env);
    }
    if (request.method === "POST" && path === "/pro/validate") {
      return handleProValidate(request, env);
    }
    if (request.method === "GET" && path === "/pro/return") {
      return handleProReturn(url, env);
    }
    return new Response("Not Found", { status: 404 });
  },
};

// ─────────────────────────────────────────────────────────────
// 1) AI 代理 (原逻辑, passthrough DeepSeek)
// ─────────────────────────────────────────────────────────────
async function handleAI(request, env) {
  const clientToken = request.headers.get(CLIENT_TOKEN_HEADER);
  if (!clientToken || clientToken !== env.MASO_CLIENT_TOKEN) {
    return new Response("Unauthorized", { status: 401 });
  }

  let body;
  try {
    body = await request.json();
  } catch (e) {
    return new Response("Invalid JSON", { status: 400 });
  }

  const bodyStr = JSON.stringify(body);
  if (bodyStr.length > 50_000) {
    return new Response("Request too large", { status: 413 });
  }

  const allowedModels = ["deepseek-chat", "deepseek-coder"];
  if (!body.model || !allowedModels.includes(body.model)) {
    body.model = "deepseek-chat";
  }
  if (typeof body.max_tokens === "number") {
    body.max_tokens = Math.min(body.max_tokens, 4000);
  } else {
    body.max_tokens = 2000;
  }

  const upstreamRes = await fetch(UPSTREAM, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
    },
    body: JSON.stringify(body),
  });

  const responseBody = await upstreamRes.text();
  return new Response(responseBody, {
    status: upstreamRes.status,
    headers: {
      "Content-Type": upstreamRes.headers.get("Content-Type") || "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

// ─────────────────────────────────────────────────────────────
// 2) Polar license key 校验
//    收 {key} → 调 Polar validate → 归一化成 {active, status, expiresAt}.
//    active 判定: status=="granted" 且 (expires_at 为空 或 未过期).
//    org token / org id 只在 Worker 里, 不进 app binary.
// ─────────────────────────────────────────────────────────────
async function handleProValidate(request, env) {
  const clientToken = request.headers.get(CLIENT_TOKEN_HEADER);
  if (!clientToken || clientToken !== env.MASO_CLIENT_TOKEN) {
    return json({ active: false, error: "unauthorized" }, 401);
  }
  if (!env.POLAR_TOKEN || !env.POLAR_ORG_ID) {
    return json({ active: false, error: "server_not_configured" }, 500);
  }

  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json({ active: false, error: "bad_request" }, 400);
  }
  const key = (body.key || "").trim();
  if (!key) return json({ active: false, error: "missing_key" }, 400);

  const res = await fetch(POLAR_VALIDATE, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.POLAR_TOKEN}`,
    },
    body: JSON.stringify({ key, organization_id: env.POLAR_ORG_ID }),
  });

  // Polar 对无效 key 返回 4xx — 视作 not active, 不当服务器错误.
  if (!res.ok) {
    return json({ active: false, status: "invalid" });
  }

  const lk = await res.json().catch(() => ({}));
  const status = lk.status || "unknown";
  const expiresAt = lk.expires_at || null;
  const notExpired = !expiresAt || Date.parse(expiresAt) > Date.now();
  const active = status === "granted" && notExpired;

  return json({ active, status, expiresAt });
}

// ─────────────────────────────────────────────────────────────
// 3) Polar 结账成功回跳
//    Polar checkout 的 success_url 设成:
//      https://<worker>/pro/return?checkout_id={CHECKOUT_ID}
//    这里: checkout → customer_id → 该 customer 的 license key → 302 深链回 app.
//    任一步失败 → 渲染手动兜底页 (提示去邮箱拿激活码手动输入).
// ─────────────────────────────────────────────────────────────
async function handleProReturn(url, env) {
  const checkoutId = url.searchParams.get("checkout_id");
  if (!checkoutId || !env.POLAR_TOKEN || !env.POLAR_ORG_ID) {
    return manualFallbackPage();
  }

  try {
    const auth = { Authorization: `Bearer ${env.POLAR_TOKEN}` };

    // checkout → customer_id
    const coRes = await fetch(POLAR_CHECKOUT + encodeURIComponent(checkoutId), { headers: auth });
    if (!coRes.ok) return manualFallbackPage();
    const co = await coRes.json();
    const customerId = co.customer_id || co.customer?.id;
    if (!customerId) return manualFallbackPage();

    // 该 customer 在本 org 下的 license key
    const lkUrl = `${POLAR_LICENSE_KEYS}?organization_id=${encodeURIComponent(env.POLAR_ORG_ID)}&customer_id=${encodeURIComponent(customerId)}`;
    const lkRes = await fetch(lkUrl, { headers: auth });
    if (!lkRes.ok) return manualFallbackPage();
    const lkList = await lkRes.json();
    const items = lkList.items || [];
    const granted = items.find((k) => k.status === "granted") || items[0];
    const key = granted?.key;
    if (!key) return manualFallbackPage();

    // 深链回 app, 自动带 key.
    const deepLink = `${APP_ACTIVATE_SCHEME}?key=${encodeURIComponent(key)}`;
    return successPage(deepLink);
  } catch (e) {
    return manualFallbackPage();
  }
}

function successPage(deepLink) {
  const html = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Masso Pro</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#121212;color:#fff;
display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;text-align:center}
.box{padding:32px;max-width:360px}h1{font-size:22px}.btn{display:inline-block;margin-top:20px;
background:#1ED760;color:#000;font-weight:700;padding:14px 28px;border-radius:999px;text-decoration:none}
p{color:#b3b3b3;font-size:14px;line-height:1.5}</style>
<script>setTimeout(function(){location.href=${JSON.stringify(deepLink)}},600);</script></head>
<body><div class="box"><h1>You're Pro 🎉</h1>
<p>Thanks for supporting Masso. Tap below to unlock Pro in the app.</p>
<a class="btn" href="${deepLink}">Open Masso</a></div></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

function manualFallbackPage() {
  const html = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Masso Pro</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#121212;color:#fff;
display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;text-align:center}
.box{padding:32px;max-width:360px}h1{font-size:22px}p{color:#b3b3b3;font-size:14px;line-height:1.5}</style>
</head><body><div class="box"><h1>Thank you 🎉</h1>
<p>Your Masso Pro activation code was sent to your email. Open Masso, go to the Pro screen, tap "Enter code," and paste it in.</p>
</div></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
