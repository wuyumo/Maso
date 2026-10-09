import { test } from "node:test";
import assert from "node:assert/strict";
import { handleRequest } from "./handler.mjs";

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

test("both unusable outputs fail visibly instead of returning truncated JSON", async t => {
  t.mock.method(globalThis, "fetch", async () => completion('{"routines":', "max_tokens"));
  assert.equal((await handleRequest(request(), env)).status, 502);
});
