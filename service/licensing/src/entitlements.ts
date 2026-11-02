import {loadEntitlementSnapshot,planSourceSelection,billingSnapshotConditions,loadBillingProtection,billingProtectionDecision} from './entitlementPlans';
import {inspectSchema} from './sessionAuthorization';
import {legacyHeadCondition,planActivationDeletion} from './activationPlans';
import { validGuard, type AccountGuard } from './store';
import { AuthService, fixtureRandom, keyedDigest, type SessionCredential } from './auth';
import { cleanupEligibility, retentionDeadline, trialEligibility, trialMarkerOnDeletion, type TrialMarker, type RetentionRecord } from './retention';
import { produceLease, type LeaseClaims, type SyntheticSigner } from './leases';
import type { FixtureEnvironment } from './environment';
/** Fixture facts grant no productive session, activation, signing or cleanup authority. */
export interface TrialFacts { now: number; trialStartedAt: number | null; trialEndsAt: number | null; betaInvited: boolean; betaEndsAt: number | null; revoked: boolean; marker: TrialMarker | null; }
export type TrialDecision = {outcome:'started'|'existing'; startedAt:number; expiresAt:number} | {outcome:'refused'|'trial-unavailable-during-beta'};
const MAX_TIME=253402300799, TRIAL=1209600;
const time=(n:unknown):n is number=>typeof n==='number'&&Number.isSafeInteger(n)&&n>=0&&n<=MAX_TIME;
const revision=(n:unknown):n is number=>typeof n==='number'&&Number.isSafeInteger(n)&&n>=0&&n<Number.MAX_SAFE_INTEGER;
function closed(x:unknown,keys:string[]):x is Record<string,unknown>{return !!x&&typeof x==='object'&&!Array.isArray(x)&&Reflect.ownKeys(x).length===keys.length&&keys.every(k=>Object.hasOwn(x,k));}
const id=(x:unknown):x is string=>typeof x==='string'&&/^[a-f0-9]{32}$/.test(x);
const token=(x:unknown):x is string=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const name=(x:unknown):x is string=>typeof x==='string'&&/^[a-zA-Z0-9-]{1,64}$/.test(x);
function credential(x:unknown):x is SessionCredential{return closed(x,['sessionID','accessToken'])&&id(x.sessionID)&&token(x.accessToken);}
function guardOK(x:AccountGuard):boolean{return validGuard(x)&&id(x.accountID)&&revision(x.accountRevision);}
export function decideTrial(facts:TrialFacts):TrialDecision {
 try{
  const f=facts;
  if(!closed(f,['now','trialStartedAt','trialEndsAt','betaInvited','betaEndsAt','revoked','marker'])||!time(f.now)||!time(f.now+TRIAL)||typeof f.betaInvited!=='boolean'||typeof f.revoked!=='boolean'||f.revoked||(f.betaEndsAt!==null&&!time(f.betaEndsAt)))return {outcome:'refused'};
  if(f.trialStartedAt!==null||f.trialEndsAt!==null){return time(f.trialStartedAt)&&time(f.trialEndsAt)&&f.trialStartedAt<=f.now&&f.trialEndsAt===f.trialStartedAt+TRIAL?{outcome:'existing',startedAt:f.trialStartedAt,expiresAt:f.trialEndsAt}:{outcome:'refused'};}
  if(trialEligibility({now:f.now,accountTrialUsed:false,existingMarker:f.marker}).kind!=='eligible')return {outcome:'refused'};
  return f.betaInvited&&(f.betaEndsAt===null||f.betaEndsAt>f.now)?{outcome:'trial-unavailable-during-beta'}:{outcome:'started',startedAt:f.now,expiresAt:f.now+TRIAL};
 }catch{return {outcome:'refused'};}
}
export interface TrialStart { credential: SessionCredential; guard: AccountGuard; requestID: string; requestHash: string; }
export interface CleanupRow { rowID: string; record: RetentionRecord; maxGrantPermittedUntil: number|null; pendingProviderIntent: boolean; reconciliationReference: boolean; approvedHoldRequiresRow: boolean; }
export interface FixtureLicensingDependencies { requiredSessionKind?:'web'; db:D1Database; now:()=>number; marker:'PAT-2643-synthetic'; syntheticKey:Uint8Array; signer?:SyntheticSigner; }
export interface AccountDeletion { credential:SessionCredential; guard:AccountGuard; }
export interface CleanupRequest { guard:AccountGuard; limit:number; dryRun:boolean; }
export interface ActivationRequest extends AccountDeletion { activationID:string; }
export type MutationResult = {status:200|400|401|409|503; body:Record<string,unknown>};
type Row=Record<string,string|number|null>;
type Condition={sql:string;args:(string|number|null)[];authentication?:true};
const refuse=(status:MutationResult['status']=409):MutationResult=>({status,body:{outcome:'refused'}});
export class TrialService {
 private readonly requiredSessionKind: unknown;
 constructor(private readonly dependencies?:FixtureLicensingDependencies) {this.requiredSessionKind=dependencies?.requiredSessionKind;}
 private ready():boolean {const d=this.dependencies;return (this.requiredSessionKind===undefined||this.requiredSessionKind==='web')&&!!d&&d.marker==='PAT-2643-synthetic'&&!!d.db&&typeof d.now==='function'&&d.syntheticKey instanceof Uint8Array&&d.syntheticKey.length===32;}
 private stmt(sql:string,...args:(string|number|null)[]):D1PreparedStatement{return this.dependencies!.db.prepare(sql).bind(...args);}
 private row(sql:string,...args:(string|number|null)[]):Promise<Row|null>{return this.stmt(sql,...args).first<Row>();}
 private async rows(sql:string,...args:(string|number|null)[]):Promise<Row[]>{return (await this.stmt(sql,...args).all<Row>()).results;}
 // The NOT NULL violation deliberately aborts the entire D1 batch when a required
 // write is skipped (including triggers that silently ignore a dependent insert).
 private assertChanges(n=1):D1PreparedStatement{return this.stmt("INSERT INTO account_guard SELECT NULL,NULL,NULL WHERE changes()<>?",n);}
 private snapshot(table:'accounts'|'entitlement_sources'|'lease_heads'|'trial_markers'|'retention_rows'|'sessions'|'challenges'|'trial_requests'|'request_limits',key:string,value:string,row:Row|null):Condition {
  // Identifiers originate exclusively in source or D1's closed schema, never input.
  const columns:Record<string,string[]>={accounts:['account_id','email_hmac','created_at','revoked_at','entitlement_revision','activation_revision'],entitlement_sources:['account_id','trial_started_at','trial_ends_at','beta_invited','beta_ends_at'],lease_heads:['activation_id','account_id','device_key_sha256','activation_revision','sequence','released_at','last_grant_state','last_grant_issued_at','last_grant_permitted_until','last_grant_hard_end','max_grant_permitted_until','commit_nonce'],trial_markers:['email_hmac','original_deleted_at','expires_at'],retention_rows:['row_id','account_id','record_json','max_grant_permitted_until','pending_provider_intent','reconciliation_reference','approved_hold_requires_row','commit_nonce'],sessions:['session_id','account_id','kind','activation_id','authenticated_at','created_at','access_hmac','access_expires_at','refresh_hmac','refresh_expires_at','expires_at','revoked_at','commit_nonce'],challenges:['challenge_id','email_hmac','purpose','code_hmac','created_at','expires_at','wrong_attempts','superseded_at','consumed_at','consume_nonce','bound_account_id','bound_session_id'],trial_requests:['account_id','request_id','request_hash','response_json','created_at','commit_nonce'],request_limits:['request_id','email_hmac','ip_hmac','requested_at','sent']};
  if(!columns[table].includes(key))throw Error('identifier refused');
  return row?{sql:`EXISTS(SELECT 1 FROM ${table} WHERE ${columns[table].map(c=>`${c} IS ?`).join(' AND ')})`,args:columns[table].map(c=>row[c])}:{sql:`NOT EXISTS(SELECT 1 FROM ${table} WHERE ${key}=?)`,args:[value]};
 }
 private async auth(c:SessionCredential,g:AccountGuard,now:number):Promise<Condition|null>{
  const d=this.dependencies!;
  const a=await new AuthService({requiredSessionKind:this.requiredSessionKind as 'web'|undefined,db:d.db,now:()=>now,syntheticKey:d.syntheticKey,randomBytes:()=>{throw Error('entropy unavailable');},delivery:async()=>{throw Error('delivery unavailable');}}).authorize(c,{kind:'ordinary'});
  return a&&a.accountID===g.accountID?{authentication:true,...a.condition}:null;
 }
 private nonceCondition(g:AccountGuard):Condition {return {sql:`NOT EXISTS(SELECT 1 FROM account_nonce_history WHERE commit_nonce=?) AND NOT EXISTS(SELECT 1 FROM account_audit WHERE commit_nonce=?) AND NOT EXISTS(SELECT 1 FROM challenges WHERE consume_nonce=?) AND NOT EXISTS(SELECT 1 FROM account_requests WHERE commit_nonce=?) AND NOT EXISTS(SELECT 1 FROM account_guard WHERE commit_nonce=?)`,args:Array(5).fill(g.commitNonce)};}
 private async currentGuard(g:AccountGuard):Promise<boolean>{const n=this.nonceCondition(g);return !!await this.row(`SELECT account_id FROM account_guard WHERE account_id=? AND account_revision=? AND ${n.sql}`,g.accountID,g.accountRevision,...n.args);}
 private fence(g:AccountGuard):Condition{return {sql:'EXISTS(SELECT 1 FROM account_guard WHERE account_id=? AND account_revision=? AND commit_nonce=?)',args:[g.accountID,g.accountRevision+1,g.commitNonce]};}
 private begin(g:AccountGuard,conditions:Condition[]):D1PreparedStatement[]{
  const cas=[this.nonceCondition(g),...conditions.filter(c=>c.authentication)];
  // Keep each statement below D1's 100 bindings. The CAS and ALL subsequent
  // snapshot assertions share one batch transaction; failed/NULL facts abort
  // that winner before any source/session/grant/deletion effect can commit.
  return [this.stmt(`UPDATE account_guard SET account_revision=account_revision+1,commit_nonce=? WHERE account_id=? AND account_revision=? AND ${cas.map(c=>`(${c.sql})`).join(' AND ')}`,g.commitNonce,g.accountID,g.accountRevision,...cas.flatMap(c=>c.args)),this.assertChanges(),...conditions.filter(c=>!c.authentication).map(c=>this.stmt(`INSERT INTO account_guard SELECT NULL,NULL,NULL WHERE COALESCE((${c.sql}),0)<>1`,...c.args))];
 }
 private finish(g:AccountGuard,action:string,now:number):D1PreparedStatement[]{const f=this.fence(g);return [this.stmt(`INSERT INTO account_nonce_history SELECT account_id,? FROM account_guard WHERE account_id=? AND ${f.sql}`,g.commitNonce,g.accountID,...f.args),this.assertChanges(),this.stmt(`INSERT INTO account_audit SELECT ?,account_id,?,account_revision,?,? FROM account_guard WHERE account_id=? AND ${f.sql}`,g.commitNonce,action,g.commitNonce,now,g.accountID,...f.args),this.assertChanges()];}
 private async account(g:AccountGuard):Promise<Row|null>{const a=await this.row('SELECT * FROM accounts WHERE account_id=?',g.accountID);return a&&revision(a.entitlement_revision)&&revision(a.activation_revision)&&time(a.created_at)?a:null;}
 async start(input:TrialStart):Promise<TrialDecision>{return (await this.startResult(input)).body as TrialDecision;}
 async startResult(input:TrialStart):Promise<MutationResult>{
  if(!this.ready())return refuse(503);if(!closed(input,['credential','guard','requestID','requestHash'])||!credential(input.credential)||!guardOK(input.guard)||!name(input.requestID)||!token(input.requestHash))return refuse(400);
  try{
   const now=this.dependencies!.now();if(!time(now)||!time(now+TRIAL))return refuse();const g=input.guard,auth=await this.auth(input.credential,g,now);if(!auth)return refuse(401);
   const replay=await this.row(`SELECT * FROM trial_requests WHERE account_id=? AND request_id=? AND ${auth.sql}`,g.accountID,input.requestID,...auth.args);
   if(replay)return replay.request_hash===input.requestHash?{status:200,body:JSON.parse(String(replay.response_json))}:refuse();
   const a=await this.account(g);if(!a||a.revoked_at!==null)return refuse();const source=await this.row('SELECT * FROM entitlement_sources WHERE account_id=?',g.accountID);const marker=await this.row('SELECT * FROM trial_markers WHERE email_hmac=?',a.email_hmac);
   const decision=decideTrial({now,trialStartedAt:source?.trial_started_at as number|null??null,trialEndsAt:source?.trial_ends_at as number|null??null,betaInvited:source?.beta_invited===1,betaEndsAt:source?.beta_ends_at as number|null??null,revoked:false,marker:marker?{originalDeletedAt:Number(marker.original_deleted_at),expiresAt:Number(marker.expires_at)}:null});
   if(decision.outcome==='refused'||decision.outcome==='trial-unavailable-during-beta')return {status:409,body:decision};
   const f=this.fence(g);const statements=this.begin(g,[auth,this.snapshot('accounts','account_id',g.accountID,a),this.snapshot('entitlement_sources','account_id',g.accountID,source),this.snapshot('trial_markers','email_hmac',String(a.email_hmac),marker)]);
   if(decision.outcome==='started'){
    statements.push(this.stmt(`INSERT INTO entitlement_sources(account_id,trial_started_at,trial_ends_at) SELECT ?,?,? WHERE ${f.sql} ON CONFLICT(account_id) DO UPDATE SET trial_started_at=excluded.trial_started_at,trial_ends_at=excluded.trial_ends_at`,g.accountID,decision.startedAt,decision.expiresAt,...f.args),this.assertChanges(),this.stmt(`UPDATE accounts SET entitlement_revision=entitlement_revision+1 WHERE account_id=? AND ${f.sql}`,g.accountID,...f.args),this.assertChanges());
   }
   statements.push(this.stmt(`INSERT INTO trial_requests SELECT ?,?,?,?,?,? WHERE ${f.sql}`,g.accountID,input.requestID,input.requestHash,JSON.stringify(decision),now,g.commitNonce,...f.args),this.assertChanges(),...this.finish(g,'trial-start',now));
   await this.dependencies!.db.batch(statements);return {status:200,body:decision};
  }catch{return refuse();}
 }
 private headValid(h:Row,now:number):boolean {
  if(!revision(h.sequence)||!revision(h.activation_revision)||Number(h.activation_revision)<1||!token(h.device_key_sha256)||(h.released_at!==null&&(!time(h.released_at)||h.released_at>now))||(h.max_grant_permitted_until!==null&&!time(h.max_grant_permitted_until)))return false;
  const history=[h.last_grant_state,h.last_grant_issued_at,h.last_grant_permitted_until,h.last_grant_hard_end];
  if(history.every(v=>v===null))return true;
  return ['paid','grace','beta','trial'].includes(String(h.last_grant_state))&&time(h.last_grant_issued_at)&&h.last_grant_issued_at<=now&&time(h.last_grant_permitted_until)&&time(h.last_grant_hard_end)&&h.last_grant_issued_at<h.last_grant_permitted_until&&h.last_grant_permitted_until<=h.last_grant_hard_end&&time(h.max_grant_permitted_until)&&h.max_grant_permitted_until>=h.last_grant_permitted_until;
 }
 private async protections(accountID:string,now:number):Promise<{held:boolean;conditions:Condition[]}>{
  const billing=await loadBillingProtection(this.dependencies!.db,accountID,now);if(billing.outcome!=='loaded')return {held:true,conditions:[]};const protectedBilling=billingProtectionDecision(billing.snapshot);if(protectedBilling.outcome!=='clear')return {held:true,conditions:[]};
  const heads=await this.rows('SELECT * FROM lease_heads WHERE account_id=? LIMIT 101',accountID),rows=await this.rows('SELECT * FROM retention_rows WHERE account_id=? LIMIT 101',accountID);
  if(heads.length>100||rows.length>100)return {held:true,conditions:[]};
  const conditions:Condition[]=[{sql:'(SELECT COUNT(*) FROM lease_heads WHERE account_id=?)=?',args:[accountID,heads.length]},{sql:'(SELECT COUNT(*) FROM retention_rows WHERE account_id=?)=?',args:[accountID,rows.length]},...heads.map(r=>this.snapshot('lease_heads','activation_id',String(r.activation_id),r)),...rows.map(r=>this.snapshot('retention_rows','row_id',String(r.row_id),r))];
  let held=heads.some(h=>!this.headValid(h,now)||(h.max_grant_permitted_until!==null&&Number(h.max_grant_permitted_until)>now));
  for(const r of rows){try{const record=JSON.parse(String(r.record_json)) as RetentionRecord;const deadline=retentionDeadline(record);if((r.max_grant_permitted_until!==null&&(!time(r.max_grant_permitted_until)||r.max_grant_permitted_until>now))||deadline.kind==='refused'||(deadline.kind==='none'&&deadline.reason==='separate-financial-schedule')||r.pending_provider_intent!==0||r.reconciliation_reference!==0||r.approved_hold_requires_row!==0)held=true;}catch{held=true;}}
  return {held,conditions:[...conditions,...protectedBilling.conditions]};
 }
 async deleteAccount(input:AccountDeletion):Promise<MutationResult>{
  if(!this.ready())return refuse(503);if(!closed(input,['credential','guard'])||!credential(input.credential)||!guardOK(input.guard))return refuse(400);
  try{
   const now=this.dependencies!.now();if(!time(now))return refuse();const g=input.guard,auth=await this.auth(input.credential,g,now);if(!auth)return refuse(401);
   const a=await this.account(g);if(!a||a.revoked_at!==null||!token(a.email_hmac))return refuse();const p=await this.protections(g.accountID,now);if(p.held)return refuse();
   const source=await this.row('SELECT * FROM entitlement_sources WHERE account_id=?',g.accountID),marker=await this.row('SELECT * FROM trial_markers WHERE email_hmac=?',a.email_hmac);
   const decision=trialMarkerOnDeletion({now,deletedAt:now,accountTrialUsed:source?.trial_started_at!==null&&source?.trial_started_at!==undefined,existingMarker:marker?{originalDeletedAt:Number(marker.original_deleted_at),expiresAt:Number(marker.expires_at)}:null});if(decision.kind==='refused')return refuse();
   const sessions=await this.rows('SELECT * FROM sessions WHERE account_id=? LIMIT 101',g.accountID);if(sessions.length>100)return refuse();
   const plan=await planActivationDeletion(this.dependencies!.db,g,now,await inspectSchema(this.dependencies!.db));if(!plan)return refuse();
   const f=this.fence(g),statements=this.begin(g,[auth,...plan.conditions,...p.conditions,{sql:'(SELECT COUNT(*) FROM sessions WHERE account_id=?)=?',args:[g.accountID,sessions.length]},...sessions.map(row=>this.snapshot('sessions','session_id',String(row.session_id),row)),this.snapshot('accounts','account_id',g.accountID,a),this.snapshot('entitlement_sources','account_id',g.accountID,source),this.snapshot('trial_markers','email_hmac',String(a.email_hmac),marker)]);
   statements.push(...plan.statements);
   if(decision.kind==='propose-marker')statements.push(this.stmt(`INSERT INTO trial_markers SELECT ?,?,? WHERE ${f.sql} ON CONFLICT(email_hmac) DO UPDATE SET original_deleted_at=excluded.original_deleted_at,expires_at=excluded.expires_at`,a.email_hmac,decision.marker.originalDeletedAt,decision.marker.expiresAt,...f.args),this.assertChanges());
   statements.push(this.stmt(`UPDATE accounts SET email_hmac=?,revoked_at=?,entitlement_revision=entitlement_revision+1 WHERE account_id=? AND ${f.sql}`,'deleted:'+g.accountID,now,g.accountID,...f.args),this.assertChanges(),this.stmt(`UPDATE sessions SET revoked_at=COALESCE(revoked_at,?),commit_nonce=? WHERE account_id=? AND ${f.sql}`,now,g.commitNonce,g.accountID,...f.args),this.assertChanges(sessions.length),...this.finish(g,'account-delete',now));
   await this.dependencies!.db.batch(statements);return {status:200,body:{outcome:'deleted'}};
  }catch{return refuse();}
 }
 async cleanup(input:CleanupRequest):Promise<MutationResult>{
  if(!this.ready())return refuse(503);if(!closed(input,['guard','limit','dryRun'])||!guardOK(input.guard)||!Number.isSafeInteger(input.limit)||input.limit<1||input.limit>100||typeof input.dryRun!=='boolean')return refuse(400);
  try{
   const now=this.dependencies!.now(),g=input.guard;if(!time(now)||!await this.currentGuard(g))return refuse();const a=await this.account(g);if(!a)return refuse();const p=await this.protections(g.accountID,now);
   const schema=await inspectSchema(this.dependencies!.db);if(schema.kind==='unsupported')return refuse();if(schema.kind==='a2'&&await this.row('SELECT activation_id FROM activations WHERE account_id=? LIMIT 1',g.accountID))p.held=true;
   if(p.held)return await this.currentGuard(g)?{status:200,body:input.dryRun?{eligible:0}:{deleted:0}}:refuse();
   type Candidate={table:'challenges'|'sessions'|'trial_requests'|'retention_rows';key:string;row:Row;record:RetentionRecord};
   const candidates:Candidate[]=[];
   const eligible=(record:RetentionRecord,r?:Row)=>cleanupEligibility({now,record,maxGrantPermittedUntil:r?.max_grant_permitted_until as number|null??null,pendingProviderIntent:r?.pending_provider_intent===1,reconciliationReference:r?.reconciliation_reference===1,approvedHoldRequiresRow:r?.approved_hold_requires_row===1}).kind==='eligible';
   const add=(table:Candidate['table'],key:string,row:Row,record:RetentionRecord)=>{if(candidates.length<input.limit&&eligible(record,row))candidates.push({table,key,row,record});};
   for(const row of await this.rows('SELECT * FROM challenges WHERE email_hmac=? OR bound_account_id=? ORDER BY challenge_id LIMIT 100',a.email_hmac,g.accountID))add('challenges','challenge_id',row,{category:'challenge',createdAt:Number(row.created_at)});
   const sessions=await this.rows('SELECT * FROM sessions WHERE account_id=? ORDER BY session_id LIMIT 101',g.accountID);if(sessions.length>100)return await this.currentGuard(g)?{status:200,body:input.dryRun?{eligible:0}:{deleted:0}}:refuse();
   for(const row of sessions)if((time(row.expires_at)&&row.expires_at<=now)||row.revoked_at!==null)add('sessions','session_id',row,{category:'session',firstExpiresAt:Number(row.expires_at),firstRevokedAt:row.revoked_at as number|null});
   for(const row of await this.rows('SELECT * FROM trial_requests WHERE account_id=? ORDER BY request_id LIMIT 100',g.accountID))add('trial_requests','request_id',row,{category:'ordinary-retry',createdAt:Number(row.created_at),terminalResultAt:Number(row.created_at),abandoned:false});
   for(const row of await this.rows('SELECT * FROM retention_rows WHERE account_id=? ORDER BY row_id LIMIT 100',g.accountID)){try{add('retention_rows','row_id',row,JSON.parse(String(row.record_json)) as RetentionRecord);}catch{/* Unknown rows held above. */}}
   if(input.dryRun)return await this.currentGuard(g)?{status:200,body:{eligible:candidates.length}}:refuse();
   if(!candidates.length)return await this.currentGuard(g)?{status:200,body:{deleted:0}}:refuse();
   const f=this.fence(g),statements=this.begin(g,[...p.conditions,this.snapshot('accounts','account_id',g.accountID,a),...candidates.map(c=>this.snapshot(c.table,c.key,String(c.row[c.key]),c.row))]);
   for(const c of candidates){
    if(c.table==='sessions')statements.push(this.stmt(`DELETE FROM used_refresh_tokens WHERE session_id=? AND ${f.sql}`,c.row.session_id,...f.args));
    // Trial request identity includes account; a request name is never global.
    statements.push(this.stmt(`DELETE FROM ${c.table} WHERE ${c.key}=? ${c.table==='trial_requests'?'AND account_id=?':''} AND ${f.sql}`,c.row[c.key],...(c.table==='trial_requests'?[g.accountID]:[]),...f.args),this.assertChanges());
   }
   statements.push(...this.finish(g,'cleanup',now));await this.dependencies!.db.batch(statements);return {status:200,body:{deleted:candidates.length}};
  }catch{return refuse();}
 }
 async issue(input:ActivationRequest):Promise<MutationResult>{return this.activation(input,false);}
 async release(input:ActivationRequest):Promise<MutationResult>{return this.activation(input,true);}
 private async activation(input:ActivationRequest,release:boolean):Promise<MutationResult>{
  if(!this.ready())return refuse(503);if(!closed(input,['credential','guard','activationID'])||!credential(input.credential)||!guardOK(input.guard)||!id(input.activationID))return refuse(400);
  try{
   const now=this.dependencies!.now();if(!time(now))return refuse();const g=input.guard,auth=await this.auth(input.credential,g,now);if(!auth)return refuse(401);
   const a=await this.account(g),h=await this.row('SELECT * FROM lease_heads WHERE activation_id=? AND account_id=?',input.activationID,g.accountID);if(!a||a.revoked_at!==null||!h||h.released_at!==null||!this.headValid(h,now))return refuse();
   const legacy=legacyHeadCondition(await inspectSchema(this.dependencies!.db),input.activationID,g.accountID);if(!legacy||!await this.row(`SELECT 1 AS valid WHERE ${legacy.sql}`,...legacy.args))return refuse();
   const source=await this.row('SELECT * FROM entitlement_sources WHERE account_id=?',g.accountID);let envelope:Uint8Array|null=null;let claims:LeaseClaims|undefined;let billingConditions:readonly Condition[]=[];
   if(!release){
    if(Number(a.entitlement_revision)<1)return refuse();
    const loaded=await loadEntitlementSnapshot(this.dependencies!.db,g.accountID,now);if(loaded.outcome!=='loaded')return refuse();const selected=planSourceSelection(loaded.snapshot),conditions=billingSnapshotConditions(loaded.snapshot);if(!selected||!conditions)return refuse();billingConditions=conditions;
    const state=selected.state,end=selected.state==='paid'?selected.paidThrough:selected.state==='grace'?selected.graceDeadline:selected.state==='beta'?selected.hardEnd:selected.state==='trial'?selected.expiresAt:now;
    const permittedUntil=Math.min(end,now+2592000);if(!time(end)||!time(permittedUntil))return refuse();
    claims={schemaVersion:1,issuer:'im.patched.licence',audience:'im.patched.mac',accountID:g.accountID,activationID:input.activationID,deviceKeySHA256:String(h.device_key_sha256),state,entitlementRevision:Number(a.entitlement_revision),activationRevision:Number(h.activation_revision),sequence:Number(h.sequence)+1,issuedAt:now,permittedUntil,hardEnd:end,...(selected.state==='paid'?{paid:{paidThrough:selected.paidThrough}}:selected.state==='grace'?{grace:{paidThrough:selected.paidThrough,graceDeadline:selected.graceDeadline}}:selected.state==='trial'?{trial:{startedAt:selected.startedAt,expiresAt:selected.expiresAt}}:{})};
    envelope=await produceLease(claims,this.dependencies!.signer);if(!envelope)return refuse(503);
   }
   const f=this.fence(g),statements=this.begin(g,[auth,legacy,...billingConditions,this.snapshot('accounts','account_id',g.accountID,a),this.snapshot('lease_heads','activation_id',input.activationID,h),this.snapshot('entitlement_sources','account_id',g.accountID,source)]);
   if(release)statements.push(this.stmt(`UPDATE lease_heads SET released_at=?,activation_revision=activation_revision+1,commit_nonce=? WHERE activation_id=? AND ${f.sql}`,now,g.commitNonce,input.activationID,...f.args),this.assertChanges());
   else {
    const granting=claims!.permittedUntil>now;
    statements.push(this.stmt(`UPDATE lease_heads SET sequence=sequence+1,commit_nonce=?,last_grant_state=CASE WHEN ? THEN ? ELSE last_grant_state END,last_grant_issued_at=CASE WHEN ? THEN ? ELSE last_grant_issued_at END,last_grant_permitted_until=CASE WHEN ? THEN ? ELSE last_grant_permitted_until END,last_grant_hard_end=CASE WHEN ? THEN ? ELSE last_grant_hard_end END,max_grant_permitted_until=CASE WHEN ? THEN MAX(COALESCE(max_grant_permitted_until,0),?) ELSE max_grant_permitted_until END WHERE activation_id=? AND ${f.sql}`,g.commitNonce,granting?1:0,claims!.state,granting?1:0,now,granting?1:0,claims!.permittedUntil,granting?1:0,claims!.hardEnd,granting?1:0,claims!.permittedUntil,input.activationID,...f.args),this.assertChanges());
   }
   statements.push(...this.finish(g,release?'lease-release':'lease-issue',now));await this.dependencies!.db.batch(statements);
   return {status:200,body:release?{outcome:'released'}:{outcome:'issued',envelope:new TextDecoder().decode(envelope!)}};
  }catch{return refuse();}
 }
}

