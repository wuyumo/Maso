export const products = new Set(['com.yumowu.maso.pro.monthly','com.yumowu.maso.pro.yearly']);
export function normalizeCode(value) {
  const code=String(value||'').trim().toUpperCase();
  if(!/^[A-Z][A-Z0-9]{3,19}$/.test(code)||/^(MASSO|APPLE|ADMIN|SUPPORT|TEST)/.test(code)) throw new Error('invalid_code');
  return code;
}
export function normalizeTransaction(t, now=Date.now()) {
  if(!products.has(t.productId)||!['Production','Sandbox'].includes(t.environment)||!t.transactionId||!t.originalTransactionId||!Number.isFinite(t.purchaseDate)||t.purchaseDate>now+300000)throw new Error('invalid_transaction');
  return {id:t.transactionId,original:t.originalTransactionId,environment:t.environment,product:t.productId,purchased:t.purchaseDate,expires:t.expiresDate??null,revoked:t.revocationDate??null,trial:t.offerDiscountType==='FREE_TRIAL'?1:0,amount:Number.isInteger(t.price)?t.price:null,currency:t.currency??null,token:t.appAccountToken?.toLowerCase()??null,offer:t.offerIdentifier??null};
}
export function canAttribute(t,claim,device,offer,now=Date.now(),environment='Production') {
  if(!['Production','Sandbox'].includes(environment)||!claim||t.environment!==environment||t.revoked||t.purchased<claim.created||now-claim.created>30*86400000)return false;
  return t.token===device || (!!offer && t.offer===offer);
}
export function calculateCommission(netMinor,bps) {
  if(!Number.isSafeInteger(netMinor)||netMinor<0||!Number.isInteger(bps)||bps<0||bps>10000)throw new Error('invalid_amount');
  return Math.floor(netMinor*bps/10000);
}
// Counts people by their first subscription chain; renewals never create another acquisition.
export function summarize(rows,now=Date.now()) {
  const chains=new Map();
  for(const t of rows){if(t.environment!=='Production')continue;const a=chains.get(t.original)||[];a.push(t);chains.set(t.original,a);}
  const result={attributed:chains.size,trialing:0,paid:0,refunded:0,active:0,monthly:0,yearly:0,monthlyPaid:0,yearlyPaid:0,monthlyTrialing:0,yearlyTrialing:0,maturedTrials:0,convertedTrials:0};
  for(const list of chains.values()){
    list.sort((a,b)=>a.purchased-b.purchased||a.id.localeCompare(b.id));const first=list[0],latest=list.at(-1);
    const charged=list.filter(t=>!t.trial&&t.amount>0&&!t.revoked);
    if(charged.length){result.paid++;result[charged[0].product.endsWith('yearly')?'yearlyPaid':'monthlyPaid']++;}
    if(list.some(t=>t.revoked))result.refunded++;
    if(!latest.revoked&&latest.expires>now){result.active++;if(latest.trial){result.trialing++;result[latest.product.endsWith('yearly')?'yearlyTrialing':'monthlyTrialing']++;}result[latest.product.endsWith('yearly')?'yearly':'monthly']++;}
    if(first.trial&&first.expires<=now){result.maturedTrials++;if(charged.length)result.convertedTrials++;}
  }
  result.trialConversion=result.maturedTrials?result.convertedTrials/result.maturedTrials:null;
  return result;
}
