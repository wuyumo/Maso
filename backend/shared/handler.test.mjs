import { test } from "node:test";
import assert from "node:assert/strict";
import { handleRequest, sendFeedbackDigest, validateRoutineContract } from "./handler.mjs";

const env = { MASO_CLIENT_TOKEN: "test-client", ANTHROPIC_API_KEY: "test-key" };
const body = {
  messages: [{ role: "system", content: "Strict JSON" }, { role: "user", content: "Create a workout" }],
  response_format: { type: "json_object" }, max_tokens: 8192,
};
function request(token = env.MASO_CLIENT_TOKEN) {
  return new Request("https://example.test/v1/chat/completions", {
    method: "POST", headers: { "Content-Type": "application/json", "X-Maso-Client-Token": token },
    body: JSON.stringify(body),
  });
}
function completion(text, stop_reason = "end_turn", model = "claude-haiku-5-5") {
  return Response.json({ model, id: "test", content: [{ type: "text", text }], stop_reason,
    usage: { input_tokens: 100, output_tokens: 200 } });
}

test("cheap model returns the existing iOS response shape without calling Sonnet", async t => {
  const calls = [];
  t.mock.method(globalThis, "fetch", async (_, options) => {
    calls.push(JSON.parse(options.body)); return completion('{"routines":[]}');
  });
  const res = await handleRequest(request(), env);
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.deepEqual(JSON.parse(data.choices[0].message.content), { routines: [] });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].model, "claude-haiku-5-5");
  assert.equal(calls[0].max_tokens, 8192);
  assert.equal(calls[0].thinking.type, "disabled");
  assert.equal(data.usage.total_tokens, 300);
});

for (const failure of ["invalid-json", "truncated", "rate-limit", "network"]) {
  test(`${failure} retries Sonnet and returns a complete JSON response`, async t => {
    const calls = [];
    t.mock.method(globalThis, "fetch", async (_, options) => {
      calls.push(JSON.parse(options.body).model);
      if (calls.length === 1) {
        if (failure === "network") throw new Error("offline");
        if (failure === "rate-limit") return Response.json({ error: "rate limited" }, { status: 429 });
        return completion(failure === "truncated" ? '{"routines":[' : "unusable", failure === "truncated" ? "max_tokens" : "end_turn");
      }
      return completion('{"routines":[]}', "end_turn", "claude-sonnet-5");
    });
    const res = await handleRequest(request(), env);
    assert.equal(res.status, 200);
    assert.equal((await res.json()).model, "claude-sonnet-5");
    assert.deepEqual(calls, ["claude-haiku-5-5", "claude-sonnet-5"]);
  });
}

test("bad client credentials never reach a paid model", async t => {
  const mock = t.mock.method(globalThis, "fetch", async () => { throw new Error("must not call"); });
  assert.equal((await handleRequest(request("wrong"), env)).status, 401);
  assert.equal(mock.mock.callCount(), 0);
});

test("upstream auth errors are returned without retrying a second paid model", async t => {
  const mock = t.mock.method(globalThis, "fetch", async () => Response.json({ error: "invalid key" }, { status: 401 }));
  assert.equal((await handleRequest(request(), env)).status, 401);
  assert.equal(mock.mock.callCount(), 1);
});


function regionRequest(headers = {}) {
  return new Request("https://example.test/region", {
    method: "GET",
    headers: { "X-Maso-Client-Token": env.MASO_CLIENT_TOKEN, "x-forwarded-for": "203.0.113.8", ...headers },
  });
}

test("region returns Cloudflare country and never the client IP", async () => {
  const request = regionRequest({ "x-vercel-ip-country": "US" });
  Object.defineProperty(request, "cf", { value: { country: "CN" } });
  const res = await handleRequest(request, env);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("cache-control"), "private, no-store");
  const body = await res.text();
  assert.deepEqual(JSON.parse(body), { country: "CN" });
  assert.equal(body.includes("203.0.113.8"), false);
});

test("region ignores a spoofed header when Cloudflare already marked the country unknown", async () => {
  const request = regionRequest({ "x-vercel-ip-country": "US" });
  Object.defineProperty(request, "cf", { value: { country: "XX" } });
  const res = await handleRequest(request, env);
  assert.deepEqual(await res.json(), { country: null });
});

test("region uses the Vercel country header only when Cloudflare geo is absent", async () => {
  const res = await handleRequest(regionRequest({ "x-vercel-ip-country": "GB" }), env);
  assert.deepEqual(await res.json(), { country: "GB" });
});

test("region rejects a missing client token", async () => {
  const request = new Request("https://example.test/region");
  assert.equal((await handleRequest(request, env)).status, 401);
});

test("both unusable outputs fail visibly instead of returning truncated JSON", async t => {
  t.mock.method(globalThis, "fetch", async () => completion('{"routines":', "max_tokens"));
  assert.equal((await handleRequest(request(), env)).status, 502);
});

