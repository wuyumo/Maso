import { spawn } from 'node:child_process'
import fs from 'node:fs'
import { createPreviewServer } from './preview-server.mjs'

const out = process.env.SHOT_DIR || '/tmp/partner-shots'
fs.mkdirSync(out, { recursive: true })
const server = createPreviewServer()
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
const base = `http://127.0.0.1:${server.address().port}`
const chrome = spawn('google-chrome', [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--disable-dev-shm-usage',
  '--remote-debugging-port=0', '--user-data-dir=/tmp/partner-chrome',
], { stdio: ['ignore', 'pipe', 'pipe'] })
let dbg = ''
const wsUrl = await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('chrome did not open')), 15000)
  const onData = buf => {
    dbg += buf.toString()
    const match = dbg.match(/DevTools listening on (ws:\/\/\S+)/)
    if (match) { clearTimeout(timer); resolve(match[1]) }
  }
  chrome.stderr.on('data', onData)
  chrome.stdout.on('data', onData)
})
const version = await (await fetch(wsUrl.replace('ws://', 'http://').replace(/\/devtools\/browser\/.*/, '/json/version'))).json()
const browser = new WebSocket(version.webSocketDebuggerUrl)
let seq = 0
const pending = new Map()
await new Promise(resolve => browser.addEventListener('open', resolve, { once: true }))
browser.addEventListener('message', event => {
  const msg = JSON.parse(event.data)
  if (msg.id && pending.has(msg.id)) pending.get(msg.id)(msg)
})
function cdp(method, params = {}, sessionId) {
  const id = ++seq
  const payload = { id, method, params }
  if (sessionId) payload.sessionId = sessionId
  browser.send(JSON.stringify(payload))
  return new Promise((resolve, reject) => {
    pending.set(id, msg => {
      pending.delete(id)
      if (msg.error) reject(new Error(JSON.stringify(msg.error)))
      else resolve(msg.result)
    })
  })
}
const { targetId } = await cdp('Target.createTarget', { url: 'about:blank' })
const { sessionId } = await cdp('Target.attachToTarget', { targetId, flatten: true })
await cdp('Page.enable', {}, sessionId)
await cdp('Runtime.enable', {}, sessionId)
await cdp('Emulation.setEmulatedMedia', { media: 'screen', features: [{ name: 'prefers-color-scheme', value: 'dark' }] }, sessionId)

async function go(path, width, height) {
  await cdp('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 900 }, sessionId)
  await cdp('Page.navigate', { url: base + path }, sessionId)
  await new Promise(resolve => setTimeout(resolve, 700))
}
async function check(expression) {
  const result = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, sessionId)
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails))
  if (result.result.value !== true) throw new Error(String(result.result.value))
}
async function snap(name) {
  const { data } = await cdp('Page.captureScreenshot', { format: 'png' }, sessionId)
  fs.writeFileSync(`${out}/${name}.png`, Buffer.from(data, 'base64'))
  console.log(`${out}/${name}.png`)
}

