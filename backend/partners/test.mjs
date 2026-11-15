import test from 'node:test';import assert from 'node:assert/strict';
import {normalizeCode,normalizeTransaction,canAttribute,calculateCommission,summarize} from './domain.mjs';
const t={id:'1',original:'o',environment:'Production',product:'com.yumowu.maso.pro.yearly',purchased:100,expires:200,revoked:null,trial:1,amount:0,token:'d',offer:'offer'};
test('codes normalize; reserved and injected names rejected',()=>{assert.equal(normalizeCode(' alex20 '),'ALEX20');for(const c of ['admin','a','<script>','a/b','APPLE20'])assert.throws(()=>normalizeCode(c));});
test('signed payload still needs supported SKU/environment/dates',()=>{assert.throws(()=>normalizeTransaction({productId:'fake'}));assert.throws(()=>normalizeTransaction({productId:t.product,transactionId:'1',originalTransactionId:'o',environment:'Xcode',purchaseDate:1}));});
test('attribution excludes old subscriptions, sandbox, refunds and expired claims',()=>{const c={created:90};assert(canAttribute(t,c,'d','offer',150));assert(!canAttribute({...t,environment:'Sandbox'},c,'d','offer',150));assert(!canAttribute({...t,revoked:120},c,'d','offer',150));assert(!canAttribute(t,{created:101},'d','offer',150));assert(!canAttribute(t,c,'other','different',150));assert(!canAttribute(t,c,'d','offer',31*86400000));});
test('trial cohort excludes immature trials; renewals and duplicated chains are not new users',()=>{let s=summarize([t],150);assert.equal(s.trialing,1);assert.equal(s.yearlyTrialing,1);assert.equal(s.paid,0);assert.equal(s.trialConversion,null);const paid={...t,id:'2',purchased:201,expires:400,trial:0,amount:23990};s=summarize([t,paid,{...paid,id:'3',purchased:401,expires:600}],450);assert.equal(s.attributed,1);assert.equal(s.paid,1);assert.equal(s.yearlyPaid,1);assert.equal(s.trialConversion,1);assert.equal(s.yearly,1);s=summarize([t,{...paid,revoked:250}],260);assert.equal(s.paid,0);assert.equal(s.refunded,1);assert.equal(s.active,0);});
test('commission uses integer reconciled proceeds; negative/refund amounts cannot create credit',()=>{assert.equal(calculateCommission(2039,2000),407);for(const x of [-1,1.5,NaN])assert.throws(()=>calculateCommission(x,2000));});
test('explicit Sandbox validation uses the same eligibility rules but never creates production metrics',()=>{
 const sandbox={...t,environment:'Sandbox'},claim={created:90};
 assert(!canAttribute(sandbox,claim,'d','offer',150));
 assert(canAttribute(sandbox,claim,'d','offer',150,'Sandbox'));
 assert(!canAttribute({...sandbox,revoked:120},claim,'d','offer',150,'Sandbox'));
 assert(!canAttribute({...sandbox,purchased:80},claim,'d','offer',150,'Sandbox'));
 assert(!canAttribute(t,claim,'d','offer',150,'Sandbox'));
 assert.equal(summarize([sandbox,{...sandbox,id:'paid-test',trial:0,amount:23990}],150).attributed,0);
});
test('official verifier rejects unsigned data',async()=>{const {SignedDataVerifier,Environment}=await import('@apple/app-store-server-library');const {roots}=await import('./roots.mjs');const v=new SignedDataVerifier(roots.map(x=>Buffer.from(x,'base64')),true,Environment.PRODUCTION,'com.yumowu.maso',6776689750);await assert.rejects(v.verifyAndDecodeTransaction('eyJhbGciOiJub25lIn0.e30.'));});
test('Apple token is verifiable ES256 JOSE with correct audience, scope and short lifetime',async()=>{
 const {appleToken}=await import('./apple-token.mjs');const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const der=await crypto.subtle.exportKey('pkcs8',keys.privateKey);const pem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(der).toString('base64')+'\n-----END PRIVATE KEY-----';
 const jwt=await appleToken({keyId:'test',issuer:'issuer',privateKey:pem,bundleId:'com.yumowu.maso'},1000000),parts=jwt.split('.');
 const payload=JSON.parse(Buffer.from(parts[1],'base64url'));assert.equal(payload.aud,'appstoreconnect-v1');assert.equal(payload.bid,'com.yumowu.maso');assert.equal(payload.exp-payload.iat,120);
 assert.equal(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},keys.publicKey,Buffer.from(parts[2],'base64url'),new TextEncoder().encode(parts[0]+'.'+parts[1])),true);
});

test('optional referral notification storage requires prior attribution; Sandbox cannot mutate money',async()=>{
 const {storeTransaction}=await import('./worker.mjs');
 const payload={productId:'com.yumowu.maso.pro.yearly',transactionId:'owned-annual',originalTransactionId:'owned',environment:'Sandbox',purchaseDate:Date.now()-1000,expiresDate:Date.now()+3600000,revocationDate:Date.now(),price:23990,currency:'USD'};
 let writes=[],known=false,queries=[];
 const env={DB:{prepare(sql){queries.push(sql);return {bind(){return this;},async first(){return known?{original:'owned'}:null;},async run(){writes.push(sql);return {};}};}}};
 assert.equal(await storeTransaction(payload,env,true),null);assert.equal(writes.length,0);
 known=true;await storeTransaction(payload,env,true);
 assert.equal(writes.length,1);assert(writes[0].startsWith('INSERT INTO partner_transactions'));
 assert(!queries.some(q=>q.includes('partner_settlements')||q.includes('partner_adjustments')));
 assert(queries.some(q=>q.includes('partner_sandbox_attributions')));
 writes=[];known=false;await storeTransaction({...payload,environment:'Production'},env,true);assert.equal(writes.length,0);
});