test("body photo blocks reach vision unchanged and return structured analysis", async t => {
  const image = { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "dGVzdA==" } };
  const result = { summary: "Photo is unclear", focusNote: "", canSuggestPlan: false };
  t.mock.method(globalThis, "fetch", async (_, options) => {
    const forwarded = JSON.parse(options.body);
    assert.deepEqual(forwarded.messages[0].content[0], image);
    return completion(JSON.stringify(result));
  });
  const req = new Request("https://example.test/v1/chat/completions", {
    method: "POST", headers: { "Content-Type": "application/json", "X-Maso-Client-Token": env.MASO_CLIENT_TOKEN },
    body: JSON.stringify({ messages: [{ role: "user", content: [image, { type: "text", text: "Review photo" }] }], response_format: { type: "json_object" } }),
  });
  const res = await handleRequest(req, env);
  assert.equal(res.status, 200);
  assert.deepEqual(JSON.parse((await res.json()).choices[0].message.content), result);
});

test("feedback intake validates and stores a minimal report idempotently", async () => {
  const inserted = [];
  const db = { prepare(sql) { return { bind(...values) { return { run: async () => inserted.push({ sql, values }) }; } }; } };
  const req = new Request("https://example.test/feedback", {
    method: "POST", headers: { "Content-Type": "application/json", "X-Maso-Client-Token": env.MASO_CLIENT_TOKEN },
    body: JSON.stringify({ id: "123e4567-e89b-12d3-a456-426614174000", body: "Button is stuck", appVersion: "1.2", osVersion: "iOS 18", language: "en" }),
  });
  const res = await handleRequest(req, { ...env, FEEDBACK_DB: db });
  assert.equal(res.status, 202);
  assert.equal(inserted.length, 1);
  assert.match(inserted[0].sql, /INSERT OR IGNORE/);
  assert.equal(inserted[0].values[2], "Button is stuck");
});

test("feedback intake rejects invalid credentials and oversized report text", async () => {
  const db = { prepare() { throw new Error("should not store"); } };
  const req = (token, text) => new Request("https://example.test/feedback", {
    method: "POST", headers: { "Content-Type": "application/json", "X-Maso-Client-Token": token },
    body: JSON.stringify({ id: "123e4567-e89b-12d3-a456-426614174000", body: text }),
  });
  assert.equal((await handleRequest(req("wrong", "bug"), { ...env, FEEDBACK_DB: db })).status, 401);
  assert.equal((await handleRequest(req(env.MASO_CLIENT_TOKEN, "x".repeat(4001)), { ...env, FEEDBACK_DB: db })).status, 400);
});

test("weekly digest retains reports unless email accepts the digest", async t => {
  const calls = [];
  const db = {
    prepare(sql) {
      return {
        bind(id) { return { run: async () => calls.push(["delete", id]) }; },
        all: async () => ({ results: [{ id: "report-1", submitted_at: "2026-10-01T10:00:00.000Z", body: "Broken control", app_version: "1", os_version: "iOS", language: "en" }] }),
      };
    },
    batch: async statements => Promise.all(statements.map(s => s.run())),
  };
  const email = t.mock.method(globalThis, "fetch", async (_url, options) => {
    assert.equal(options.headers.Origin, "https://ai.replai.sh");
    assert.equal(options.headers.Referer, "https://ai.replai.sh/");
    calls.push(["email", new URLSearchParams(options.body).get("feedbacks")]);
    return Response.json({ success: "true" }, { status: 200 });
  });
  const result = await sendFeedbackDigest({ FEEDBACK_DB: db });
  assert.deepEqual(result, { sent: true, count: 1 });
  assert.equal(email.mock.callCount(), 1);
  assert.ok(calls.some(c => c[0] === "delete" && c[1] === "report-1"));
});

test("failed weekly delivery leaves reports queued", async t => {
  let deleteCount = 0;
  const db = {
    prepare(sql) {
      return {
        bind() { return { run: async () => { deleteCount++; } }; },
        all: async () => ({ results: [{ id: "report-2", submitted_at: "2026-10-01", body: "Still broken", app_version: "1", os_version: "iOS", language: "en" }] }),
      };
    },
    batch: async statements => Promise.all(statements.map(s => s.run())),
  };
  t.mock.method(globalThis, "fetch", async () => Response.json({ success: "false" }, { status: 200 }));
  const result = await sendFeedbackDigest({ FEEDBACK_DB: db });
  assert.deepEqual(result, { sent: false, count: 1 });
  assert.equal(deleteCount, 0);
});

