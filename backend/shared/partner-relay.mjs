const routes = new Set(['register', 'claim', 'transaction']);
const origin = 'https://masso-partners.wuyumo.workers.dev';
const error = (code, status) => Response.json({error: code}, {status, headers: {'Cache-Control': 'no-store'}});

// A fixed gateway to the canonical referral service, not a general-purpose proxy.
export async function relayPartnerRequest(request, send = fetch) {
  const path = new URL(request.url).pathname;
  const action = path.slice('/partners/api/app/'.length);
  if (!path.startsWith('/partners/api/app/') || !routes.has(action)) return error('not_found', 404);
  if (request.method !== 'POST') return error('method_not_allowed', 405);
  if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) return error('invalid_content_type', 415);
  if (Number(request.headers.get('content-length')) > 24000) return error('request_too_large', 413);
  const body = await request.arrayBuffer();
  if (body.byteLength > 24000) return error('request_too_large', 413);
  const headers = new Headers({'Content-Type': 'application/json'});
  const authorization = request.headers.get('authorization');
  if (authorization) headers.set('Authorization', authorization);
  try {
    const response = await send(`${origin}/api/app/${action}`, {
      method: 'POST', headers, body, redirect: 'manual', signal: AbortSignal.timeout(15000)
    });
    if (!response.headers.get('content-type')?.includes('application/json') || response.status >= 300 && response.status < 400) {
      return error('referral_gateway_unavailable', 502);
    }
    return new Response(response.body, {status: response.status, headers: {
      'Content-Type': 'application/json', 'Cache-Control': 'no-store'
    }});
  } catch { return error('referral_gateway_unavailable', 502); }
}