// A bounded recursive parser rejects duplicate object keys after escape decoding.
// It has no reviver or executable input. Depth is independently bounded.
function strictJSON(source: string): unknown {
  let i=0;
  const whitespace=()=>{while(/[\x20\x09\x0a\x0d]/.test(source[i]??'!')) i++;};
  const string=():string=>{const start=i++;while(i<source.length){const c=source[i++];if(c==='"') return JSON.parse(source.slice(start,i)) as string;if(c==='\\')i++;}throw new Error('string refused');};
  const value=(depth:number):unknown=>{
    if(depth>32)throw new Error('depth refused');whitespace();const c=source[i];
    if(c==='"')return string();
    if(c==='{'){i++;whitespace();const out:Record<string,unknown>=Object.create(null);const names=new Set<string>();if(source[i]==='}'){i++;return out;}while(true){whitespace();if(source[i]!=='"')throw new Error('key refused');const key=string();if(names.has(key))throw new Error('duplicate refused');names.add(key);whitespace();if(source[i++]!==':')throw new Error('colon refused');out[key]=value(depth+1);whitespace();const end=source[i++];if(end==='}')return out;if(end!==',')throw new Error('object refused');}}
    if(c==='['){i++;whitespace();const out:unknown[]=[];if(source[i]===']'){i++;return out;}while(true){out.push(value(depth+1));whitespace();const end=source[i++];if(end===']')return out;if(end!==',')throw new Error('array refused');}}
    const match=source.slice(i).match(/^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/);if(!match)throw new Error('value refused');i+=match[0].length;return JSON.parse(match[0]);
  };
  const parsed=value(0);whitespace();if(i!==source.length)throw new Error('trailing refused');return parsed;
}
/** Key material arrives only in the explicit synthetic header. The public fixture
 * identity is checked by Ed25519 verification; its private seed is never defaulted. */
