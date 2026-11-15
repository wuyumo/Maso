import { catalog } from './catalog.mjs';
const PREFIX='/v1/exercise-demos';
const VERSION='single-model07-env03-v2';
const MAX_VIDEO=25*1024*1024;
const now=()=>Math.floor(Date.now()/1000);
const response=(x,status=200)=>Response.json(x,{status,headers:{'Cache-Control':'no-store'}});
const hash=async s=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',typeof s==='string'?new TextEncoder().encode(s):s))).map(x=>x.toString(16).padStart(2,'0')).join('');
const safeEqual=(a,b)=>typeof a==='string'&&typeof b==='string'&&a.length>=32&&a.length===b.length&&[...a].reduce((n,c,i)=>n|(c.charCodeAt(0)^b.charCodeAt(i)),0)===0;
async function body(req){const t=await req.text();if(t.length>2048)throw new Error('bad_request');try{return JSON.parse(t)}catch{throw new Error('bad_request')}}
function assetKey(id){return `${VERSION}:${id}`}
function cost(env){const n=Number(env.DEMO_CREDIT_COST);return Number.isSafeInteger(n)&&n>0&&n<=100000?n:null}
function enabled(env){return env.DEMO_GENERATION_ENABLED==='true'&&env.DEMO_STYLE_APPROVED==='true'&&env.DEMO_GPU_READY==='true'&&!!env.DEMO_BUCKET&&!!cost(env)&&!!env.DEMO_GPU_TOKEN&&!!env.DEMO_REVIEW_TOKEN}
async function wallet(req,db){const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');if(!/^[A-Za-z0-9_-]{43,128}$/.test(token||''))return null;return db.prepare('SELECT * FROM demo_wallets WHERE token_hash=?').bind(await hash(token)).first()}
function walletView(w){return {walletId:w.id,balance:w.balance,held:w.held,available:w.balance-w.held}}
function jobView(j){return {jobId:j.id,exerciseId:j.exercise_id,status:j.status,failureCode:j.failure_code||null}}
async function current(db,id){return db.prepare("SELECT * FROM demo_jobs WHERE asset_key=? AND status!='failed'").bind(assetKey(id)).first()}
async function ready(db,id){return db.prepare('SELECT * FROM demo_assets WHERE asset_key=?').bind(assetKey(id)).first()}
function assetView(a){return {exerciseId:a.exercise_id,status:'ready',sha256:a.sha256,bytes:a.bytes,videoPath:`${PREFIX}/video/${a.sha256}`,version:VERSION,mediaType:a.blob_key.toLowerCase().endsWith('.gif')?'gif':'video'}}

// Called by both gateways. D1 and video bytes have one canonical owner: the Worker.
export async function handleDemoRequest(req,env){
 const url=new URL(req.url);const start=url.pathname.indexOf(PREFIX);if(start<0)return null;
 const path=url.pathname.slice(start+PREFIX.length);
 const internal=path.startsWith('/internal/');
 if(internal){
  if(!env.FEEDBACK_DB)return response({error:'not_found'},404);
  const review=path.startsWith('/internal/review')||path.startsWith('/internal/import/')||path==='/internal/grant';
  const secret=review?env.DEMO_REVIEW_TOKEN:env.DEMO_GPU_TOKEN;
  if(!safeEqual(req.headers.get('Authorization')?.replace(/^Bearer /,''),secret))return response({error:'unauthorized'},401);
 }else if(!safeEqual(req.headers.get('X-Maso-Client-Token'),env.MASO_CLIENT_TOKEN))return response({error:'unauthorized'},401);
 if(!env.FEEDBACK_DB){
  // Fixed destination only. Never forward internal admin endpoints or browser credentials.
  if(internal||!['GET','POST'].includes(req.method))return response({error:'not_found'},404);
  const target='https://maso-ai.wuyumo.workers.dev'+PREFIX+path;
  const headers=new Headers({'X-Maso-Client-Token':env.MASO_CLIENT_TOKEN});
  for(const name of ['Authorization','Content-Type','Range'])if(req.headers.has(name))headers.set(name,req.headers.get(name));
  const raw=req.method==='POST'?await req.arrayBuffer():undefined;
  if(raw?.byteLength>2048)return response({error:'bad_request'},413);
  return fetch(target,{method:req.method,headers,body:raw,redirect:'error'});
 }
 const db=env.FEEDBACK_DB;
 try{
  if(path.startsWith('/internal/import/')&&req.method==='POST'){
   const id=path.slice('/internal/import/'.length);if(!catalog[id])return response({error:'unknown_exercise'},404);
   if(env.DEMO_STYLE_APPROVED!=='true'||!env.DEMO_BUCKET)return response({error:'service_not_ready'},503);
   if(req.headers.get('X-Demo-Reviewed')!=='technique,identity,crop,loop')return response({error:'review_incomplete'},400);
   const existing=await ready(db,id);if(existing)return response(assetView(existing));
   if(await current(db,id))return response({error:'active_job_exists'},409);
   const size=Number(req.headers.get('Content-Length'));if(!Number.isInteger(size)||size<1024||size>MAX_VIDEO)return response({error:'invalid_video'},413);
   const bytes=await req.arrayBuffer();if(bytes.byteLength!==size||new TextDecoder().decode(bytes.slice(4,8))!=='ftyp')return response({error:'invalid_video'},400);
   const sha=await hash(bytes);const key=`exercise-demos/${VERSION}/imports/${id}/${sha}.mp4`;
   await env.DEMO_BUCKET.put(key,bytes,{httpMetadata:{contentType:'video/mp4'}});
   // No wallet/job mutation: operator-supplied library assets never charge users.
   await db.prepare('INSERT OR IGNORE INTO demo_assets VALUES(?,?,?,?,?,?,?)').bind(assetKey(id),id,'import:'+assetKey(id),key,sha,size,now()).run();
   return response(assetView(await ready(db,id)));
  }
  if(path==='/catalog'&&req.method==='GET'){
   // Only the reviewed App-derived manifest may select ID/SHA pairs. demo_assets
   // retains historical versions and must never act as an approval list.
   if(!env.DEMO_BUCKET)return response({error:'catalog_unavailable'},503);
   const manifest=await env.DEMO_BUCKET.get('exercise-demos/catalog/approved-v1.json');
   if(!manifest)return response({error:'catalog_unavailable'},503);
   const data=await manifest.json();
   if(data?.version!==1||!Array.isArray(data.assets)||data.assets.length>2000)return response({error:'invalid_catalog'},503);
   return response(data);
  }
  if(path==='/config'&&req.method==='GET')return response({enabled:enabled(env),cost:cost(env),version:VERSION,reason:enabled(env)?null:'service_not_ready'});
  if(path==='/wallet'&&req.method==='POST'){
   const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');if(!/^[A-Za-z0-9_-]{43,128}$/.test(token||''))return response({error:'unauthorized'},401);
   const digest=await hash(token);await db.prepare('INSERT OR IGNORE INTO demo_wallets(id,token_hash,created_at) VALUES(?,?,?)').bind(crypto.randomUUID(),digest,now()).run();
   return response(walletView(await wallet(req,db)));
  }
  if(path.startsWith('/assets/')&&req.method==='GET'){
   const id=path.slice(8);if(!catalog[id])return response({error:'unknown_exercise'},404);
   const a=await ready(db,id);if(a)return response(assetView(a));
   const j=await current(db,id);return response(j?jobView(j):{exerciseId:id,status:catalog[id].core?'core_pending':'missing'});
  }
  if(path.startsWith('/video/')&&req.method==='GET'){
   const sha=path.slice(7);if(!/^[0-9a-f]{64}$/.test(sha))return response({error:'not_found'},404);
   const a=await db.prepare('SELECT * FROM demo_assets WHERE sha256=?').bind(sha).first();if(!a||!env.DEMO_BUCKET)return response({error:'not_found'},404);
   // Serve bounded byte ranges for AVPlayer and the primary gateway's response size limit.
   let offset=0,end=Math.min(a.bytes-1,1024*1024-1);const range=req.headers.get('Range');
   if(range){const m=/^bytes=(\d+)-(\d*)$/.exec(range);if(!m)return new Response(null,{status:416});offset=Number(m[1]);end=m[2]?Math.min(Number(m[2]),offset+1024*1024-1,a.bytes-1):Math.min(offset+1024*1024-1,a.bytes-1)}
   if(offset>=a.bytes||end<offset)return new Response(null,{status:416,headers:{'Content-Range':`bytes */${a.bytes}`}});
   const object=await env.DEMO_BUCKET.get(a.blob_key,{range:{offset,length:end-offset+1}});if(!object)return response({error:'not_found'},404);
   const contentType=a.blob_key.toLowerCase().endsWith('.gif')?'image/gif':'video/mp4';
   return new Response(object.body,{status:206,headers:{'Content-Type':contentType,'Accept-Ranges':'bytes','Content-Range':`bytes ${offset}-${end}/${a.bytes}`,'Content-Length':String(end-offset+1),'Cache-Control':'private,max-age=86400','ETag':`"${sha}"`}});
  }
  if(path==='/quote'&&req.method==='POST'){
   const b=await body(req);const e=catalog[b.exerciseId];if(!e)return response({error:'unknown_exercise'},404);
   const w=await wallet(req,db);if(!w)return response({error:'unauthorized'},401);
   const a=await ready(db,e.id);if(a)return response({...assetView(a),cost:0,wallet:walletView(w)});
   const j=await current(db,e.id);if(j)return response({...jobView(j),cost:0,wallet:walletView(w)});
   return response({exerciseId:e.id,status:e.core?'core_pending':'missing',enabled:enabled(env)&&!e.core,cost:cost(env),wallet:walletView(w),version:VERSION});
  }
  if(path==='/jobs'&&req.method==='POST'){
   const b=await body(req);const e=catalog[b.exerciseId];if(!e)return response({error:'unknown_exercise'},404);
   const w=await wallet(req,db);if(!w)return response({error:'unauthorized'},401);
   const a=await ready(db,e.id);if(a)return response(assetView(a));
   const existing=await current(db,e.id);if(existing)return response(jobView(existing));
   if(!enabled(env)||e.core)return response({error:'service_not_ready'},503);
   if(b.version!==VERSION||b.acceptedCost!==cost(env)||b.shareConsent!==true)return response({error:'quote_changed'},409);
   const id=crypto.randomUUID();
   try{await db.prepare('INSERT INTO demo_jobs(id,asset_key,exercise_id,recipe_json,wallet_id,cost,status,created_at,updated_at) VALUES(?,?,?,?,?,?,\'queued\',?,?)').bind(id,assetKey(e.id),e.id,JSON.stringify({recipe:e,style:VERSION,model:'MODEL-07-photo-v1',scene:'ENV-03',sourceInstructions:'requires_technique_verification',composition:{size:[1280,1280],safeRect:[.23,.23,.54,.54]},referenceContract:'Masso-core100/generation-contract.json'}),w.id,cost(env),now(),now()).run()}
   catch(err){const duplicate=await current(db,e.id);if(duplicate)return response(jobView(duplicate));if(String(err).includes('insufficient_credits'))return response({error:'insufficient_credits'},402);throw err}
   return response({jobId:id,exerciseId:e.id,status:'queued'},202);
  }
  if(path.startsWith('/jobs/')&&req.method==='GET'){
   const w=await wallet(req,db);if(!w)return response({error:'unauthorized'},401);
   const j=await db.prepare('SELECT * FROM demo_jobs WHERE id=?').bind(path.slice(6)).first();if(!j)return response({error:'not_found'},404);
   // Global canonical task is observable, never expose sponsor or billing data.
   const a=j.status==='ready'?await ready(db,j.exercise_id):null;
   return response({...jobView(j),...(a?assetView(a):{}),wallet:walletView(w)});
  }
  if(path==='/internal/claim'&&req.method==='POST'){
   if(!enabled(env))return response({error:'service_not_ready'},503);
   await expireDemoJobs(env);
   const claim=crypto.randomUUID();const n=now();
   const j=await db.prepare("UPDATE demo_jobs SET status='running',claim_token=?,lease_until=?,updated_at=? WHERE id=(SELECT id FROM demo_jobs WHERE status='queued' ORDER BY created_at LIMIT 1) AND status='queued' RETURNING *").bind(claim,n+900,n).first();
   return response(j?{...jobView(j),claimToken:claim,recipe:JSON.parse(j.recipe_json),leaseUntil:j.lease_until}: {jobId:null});
  }
  const match=/^\/internal\/jobs\/([a-f0-9-]{36})\/(heartbeat|upload|fail)$/.exec(path);
  if(match&&req.method==='POST'){
   const j=await db.prepare('SELECT * FROM demo_jobs WHERE id=?').bind(match[1]).first();const claim=req.headers.get('X-Demo-Claim');
   if(!j||j.status!=='running'||claim!==j.claim_token||j.lease_until<now())return response({error:'stale_claim'},409);
   if(match[2]==='heartbeat'){await db.prepare("UPDATE demo_jobs SET lease_until=?,updated_at=? WHERE id=? AND status='running' AND claim_token=?").bind(now()+900,now(),j.id,claim).run();return response({ok:true})}
   if(match[2]==='fail'){await db.prepare("UPDATE demo_jobs SET status='failed',failure_code='generation_failed',updated_at=? WHERE id=? AND status='running' AND claim_token=?").bind(now(),j.id,claim).run();return response({ok:true})}
   if(!env.DEMO_BUCKET)return response({error:'service_not_ready'},503);
   const size=Number(req.headers.get('Content-Length'));if(!Number.isInteger(size)||size<1024||size>MAX_VIDEO)return response({error:'invalid_video'},413);
   const bytes=await req.arrayBuffer();if(bytes.byteLength!==size||new TextDecoder().decode(bytes.slice(4,8))!=='ftyp')return response({error:'invalid_video'},400);
   const sha=await hash(bytes);const key=`exercise-demos/${VERSION}/${j.id}/${sha}.mp4`;
   await env.DEMO_BUCKET.put(key,bytes,{httpMetadata:{contentType:'video/mp4'}});
   const result=await db.prepare("UPDATE demo_jobs SET status='review',blob_key=?,sha256=?,bytes=?,updated_at=? WHERE id=? AND status='running' AND claim_token=? AND lease_until>=?").bind(key,sha,size,now(),j.id,claim,now()).run();
   if(!result.meta.changes){await env.DEMO_BUCKET.delete(key);return response({error:'stale_claim'},409)}
   return response({jobId:j.id,status:'review'});
  }
  if(path==='/internal/review'&&req.method==='POST'){
   const b=await body(req);const j=await db.prepare('SELECT * FROM demo_jobs WHERE id=?').bind(b.jobId||'').first();if(!j)return response({error:'not_found'},404);
   if(j.status==='ready'||j.status==='failed')return response(jobView(j));
   if(j.status!=='review')return response({error:'invalid_state'},409);
   if(b.approve===true){
    if(b.techniqueVerified!==true||b.identityVerified!==true||b.cropVerified!==true||b.loopVerified!==true)return response({error:'review_incomplete'},400);
    if(!await env.DEMO_BUCKET?.head(j.blob_key))return response({error:'invalid_video'},400);
    await db.prepare("UPDATE demo_jobs SET status='ready',updated_at=? WHERE id=? AND status='review'").bind(now(),j.id).run();
   }else if(b.approve===false){await db.prepare("UPDATE demo_jobs SET status='failed',failure_code='review_rejected',updated_at=? WHERE id=? AND status='review'").bind(now(),j.id).run()}
   else return response({error:'bad_request'},400);
   return response(jobView(await db.prepare('SELECT * FROM demo_jobs WHERE id=?').bind(j.id).first()));
  }
  if(path==='/internal/grant'&&req.method==='POST'){
   const b=await body(req);if(!/^[a-zA-Z0-9_-]{8,100}$/.test(b.reference||'')||!Number.isSafeInteger(b.amount)||b.amount<1||b.amount>100000)return response({error:'bad_request'},400);
   const w=await db.prepare('SELECT * FROM demo_wallets WHERE id=?').bind(b.walletId||'').first();if(!w)return response({error:'not_found'},404);
   // A unique verified grant reference is mandatory; retries never mint twice.
   await db.batch([db.prepare("INSERT OR IGNORE INTO demo_ledger(id,wallet_id,kind,amount,created_at) VALUES(?,?,'grant',?,?)").bind('grant:'+b.reference,w.id,b.amount,now()),db.prepare('UPDATE demo_wallets SET balance=balance+? WHERE id=? AND changes()=1').bind(b.amount,w.id)]);
   return response(walletView(await db.prepare('SELECT * FROM demo_wallets WHERE id=?').bind(w.id).first()));
  }
  return response({error:'not_found'},404);
 }catch(e){if(String(e).includes('bad_request'))return response({error:'bad_request'},400);console.error('demo_service_error',String(e).replace(/[A-Za-z0-9_-]{40,}/g,'[redacted]').slice(0,200));return response({error:'temporarily_unavailable'},503)}
}
export async function expireDemoJobs(env){if(!env.FEEDBACK_DB)return;const n=now();await env.FEEDBACK_DB.prepare("UPDATE demo_jobs SET status='failed',failure_code='generation_expired',updated_at=? WHERE (status='queued' AND created_at<?) OR (status='running' AND lease_until<?) OR (status='review' AND updated_at<?)").bind(n,n-86400,n,n-259200).run()}