test("Qwen converts image blocks and falls back to Plus on invalid JSON", async t => {
  const calls = [];
  t.mock.method(globalThis, "fetch", async (url, options) => {
    const payload = JSON.parse(options.body); calls.push(payload);
    assert.equal(url, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions");
    assert.equal(payload.enable_thinking, false);
    assert.equal(options.headers.Authorization, "Bearer qwen-test");
    assert.equal(payload.messages[1].content[0].image_url.url, "data:image/png;base64,dGVzdA==");
    return Response.json({ model: payload.model, choices: [{ message: { content: calls.length === 1 ? 'bad' : '{"ok":true}' }, finish_reason: "stop" }], usage: { prompt_tokens: 12, completion_tokens: 4 } });
  });
  const req = new Request("https://example.test/v1/chat/completions", { method: "POST", headers: { "X-Maso-Client-Token": "test-client", "Content-Type": "application/json" }, body: JSON.stringify({ ...body, messages: [body.messages[0], { role: "user", content: [{ type: "image", source: { type: "base64", media_type: "image/png", data: "dGVzdA==" } }] }] }) });
  const res = await handleRequest(req, { ...env, DASHSCOPE_API_KEY: "qwen-test" });
  const result = await res.json();
  assert.equal(res.status, 200);
  assert.equal(result.model, "qwen3.5-plus");
  assert.equal(result.usage.total_tokens, 16);
  assert.deepEqual(calls.map(c => c.model), ["qwen3.7-flash", "qwen3.5-plus"]);
});

test("Qwen forwards zero temperature but ignores invalid values", async t => {
  const temperatures = [0, 0.3, -1, 3, "0"];
  const calls = [];
  t.mock.method(globalThis, "fetch", async (_url, options) => {
    const payload = JSON.parse(options.body); calls.push(payload);
    return Response.json({ model: payload.model, choices: [{ message: { content: '{"ok":true}' }, finish_reason: "stop" }], usage: { prompt_tokens: 1, completion_tokens: 1 } });
  });
  for (const temperature of temperatures) {
    const req = new Request("https://example.test/v1/chat/completions", {
      method: "POST", headers: { "Content-Type": "application/json", "X-Maso-Client-Token": env.MASO_CLIENT_TOKEN },
      body: JSON.stringify({ ...body, temperature }),
    });
    assert.equal((await handleRequest(req, { ...env, DASHSCOPE_API_KEY: "test" })).status, 200);
  }
  assert.deepEqual(calls.map(payload => payload.temperature), [0, 0.3, undefined, undefined, undefined]);
});

// The same filtered ID/group snapshot is sent by the native prompt/validator.
test("semantic routine failure invokes stronger model instead of returning a valid JSON failure", async t => {
  const contract = {version:1,count:1,steps:2,single:false,catalog:[{id:'bench',group:'press'},{id:'db_bench',group:'press'},{id:'row',group:'pull'}]};
  const invalid = {routines:[{name:'A',steps:[{exercise_id:'bench'},{exercise_id:'db_bench'}]}]};
  const valid = {routines:[{name:'A',steps:[{exercise_id:'bench'},{exercise_id:'row'}]}]};
  let calls=0;
  t.mock.method(globalThis,'fetch',async()=>completion(JSON.stringify(++calls===1?invalid:valid)));
  const res=await handleRequest(new Request('https://example.test/v1/chat/completions',{method:'POST',headers:{'Content-Type':'application/json','X-Maso-Client-Token':env.MASO_CLIENT_TOKEN},body:JSON.stringify({...body,routine_contract:contract})}),env);
  assert.equal(res.status,200);assert.equal(calls,2);
  assert.deepEqual(JSON.parse((await res.json()).choices[0].message.content),valid);
});

for (const bad of [
 {routines:[{name:'A',steps:[{exercise_id:'missing'},{exercise_id:'row'}]}]},
 {routines:[{name:'A',steps:[{exercise_id:'bench'},{exercise_id:'db_bench'}]}]},
 {routines:[]},
 {routines:[{name:'A',steps:[{exercise_id:'bench'}]}]},
]) test('catalog contract rejects '+JSON.stringify(bad),()=>{
 assert.equal(validateRoutineContract(bad,{version:1,count:1,steps:2,catalog:[{id:'bench',group:'press'},{id:'db_bench',group:'press'},{id:'row',group:'pull'}]}),false);
});

test('both invalid models fail closed without inventing a replacement',async t=>{
 let calls=0;t.mock.method(globalThis,'fetch',async()=>{calls++;return completion(JSON.stringify({routines:[{name:'A',steps:[{exercise_id:'invented'}]}]}));});
 const req=new Request('https://example.test/v1/chat/completions',{method:'POST',headers:{'Content-Type':'application/json','X-Maso-Client-Token':env.MASO_CLIENT_TOKEN},body:JSON.stringify({...body,routine_contract:{version:1,count:1,steps:1,catalog:[{id:'row',group:'pull'}]}})});
 const res=await handleRequest(req,env);assert.equal(res.status,502);assert.equal(calls,2);assert.equal((await res.json()).choices,undefined);
});
