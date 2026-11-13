import { spawn } from 'node:child_process';
import fs from 'node:fs';
import { createPreviewServer } from './preview-server.mjs';

const out = process.env.SHOT_DIR || '/tmp/partner-shots';
fs.mkdirSync(out, { recursive: true });

const server = createPreviewServer();
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
const base = `http://127.0.0.1:${port}`;

const chrome = spawn('google-chrome', [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage',
  '--remote-debugging-port=0', '--user-data-dir=/tmp/partner-chrome',
  '--window-size=1280,900'
], { stdio: ['ignore', 'pipe', 'pipe'] });
let dbg = '';
const url = await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('chrome did not open a debugging port')), 15000);
  const onData = buf => {
    dbg += buf.toString();
    const match = dbg.match(/DevTools listening on (ws:\/\/\S+)/);
    if (match) { clearTimeout(timer); resolve(match[1]); }
  };
  chrome.stderr.on('data', onData);
  chrome.stdout.on('data', onData);
});
const version = await (await fetch(url.replace('ws://', 'http://').replace(/\/devtools\/browser\/.*/, '/json/version'))).json();
const browser = new WebSocket(version.webSocketDebuggerUrl);
let seq = 0;
const pending = new Map();
await new Promise(resolve => { browser.addEventListener('open', resolve, { once: true }); });
browser.addEventListener('message', event => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) pending.get(msg.id)(msg);
});
function cdp(method, params = {}, sessionId) {
  const id = ++seq;
  const payload = { id, method, params };
  if (sessionId) payload.sessionId = sessionId;
  browser.send(JSON.stringify(payload));
  return new Promise((resolve, reject) => {
    pending.set(id, msg => {
      pending.delete(id);
      if (msg.error) reject(new Error(JSON.stringify(msg.error)));
      else resolve(msg.result);
    });
  });
}
const { targetId } = await cdp('Target.createTarget', { url: 'about:blank' });
const { sessionId } = await cdp('Target.attachToTarget', { targetId, flatten: true });
await cdp('Page.enable', {}, sessionId);
await cdp('Runtime.enable', {}, sessionId);
await cdp('Emulation.setEmulatedMedia', { media: 'screen', features: [{ name: 'prefers-color-scheme', value: 'dark' }] }, sessionId);

