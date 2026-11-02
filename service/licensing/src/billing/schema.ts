export type ObjectValue=Record<string,any>;
export const MAX=253402300799;
export function closed(x:unknown,keys:readonly string[]):x is ObjectValue {
 if(!x||typeof x!=='object'||Array.isArray(x)||Object.getPrototypeOf(x)!==Object.prototype||Reflect.ownKeys(x).length!==keys.length)return false;
 return keys.every(k=>{const d=Object.getOwnPropertyDescriptor(x,k);return !!d&&Object.hasOwn(d,'value');});
}
export const time=(x:unknown):x is number=>typeof x==='number'&&Number.isSafeInteger(x)&&x>=0&&!Object.is(x,-0)&&x<=MAX;
export const generation=(x:unknown):x is number=>typeof x==='number'&&Number.isSafeInteger(x)&&x>=1;
export const identity=(x:unknown):x is string=>typeof x==='string'&&/^[a-f0-9]{32}$/.test(x)&&x!=='0'.repeat(32);
export const digest=(x:unknown):x is string=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
export const entityID=(x:unknown,kind:string):x is string=>typeof x==='string'&&new RegExp('^'+kind+'_fixture_[A-Za-z0-9-]{1,48}$').test(x);
export function C(value:any):string {
 if(Array.isArray(value))return '['+value.map(C).join(',')+']';
 if(value!==null&&typeof value==='object')return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+C(value[k])).join(',')+'}';
 return JSON.stringify(value);
}
// Synchronous SHA256 is necessary for this pure synchronous API. Uint32 words
// and explicit byte padding implement SHA256 over the closed canonical UTF8.
export function sha(text:string):string {
 const input=new TextEncoder().encode(text),size=Math.ceil((input.length+9)/64)*64,b=new Uint8Array(size);b.set(input);b[input.length]=128;
 const dv=new DataView(b.buffer),bits=input.length*8;dv.setUint32(size-8,Math.floor(bits/4294967296));dv.setUint32(size-4,bits>>>0);
 const k=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
 const h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19],w=new Uint32Array(64),ro=(n:number,s:number)=>(n>>>s)|(n<<(32-s));
 for(let start=0;start<size;start+=64){
  for(let i=0;i<16;i++)w[i]=dv.getUint32(start+i*4);
  for(let i=16;i<64;i++){const x=w[i-15],y=w[i-2];w[i]=(w[i-16]+(ro(x,7)^ro(x,18)^(x>>>3))+w[i-7]+(ro(y,17)^ro(y,19)^(y>>>10)))>>>0;}
  let [a,c,d,e,f,g,j,l]=h;
  for(let i=0;i<64;i++){const t=(l+(ro(f,6)^ro(f,11)^ro(f,25))+((f&g)^(~f&j))+k[i]+w[i])>>>0,u=((ro(a,2)^ro(a,13)^ro(a,22))+((a&c)^(a&d)^(c&d)))>>>0;l=j;j=g;g=f;f=(e+t)>>>0;e=d;d=c;c=a;a=(t+u)>>>0;}
  [a,c,d,e,f,g,j,l].forEach((v,i)=>h[i]=(h[i]+v)>>>0);
 }
 return h.map(n=>n.toString(16).padStart(8,'0')).join('');
}
export const H=(domain:string,tuple:any[])=>sha(domain+'\0'+C(tuple));
export function terms(x:any):boolean{return ['GBP','USD'].includes(x.currency)&&x.priceID===(x.currency==='GBP'?'fixture-price-gbp-annual':'fixture-price-usd-annual')&&x.quantity===1&&x.unitAmount===1999&&x.taxInclusive===true;}
export function interval(x:any):boolean{return closed(x,['startsAt','endsAt'])&&time(x.startsAt)&&time(x.endsAt)&&x.startsAt<x.endsAt;}
export function charge(x:any):boolean {
 return closed(x,['kind','reason'])&&x.kind==='unavailable'&&['absent','contradictory'].includes(x.reason)||closed(x,['kind','at','priceID','currency','quantity','unitAmount','taxInclusive','evidenceSHA256'])&&x.kind==='known'&&time(x.at)&&terms(x)&&digest(x.evidenceSHA256);
}
export function subscription(s:any):boolean {
 return closed(s,['id','bindingID','updatedAt','status','renewalGeneration','currentPeriod','cancellation','nextCharge'])&&entityID(s.id,'sub')&&entityID(s.bindingID,'bind')&&time(s.updatedAt)&&generation(s.renewalGeneration)&&['active','pastDue','cancelled'].includes(s.status)&&charge(s.nextCharge)&&closed(s.cancellation,['state','effectiveAt'])&&(s.cancellation.state==='none'&&s.cancellation.effectiveAt===null||['scheduled','effective'].includes(s.cancellation.state)&&time(s.cancellation.effectiveAt))&&(s.currentPeriod===null||closed(s.currentPeriod,['transactionID','startsAt','endsAt'])&&entityID(s.currentPeriod.transactionID,'txn')&&time(s.currentPeriod.startsAt)&&time(s.currentPeriod.endsAt)&&s.currentPeriod.startsAt<s.currentPeriod.endsAt);
}
export function snapshot(x:any,now:number):boolean {
 if(!closed(x,['fixture','environment','subscription','transactions','adjustments','disputes'])||x.fixture!=='PAT-2646-snapshot-v1'||x.environment!=='synthetic-sandbox'||!subscription(x.subscription)||x.subscription.updatedAt>now)return false;
 for(const [field,kind] of [['transactions','txn'],['adjustments','adj'],['disputes','dsp']]){
  if(!Array.isArray(x[field])||new Set(x[field].map((r:any)=>r?.id)).size!==x[field].length)return false;
  for(const r of x[field]){
   if(!entityID(r?.id,kind)||!time(r.updatedAt)||r.updatedAt>now)return false;
   if(field==='transactions'){
    if(!closed(r,['id','subscriptionID','bindingID','updatedAt','status','origin','period','priceID','currency','quantity','unitAmount','taxInclusive'])||!entityID(r.subscriptionID,'sub')||!entityID(r.bindingID,'bind')||!['completed','pending','failed'].includes(r.status)||!['existing','renewal'].includes(r.origin)||!interval(r.period)||!terms(r))return false;
   }else if(field==='adjustments'){
    if(!closed(r,['id','transactionID','updatedAt','kind','status','amount','currency','coverage'])||!entityID(r.transactionID,'txn')||!['refund','chargeback'].includes(r.kind)||!['pending','approved','rejected','reversed'].includes(r.status)||!['GBP','USD'].includes(r.currency)||!Number.isSafeInteger(r.amount)||!(r.coverage==='full'&&r.amount===1999||r.coverage==='partial'&&r.amount>0&&r.amount<1999))return false;
   }else if(!closed(r,['id','transactionID','updatedAt','state'])||!entityID(r.transactionID,'txn')||!['warning','open','customerWon','confirmedLoss'].includes(r.state))return false;
  }
 }
 return true;
}

