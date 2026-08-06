// Maso AI / Pro 后端 — **唯一逻辑源**, 两个入口共用:
//   - Cloudflare Worker : cloudflare-worker/worker.js  (wrangler deploy)
//   - Vercel Edge       : api/index.js  → https://maso-two.vercel.app  (项目 maso, Root Directory = backend)
//
// ⚠️ 为什么要两处部署: `*.workers.dev` 在中国大陆被 DNS 污染 (114 DNS 返回假 IP 64.13.192.76,
//    8.8.8.8 返回真 Cloudflare IP 104.21.x) → 大陆用户手机上 AI 100% 连不上.
//    iOS 端 (AIWorkoutService) 主用一个 endpoint, 失败自动切另一个.
//
// 路由匹配用 endsWith 而不是 ===: Vercel 把所有路径 rewrite 到 /api, 实际 pathname 可能带前缀.
//
// 两条职责:
//   1. POST /v1/chat/completions  → Claude AI 代理 (对外仍是 OpenAI 形状) (把 API key 从 app binary 里挪出来)
//   2. POST /pro/validate         → Polar license key 校验 (把 Polar org token 藏在这里)
//   3. GET  /pro/return           → Polar 结账成功后的回跳页: 查出 license key → 深链回 app
//
// 部署:
//   wrangler secret put ANTHROPIC_API_KEY   ← Claude API key (AI 后端已从 DeepSeek 切到 Claude)
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
// AI 后端 = Anthropic Claude (2026-07 从 DeepSeek 切换).
// ⚠️ 路由和出入参形状**故意保持 OpenAI/DeepSeek 风格不变** — iOS 端 (AIWorkoutService) 发
// {model, messages, max_tokens, temperature, response_format} 收 {choices[0].message.content},
// 翻译全在这个 Worker 里做. 好处: 已上架的 app 版本 (2.0.4 及更早) 不用更新就直接吃到 Claude.
const UPSTREAM = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
// 健身教练场景 = 结构化 JSON 生成 + 需要靠谱的动作学常识 → Sonnet 5 (质量/成本平衡点).
const CLAUDE_MODEL = "claude-sonnet-5";
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

export async function handleRequest(request, env) {
  {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "POST" && path.endsWith(AI_PATH)) {
      return handleAI(request, env);
    }
    if (request.method === "POST" && path.endsWith("/pro/validate")) {
      return handleProValidate(request, env);
    }
    if (request.method === "GET" && path.endsWith("/pro/return")) {
      return handleProReturn(url, env);
    }
    return new Response("Not Found", { status: 404 });
  }
}

// ─────────────────────────────────────────────────────────────
// 1) AI 代理 — 收 OpenAI 形状, 转 Anthropic Claude, 再转回 OpenAI 形状
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

  // ── OpenAI 形状 → Anthropic Messages API ──
  // 三处不兼容, 逐个搬平:
  //   ① system 在 Anthropic 是**顶层参数**, 不是 messages 里的一条 → 抽出来合并
  //   ② messages 只允许 user/assistant 交替; content 必须是字符串或 block 数组
  //   ③ 没有 response_format:json_object → 靠 system 指令 + 回包剥 markdown 围栏兜底
  const msgs = Array.isArray(body.messages) ? body.messages : [];
  const systemParts = msgs.filter(m => m?.role === "system").map(m => String(m.content ?? ""));
  const convo = msgs
    .filter(m => m?.role === "user" || m?.role === "assistant")
    .map(m => ({ role: m.role, content: String(m.content ?? "") }));
  if (convo.length === 0) {
    return json({ error: { message: "no user message" } }, 400);
  }
  // iOS 请求带 response_format:json_object 时, 把"只输出 JSON"再钉一遍 (Anthropic 无此参数).
  if (body.response_format?.type === "json_object") {
    systemParts.push("Respond with a single raw JSON object only. No prose, no explanations, no markdown code fences.");
  }

  const maxTokens = typeof body.max_tokens === "number"
    ? Math.min(Math.max(body.max_tokens, 1), 4000)
    : 2000;

  const upstreamPayload = {
    model: CLAUDE_MODEL,          // 忽略客户端传的 model — 后端由 Worker 单方面决定
    max_tokens: maxTokens,        // Anthropic 必填
    messages: convo,
  };
  if (systemParts.length) upstreamPayload.system = systemParts.join("\n\n");
  // ⚠️ **不转发 temperature**. Claude 5 系列已弃用该参数 — 实测带上直接 400
  // ("`temperature` is deprecated for this model"). iOS 仍会发 0.6/0.3, 这里静默丢掉:
  // 生成的发散度改由 prompt 本身控制 (原意图: 0.6 出计划要点创造性 / 0.3 解读要忠于数据).

  const upstreamRes = await fetch(UPSTREAM, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify(upstreamPayload),
  });

  const raw = await upstreamRes.text();
  if (!upstreamRes.ok) {
    // 上游报错原样透传 (状态码 + body), 方便 app 侧 fallback + 排查.
    return new Response(raw, {
      status: upstreamRes.status,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }

  // ── Anthropic 回包 → OpenAI 形状 (iOS 只读 choices[0].message.content) ──
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    return json({ error: { message: "upstream returned non-JSON" } }, 502);
  }
  const text = (parsed.content || [])
    .filter(b => b?.type === "text")
    .map(b => b.text || "")
    .join("");

  return json({
    id: parsed.id,
    object: "chat.completion",
    model: parsed.model,
    choices: [{
      index: 0,
      message: { role: "assistant", content: cleanJSONText(text) },
      finish_reason: parsed.stop_reason === "max_tokens" ? "length" : "stop",
    }],
    usage: {
      prompt_tokens: parsed.usage?.input_tokens ?? 0,
      completion_tokens: parsed.usage?.output_tokens ?? 0,
      total_tokens: (parsed.usage?.input_tokens ?? 0) + (parsed.usage?.output_tokens ?? 0),
    },
  });
}

/// 剥掉 markdown 围栏 / 前后闲聊, 只留 JSON 主体 — iOS 侧直接 JSONSerialization 解析,
/// 一旦 Claude 包了 ```json 就会解析失败. 没找到 JSON 边界就原样返回 (交给 app 的 fallback).
function cleanJSONText(s) {
  let t = (s || "").trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```[a-zA-Z]*\s*/, "").replace(/```\s*$/, "").trim();
  }
  if (t.startsWith("{") || t.startsWith("[")) return t;
  // 兜底: 抓第一个 { 到最后一个 } (对象优先, 再试数组).
  const o = t.indexOf("{"), oe = t.lastIndexOf("}");
  if (o !== -1 && oe > o) return t.slice(o, oe + 1);
  const a = t.indexOf("["), ae = t.lastIndexOf("]");
  if (a !== -1 && ae > a) return t.slice(a, ae + 1);
  return t;
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
