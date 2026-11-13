// Local visual preview of the existing Masso partner pages.
// Serves the public client and a frozen read of the public policy.
// Write routes answer locally and never call the production partner service.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), 'public');
const types = {'.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml'};

// Snapshot of the public GET /api/policy response observed 2026-11-13.
// Flags stay closed. This server does not flip registration or campaign switches.
export const publicPolicySnapshot = {
  registrationOpen: false,
  campaignReady: false,
  commissionBps: 2000,
  offer: 'New subscribers: US annual plan $23.99 for the first year, then standard pricing. Eligible introductory trial may apply first. Local prices and availability are confirmed by Apple.',
  maxCodes: 3
};

const writeErrors = {
  'login': 'registration_not_ready',
  'login/verify': 'registration_not_ready',
  'logout': 'sign_in_required',
  'codes': 'campaign_not_ready',
  'codes/status': 'campaign_not_ready'
};

function send(res, status, body, type = 'application/json; charset=utf-8') {
  const buf = Buffer.isBuffer(body) ? body : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body));
  res.writeHead(status, {
    'Content-Type': type,
    'Cache-Control': 'no-store',
    'Content-Length': buf.length,
    'X-Masso-Preview': 'local-only'
  });
  res.end(buf);
}

function demoQr(code) {
  const safe = String(code).replace(/[^A-Za-z0-9]/g, '').slice(0, 20) || 'LOCAL';
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="180" height="180" viewBox="0 0 180 180" role="img" aria-label="Not a scannable code">
  <rect width="180" height="180" fill="#121212"/>
  <text x="90" y="78" text-anchor="middle" font-family="ui-sans-serif,system-ui" font-size="13" font-weight="700" fill="#1ED760">NOT A SCANNABLE CODE</text>
  <text x="90" y="104" text-anchor="middle" font-family="ui-sans-serif,system-ui" font-size="12" fill="#FFFFFF">LOCAL MOCK ${safe}</text>
</svg>`;
}

export function createPreviewServer() {
  return http.createServer((req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    if (url.pathname === '/api/policy' && req.method === 'GET') return send(res, 200, publicPolicySnapshot);
    if (url.pathname === '/api/dashboard' && req.method === 'GET') return send(res, 401, {error: 'sign_in_required'});
    if (url.pathname.startsWith('/api/')) {
      const action = url.pathname.slice('/api/'.length);
      if (req.method === 'POST' && action in writeErrors) return send(res, action === 'logout' ? 401 : 403, {error: writeErrors[action]});
      return send(res, 404, {error: 'not_found'});
    }
    const qr = url.pathname.match(/^\/qr\/([A-Za-z0-9]+)\.svg$/);
    if (qr && req.method === 'GET') return send(res, 200, demoQr(qr[1]), 'image/svg+xml');
    let file = url.pathname;
    if (file === '/' || file.startsWith('/r/')) file = '/index.html';
    else if (file === '/terms' || file === '/terms.html') file = '/terms.html';
    const full = path.normalize(path.join(root, file));
    if (!full.startsWith(root) || !fs.existsSync(full) || !fs.statSync(full).isFile()) return send(res, 404, 'Not found', 'text/plain; charset=utf-8');
    send(res, 200, fs.readFileSync(full), types[path.extname(full)] || 'application/octet-stream');
  });
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const port = Number(process.env.PORT || 4173);
  createPreviewServer().listen(port, '127.0.0.1', () => {
    console.log(`Local partner preview http://127.0.0.1:${port}/`);
    console.log('Closed landing, ?preview=verify, ?preview=dashboard, ?preview=error, /r/DEMOFIT');
  });
}