async function shoot(name, path, width, height, checks) {
  await cdp('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 500 }, sessionId);
  await cdp('Page.navigate', { url: base + path }, sessionId);
  await new Promise(resolve => setTimeout(resolve, 800));
  const result = await cdp('Runtime.evaluate', { expression: checks, returnByValue: true }, sessionId);
  if (result.exceptionDetails) throw new Error(name + ' ' + JSON.stringify(result.exceptionDetails));
  const value = result.result.value;
  if (value !== true) throw new Error(name + ' check failed: ' + JSON.stringify(value));
  const { data } = await cdp('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true }, sessionId);
  const file = `${out}/${name}.png`;
  fs.writeFileSync(file, Buffer.from(data, 'base64'));
  console.log(file);
}

const closed = `(() => {
  const btn = document.querySelector('#login button');
  const text = document.getElementById('policy').innerText;
  return btn.disabled === true && text.includes('Partner enrollment is not open yet.') && text.includes('not an approved commercial term') && text.includes('download is free') && getComputedStyle(document.body).backgroundColor === 'rgb(18, 18, 18)';
})()`;
const verify = `(() => {
  const form = document.getElementById('verify');
  const otp = form.querySelector('input');
  otp.value = '12';
  const invalid = !form.checkValidity();
  otp.value = '123456';
  const valid = form.checkValidity();
  otp.value = '';
  return form.hidden === false && invalid && valid && document.getElementById('demo-banner').hidden === false;
})()`;
const dash = `(() => {
  const overview = document.getElementById('panel-overview');
  const text = document.body.innerText;
  return document.getElementById('dashboard').hidden === false && overview.hidden === false && document.getElementById('panel-codes').hidden === true && document.getElementById('tabs').querySelectorAll('[role=tab]').length === 4 && text.includes('Local demo') && text.includes('—') && !text.includes('$0.00') && getComputedStyle(document.getElementById('tab-overview')).color === 'rgb(30, 215, 96)';
})()`;
const emptyDash = `(() => document.getElementById('codes').textContent.includes('No codes on this account.') && document.getElementById('settlements').textContent.includes('No reconciled statements yet') && document.getElementById('panel-overview').hidden === false)()`;
const unauthorized = `(() => document.getElementById('message').textContent === 'Sign-in required.' && document.getElementById('landing').hidden === false)()`;
const referral = `(() => {
  const text = document.body.innerText;
  return document.getElementById('public-code').textContent === 'LOCALONLY' && text.includes('not an approved commercial term') && text.includes('download is free') && text.includes('Local preview link only');
})()`;
const error = `(() => document.getElementById('message').className === 'error' && document.getElementById('message').textContent.includes('could not be completed'))()`;
const zh = `(() => document.documentElement.lang === 'zh-Hans' && document.body.innerText.includes('合作计划尚未开放注册'))()`;

await shoot('flow-desktop-landing', '/?lang=en', 1280, 1100, closed);
await shoot('flow-mobile-landing', '/?lang=en', 390, 1000, closed);
await shoot('flow-desktop-verify', '/?lang=en&preview=verify', 1280, 1000, verify);
await shoot('flow-mobile-verify', '/?lang=en&preview=verify', 390, 1000, verify);
await shoot('flow-desktop-dashboard', '/?lang=en&preview=dashboard', 1280, 1500, dash);
await shoot('flow-mobile-dashboard', '/?lang=en&preview=dashboard', 390, 1700, dash);
await shoot('flow-desktop-empty', '/?lang=en&preview=empty', 1280, 1100, emptyDash);
await shoot('flow-mobile-unauthorized', '/?lang=en&preview=unauthorized', 390, 844, unauthorized);
await shoot('flow-desktop-referral', '/r/LOCALONLY?lang=en', 1280, 1000, referral);
await shoot('flow-mobile-referral', '/r/LOCALONLY?lang=en', 390, 900, referral);
await shoot('flow-desktop-error', '/?lang=en&preview=error', 1280, 1100, error);
await shoot('flow-mobile-zh-landing', '/?lang=zh-Hans', 390, 1100, zh);

async function page(expression) {
  const result = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, sessionId);
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  if (result.result.value !== true) throw new Error(String(result.result.value));
}
async function snap(name) {
  const { data } = await cdp('Page.captureScreenshot', { format: 'png' }, sessionId);
  fs.writeFileSync(`${out}/${name}.png`, Buffer.from(data, 'base64'));
  console.log(`${out}/${name}.png`);
}
await cdp('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true }, sessionId);
await cdp('Page.navigate', { url: base + '/?lang=en&preview=dashboard' }, sessionId);
await new Promise(resolve => setTimeout(resolve, 800));
await page(`(async () => {
  const posts = [];
  const orig = window.fetch;
  window.fetch = (url, opts) => { if (String((opts && opts.method) || 'GET').toUpperCase() === 'POST') posts.push(String(url)); return orig(url, opts); };
  document.getElementById('metrics').textContent = 'SECRET-ACCOUNT';
  document.getElementById('refresh').click();
  await new Promise(resolve => setTimeout(resolve, 200));
  if (document.getElementById('metrics').textContent.includes('SECRET-ACCOUNT')) return 'old metrics remained';
  if (posts.length) return 'refresh wrote ' + posts.join(',');
  for (const id of ['codes', 'statements', 'account', 'overview']) document.getElementById('tab-' + id).click();
  if (posts.length) return 'tab click wrote ' + posts.join(',');
  const visible = ['overview', 'codes', 'statements', 'account'].filter(id => !document.getElementById('panel-' + id).hidden);
  if (visible.join() !== 'overview') return 'visible ' + visible.join();
  document.getElementById('tab-overview').focus();
  document.getElementById('tab-overview').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
  if (document.activeElement.id !== 'tab-codes' || location.hash !== '#codes') return 'keyboard ' + document.activeElement.id + location.hash;
  if (document.getElementById('tab-codes').getAttribute('aria-current') !== 'page') return 'missing aria-current';
  history.back();
  await new Promise(resolve => setTimeout(resolve, 250));
  if (location.hash !== '#overview' || document.getElementById('panel-codes').hidden === false) return 'back ' + location.hash;
  window.scrollTo(0, 360);
  document.getElementById('tab-codes').click();
  await new Promise(resolve => setTimeout(resolve, 80));
  if (window.scrollY > 4) return 'codes scroll ' + window.scrollY;
  const selected = getComputedStyle(document.getElementById('tab-codes'));
  if (selected.color !== 'rgb(30, 215, 96)') return 'selected color ' + selected.color;
  if (selected.outlineStyle !== 'none' && Number.parseFloat(selected.outlineWidth) > 0) return 'selected outline ' + selected.outlineStyle;
  const title = document.querySelector('#panel-codes h2').getBoundingClientRect();
  const header = document.querySelector('header').getBoundingClientRect();
  const nav = document.getElementById('tabs').getBoundingClientRect();
  if (title.top < header.bottom - 1) return 'title ' + title.top + ' header ' + header.bottom;
  if (nav.bottom < window.innerHeight - 2) return 'nav not at bottom ' + nav.bottom;
  document.getElementById('tab-overview').click();
  await new Promise(resolve => setTimeout(resolve, 80));
  if (Math.abs(window.scrollY - 360) > 40) return 'restore ' + window.scrollY;
  return true;
})()`);
for (const id of ['overview', 'codes', 'statements', 'account']) {
  await page(`(() => { document.getElementById('tab-${id}').click(); return location.hash === '#${id}' && document.getElementById('panel-${id}').hidden === false; })()`);
  await snap('tab-mobile-' + id);
}
await cdp('Page.reload', {}, sessionId);
await new Promise(resolve => setTimeout(resolve, 800));
await page(`(() => location.hash === '#account' && document.getElementById('panel-account').hidden === false && document.getElementById('panel-overview').hidden === true)()`);
await cdp('Emulation.setDeviceMetricsOverride', { width: 844, height: 390, deviceScaleFactor: 1, mobile: true }, sessionId);
await page(`(() => {
  document.documentElement.style.fontSize = '24px';
  const bar = document.getElementById('tabs');
  const button = bar.querySelector('button');
  const style = getComputedStyle(bar);
  const link = document.querySelector('#panel-account a');
  link.scrollIntoView({ block: 'center' });
  const nav = document.getElementById('tabs').getBoundingClientRect();
  const box = link.getBoundingClientRect();
  return button.getBoundingClientRect().height >= 44 && style.position === 'fixed' && document.documentElement.scrollWidth <= window.innerWidth + 1 && box.bottom <= nav.top + 1;
})()`);
await snap('tab-mobile-landscape');
await cdp('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true }, sessionId);
await cdp('Page.navigate', { url: base + '/?lang=zh-Hans&preview=dashboard#codes' }, sessionId);
await new Promise(resolve => setTimeout(resolve, 800));
await page(`(async () => {
  const labels = {overview: '概览', codes: '优惠码', statements: '结算', account: '账户'};
  for (const id of Object.keys(labels)) {
    document.getElementById('tab-' + id).click();
    await new Promise(resolve => setTimeout(resolve, 80));
    const panel = document.getElementById('panel-' + id);
    const heading = panel.querySelector('h1, h2');
    const bar = document.getElementById('tabs').getBoundingClientRect();
    if (panel.hidden || !heading || heading.getBoundingClientRect().top < 0) return id + ' title';
    if (bar.bottom < window.innerHeight - 2 || bar.top < window.innerHeight * 0.5) return id + ' bar ' + bar.top;
    if (!document.getElementById('tab-' + id).textContent.includes(labels[id])) return id + ' label';
  }
  return true;
})()`);
for (const id of ['overview', 'codes', 'statements', 'account']) {
  await page(`(() => { document.getElementById('tab-${id}').click(); return document.getElementById('panel-${id}').hidden === false; })()`);
  await new Promise(resolve => setTimeout(resolve, 60));
  await snap('zh-tab-mobile-' + id);
}
await cdp('Page.navigate', { url: base + '/?lang=ar&preview=dashboard#account' }, sessionId);
await new Promise(resolve => setTimeout(resolve, 800));
await page(`(() => {
  if (document.documentElement.dir !== 'rtl') return 'dir ' + document.documentElement.dir;
  document.getElementById('tab-account').focus();
  document.getElementById('tab-account').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }));
  return document.activeElement.id === 'tab-statements';
})()`);
await snap('tab-mobile-ar-account');
await cdp('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false }, sessionId);
await cdp('Page.navigate', { url: base + '/?lang=en&preview=dashboard#overview' }, sessionId);
await new Promise(resolve => setTimeout(resolve, 800));
await page(`(() => {
  const bar = document.getElementById('tabs');
  const box = bar.getBoundingClientRect();
  return getComputedStyle(bar).position === 'static' && box.width < 560 && box.width > 200 && document.getElementById('dashboard').hidden === false;
})()`);
await snap('tab-desktop-overview');
await page(`(() => { document.getElementById('tab-statements').click(); return location.hash === '#statements'; })()`);
await snap('tab-desktop-statements');
await cdp('Emulation.setDeviceMetricsOverride', { width: 320, height: 640, deviceScaleFactor: 1, mobile: true }, sessionId);
await cdp('Page.navigate', { url: base + '/?lang=de&preview=dashboard#overview' }, sessionId);
await new Promise(resolve => setTimeout(resolve, 800));
await page(`(() => document.getElementById('tab-overview').textContent.includes('Übersicht') && document.documentElement.scrollWidth <= window.innerWidth + 1)()`);
await snap('tab-mobile-de-320');
await page(`(() => { document.documentElement.style.fontSize = '32px'; return document.documentElement.scrollWidth <= window.innerWidth + 1 && document.getElementById('tab-overview').getBoundingClientRect().height >= 44; })()`);
await snap('tab-mobile-de-200');
await cdp('Page.navigate', { url: base + '/?lang=en&preview=error' }, sessionId);
await new Promise(resolve => setTimeout(resolve, 800));
await page(`(() => document.getElementById('message').className === 'error' && document.getElementById('dashboard').hidden === true)()`);
await snap('tab-mobile-error');
await cdp('Page.navigate', { url: base + '/?lang=en' }, sessionId);
await new Promise(resolve => setTimeout(resolve, 800));
await page(`(() => document.getElementById('dashboard').hidden === true && document.getElementById('landing').hidden === false)()`);

chrome.kill();
await new Promise(resolve => server.close(resolve));
console.log('captured');