export const columns:Record<string,readonly string[]>={"billing_subscription":["environment","subscription_id","account_id","binding_id","mapping_revision","revision","provider_updated_at","canonical_sha256","canonical_json","status","cancellation_state","cancellation_effective_at","renewal_generation","notice_revision","next_charge_json","commit_nonce"],"billing_existing_transaction":["environment","subscription_id","account_id","transaction_id","commit_nonce"],"billing_reconcile":["environment","subscription_id","account_id","wanted","done","claim_generation","claimed_wanted","claim_fence","claim_expires_at","read_generation","failures","commit_nonce"],"billing_event_consumed":["environment","event_id","subscription_id","account_id","event_sha256","wanted","commit_nonce"],"billing_snapshot":["environment","subscription_id","account_id","read_generation","claim_generation","claimed_wanted","fence","read_started_at","read_finished_at","canonical_sha256","canonical_json","commit_nonce"],"billing_entity_version":["environment","subscription_id","account_id","entity_kind","entity_id","updated_at","read_generation","canonical_sha256","canonical_json","commit_nonce"],"billing_period":["environment","subscription_id","account_id","transaction_id","starts_at","ends_at","price_id","currency","quantity","unit_amount","tax_inclusive","origin","commit_nonce"],"billing_period_end":["environment","subscription_id","account_id","transaction_id","adjustment_id","reason","ended_at","commit_nonce"],"billing_restoration":["environment","subscription_id","account_id","transaction_id","chargeback_id","reversal_evidence_sha256","confirmation_id","restored_at","original_ends_at","commit_nonce"],"billing_adjustment":["environment","subscription_id","account_id","adjustment_id","transaction_id","kind","coverage","amount","currency","status","updated_at","evidence_sha256","commit_nonce"],"billing_dispute":["environment","subscription_id","account_id","dispute_id","transaction_id","state","updated_at","evidence_sha256","commit_nonce"],"billing_grace":["environment","subscription_id","account_id","anchor_transaction_id","original_paid_through","anchor_source_sha256","deadline","created_at","failed_transaction_id","failure_read_generation","commit_nonce"],"billing_grace_void":["environment","subscription_id","account_id","anchor_transaction_id","original_paid_through","reason","evidence_sha256","voided_at","commit_nonce"],"billing_renewal_stop":["environment","subscription_id","account_id","renewal_generation","state","dispatch_id","claimed_at","confirmation_sha256","revision","commit_nonce"],"billing_stop_cause":["environment","subscription_id","account_id","renewal_generation","cause_kind","cause_id","state","evidence_sha256","acknowledgement_json","commit_nonce"],"billing_lifecycle_request":["account_id","operation","request_id","environment","subscription_id","request_sha256","result_json","created_at","commit_nonce"],"billing_review_confirmation":["confirmation_id","operator_id","operator_session_id","account_id","environment","subscription_id","transaction_id","chargeback_id","reversal_evidence_sha256","original_ends_at","account_revision","subscription_revision","authenticated_at","expires_at","consumed_at","commit_nonce"],"billing_lifecycle_commit":["commit_nonce","account_id","environment","subscription_id","operation","account_revision","source_delta","manifest_sha256","complete"]};
export function ledgerValid(l:any):boolean {
 if(!closed(l,['environment','account','entitlementSources',...Object.keys(columns)])||l.environment!=='synthetic-sandbox'||!closed(l.account,['accountID','revokedAt','entitlementRevision'])||!identity(l.account.accountID)||l.account.revokedAt!==null&&!time(l.account.revokedAt)||!Number.isSafeInteger(l.account.entitlementRevision)||l.account.entitlementRevision<0||!closed(l.entitlementSources,['accountID','trialStartedAt','trialEndsAt','betaInvited','betaEndsAt'])||l.entitlementSources.accountID!==l.account.accountID||typeof l.entitlementSources.betaInvited!=='boolean')return false;
 const es=l.entitlementSources;
 if(es.betaEndsAt!==null&&!time(es.betaEndsAt)||!(es.trialStartedAt===null&&es.trialEndsAt===null||time(es.trialStartedAt)&&time(es.trialEndsAt)&&es.trialEndsAt===es.trialStartedAt+1209600))return false;
 for(const [table,fields] of Object.entries(columns)){
  if(!Array.isArray(l[table]))return false;
  for(const r of l[table]){
   if(!closed(r,fields)||r.account_id!==l.account.accountID||r.environment!=='synthetic-sandbox'||!identity(r.commit_nonce))return false;
   for(const key of fields){const v=r[key];if(v===null)continue;
    if(['canonical_sha256','evidence_sha256','event_sha256','reversal_evidence_sha256','anchor_source_sha256','confirmation_sha256','request_sha256','manifest_sha256'].includes(key)&&!digest(v))return false;
    if(key==='subscription_id'&&!entityID(v,'sub')||key==='binding_id'&&!entityID(v,'bind')||['transaction_id','anchor_transaction_id','failed_transaction_id'].includes(key)&&!entityID(v,'txn')||['adjustment_id','chargeback_id'].includes(key)&&!entityID(v,'adj')||key==='dispute_id'&&!entityID(v,'dsp'))return false;
    if(/(_at|_through|deadline|starts_at|ends_at|original_ends_at)$/.test(key)&&!time(v))return false;
    if(typeof v==='number'&&(!Number.isSafeInteger(v)||v<0))return false;
   }
   if(Object.hasOwn(r,'canonical_json')){let decoded;try{decoded=JSON.parse(r.canonical_json);}catch{return false;}if(C(decoded)!==r.canonical_json||sha(r.canonical_json)!==r.canonical_sha256)return false;}
   if(Object.hasOwn(r,'subscription_id')&&!l.billing_subscription.some((s:any)=>s.subscription_id===r.subscription_id))return false;
  }
 }
 if(l.billing_subscription.length>8)return false;
 const ids=new Set();
 for(const s of l.billing_subscription){if(ids.has(s.subscription_id)||!generation(s.revision)||!generation(s.notice_revision)||!generation(s.mapping_revision)||!generation(s.renewal_generation))return false;ids.add(s.subscription_id);const p=JSON.parse(s.canonical_json);if(!subscription(p)||p.id!==s.subscription_id||p.bindingID!==s.binding_id||p.renewalGeneration!==s.renewal_generation||p.updatedAt!==s.provider_updated_at||p.status!==s.status||C(p.nextCharge)!==s.next_charge_json)return false;if(s.cancellation_state!==p.cancellation.state&&!(s.cancellation_state==='requested'&&p.cancellation.state==='none'))return false;}
 for(const p of l.billing_period){if(!time(p.starts_at)||!time(p.ends_at)||p.starts_at>=p.ends_at||!terms({priceID:p.price_id,currency:p.currency,quantity:p.quantity,unitAmount:p.unit_amount,taxInclusive:p.tax_inclusive===1})||!['existing','renewal'].includes(p.origin))return false;}
 for(const g of l.billing_grace){const p=l.billing_period.find((p:any)=>p.transaction_id===g.anchor_transaction_id&&p.subscription_id===g.subscription_id),s=l.billing_subscription.find((s:any)=>s.subscription_id===g.subscription_id);if(!p||g.original_paid_through!==p.ends_at||g.deadline!==p.ends_at+604800||g.deadline>MAX||g.anchor_source_sha256!==H('PAT-2646-grace-anchor-v1',[l.environment,l.account.accountID,s.subscription_id,s.binding_id,p.transaction_id,p.starts_at,p.ends_at,p.price_id,p.currency,p.quantity,p.unit_amount,true]))return false;}

 for(const [table,pk] of Object.entries({billing_subscription:['subscription_id'],billing_existing_transaction:['transaction_id'],billing_reconcile:['subscription_id'],billing_event_consumed:['event_id'],billing_snapshot:['subscription_id','read_generation'],billing_entity_version:['subscription_id','entity_kind','entity_id'],billing_period:['transaction_id'],billing_period_end:['transaction_id'],billing_restoration:['transaction_id','chargeback_id'],billing_adjustment:['adjustment_id'],billing_dispute:['dispute_id'],billing_grace:['subscription_id','original_paid_through'],billing_grace_void:['subscription_id','original_paid_through'],billing_renewal_stop:['subscription_id','renewal_generation'],billing_stop_cause:['subscription_id','renewal_generation','cause_kind','cause_id'],billing_lifecycle_request:['operation','request_id'],billing_review_confirmation:['confirmation_id'],billing_lifecycle_commit:['commit_nonce']})){const keys=l[table].map((r:any)=>C(pk.map(k=>r[k])));if(new Set(keys).size!==keys.length)return false;}
 for(const r of l.billing_reconcile)if(!Number.isSafeInteger(r.wanted)||!Number.isSafeInteger(r.done)||r.done>r.wanted||!Number.isSafeInteger(r.claim_generation)||!Number.isSafeInteger(r.read_generation)||![0,1,2,3].includes(r.failures)||!(r.claim_fence===null&&r.claimed_wanted===null&&r.claim_expires_at===null||identity(r.claim_fence)&&r.claim_fence!=='0'.repeat(32)&&generation(r.claimed_wanted)&&r.claimed_wanted<=r.wanted&&time(r.claim_expires_at)))return false;
 for(const r of l.billing_snapshot){if(!generation(r.read_generation)||!generation(r.claim_generation)||!generation(r.claimed_wanted)||!identity(r.fence)||r.read_started_at>r.read_finished_at||!snapshot(JSON.parse(r.canonical_json),r.read_finished_at))return false;const x=JSON.parse(r.canonical_json),sub=l.billing_subscription.find((s:any)=>s.subscription_id===r.subscription_id);if(x.subscription.id!==r.subscription_id||x.subscription.bindingID!==sub.binding_id)return false;}
 for(const r of l.billing_entity_version){const value=JSON.parse(r.canonical_json),sub=l.billing_subscription.find((s:any)=>s.subscription_id===r.subscription_id);if(!generation(r.read_generation)||!['subscription','transaction','adjustment','dispute'].includes(r.entity_kind)||value.id!==r.entity_id||value.updatedAt!==r.updated_at)return false;const x={fixture:'PAT-2646-snapshot-v1',environment:l.environment,subscription:JSON.parse(sub.canonical_json),transactions:[],adjustments:[],disputes:[]} as any;if(r.entity_kind==='subscription')x.subscription=value;else x[r.entity_kind==='transaction'?'transactions':r.entity_kind==='adjustment'?'adjustments':'disputes']=[value];if(!snapshot(x,MAX))return false;}
 for(const r of l.billing_adjustment){const p=l.billing_period.find((p:any)=>p.subscription_id===r.subscription_id&&p.transaction_id===r.transaction_id),sub=l.billing_subscription.find((s:any)=>s.subscription_id===r.subscription_id);if(!p||r.currency!==p.currency||!['refund','chargeback'].includes(r.kind)||!['pending','approved','rejected','reversed'].includes(r.status)||!(r.coverage==='full'&&r.amount===1999||r.coverage==='partial'&&Number.isSafeInteger(r.amount)&&r.amount>0&&r.amount<1999)||r.kind==='chargeback'&&r.coverage!=='full')return false;const a={id:r.adjustment_id,transactionID:r.transaction_id,updatedAt:r.updated_at,kind:r.kind,status:r.status,amount:r.amount,currency:r.currency,coverage:r.coverage};if(r.evidence_sha256!==H('PAT-2646-adjustment-evidence-v1',[l.environment,l.account.accountID,r.subscription_id,sub.binding_id,a]))return false;}
 for(const r of l.billing_dispute){const sub=l.billing_subscription.find((s:any)=>s.subscription_id===r.subscription_id);if(!l.billing_period.some((p:any)=>p.subscription_id===r.subscription_id&&p.transaction_id===r.transaction_id)||!['warning','open','customerWon','confirmedLoss'].includes(r.state)||r.evidence_sha256!==H('PAT-2646-dispute-evidence-v1',[l.environment,l.account.accountID,r.subscription_id,sub.binding_id,{id:r.dispute_id,transactionID:r.transaction_id,updatedAt:r.updated_at,state:r.state}]))return false;}
 for(const r of l.billing_period_end)if(!['refunded','charged_back'].includes(r.reason)||!l.billing_adjustment.some((a:any)=>a.subscription_id===r.subscription_id&&a.transaction_id===r.transaction_id&&a.adjustment_id===r.adjustment_id&&a.coverage==='full'&&['approved','reversed'].includes(a.status)&&a.kind===(r.reason==='refunded'?'refund':'chargeback')))return false;
 for(const r of l.billing_grace){const accepted=l.billing_snapshot.find((s:any)=>s.subscription_id===r.subscription_id&&s.read_generation===r.failure_read_generation);if(!accepted||r.created_at<accepted.read_finished_at)return false;const x=JSON.parse(accepted.canonical_json),failed=x.transactions.find((t:any)=>t.id===r.failed_transaction_id),anchor=x.transactions.find((t:any)=>t.id===r.anchor_transaction_id);if(!failed||failed.status!=='failed'||failed.origin!=='renewal'||failed.period.startsAt!==r.original_paid_through||!anchor||anchor.status!=='completed'||anchor.period.endsAt!==r.original_paid_through||x.subscription.status!=='pastDue'||x.subscription.cancellation.state!=='none'||x.subscription.currentPeriod?.transactionID!==anchor.id)return false;}
 for(const r of l.billing_grace_void)if(!['recovered','cancelled','refunded','charged_back'].includes(r.reason)||!l.billing_grace.some((g:any)=>g.subscription_id===r.subscription_id&&g.anchor_transaction_id===r.anchor_transaction_id&&g.original_paid_through===r.original_paid_through&&r.voided_at>=g.created_at))return false;
 for(const r of l.billing_renewal_stop)if(!generation(r.renewal_generation)||!generation(r.revision)||!['awaitingRefundApproval','intent','dispatching','unknown','accepted','confirmed','notRequired','needsOperator'].includes(r.state)||!(r.dispatch_id===null&&r.claimed_at===null||identity(r.dispatch_id)&&time(r.claimed_at))||r.state==='confirmed'&&!digest(r.confirmation_sha256)||r.state!=='confirmed'&&r.confirmation_sha256!==null)return false;
 for(const r of l.billing_stop_cause){if(!['customerCancel','fullRefund','chargeback'].includes(r.cause_kind)||!['awaitingApproval','enabled','closed'].includes(r.state)||!l.billing_renewal_stop.some((s:any)=>s.subscription_id===r.subscription_id&&s.renewal_generation===r.renewal_generation))return false;if(r.cause_kind==='customerCancel'){if(!identity(r.cause_id)||typeof r.acknowledgement_json!=='string')return false;let ack;try{ack=JSON.parse(r.acknowledgement_json);}catch{return false;}if(C(ack)!==r.acknowledgement_json||!(closed(ack,['kind'])&&ack.kind==='paidAccessPreserved'||closed(ack,['kind','anchorTransactionID','originalPaidThrough','graceDeadline','renewalGeneration'])&&ack.kind==='graceEnds'&&entityID(ack.anchorTransactionID,'txn')&&time(ack.originalPaidThrough)&&ack.graceDeadline===ack.originalPaidThrough+604800&&generation(ack.renewalGeneration)))return false;}else if(!entityID(r.cause_id,'adj')||r.acknowledgement_json!==null)return false;}
 for(const r of l.billing_lifecycle_request){let result;try{result=JSON.parse(r.result_json);}catch{return false;}if(!['cancel','reviewReversal'].includes(r.operation)||!identity(r.request_id)||!closed(result,['outcome','requestID'])||result.requestID!==r.request_id||!['requested','confirmed','restored','noRemainingTime'].includes(result.outcome)||C(result)!==r.result_json)return false;}
 for(const r of l.billing_review_confirmation)if(!identity(r.confirmation_id)||!identity(r.operator_id)||!identity(r.operator_session_id)||!generation(r.subscription_revision)||r.authenticated_at>r.consumed_at||r.consumed_at>=r.expires_at||r.expires_at-r.authenticated_at>600)return false;
 for(const r of l.billing_lifecycle_commit)if(!['consume','sweep','claim','reconcile','cancel','reviewReversal','dispatch','dispatchResult','hold'].includes(r.operation)||!generation(r.account_revision)||![0,1].includes(r.source_delta)||r.complete!==1)return false;
 return true;
}
export function paidEnd(l:any,sub:string,now:number):number|null {
 const spans=l.billing_period.filter((r:any)=>r.subscription_id===sub).flatMap((p:any)=>{
  const end=l.billing_period_end.find((x:any)=>x.transaction_id===p.transaction_id);
  if(!end)return [[p.starts_at,p.ends_at]];
  const restored=l.billing_restoration.find((x:any)=>x.transaction_id===p.transaction_id&&x.chargeback_id===end.adjustment_id);
  return restored?[[restored.restored_at,restored.original_ends_at]]:[];
 }).sort((a:number[],b:number[])=>a[0]-b[0]||a[1]-b[1]);
 let start=-1,end=-1;
 for(const [a,b] of spans){if(a>end){if(start<=now&&now<end)return end;start=a;end=b;}else end=Math.max(end,b);}
 return start<=now&&now<end?end:null;
}
export function liveGrace(l:any,sub:string,now:number):any {
 return l.billing_grace.filter((g:any)=>g.subscription_id===sub&&g.original_paid_through<=now&&now<g.deadline&&!l.billing_grace_void.some((v:any)=>v.subscription_id===sub&&v.original_paid_through===g.original_paid_through)).sort((a:any,b:any)=>b.deadline-a.deadline||(a.anchor_transaction_id<b.anchor_transaction_id?-1:1))[0]??null;
}
export function notice(s:any,l:any,now:number):any[] {
 const chargeValue=JSON.parse(s.next_charge_json),paid=paidEnd(l,s.subscription_id,now);
 const stop=l.billing_renewal_stop.find((r:any)=>r.subscription_id===s.subscription_id&&r.renewal_generation===s.renewal_generation);
 const enabled=l.billing_stop_cause.some((r:any)=>r.subscription_id===s.subscription_id&&r.renewal_generation===s.renewal_generation&&r.state==='enabled');
 const affected=l.billing_period_end.some((r:any)=>r.subscription_id===s.subscription_id)&&paid===null;
 const ineligible=l.account.revokedAt!==null||s.cancellation_state!=='none'||s.status!=='active'||liveGrace(l,s.subscription_id,now)!==null||affected||enabled||stop&&!['notRequired','awaitingRefundApproval'].includes(stop.state)||chargeValue.kind==='known'&&chargeValue.at<=now;
 const eligibility=ineligible?'ineligible':chargeValue.kind!=='known'||paid===null?'unavailable':'eligible';
 return [s.cancellation_state,s.cancellation_effective_at,eligibility,chargeValue.kind==='known'?[chargeValue.at,chargeValue.priceID,chargeValue.currency,chargeValue.quantity,chargeValue.unitAmount,chargeValue.taxInclusive]:null];
}