await go('/?lang=en', 390, 844)
await check(`(() => document.querySelector('h1') && document.body.innerText.includes('Partner enrollment is not open yet.') && !document.getElementById('tab-overview'))()`)
await snap('shadcn-mobile-login')
await go('/?lang=en&preview=error', 390, 844)
await check(`(() => document.getElementById('message').textContent.includes('could not be completed') && !document.getElementById('tab-overview'))()`)
await snap('shadcn-mobile-error')
await go('/?lang=en&preview=dashboard', 390, 844)
await check(`(async () => {
  const posts = []
  const orig = window.fetch
  window.fetch = (url, opts) => { if (String((opts && opts.method) || 'GET').toUpperCase() === 'POST') posts.push(String(url)); return orig(url, opts) }
  document.getElementById('refresh').click()
  await new Promise(resolve => setTimeout(resolve, 150))
  if (!document.getElementById('greeting').textContent.includes('Local demo')) return 'refresh cleared the demo ' + document.getElementById('greeting').textContent
  if (posts.length) return 'refresh wrote'
  const scroller = document.querySelector('.overflow-y-auto')
  scroller.scrollTop = 240
  document.getElementById('tab-codes').click()
  await new Promise(resolve => setTimeout(resolve, 80))
  if (scroller.scrollTop > 4) return 'codes not top ' + scroller.scrollTop
  if (!document.getElementById('panel-codes').querySelector('h1')) return 'codes title'
  if (posts.length) return 'tab wrote'
  document.getElementById('tab-overview').click()
  await new Promise(resolve => setTimeout(resolve, 80))
  if (Math.abs(scroller.scrollTop - 240) > 30) return 'restore ' + scroller.scrollTop
  const nav = [...document.querySelectorAll('nav')].find(el => el.getBoundingClientRect().height > 0)
  const box = nav.getBoundingClientRect()
  if (box.bottom < window.innerHeight - 2) return 'nav ' + box.top + ',' + box.bottom
  return true
})()`)
for (const id of ['overview', 'codes', 'statements', 'account']) {
  await check(`(async () => { document.getElementById('tab-${id}').click(); await new Promise(resolve => setTimeout(resolve, 60)); return document.getElementById('panel-${id}') !== null })()`)
  await snap('shadcn-mobile-' + id)
}
await go('/?lang=zh-Hans&preview=dashboard', 390, 844)
for (const [id, label] of [['overview', '概览'], ['codes', '优惠码'], ['statements', '结算'], ['account', '账户']]) {
  await check(`(async () => { document.getElementById('tab-${id}').click(); await new Promise(resolve => setTimeout(resolve, 60)); const panel = document.getElementById('panel-${id}'); const heading = panel && panel.querySelector('h1'); const bar = [...document.querySelectorAll('nav')].find(el => el.getBoundingClientRect().height > 0).getBoundingClientRect(); if (!heading) return 'missing ${id}'; if (heading.getBoundingClientRect().top < 0) return 'title ${id}'; if (!document.getElementById('tab-${id}').textContent.includes('${label}')) return 'label ${id} ' + document.getElementById('tab-${id}').textContent; if (bar.bottom < window.innerHeight - 2) return 'bar ${id} ' + bar.bottom; return true })()`)
  await snap('shadcn-zh-' + id)
}
await go('/?lang=ar&preview=dashboard#account', 390, 844)
await check(`(async () => { if (document.documentElement.dir !== 'rtl') return 'dir'; const tab = document.getElementById('tab-account'); tab.focus(); tab.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true })); await new Promise(resolve => setTimeout(resolve, 50)); return document.getElementById('tab-statements').getAttribute('aria-current') === 'page' })()`)
await snap('shadcn-ar-account')
await go('/?lang=de&preview=dashboard', 320, 640)
await check(`(() => document.getElementById('tab-overview').textContent.includes('Übersicht') && document.documentElement.scrollWidth <= window.innerWidth + 1)()`)
await check(`(() => { document.documentElement.style.fontSize = '32px'; return document.documentElement.scrollWidth <= window.innerWidth + 1 && document.getElementById('tab-overview').getBoundingClientRect().height >= 44 })()`)
await snap('shadcn-de-200')
await go('/?lang=en&preview=dashboard#overview', 1280, 900)
await check(`(() => { const aside = document.querySelector('aside'); const nav = document.querySelector('nav'); const bottom = [...document.querySelectorAll('nav')].find(el => el.className.includes('lg:hidden'))
  return getComputedStyle(aside).display !== 'none' && getComputedStyle(bottom).display === 'none' && !!document.getElementById('greeting') })()`)
await snap('shadcn-desktop-overview')
await check(`(() => { document.getElementById('tab-statements').click(); return location.hash === '#statements' })()`)
await snap('shadcn-desktop-statements')

chrome.kill()
await new Promise(resolve => server.close(resolve))
console.log('captured')
