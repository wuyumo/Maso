import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPreviewServer, publicPolicySnapshot } from './preview-server.mjs';

const dir = path.dirname(fileURLToPath(import.meta.url));
const read = name => fs.readFileSync(path.join(dir, name), 'utf8');

test('public policy snapshot stays closed', () => {
  assert.equal(publicPolicySnapshot.registrationOpen, false);
  assert.equal(publicPolicySnapshot.campaignReady, false);
});

test('preview server never calls the production partner host', () => {
  const source = read('preview-server.mjs') + read('public/app.js');
  assert.equal(source.includes('workers.dev'), false);
  assert.equal(source.includes('ai.replai.sh'), false);
  assert.equal(source.includes('fetch('), true);
  assert.equal(read('preview-server.mjs').includes('fetch('), false);
});

test('visual tokens match the app and existing copy is unchanged', () => {
  const css = read('public/style.css');
  for (const token of ['#1ED760', '#121212', '#191919', '#262626', '#B3B3B3', '#F3727F', '16px', '999px']) {
    assert.equal(css.includes(token), true, token);
  }
  const en = read('public/i18n.js');
  assert.equal(en.includes('Partner enrollment is not open yet.'), true);
  assert.equal(en.includes('No lifetime commission.'), true);
  assert.equal(en.includes('permanently free'), false);
  assert.equal(en.includes('now open'), false);
  assert.equal(en.includes('free forever'), false);
  const html = read('public/index.html');
  assert.match(html, /type="email"/);
  assert.match(html, /pattern="\[0-9\]\{6\}"/);
  assert.match(html, /pattern="\[A-Za-z\]\[A-Za-z0-9\]\{3,19\}"/);
  assert.match(html, /id="login"/);
  assert.match(html, /id="dashboard"/);
  assert.match(html, /id="referral"/);
});

test('local routes keep the closed contract and reject writes', async () => {
  const server = createPreviewServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const {port} = server.address();
  const base = `http://127.0.0.1:${port}`;
  try {
    const policy = await (await fetch(base + '/api/policy')).json();
    assert.deepEqual(policy, publicPolicySnapshot);
    const dashboard = await fetch(base + '/api/dashboard');
    assert.equal(dashboard.status, 401);
    assert.deepEqual(await dashboard.json(), {error: 'sign_in_required'});
    for (const [path, error] of [['/api/login', 'registration_not_ready'], ['/api/login/verify', 'registration_not_ready'], ['/api/codes', 'campaign_not_ready'], ['/api/codes/status', 'campaign_not_ready']]) {
      const res = await fetch(base + path, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'});
      assert.equal(res.status, 403, path);
      assert.deepEqual(await res.json(), {error});
    }
    const page = await (await fetch(base + '/')).text();
    assert.match(page, /id="landing"/);
    const referral = await (await fetch(base + '/r/DEMOFIT')).text();
    assert.match(referral, /id="referral"/);
    const qr = await (await fetch(base + '/qr/DEMOFIT.svg')).text();
    assert.match(qr, /LOCAL DEMO/);
    assert.doesNotMatch(qr, /apps\.apple\.com/);
    const terms = await (await fetch(base + '/terms')).text();
    assert.match(terms, /There is no lifetime renewal commission/);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