async function headerSigner(raw:string):Promise<SyntheticSigner|null>{
 try{
  if(!/^[A-Za-z0-9+/]{43}=$/.test(raw))return null;const seed=Uint8Array.from(atob(raw),c=>c.charCodeAt(0));if(seed.length!==32||btoa(String.fromCharCode(...seed))!==raw)return null;
  const prefix=Uint8Array.from([0x30,0x2e,0x02,0x01,0,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x04,0x22,0x04,0x20]),der=new Uint8Array(48);der.set(prefix);der.set(seed,16);
  const privateKey=await crypto.subtle.importKey('pkcs8',der,{name:'Ed25519'},false,['sign']);
  // Public TEST-only L1 key, also independently checked by the immutable corpus.
  const publicKey=await crypto.subtle.importKey('jwk',{kty:'OKP',crv:'Ed25519',x:'GivlKhF1F-EVlA7FE1xzas09V9Z5uGbCD0styu-uJRo',ext:true},{name:'Ed25519'},false,['verify']);
  const message=new TextEncoder().encode('PAT-2643-synthetic-key-check');const proof=await crypto.subtle.sign('Ed25519',privateKey,message);if(!await crypto.subtle.verify('Ed25519',publicKey,proof,message))return null;
  return {marker:'PAT-2643-synthetic',keyID:'fixture-only-1',sign:async bytes=>new Uint8Array(await crypto.subtle.sign('Ed25519',privateKey,bytes as Uint8Array<ArrayBuffer>))};
 }catch{return null;}
}
export async function fixtureLicensingFetch(request:Request,env:FixtureEnvironment):Promise<Response>{
 const response=(status:number,body:unknown)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}}),failure=(status:number)=>response(status,{outcome:'refused'});
 const path=new URL(request.url).pathname,prefix='/__fixture/licensing/';const route=path.startsWith(prefix)?path.slice(prefix.length):'';
 if(!['start','delete','cleanup','issue','release'].includes(route))return failure(404);if(request.method!=='POST')return failure(405);
 const rawNow=request.headers.get('x-fixture-now')??'',seed=request.headers.get('x-fixture-seed')??'',delivery=request.headers.get('x-fixture-delivery');
 if(env.ENVIRONMENT!=='local-fixture'||env.FIXTURE_MARKER!=='PAT-2639-local-only'||env.PROVIDER_MODE!=='fake'||!env.FIXTURE_DB||request.headers.get('x-fixture-key')!=='PAT-2643-synthetic'||!fixtureRandom(seed)||!/^(0|[1-9][0-9]*)$/.test(rawNow)||!time(Number(rawNow))||!['capture','refuse'].includes(delivery??''))return failure(503);
 const signer=await headerSigner(request.headers.get('x-fixture-signing-seed')??'');if(!signer)return failure(503);
 let input:unknown;
 try{
  const reader=request.body?.getReader(),chunks:Uint8Array[]=[];let size=0;if(reader)while(true){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>2048){await reader.cancel();return failure(413);}chunks.push(part.value);}
  const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}input=strictJSON(new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(bytes));
 }catch{return failure(400);}
 const service=new TrialService({db:env.FIXTURE_DB,now:()=>Number(rawNow),marker:'PAT-2643-synthetic',syntheticKey:new Uint8Array(32).fill(7),signer});
 const result=route==='start'?await service.startResult(input as TrialStart):route==='delete'?await service.deleteAccount(input as AccountDeletion):route==='cleanup'?await service.cleanup(input as CleanupRequest):route==='issue'?await service.issue(input as ActivationRequest):await service.release(input as ActivationRequest);
 return response(result.status,result.body);
}
