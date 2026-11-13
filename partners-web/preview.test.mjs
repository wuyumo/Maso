import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { createPreviewServer, publicPolicySnapshot } from './preview-server.mjs';
import {
  routes, gaps, summaryFields, settlementFields, localDemo, emptyDemo, notices,
  validateEmail, validateName, validateOtp, validateCode, loginDisabled, createDisabled,
  countText, ratioText, settlementReady, knownStatus, shareLink, tabs, tabLabels, tabFromHash, tabLabel
} from './src/lib/contract.mjs';

const dir = path.dirname(fileURLToPath(import.meta.url));
const read = name => fs.readFileSync(path.join(dir, name), 'utf8');

test('public policy snapshot stays closed', () => {
  assert.equal(publicPolicySnapshot.registrationOpen, false);
  assert.equal(publicPolicySnapshot.campaignReady, false);
});

test('preview server never calls the production partner host', () => {
  const source = read('preview-server.mjs') + read('src/App.tsx');
  assert.equal(source.includes('workers.dev'), false);
  assert.equal(source.includes('ai.replai.sh'), false);
  assert.equal(source.includes('fetch('), true);
  assert.equal(read('preview-server.mjs').includes('fetch('), false);
});

test('uses official shadcn components and keeps the brand green', () => {
  const button = read('src/components/ui/button.tsx');
  assert.match(button, /@radix-ui\/react-slot/);
  assert.match(button, /class-variance-authority/);
  assert.match(read('src/components/ui/card.tsx'), /CardHeader/);
  assert.match(read('src/components/ui/table.tsx'), /TableHeader/);
  assert.match(read('src/index.css'), /#1ED760/);
  assert.match(read('THIRD_PARTY_NOTICES.md'), /MIT License/);
  const en = read('src/i18n/strings.mjs');
  assert.equal(en.includes('Partner enrollment is not open yet.'), true);
  assert.equal(en.includes('No lifetime commission.'), true);
  assert.equal(en.includes('permanently free'), false);
  assert.equal(en.includes('free forever'), false);
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
    assert.match(page, /id="root"/);
    const referral = await (await fetch(base + '/r/DEMOFIT')).text();
    assert.match(referral, /id="root"/);
    const qr = await (await fetch(base + '/qr/LOCALONLY.svg')).text();
    assert.match(qr, /NOT A SCANNABLE CODE/);
    assert.match(qr, /LOCAL MOCK/);
    assert.doesNotMatch(qr, /apps\.apple\.com/);
    assert.doesNotMatch(qr, /<path/);
    const pilot = await (await fetch(base + '/api/policy?pilot=1')).json();
    assert.equal(pilot.registrationOpen, false);
    assert.equal((await fetch(base + '/api/login')).status, 404);
    const invented = await fetch(base + '/api/payout', {method: 'POST', body: '{}'});
    assert.equal(invented.status, 404);
    const terms = await (await fetch(base + '/terms')).text();
    assert.match(terms, /There is no lifetime renewal commission/);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('commercial sentences stay unchanged and are still marked pending', () => {
  const en = read('src/i18n/strings.mjs');
  assert.equal(en.includes('No lifetime commission.'), true);
  assert.equal(en.includes('Partner enrollment is not open yet.'), true);
  assert.equal(en.includes('permanently free'), false);
  assert.match(notices.pendingFigures, /not an approved commercial term/);
  assert.match(read('src/i18n/notices.mjs'), /待确认/);
  assert.equal(read('src/App.tsx').includes('commissionBps'), false);
  assert.equal(createHash('sha256').update(en).digest('hex').length, 64);
});

test('step: instagram invite has no client field and the share link is only a relative path', () => {
  assert.equal(gaps.some(gap => gap.id === 'instagram-invite'), true);
  assert.equal(shareLink('http://127.0.0.1:4173', 'LOCALONLY'), 'http://127.0.0.1:4173/r/LOCALONLY');
  assert.equal(routes.some(route => route.path.includes('instagram')), false);
});

test('step: registration stays closed and input boundaries are rejected before a request', () => {
  assert.equal(loginDisabled({registrationOpen: false}, false), true);
  assert.equal(loginDisabled({registrationOpen: false}, true), false);
  assert.equal(loginDisabled({registrationOpen: true}, false), false);
  assert.equal(validateEmail(''), 'email');
  assert.equal(validateEmail('a@b'), 'email');
  assert.equal(validateEmail('person@example.com'), '');
  assert.equal(validateEmail('  person@example.com  '), '');
  assert.equal(validateEmail('a'.repeat(250) + '@b.co'), 'email');
  assert.equal(validateName(''), 'name');
  assert.equal(validateName('   '), 'name');
  assert.equal(validateName('A'.repeat(81)), 'name');
  assert.equal(validateName('Alex'), '');
  assert.equal(validateOtp('12345'), 'otp');
  assert.equal(validateOtp('1234567'), 'otp');
  assert.equal(validateOtp('12 456'), 'otp');
  assert.equal(validateOtp('123456'), '');
});

test('step: code boundaries and campaign gate do not invent a created code', () => {
  assert.equal(createDisabled({campaignReady: false}, false), true);
  assert.equal(createDisabled({campaignReady: false}, true), false);
  assert.equal(validateCode('abc'), 'code');
  assert.equal(validateCode('1ABCD'), 'code');
  assert.equal(validateCode('abcd'), '');
  assert.equal(validateCode('A'.repeat(21)), 'code');
  assert.equal(localDemo.codes.some(code => code.code === 'LOCALONLY'), true);
  assert.equal(localDemo.settlements.length, 0);
  assert.equal(emptyDemo.codes.length, 0);
});

test('step: private stats and statements use only returned fields and refuse mock money', () => {
  for (const field of summaryFields) assert.equal(localDemo.summary[field], null);
  for (const field of settlementFields) assert.equal(Object.hasOwn(localDemo, field), false);
  assert.equal(countText(null, 'en'), '—');
  assert.equal(countText(undefined, 'en'), '—');
  assert.equal(countText(0, 'en'), '0');
  assert.equal(ratioText(null, 3, 'en'), '—');
  assert.equal(ratioText(1, 0, 'en'), '—');
  assert.equal(settlementReady({created: '2026-11-01', currency: 'USD', status: 'eligible'}), false);
  assert.equal(settlementReady({created: '2026-11-01', commission_minor: 0, currency: 'USD', status: 'eligible'}), true);
  assert.equal(knownStatus('active'), 'active');
  assert.equal(knownStatus('paid'), '');
  assert.equal(localDemo.mock, true);
  assert.equal(gaps.some(gap => gap.id === 'apple-net'), true);
  assert.equal(gaps.some(gap => gap.id === 'manual-confirm'), true);
  assert.equal(gaps.some(gap => gap.id === 'apple-redeem'), true);
  assert.equal(gaps.some(gap => gap.id === 'refund-detail'), true);
  assert.equal(gaps.some(gap => gap.id === 'session'), true);
  const source = read('src/App.tsx');
  for (const path of ['/api/payout', '/api/instagram', '/api/redeem', '/api/confirm']) {
    assert.equal(source.includes(path), false, path);
  }
  assert.match(source, /settlementReady/);
  assert.match(notices.localDemo, /not Apple-reconciled revenue/);
  assert.match(notices.notScannable, /Not a scannable code/);
  assert.match(notices.settlementReadonly, /cannot confirm or send a payout/);
});

test('tabs split the private page and do not add a write route', () => {
  assert.deepEqual(tabs, ['overview', 'codes', 'statements', 'account']);
  assert.equal(tabFromHash('#codes'), 'codes');
  assert.equal(tabFromHash('#nope'), 'overview');
  assert.equal(tabFromHash(''), 'overview');
  for (const lang of ['en', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'de', 'es', 'fr', 'it', 'pt', 'ru', 'ar']) {
    for (const key of ['nav', 'overview', 'codes', 'statements', 'account']) {
      assert.equal(tabLabel(lang, key).length > 0, true, lang + key);
    }
  }
  const html = read('src/App.tsx');
  assert.match(html, /id="panel-overview"/);
  assert.match(html, /id="panel-codes"/);
  assert.match(html, /id="panel-statements"/);
  assert.match(html, /id="panel-account"/);
  assert.match(html, /lg:hidden/);
  const source = read('src/App.tsx');
  const showTab = source.slice(source.indexOf('function applyTab'), source.indexOf('async function onLogin'));
  assert.equal(showTab.includes('api('), false);
  assert.equal(showTab.includes('fetch('), false);
  assert.match(source, /clearSession/);
  assert.match(source, /safe-area-inset-bottom/);
  assert.match(source, /h-11/);
});
