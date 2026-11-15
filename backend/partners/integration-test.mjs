// Run only against the local Wrangler database with /tmp/masso-referral-seed.sql.
import assert from 'node:assert/strict';
const base='http://localhost:8894';
const get=(p,headers={})=>fetch(base+p,{headers});
const post=(p,b,headers={})=>fetch(base+p,{method:'POST',headers:{'Content-Type':'application/json',Origin:base,...headers},body:JSON.stringify(b)});
assert.equal((await get('/api/dashboard')).status,401);
let r=await get('/api/dashboard',{Cookie:'masso_partner=local-integration-session'});assert.equal(r.status,200);let d=await r.json();assert.deepEqual(d.codes.map(x=>x.code),['LOCALONE']);assert.equal(d.partner.email,undefined);assert.equal(d.summary.paid,0);
// Local Sandbox paid-acquisition fixture must not appear in the creator's production metrics.
assert.equal(d.summary.attributed,0);assert.equal(d.summary.active,0);assert.equal(d.settlements.length,0);
assert.equal((await post('/api/codes/status',{code:'LOCALTWO',status:'disabled'},{Cookie:'masso_partner=local-integration-session'})).status,404);
assert.equal((await post('/api/logout',{}, {Origin:'https://attacker.example'})).status,403);
r=await post('/api/app/register',{});assert.equal(r.status,200);d=await r.json();const auth={Authorization:'Bearer '+d.credential};
assert.equal((await post('/api/app/claim',{code:'FAKECODE'},auth)).status,400);
r=await post('/api/app/transaction',{signedTransaction:'eyJhbGciOiJub25lIn0.e30.'},auth);assert.equal(r.status,400);assert.equal((await r.json()).error,'referral_required');
assert.equal((await post('/api/apple/notifications',{signedPayload:'not-signed'})).status,422);
assert.equal((await post('/api/admin/settle',{})).status,401);
assert.equal((await post('/api/login',{email:'test@example.test'})).status,503);
assert.equal((await get('/')).headers.get('content-security-policy').includes("frame-ancestors 'none'"),true);
console.log('PASS: local Worker auth isolation, CSRF, anonymous registration, failed claims, Apple JWS rejection, notification rejection, settlement access, enrollment gate and CSP');
