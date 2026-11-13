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
  const text = document.body.innerText;
  const create = document.querySelector('#create button');
  return document.getElementById('dashboard').hidden === false && create.disabled && text.includes('Local demo') && text.includes('LOCALONLY') && text.includes('Not a scannable code') && text.includes('not Apple-reconciled revenue') && text.includes('No reconciled statements yet') && !text.includes('$0.00');
})()`;
const emptyDash = `(() => document.body.innerText.includes('No codes on this account.') && document.body.innerText.includes('No reconciled statements yet'))()`;
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

chrome.kill();
await new Promise(resolve => server.close(resolve));
console.log('captured');
