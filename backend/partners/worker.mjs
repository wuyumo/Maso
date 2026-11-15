import { appleToken } from './apple-token.mjs';
import { roots } from './roots.mjs';
import { normalizeCode as parseCode,normalizeTransaction,canAttribute,calculateCommission,summarize } from './domain.mjs';
const now=()=>Date.now(), random=()=>crypto.randomUUID(), enc=new TextEncoder();
const hash=async s=>Buffer.from(await crypto.subtle.digest('SHA-256',enc.encode(s))).toString('hex');
const json=(data,status=200,headers={})=>Response.json(data,{status,headers:{'Cache-Control':'no-store',...headers}});
class Failure extends Error {constructor(code,status=400){super(code);this.status=status;}}
const fail=(code,status)=>{throw new Failure(code,status);};
function normalizeCode(value){try{return parseCode(value);}catch{fail('invalid_code');}}
function verificationFailure(e){fail(e.status===2?'apple_verification_temporarily_unavailable':'invalid_apple_signature',e.status===2?503:422);}
async function body(req){if(Number(req.headers.get('content-length'))>24000)fail('request_too_large',413);const raw=await req.text();if(raw.length>24000)fail('request_too_large',413);try{return JSON.parse(raw);}catch{fail('invalid_json');}}
async function rate(env,key,max=10,ms=3600000){
 const bucket=Math.floor(now()/ms), k=await hash(`${key}:${bucket}`);
 const r=await env.DB.prepare('INSERT INTO partner_limits(key,count,expires) VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1 RETURNING count').bind(k,now()+ms).first();if(r.count>max)fail('rate_limited',429);
}
async function logged(req,env){
 const token=(req.headers.get('cookie')||'').match(/(?:^|; )masso_partner=([^;]+)/)?.[1];if(!token)fail('sign_in_required',401);
 const s=await env.DB.prepare('SELECT partner FROM partner_sessions WHERE hash=? AND expires>?').bind(await hash(token),now()).first();if(!s)fail('sign_in_required',401);return s.partner;
}
async function device(req,env){const v=(req.headers.get('authorization')||'').replace(/^Bearer /,'').split('.');if(v.length!==2)fail('unauthorized',401);const d=await env.DB.prepare('SELECT id FROM partner_devices WHERE id=? AND secret=?').bind(v[0],await hash(v[1])).first();if(!d)fail('unauthorized',401);return d.id;}
async function verifier(env,sandbox=false){const {SignedDataVerifier,Environment}=await import('@apple/app-store-server-library');return new SignedDataVerifier(roots.map(r=>Buffer.from(r,'base64')),true,sandbox?Environment.SANDBOX:Environment.PRODUCTION,env.BUNDLE_ID,Number(env.APPLE_APP_ID));}
async function decodeTransaction(jws,env,sandbox=false){try{return await (await verifier(env,sandbox)).verifyAndDecodeTransaction(jws);}catch(e){console.error('apple_verification_failed',e.status);verificationFailure(e);}}
export async function storeTransaction(t,env,requireAttribution=false){
 let a;try{a=normalizeTransaction(t);}catch{fail('unsupported_transaction',422);}
 if(requireAttribution){
  const table=a.environment==='Sandbox'?'partner_sandbox_attributions':'partner_attributions';
  if(!await env.DB.prepare(`SELECT original FROM ${table} WHERE original=?`).bind(a.original).first())return null;
 }
 await env.DB.prepare(`INSERT INTO partner_transactions(id,original,environment,product,purchased,expires,revoked,trial,amount,currency,token,offer,received) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET revoked=COALESCE(excluded.revoked,partner_transactions.revoked),expires=excluded.expires,received=excluded.received`).bind(...Object.values(a),now()).run();
 if(a.revoked&&a.environment==='Production'){
  const first=await env.DB.prepare("SELECT id FROM partner_transactions WHERE original=? AND trial=0 AND amount>0 ORDER BY purchased,id LIMIT 1").bind(a.original).first();
  if(first?.id===a.id){
   const settled=await env.DB.prepare('SELECT * FROM partner_settlements WHERE original=?').bind(a.original).first();
   if(settled?.status==='paid')await env.DB.prepare('INSERT INTO partner_adjustments VALUES(?,?,?,?,?) ON CONFLICT(settlement) DO NOTHING').bind(random(),settled.id,-settled.commission_minor,settled.currency,now()).run();
   await env.DB.prepare("UPDATE partner_settlements SET status='reversed' WHERE original=? AND status='eligible'").bind(a.original).run();
  }
 }
 return a;
}
async function apple(env,path,method='GET',data){
 if(!env.ASC_PRIVATE_KEY||!env.ASC_KEY_ID||!env.ASC_ISSUER)fail('apple_configuration_pending',503);
 const token=await appleToken({keyId:env.ASC_KEY_ID,issuer:env.ASC_ISSUER,privateKey:env.ASC_PRIVATE_KEY});
 const r=await fetch('https://api.appstoreconnect.apple.com/v1/'+path,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});
 if(!r.ok)fail('apple_request_failed',502);return r.status===204?{}:r.json();
}
async function routes(req,env){
 const url=new URL(req.url),p=url.pathname;
 const ip=req.headers.get('CF-Connecting-IP')||'local';
 if(req.method==='POST'&&!p.startsWith('/api/app/')&&p!='/api/apple/notifications'&&p!='/api/admin/settle'){
  if(req.headers.get('origin')!==url.origin)fail('invalid_origin',403);
 }
 if(p==='/api/policy')return json({registrationOpen:env.REGISTRATION_OPEN==='true',campaignReady:env.CAMPAIGN_READY==='true',commissionBps:Number(env.COMMISSION_BPS),offer:env.OFFER_DESCRIPTION||'Offer configuration pending',maxCodes:3});
 if(p==='/api/login'&&req.method==='POST'){
  if(!env.RESEND_API_KEY||!env.MAIL_FROM)fail('registration_not_ready',503);
  await rate(env,'login-ip:'+ip,10);await rate(env,'global-email',Number(env.EMAIL_DAILY_LIMIT||80),86400000);const b=await body(req),email=String(b.email||'').trim().toLowerCase();if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254)fail('invalid_email');if(env.REGISTRATION_OPEN!=='true'&&email!==env.PILOT_EMAIL)fail('registration_not_ready',503);await rate(env,'email:'+email,3);
  const otp=String(crypto.getRandomValues(new Uint32Array(1))[0]%1000000).padStart(6,'0');
  await env.DB.prepare('INSERT INTO partner_logins(email,hash,expires,attempts) VALUES(?,?,?,0) ON CONFLICT(email) DO UPDATE SET hash=excluded.hash,expires=excluded.expires,attempts=0').bind(email,await hash(email+otp+env.AUTH_SECRET),now()+600000).run();
  const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+env.RESEND_API_KEY,'Content-Type':'application/json'},body:JSON.stringify({from:env.MAIL_FROM,to:[email],subject:'Masso Partners — sign-in code',text:`Your Masso Partners sign-in code is ${otp}. It expires in 10 minutes. Do not share this code.`})});if(!r.ok)fail('email_delivery_failed',503);return json({sent:true});
 }
 if(p==='/api/login/verify'&&req.method==='POST'){
  await rate(env,'verify:'+ip,30);const b=await body(req),email=String(b.email||'').trim().toLowerCase(),otp=String(b.otp||'');
  // Atomic attempt consumption prevents parallel guesses escaping the limit.
  const row=await env.DB.prepare('UPDATE partner_logins SET attempts=attempts+1 WHERE email=? AND expires>? AND attempts<5 RETURNING hash').bind(email,now()).first();if(!row||row.hash!==await hash(email+otp+env.AUTH_SECRET))fail('invalid_or_expired_code',401);
  const consumed=await env.DB.prepare('DELETE FROM partner_logins WHERE email=? AND hash=? RETURNING email').bind(email,row.hash).first();if(!consumed)fail('invalid_or_expired_code',401);
  const id=random();await env.DB.prepare('INSERT INTO partner_partners(id,email,name,created) VALUES(?,?,?,?) ON CONFLICT(email) DO NOTHING').bind(id,email,String(b.name||'Creator').slice(0,80),now()).run();
  const partner=await env.DB.prepare('SELECT id FROM partner_partners WHERE email=?').bind(email).first(),token=random()+random();
  await env.DB.prepare('INSERT INTO partner_sessions VALUES(?,?,?)').bind(await hash(token),partner.id,now()+7*86400000).run();
  return json({ok:true},200,{'Set-Cookie':`masso_partner=${token}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=604800`});
 }
 if(p==='/api/logout'&&req.method==='POST'){
  const token=(req.headers.get('cookie')||'').match(/(?:^|; )masso_partner=([^;]+)/)?.[1];if(token)await env.DB.prepare('DELETE FROM partner_sessions WHERE hash=?').bind(await hash(token)).run();return json({ok:true},200,{'Set-Cookie':'masso_partner=; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=0'});
 }
 if(p==='/api/dashboard'){
  const id=await logged(req,env),partner=await env.DB.prepare('SELECT name FROM partner_partners WHERE id=?').bind(id).first();
  const codes=(await env.DB.prepare('SELECT code,status,created FROM partner_codes WHERE partner=? ORDER BY created DESC').bind(id).all()).results;
  const tx=(await env.DB.prepare("SELECT t.* FROM partner_transactions t JOIN partner_attributions a ON a.original=t.original JOIN partner_codes c ON c.code=a.code WHERE c.partner=? AND t.environment='Production'").bind(id).all()).results;
  const counts=(await env.DB.prepare('SELECT c.code,(SELECT COUNT(*) FROM partner_claims WHERE code=c.code) AS bound,(SELECT COUNT(*) FROM partner_clicks WHERE code=c.code) AS visits FROM partner_codes c WHERE partner=?').bind(id).all()).results;
  const settlements=(await env.DB.prepare('SELECT s.id,s.net_minor,s.currency,s.commission_minor,s.status,s.created FROM partner_settlements s JOIN partner_attributions a ON a.original=s.original JOIN partner_codes c ON c.code=a.code WHERE c.partner=? ORDER BY s.created DESC').bind(id).all()).results;
  const adjustments=(await env.DB.prepare('SELECT adj.id,adj.commission_minor,adj.currency,adj.created FROM partner_adjustments adj JOIN partner_settlements s ON s.id=adj.settlement JOIN partner_attributions a ON a.original=s.original JOIN partner_codes c ON c.code=a.code WHERE c.partner=?').bind(id).all()).results;
  settlements.push(...adjustments.map(a=>({...a,status:'refund adjustment'})));
  const acceptedTerms=await env.DB.prepare('SELECT partner FROM partner_acceptances WHERE partner=? AND version=?').bind(id,'2026-11-12').first();
  return json({partner,acceptedTerms:!!acceptedTerms,pilot:partner&&await env.DB.prepare('SELECT id FROM partner_partners WHERE id=? AND email=?').bind(id,env.PILOT_EMAIL||'').first()!=null,codes:codes.map(c=>({...c,...counts.find(x=>x.code===c.code)})),summary:summarize(tx),settlements,updatedAt:now()});
 }
 if(p==='/api/codes'&&req.method==='POST'){
  const id=await logged(req,env);await rate(env,'codes:'+id,8,86400000);const pilot=await env.DB.prepare('SELECT id FROM partner_partners WHERE id=? AND email=?').bind(id,env.PILOT_EMAIL||'').first();if((env.CAMPAIGN_READY!=='true'&&!pilot)||!env.APPLE_OFFER_ID)fail('campaign_not_ready',503);
  const b=await body(req),code=normalizeCode(b.code);const accepted=await env.DB.prepare('SELECT partner FROM partner_acceptances WHERE partner=? AND version=?').bind(id,'2026-11-12').first();if(!accepted){if(b.acceptTerms!==true)fail('terms_required');await env.DB.prepare('INSERT INTO partner_acceptances VALUES(?,?,?) ON CONFLICT DO NOTHING').bind(id,'2026-11-12',now()).run();}
  // Single SQL statement makes the per-partner cap safe under concurrent creation.
  const r=await env.DB.prepare("INSERT INTO partner_codes(code,partner,status,created) SELECT ?,?,'creating',? WHERE (SELECT COUNT(*) FROM partner_codes WHERE partner=? AND status IN ('active','creating','disabling'))<3 ON CONFLICT(code) DO NOTHING RETURNING code").bind(code,id,now(),id).first();if(!r){const pending=await env.DB.prepare('SELECT partner,status FROM partner_codes WHERE code=?').bind(code).first();if(pending?.partner!==id||pending.status!=='creating')fail('code_taken_or_limit',409);const found=await apple(env,'subscriptionOfferCodes/'+env.APPLE_OFFER_ID+'/customCodes?limit=200');const remote=found.data.find(c=>c.attributes.customCode===code);if(remote){await env.DB.prepare("UPDATE partner_codes SET apple_id=?,status='active' WHERE code=?").bind(remote.id,code).run();return json({code,status:'active'});}}
  try{
   const result=await apple(env,'subscriptionOfferCodeCustomCodes','POST',{data:{type:'subscriptionOfferCodeCustomCodes',attributes:{customCode:code,numberOfCodes:500},relationships:{offerCode:{data:{type:'subscriptionOfferCodes',id:env.APPLE_OFFER_ID}}}}});
   await env.DB.prepare("UPDATE partner_codes SET apple_id=?,status='active' WHERE code=?").bind(result.data.id,code).run();return json({code,status:'active'});
  }catch(e){/* Keep reserved: a timed-out Apple creation may still have succeeded. */throw e;}
 }
 if(p==='/api/codes/status'&&req.method==='POST'){
  const id=await logged(req,env),b=await body(req),code=normalizeCode(b.code);
  const c=await env.DB.prepare('SELECT * FROM partner_codes WHERE code=? AND partner=?').bind(code,id).first();if(!c)fail('not_found',404);
  if(b.status==='archived'){
   if(!['disabled','failed'].includes(c.status))fail('disable_before_archiving');await env.DB.prepare("UPDATE partner_codes SET status='archived' WHERE code=?").bind(code).run();
  }else if(b.status==='disabled'){
   if(!['active','disabling'].includes(c.status))fail('invalid_status');await env.DB.prepare("UPDATE partner_codes SET status='disabling' WHERE code=?").bind(code).run();
   await apple(env,'subscriptionOfferCodeCustomCodes/'+c.apple_id,'PATCH',{data:{type:'subscriptionOfferCodeCustomCodes',id:c.apple_id,attributes:{active:false}}});
   await env.DB.prepare("UPDATE partner_codes SET status='disabled' WHERE code=?").bind(code).run();
  }else fail('invalid_status');return json({ok:true});
 }
 if(p==='/api/app/register'&&req.method==='POST'){
  await rate(env,'device:'+ip,100,86400000);const id=random(),secret=random()+random();await env.DB.prepare('INSERT INTO partner_devices VALUES(?,?,?)').bind(id,await hash(secret),now()).run();return json({id,credential:id+'.'+secret});
 }
 if(p==='/api/app/claim'&&req.method==='POST'){
  const id=await device(req,env),b=await body(req),code=normalizeCode(b.code);await rate(env,'claim:'+id,10);
  const c=await env.DB.prepare("SELECT c.code,p.email FROM partner_codes c JOIN partner_partners p ON p.id=c.partner WHERE c.code=? AND c.status='active'").bind(code).first();if(!c||(env.CAMPAIGN_READY!=='true'&&c.email!==env.PILOT_EMAIL))fail('code_unavailable');
  await env.DB.prepare('INSERT INTO partner_claims VALUES(?,?,?) ON CONFLICT(device) DO NOTHING').bind(id,code,now()).run();
  const claim=await env.DB.prepare('SELECT * FROM partner_claims WHERE device=?').bind(id).first();if(claim.code!==code)fail('referral_already_bound',409);
  if(now()-claim.created>30*86400000)fail('referral_expired',409);
  return json({code,offer:env.OFFER_DESCRIPTION,redemptionURL:`https://apps.apple.com/redeem?ctx=offercodes&id=${env.APPLE_APP_ID}&code=${encodeURIComponent(code)}`});
 }
 if(p==='/api/app/transaction'&&req.method==='POST'){
  const id=await device(req,env),b=await body(req);await rate(env,'tx:'+id,120);
  const claim=await env.DB.prepare('SELECT * FROM partner_claims WHERE device=?').bind(id).first();if(!claim)fail('referral_required');
  const t=await decodeTransaction(b.signedTransaction,env,b.environment==='Sandbox');const a=await storeTransaction(t,env);
  let attributionOffer=a.offer;
  if(b.signedRenewal){
   let renewal;try{renewal=await (await verifier(env,a.environment==='Sandbox')).verifyAndDecodeRenewalInfo(b.signedRenewal);}catch(e){verificationFailure(e);}
   if(renewal.originalTransactionId===a.original&&renewal.autoRenewProductId==='com.yumowu.maso.pro.yearly'&&renewal.offerIdentifier===env.APPLE_OFFER_REFERENCE)attributionOffer=renewal.offerIdentifier;
  }
  // Never take an old subscriber or a renewal as a new acquisition.
  // Test acquisitions stay outside the production dashboard, acquisition limit and settlement joins.
  const attributionTable=a.environment==='Sandbox'?'partner_sandbox_attributions':'partner_attributions';
  if(canAttribute({...a,offer:attributionOffer},claim,id,env.APPLE_OFFER_REFERENCE,now(),a.environment)&&t.originalPurchaseDate>=claim.created){
   await env.DB.prepare(`INSERT INTO ${attributionTable} VALUES(?,?,?,?,?) ON CONFLICT DO NOTHING`).bind(a.original,id,claim.code,now(),Number(env.COMMISSION_BPS)).run();
   if(a.environment==='Production')await env.DB.prepare('INSERT INTO partner_sync(original) VALUES(?) ON CONFLICT DO NOTHING').bind(a.original).run();
  }
  const attributed=await env.DB.prepare(`SELECT original FROM ${attributionTable} WHERE original=?`).bind(a.original).first();return json({recorded:true,attributed:!!attributed,environment:a.environment});
 }
 if(p==='/api/apple/notifications'&&req.method==='POST'){
  const b=await body(req);let notification;
  try{notification=await (await verifier(env,url.searchParams.get('environment')==='Sandbox')).verifyAndDecodeNotification(b.signedPayload);}catch(e){verificationFailure(e);}
  if(notification.data?.signedTransactionInfo)await storeTransaction(await decodeTransaction(notification.data.signedTransactionInfo,env,notification.data.environment==='Sandbox'),env,true);
  await env.DB.prepare('INSERT INTO partner_notifications VALUES(?,?) ON CONFLICT(id) DO NOTHING').bind(notification.notificationUUID,now()).run();return json({ok:true});
 }
 if(p==='/api/admin/settle'&&req.method==='POST'){
  if(!env.ADMIN_SECRET||await hash(req.headers.get('authorization')||'')!==await hash('Bearer '+env.ADMIN_SECRET))fail('unauthorized',401);
  const b=await body(req);if(b.currency!=='USD'||!b.reference)fail('invalid_settlement');
  const a=await env.DB.prepare('SELECT * FROM partner_attributions WHERE original=?').bind(b.original).first();if(!a)fail('not_attributed');
  const t=await env.DB.prepare("SELECT * FROM partner_transactions WHERE original=? AND environment='Production' AND trial=0 AND amount>0 ORDER BY purchased LIMIT 1").bind(b.original).first();if(!t||t.revoked||now()-t.purchased<30*86400000)fail('not_settleable');
  const commission=calculateCommission(b.netMinor,a.commission_bps);
  await env.DB.prepare("INSERT INTO partner_settlements VALUES(?,?,?,?,?,'eligible',?,?) ON CONFLICT(original) DO NOTHING").bind(random(),b.original,b.netMinor,b.currency,commission,String(b.reference).slice(0,120),now()).run();return json({ok:true});
 }
 if(p.startsWith('/qr/')&&p.endsWith('.svg')){
  const code=normalizeCode(p.slice(4,-4));const c=await env.DB.prepare("SELECT code FROM partner_codes WHERE code=? AND status='active'").bind(code).first();if(!c)fail('code_unavailable',404);
  const QRCode=(await import('qrcode')).default;const svg=await QRCode.toString(url.origin+'/r/'+code,{type:'svg',width:240,margin:4});return new Response(svg,{headers:{'Content-Type':'image/svg+xml','Cache-Control':'no-store'}});
 }
 if(p.startsWith('/r/')){
  const code=normalizeCode(decodeURIComponent(p.slice(3)));const c=await env.DB.prepare("SELECT code FROM partner_codes WHERE code=? AND status='active'").bind(code).first();if(!c)fail('code_unavailable',404);
  const day=new Date().toISOString().slice(0,10),visitor=await hash(day+ip+env.AUTH_SECRET);await env.DB.prepare('INSERT INTO partner_clicks VALUES(?,?,?,?) ON CONFLICT DO NOTHING').bind(random(),code,day,visitor).run();
  return env.ASSETS.fetch(new Request(url.origin+'/index.html'));
 }
 if(p.startsWith('/api/'))fail('not_found',404);
 return env.ASSETS.fetch(req);
}
export default {
 async fetch(req,env){
  try{const r=await routes(req,env);const h=new Headers(r.headers);h.set('X-Content-Type-Options','nosniff');h.set('Referrer-Policy','no-referrer');h.set('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");return new Response(r.body,{status:r.status,headers:h});}
  catch(e){if(!(e instanceof Failure))console.error('partners_request_failed',e.name,String(e.message).slice(0,250));return json({error:e instanceof Failure?e.message:'service_unavailable'},e.status||503);}
 },
 async scheduled(_event,env){await reconcile(env);await env.DB.batch([env.DB.prepare('DELETE FROM partner_sessions WHERE expires<?').bind(now()),env.DB.prepare('DELETE FROM partner_logins WHERE expires<?').bind(now()),env.DB.prepare('DELETE FROM partner_limits WHERE expires<?').bind(now()),env.DB.prepare('DELETE FROM partner_clicks WHERE day<?').bind(new Date(now()-90*86400000).toISOString().slice(0,10))]);}
};


async function reconcile(env) {
    if (env.ASC_PRIVATE_KEY && env.APPLE_OFFER_ID) {
        const pending = (await env.DB.prepare("SELECT * FROM partner_codes WHERE status IN ('creating','disabling') ORDER BY created LIMIT 20").all()).results;
        if (pending.length) {
            let response = await apple(env, 'subscriptionOfferCodes/' + env.APPLE_OFFER_ID + '/customCodes?limit=200');
            const all = [...response.data];
            while (response.links?.next) {
                const next = new URL(response.links.next);
                response = await apple(env, next.pathname.replace('/v1/', '') + next.search);
                all.push(...response.data);
            }
            for (const code of pending) {
                let remote = all.find(c => c.attributes.customCode === code.code);
                if (!remote && code.status === 'creating') {
                    try { remote = (await apple(env, 'subscriptionOfferCodeCustomCodes', 'POST', {data: {type:'subscriptionOfferCodeCustomCodes', attributes:{customCode:code.code,numberOfCodes:500},relationships:{offerCode:{data:{type:'subscriptionOfferCodes',id:env.APPLE_OFFER_ID}}}}})).data; }
                    catch { continue; }
                }
                if (!remote) continue;
                if (code.status === 'disabling') {
                    await apple(env, 'subscriptionOfferCodeCustomCodes/' + remote.id, 'PATCH', {data:{type:'subscriptionOfferCodeCustomCodes',id:remote.id,attributes:{active:false}}});
                }
                await env.DB.prepare('UPDATE partner_codes SET apple_id=?,status=? WHERE code=?').bind(remote.id,code.status==='disabling'||remote.attributes.active===false?'disabled':'active',code.code).run();
            }
        }
    }
    if (!env.IAP_PRIVATE_KEY || !env.IAP_KEY_ID || !env.ASC_ISSUER) return;
    const token=await appleToken({keyId:env.IAP_KEY_ID,issuer:env.ASC_ISSUER,privateKey:env.IAP_PRIVATE_KEY,bundleId:env.BUNDLE_ID});
    const rows = (await env.DB.prepare('SELECT * FROM partner_sync ORDER BY checked LIMIT 20').all()).results;
    for (const row of rows) {
        try {
            const query=row.revision?'?revision='+encodeURIComponent(row.revision):'';
            const response=await fetch('https://api.storekit.apple.com/inApps/v2/history/'+encodeURIComponent(row.original)+query,{headers:{Authorization:'Bearer '+token}});
            if(!response.ok)throw new Error('apple_history_request_failed');
            const history=await response.json();
            for (const signed of history.signedTransactions || []) await storeTransaction(await decodeTransaction(signed,env),env);
            await env.DB.prepare('UPDATE partner_sync SET revision=?,checked=? WHERE original=?').bind(history.revision,history.hasMore?0:now(),row.original).run();
        } catch { console.error('partner_transaction_reconciliation_failed'); }
    }
}
