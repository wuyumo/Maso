const $=id=>document.getElementById(id);let policy,email,name,acceptedTerms=false;
for(const [value,label]of Object.entries(offeredLanguages)){const o=document.createElement('option');o.value=value;o.textContent=label;$('language').append(o);}$('language').value=partnerLang;
$('language').onchange=()=>{localStorage.setItem('partner-language',$('language').value);const u=new URL(location.href);u.searchParams.set('lang',$('language').value);location.assign(u);};localize();
async function api(path,body){const r=await fetch('/api/'+path,{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json'}:{},body:body?JSON.stringify(body):undefined});const d=await r.json();if(!r.ok)throw Error(d.error||'request_failed');return d;}
function say(s){$('message').textContent=s;}
function el(tag,text){const n=document.createElement(tag);n.textContent=text;return n;}
function button(key,fn){const b=el('button',tr(key));b.type='button';b.className='secondary';b.onclick=()=>run(b,fn);return b;}
async function run(b,fn){b.disabled=true;say('');try{await fn();}catch(e){say(errorText(e));}finally{b.disabled=false;}}
function errorText(e){const key={registration_not_ready:'closed',campaign_not_ready:'closed',code_taken_or_limit:'codeConflict',invalid_or_expired_code:'otpInvalid',rate_limited:'rateLimited'}[e.message];return tr(key||'failed');}
$('login').onsubmit=e=>{e.preventDefault();const f=new FormData(e.target);email=f.get('email');name=f.get('name');run(e.submitter,async()=>{await api('login',{email});$('verify').hidden=false;say(tr('sent'));});};
$('verify').onsubmit=e=>{e.preventDefault();run(e.submitter,async()=>{await api('login/verify',{email,name,otp:new FormData(e.target).get('otp')});await dashboard();});};
$('logout').onclick=e=>run(e.target,async()=>{await api('logout',{});location.assign('/');});
$('refresh').onclick=e=>run(e.target,dashboard);
$('create').onsubmit=e=>{e.preventDefault();const f=new FormData(e.target);run(e.submitter,async()=>{if(!f.get('terms')&&!acceptedTerms)throw Error('terms_required');await api('codes',{code:f.get('code'),acceptTerms:!!f.get('terms')});e.target.reset();await dashboard();});};
async function dashboard(){
 const d=await api('dashboard');acceptedTerms=d.acceptedTerms;const consent=$('create').querySelector('[name=terms]');consent.required=!acceptedTerms;consent.closest('label').hidden=acceptedTerms;$('landing').hidden=true;$('dashboard').hidden=false;$('logout').hidden=false;$('greeting').textContent=tr('welcome')+', '+d.partner.name;$('updated').textContent=tr('synced')+' '+new Date(d.updatedAt).toLocaleString(partnerLang);
 const s=d.summary,bound=d.codes.reduce((a,c)=>a+c.bound,0);$('metrics').replaceChildren();const pct=n=>new Intl.NumberFormat(partnerLang,{style:'percent',maximumFractionDigits:1}).format(n);
 const metrics=[['attributed',s.attributed],['trialing',s.trialing],['paid',s.paid],['monthlyTrial',s.monthlyTrialing],['yearlyTrial',s.yearlyTrialing],['monthlyPaid',s.monthlyPaid],['yearlyPaid',s.yearlyPaid],['monthlyActive',s.monthly],['yearlyActive',s.yearly],['refunded',s.refunded],['referralPaid',bound?pct(s.paid/bound):'—'],['trialPaid',s.trialConversion===null?'—':pct(s.trialConversion)]];
 for(const [label,value]of metrics){const m=el('div','');m.className='metric';m.append(el('strong',typeof value==='number'?value.toLocaleString(partnerLang):value),el('span',tr(label)));$('metrics').append(m);}
 $('codes').replaceChildren();for(const c of d.codes){const box=el('article','');box.className='code';const link=location.origin+'/r/'+c.code;const h=el('h3',c.code);h.dir='ltr';const url=el('p',link);url.dir='ltr';box.append(h,el('p',`${tr('status')}: ${tr(c.status)} · ${tr('visits')}: ${c.visits.toLocaleString(partnerLang)} · ${tr('bindings')}: ${c.bound.toLocaleString(partnerLang)}`),url);
 if(c.status==='active'){const qr=document.createElement('img');qr.src='/qr/'+c.code+'.svg';qr.alt=tr('code')+' '+c.code;qr.width=180;qr.height=180;box.append(qr);box.append(button('copy',async()=>{await navigator.clipboard.writeText(c.code);say(tr('copied'));}),button('share',async()=>{await navigator.clipboard.writeText(link);say(tr('copied'));}),button('disable',async()=>{if(confirm(tr('disableAsk'))){await api('codes/status',{code:c.code,status:'disabled'});await dashboard();}}));}
 if(c.status==='creating'||c.status==='disabling')box.append(button('refresh',dashboard));
 if(c.status==='disabling')box.append(button('retry',async()=>{await api('codes/status',{code:c.code,status:'disabled'});await dashboard();}));
 if(['disabled','failed'].includes(c.status))box.append(button('archive',async()=>{await api('codes/status',{code:c.code,status:'archived'});await dashboard();}));$('codes').append(box);}
 $('settlements').replaceChildren();if(!d.settlements.length)$('settlements').append(el('p',tr('empty')));
 for(const s of d.settlements){const status=tr(s.status==='paid'?'paidStatus':s.status==='refund adjustment'?'adjustment':s.status);$('settlements').append(el('p',`${new Date(s.created).toLocaleDateString(partnerLang)} · ${new Intl.NumberFormat(partnerLang,{style:'currency',currency:s.currency}).format(s.commission_minor/100)} · ${status}`));}
 $('create').querySelector('button').disabled=!policy.campaignReady&&!d.pilot;
}
async function start(){try{policy=await api('policy');$('policy').textContent=tr('offer')+' '+tr('commission')+' '+(policy.registrationOpen?'':tr('closed'));
 if(location.pathname.startsWith('/r/')){const code=decodeURIComponent(location.pathname.slice(3));$('landing').hidden=true;$('referral').hidden=false;$('public-code').textContent=code;$('copy-public').onclick=e=>run(e.target,()=>navigator.clipboard.writeText(code));return;}
 $('login').querySelector('button').disabled=!policy.registrationOpen&&!new URLSearchParams(location.search).has('pilot');try{await dashboard();}catch(e){if(e.message!=='sign_in_required')throw e;}
 }catch(e){say(errorText(e));}}
start();
