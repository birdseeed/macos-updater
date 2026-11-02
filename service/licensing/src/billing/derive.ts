import type {LifecycleLedger,Second,DeriveResult,LifecycleDelta} from './types';
// Pure proposals only. No provider, database, clock, signer or winner capability.
import {closed,time,generation,identity,digest,entityID,C,sha,H,terms,columns,ledgerValid,snapshot,paidEnd,liveGrace,notice,type ObjectValue} from './schema';
function withoutNonce(r:ObjectValue):ObjectValue {const {commit_nonce,...value}=r;return value;}
export function derive(_snapshot:unknown,_ledger:LifecycleLedger,_now:Second):DeriveResult {
 const held=(reason:'binding'|'contradiction'|'older'|'unsupported'|'capacity'='contradiction'):DeriveResult=>({outcome:'held',reason});
 try {
  if(!time(_now)||!ledgerValid(_ledger))return held();
  if(closed(_snapshot,['fixture','environment','subscription','transactions','adjustments','disputes'])&&(['transactions','adjustments','disputes'] as const).some((k,i)=>Array.isArray(_snapshot[k])&&_snapshot[k].length>[32,64,64][i]))return held('capacity');
  if(!snapshot(_snapshot,_now))return held('unsupported');
  const x=_snapshot as ObjectValue,l=structuredClone(_ledger) as any,s=x.subscription,old=l.billing_subscription.find((v:any)=>v.subscription_id===s.id);
  if(!old||s.bindingID!==old.binding_id||s.renewalGeneration!==old.renewal_generation||l.account.revokedAt!==null)return held('binding');
  if(s.updatedAt<old.provider_updated_at)return held('older');
  if(s.updatedAt===old.provider_updated_at&&C(s)!==old.canonical_json)return held();
  if(['scheduled','effective'].includes(old.cancellation_state)&&(s.cancellation.state==='none'||old.cancellation_state==='effective'&&s.cancellation.state!=='effective'))return held();
  const K=[l.environment,l.account.accountID,s.id,s.bindingID],base={environment:l.environment,subscription_id:s.id,account_id:l.account.accountID},ops:LifecycleDelta[]=[];
  const push=(kind:LifecycleDelta['kind'],row:any)=>{ops.push({kind,row} as LifecycleDelta);};
  const target=(table:string)=>l[table].filter((r:any)=>r.subscription_id===s.id);
  const entities=[['subscription',[s]],['transaction',x.transactions],['adjustment',x.adjustments],['dispute',x.disputes]] as const;
  for(const [kind,list] of entities){for(const previous of target('billing_entity_version').filter((r:any)=>r.entity_kind===kind)){const next=(list as any[]).find(v=>v.id===previous.entity_id);if(!next)return held();if(next.updatedAt<previous.updated_at)return held('older');if(next.updatedAt===previous.updated_at&&C(next)!==previous.canonical_json)return held();}}
  const tx=new Map<string,any>();
  for(const t of x.transactions){
   if(t.subscriptionID!==s.id||t.bindingID!==s.bindingID||t.origin==='existing'&&!target('billing_existing_transaction').some((r:any)=>r.transaction_id===t.id))return held('binding');
   tx.set(t.id,t);
   const previous=l.billing_period.find((p:any)=>p.transaction_id===t.id);
   const row={...base,transaction_id:t.id,starts_at:t.period.startsAt,ends_at:t.period.endsAt,price_id:t.priceID,currency:t.currency,quantity:1,unit_amount:1999,tax_inclusive:1,origin:t.origin};
   if(previous){if(C(withoutNonce(previous))!==C(withoutNonce(row))||t.status!=='completed')return held();}
   else if(t.status==='completed'){push('insertPeriod',row);l.billing_period.push({...row,commit_nonce:old.commit_nonce});}
  }
  if(target('billing_period').some((p:any)=>!tx.has(p.transaction_id)))return held();
  if(s.currentPeriod){const t=tx.get(s.currentPeriod.transactionID);if(!t||t.status!=='completed'||t.period.startsAt!==s.currentPeriod.startsAt||t.period.endsAt!==s.currentPeriod.endsAt)return held();const later=x.transactions.some((v:any)=>v.status==='completed'&&v.id!==t.id&&v.period.startsAt>t.period.startsAt&&v.period.startsAt<t.period.endsAt&&v.period.endsAt>t.period.endsAt);if(later)return held();}
  const latestAdjustments=new Map<string,any>();
  for(const a of x.adjustments){
   const t=tx.get(a.transactionID),period=l.billing_period.find((p:any)=>p.transaction_id===a.transactionID);
   if(!t||!period||t.currency!==a.currency||a.kind==='chargeback'&&a.coverage!=='full')return held('unsupported');
   const previous=target('billing_adjustment').find((r:any)=>r.adjustment_id===a.id),evidence=H('PAT-2646-adjustment-evidence-v1',[...K,a]);
   if(previous&&(a.updatedAt<previous.updated_at||previous.transaction_id!==a.transactionID||previous.kind!==a.kind||previous.amount!==a.amount||previous.currency!==a.currency||previous.coverage!==a.coverage))return held();
   const row={...base,adjustment_id:a.id,transaction_id:a.transactionID,kind:a.kind,coverage:a.coverage,amount:a.amount,currency:a.currency,status:a.status,updated_at:a.updatedAt,evidence_sha256:evidence};
   if(previous&&a.updatedAt===previous.updated_at&&C(withoutNonce(previous))!==C(withoutNonce(row)))return held();
   if(previous&&previous.status==='approved'&&!['approved','reversed'].includes(a.status)||previous&&previous.status==='reversed'&&a.status!=='reversed'||previous&&previous.status==='rejected'&&a.status!=='rejected')return held();
   if(!previous||C(withoutNonce(previous))!==C(withoutNonce(row))){push('observeAdjustment',row);l.billing_adjustment=l.billing_adjustment.filter((v:any)=>v.adjustment_id!==a.id);l.billing_adjustment.push({...row,commit_nonce:old.commit_nonce});}
   latestAdjustments.set(a.id,{a,evidence});
   if(a.kind==='refund'&&a.coverage==='full'&&['pending','rejected'].includes(a.status)){
    const previousCause=target('billing_stop_cause').find((r:any)=>r.cause_kind==='fullRefund'&&r.cause_id===a.id&&r.renewal_generation===s.renewalGeneration),state=a.status==='pending'?'awaitingApproval':'closed';
    if(previousCause&&previousCause.state!==state){const c={...base,renewal_generation:s.renewalGeneration,cause_kind:'fullRefund',cause_id:a.id,state,evidence_sha256:H('PAT-2646-stop-full-refund-v1',[...K,s.renewalGeneration,a.id,state,evidence]),acknowledgement_json:null};push('joinStopCause',c);l.billing_stop_cause=l.billing_stop_cause.filter((v:any)=>!(v.subscription_id===s.id&&v.cause_kind==='fullRefund'&&v.cause_id===a.id&&v.renewal_generation===s.renewalGeneration));l.billing_stop_cause.push({...c,commit_nonce:old.commit_nonce});}
   }
   if(a.status==='approved'&&a.coverage==='full'){
    const reason=a.kind==='refund'?'refunded':'charged_back',end=target('billing_period_end').find((r:any)=>r.transaction_id===a.transactionID);
    if(end&&(end.adjustment_id!==a.id||end.reason!==reason))return held();
    if(!end){const ended={...base,transaction_id:a.transactionID,adjustment_id:a.id,reason,ended_at:_now};push('endPeriod',ended);l.billing_period_end.push({...ended,commit_nonce:old.commit_nonce});}
    const causeKind=a.kind==='refund'?'fullRefund':'chargeback',cause=target('billing_stop_cause').find((r:any)=>r.cause_id===a.id&&r.cause_kind===causeKind);
    if(!cause||cause.state==='awaitingApproval'){
     const c={...base,renewal_generation:s.renewalGeneration,cause_kind:causeKind,cause_id:a.id,state:'enabled',evidence_sha256:H(a.kind==='refund'?'PAT-2646-stop-full-refund-v1':'PAT-2646-stop-chargeback-v1',[...K,s.renewalGeneration,a.id,'enabled',evidence]),acknowledgement_json:null};push('joinStopCause',c);l.billing_stop_cause=l.billing_stop_cause.filter((v:any)=>!(v.subscription_id===s.id&&v.cause_id===a.id&&v.cause_kind===causeKind));l.billing_stop_cause.push({...c,commit_nonce:old.commit_nonce});
    }
   }
   if(a.status==='reversed'){
    if(a.kind!=='chargeback')return held('unsupported');
    const end=target('billing_period_end').find((r:any)=>r.transaction_id===a.transactionID&&r.adjustment_id===a.id&&r.reason==='charged_back');
    if(!end)return held();
    if(!target('billing_restoration').some((r:any)=>r.transaction_id===a.transactionID&&r.chargeback_id===a.id)){
     const confirmation=target('billing_review_confirmation').find((r:any)=>r.transaction_id===a.transactionID&&r.chargeback_id===a.id&&r.reversal_evidence_sha256===evidence&&r.original_ends_at===period.ends_at&&r.consumed_at<=_now);
     if(!confirmation||period.ends_at<=_now)return held('unsupported');
     const restore={...base,transaction_id:a.transactionID,chargeback_id:a.id,reversal_evidence_sha256:evidence,confirmation_id:confirmation.confirmation_id,restored_at:_now,original_ends_at:period.ends_at};push('restoreRemainder',restore);l.billing_restoration.push({...restore,commit_nonce:old.commit_nonce});
    }
   }
  }
  for(const d of x.disputes){
   if(!tx.has(d.transactionID)||!l.billing_period.some((p:any)=>p.transaction_id===d.transactionID))return held('binding');
   const previous=target('billing_dispute').find((r:any)=>r.dispute_id===d.id),row={...base,dispute_id:d.id,transaction_id:d.transactionID,state:d.state,updated_at:d.updatedAt,evidence_sha256:H('PAT-2646-dispute-evidence-v1',[...K,d])};
   if(previous&&(d.updatedAt<previous.updated_at||previous.transaction_id!==d.transactionID||d.updatedAt===previous.updated_at&&C(withoutNonce(previous))!==C(withoutNonce(row))))return held();
   if(!previous||C(withoutNonce(previous))!==C(withoutNonce(row))){push('observeDispute',row);l.billing_dispute=l.billing_dispute.filter((r:any)=>r.dispute_id!==d.id);l.billing_dispute.push({...row,commit_nonce:old.commit_nonce});}
  }
  let stop=target('billing_renewal_stop').find((r:any)=>r.renewal_generation===s.renewalGeneration);
  if(s.cancellation.state!=='none'&&(!stop||stop.state!=='confirmed')){
   const confirm={...base,renewal_generation:s.renewalGeneration,state:'confirmed',dispatch_id:stop?.dispatch_id??null,claimed_at:stop?.claimed_at??null,confirmation_sha256:H('PAT-2646-stop-confirmation-v1',[...K,s.renewalGeneration,sha(C(s)),s.cancellation.state,s.cancellation.effectiveAt]),revision:stop?stop.revision+1:1};
   if(!generation(confirm.revision))return held();
   push('confirmStop',confirm);stop=confirm;l.billing_renewal_stop=l.billing_renewal_stop.filter((v:any)=>!(v.subscription_id===s.id&&v.renewal_generation===s.renewalGeneration));l.billing_renewal_stop.push({...confirm,commit_nonce:old.commit_nonce});
  }
  for(const g of target('billing_grace')){
   if(target('billing_grace_void').some((v:any)=>v.original_paid_through===g.original_paid_through))continue;
   const R=[g.anchor_transaction_id,g.original_paid_through,g.anchor_source_sha256],losses=x.adjustments.filter((a:any)=>a.transactionID===g.anchor_transaction_id&&a.status==='approved'&&a.coverage==='full');
   let reason:string|undefined,evidence:string|undefined;
   const loss=losses.find((a:any)=>a.kind==='chargeback')??losses.find((a:any)=>a.kind==='refund');
   if(loss){reason=loss.kind==='chargeback'?'charged_back':'refunded';evidence=H(loss.kind==='chargeback'?'PAT-2646-grace-void-charged-back-v1':'PAT-2646-grace-void-refunded-v1',[...K,...R,loss.id,latestAdjustments.get(loss.id).evidence]);}
   else if(s.cancellation.state!=='none'){
    const cause=target('billing_stop_cause').filter((v:any)=>v.cause_kind==='customerCancel'&&v.state==='enabled'&&v.renewal_generation===s.renewalGeneration).sort((a:any,b:any)=>a.cause_id<b.cause_id?-1:1).find((v:any)=>{try{const ack=JSON.parse(v.acknowledgement_json);return closed(ack,['kind','anchorTransactionID','originalPaidThrough','graceDeadline','renewalGeneration'])&&ack.kind==='graceEnds'&&ack.anchorTransactionID===g.anchor_transaction_id&&ack.originalPaidThrough===g.original_paid_through&&ack.graceDeadline===g.deadline&&ack.renewalGeneration===s.renewalGeneration;}catch{return false;}});
    if(!cause||!stop?.confirmation_sha256)return held('unsupported');
    reason='cancelled';evidence=H('PAT-2646-grace-void-cancelled-v1',[...K,...R,s.renewalGeneration,cause.cause_id,cause.evidence_sha256,stop.confirmation_sha256]);
   }else {
    const recovery=x.transactions.filter((t:any)=>t.status==='completed'&&t.id!==g.anchor_transaction_id&&t.period.startsAt<=g.original_paid_through&&t.period.endsAt>g.original_paid_through&&!target('billing_period_end').some((e:any)=>e.transaction_id===t.id)).sort((a:any,b:any)=>a.id<b.id?-1:1)[0];
    if(recovery){reason='recovered';evidence=H('PAT-2646-grace-void-recovered-v1',[...K,...R,recovery.id,sha(C(recovery))]);}
   }
   if(reason){const row={...base,anchor_transaction_id:g.anchor_transaction_id,original_paid_through:g.original_paid_through,reason,evidence_sha256:evidence,voided_at:_now};push('voidGrace',row);l.billing_grace_void.push({...row,commit_nonce:old.commit_nonce});}
  }
  const current=s.currentPeriod&&tx.get(s.currentPeriod.transactionID);
  if(s.status==='pastDue'&&s.cancellation.state==='none'&&old.cancellation_state==='none'&&current){
   const failure=x.transactions.filter((t:any)=>t.origin==='renewal'&&t.status==='failed'&&t.period.startsAt===current.period.endsAt).sort((a:any,b:any)=>a.id<b.id?-1:1)[0];
   if(!failure&&x.transactions.some((t:any)=>t.status==='failed'))return held();
   const successor=x.transactions.some((t:any)=>t.id!==current.id&&t.status==='completed'&&t.period.startsAt<=current.period.endsAt&&t.period.endsAt>current.period.endsAt);
   const blocked=target('billing_period_end').some((v:any)=>v.transaction_id===current.id)||target('billing_dispute').some((v:any)=>v.transaction_id===current.id&&['warning','open','confirmedLoss'].includes(v.state));
   const existing=target('billing_grace').find((v:any)=>v.original_paid_through===current.period.endsAt);
   if(existing&&existing.anchor_transaction_id!==current.id)return held();
   if(failure&&!successor&&!blocked&&!existing){
    const deadline=current.period.endsAt+604800;if(!time(deadline))return held();
    const r=target('billing_reconcile')[0];if(!r||!generation(r.read_generation))return held();
    const row={...base,anchor_transaction_id:current.id,original_paid_through:current.period.endsAt,anchor_source_sha256:H('PAT-2646-grace-anchor-v1',[...K,current.id,current.period.startsAt,current.period.endsAt,current.priceID,current.currency,current.quantity,current.unitAmount,current.taxInclusive]),deadline,created_at:_now,failed_transaction_id:failure.id,failure_read_generation:r.read_generation};push('createGrace',row);l.billing_grace.push({...row,commit_nonce:old.commit_nonce});
   }
  }
  const next={...old,provider_updated_at:s.updatedAt,status:s.status,cancellation_state:s.cancellation.state==='none'&&old.cancellation_state==='requested'?'requested':s.cancellation.state,cancellation_effective_at:s.cancellation.effectiveAt,next_charge_json:C(s.nextCharge),canonical_json:C(s),canonical_sha256:sha(C(s))};
  const semanticChanged=ops.length>0||['provider_updated_at','status','cancellation_state','cancellation_effective_at','next_charge_json','canonical_json','canonical_sha256'].some(k=>old[k]!==next[k]);
  if(semanticChanged){if(old.revision===Number.MAX_SAFE_INTEGER)return held();next.revision=old.revision+1;const changed=C(notice(old,_ledger,_now))!==C(notice(next,l,_now));if(changed){if(old.notice_revision===Number.MAX_SAFE_INTEGER)return held();next.notice_revision=old.notice_revision+1;}const {commit_nonce,...row}=next;push('updateSubscription',row);}
  if(ops.length>364)return held('capacity');
  return ops.length?{outcome:'delta',operations:ops}:{outcome:'unchanged'};
 }catch{return held();}
}
