import test from 'node:test';
import assert from 'node:assert/strict';
import {relayPartnerRequest} from './partner-relay.mjs';
const request = (path, body = '{}', headers = {}) => new Request('https://ai.replai.sh' + path, {method:'POST', headers:{'content-type':'application/json', ...headers}, body});
test('only bounded app endpoints forward to the fixed canonical origin', async () => {
  for (const action of ['register','claim','transaction']) {
    let seen;
    const response = await relayPartnerRequest(request('/partners/api/app/'+action, '{"code":"EXAMPLE"}', {authorization:'Bearer test-value',cookie:'private-cookie'}), async (url, options) => {
      seen = {url, options}; return Response.json({ok:true});
    });
    assert.equal(response.status,200);
    assert.equal(seen.url,'https://masso-partners.wuyumo.workers.dev/api/app/'+action);
    assert.equal(seen.options.headers.get('authorization'),'Bearer test-value');
    assert.equal(seen.options.headers.get('cookie'),null);
    assert.equal(seen.options.redirect,'manual');
    assert.equal(response.headers.get('cache-control'),'no-store');
  }
});
test('admin, traversal and extra paths never reach upstream', async () => {
  for(const path of ['/partners/api/admin/settle','/partners/api/app/claim/extra','/partners/api/app/https://elsewhere','/partners/api/app/../register']) {
    assert.equal((await relayPartnerRequest(request(path),()=>{throw Error('must not fetch')})).status,404);
  }
});
test('rejects oversized bodies and non-JSON without forwarding', async () => {
  assert.equal((await relayPartnerRequest(request('/partners/api/app/claim','x'.repeat(24001)))).status,413);
  assert.equal((await relayPartnerRequest(request('/partners/api/app/claim','{}',{'content-type':'text/plain'}))).status,415);
});
test('preserves authentication and rate rejection; never follows upstream redirects', async () => {
  for(const status of [401,409,429]) assert.equal((await relayPartnerRequest(request('/partners/api/app/claim'),async()=>Response.json({error:'rejected'},{status}))).status,status);
  assert.equal((await relayPartnerRequest(request('/partners/api/app/claim'),async()=>new Response(null,{status:302,headers:{Location:'https://elsewhere'}}))).status,502);
});
test('transport failures return a bounded error without leaking details', async () => {
  const response=await relayPartnerRequest(request('/partners/api/app/claim'),async()=>{throw Error('sensitive detail')});
  assert.equal(response.status,502); assert.deepEqual(await response.json(),{error:'referral_gateway_unavailable'});
});
