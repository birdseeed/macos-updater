import {AuthService,type SessionCredential} from '../auth';
import {TrialService,decideTrial} from '../entitlements';
import {ActivationService,type ActivationListResult} from '../activations';
import {loadEntitlementSnapshot,planSourceSelection,billingSnapshotConditions} from '../entitlementPlans';
import {snapshot} from '../activationPlans';
import {strictJSON,hex,sha256,encode} from '../deviceProof';
import type {AuthorizedPrincipal,SQLCondition} from '../sessionAuthorization';
export interface AccountWebComposition {
 marker:'PAT-2649-account-web-synthetic'; db:D1Database; now:()=>number;
 randomBytes:(length:number)=>Uint8Array; syntheticKey:Uint8Array; csrfKey:Uint8Array;
 allowedOrigin:string; assets:{html:string;js:string;css:string};
}
type Row=Record<string,any>;
const root='/__fixture/web/account',cookieName='__Host-patched-fixture-session';
const encoder=new TextEncoder();
const time=(x:unknown):x is number=>typeof x==='number'&&Number.isSafeInteger(x)&&x>=0&&x<=253402300799;
const revision=(x:unknown):x is number=>typeof x==='number'&&Number.isSafeInteger(x)&&x>=0&&x<Number.MAX_SAFE_INTEGER&&!Object.is(x,-0);
const id=(x:unknown):x is string=>typeof x==='string'&&/^[a-f0-9]{32}$/.test(x);
const closed=(x:unknown,k:string[]):x is Record<string,unknown>=>!!x&&typeof x==='object'&&!Array.isArray(x)&&Reflect.ownKeys(x).length===k.length&&k.every(n=>Object.hasOwn(x,n));
const security={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"};
const json=(status:number,body:unknown,extra:Record<string,string>={})=>Response.json(body,{status,headers:{...security,...extra}});
const refused=(status:number)=>json(status,{outcome:'refused'});
function copyComposition(c?:AccountWebComposition):AccountWebComposition|null {
 try {
  if(!closed(c,['marker','db','now','randomBytes','syntheticKey','csrfKey','allowedOrigin','assets'])||c.marker!=='PAT-2649-account-web-synthetic'||!c.db||typeof c.now!=='function'||typeof c.randomBytes!=='function'||!(c.syntheticKey instanceof Uint8Array)||c.syntheticKey.length!==32||!(c.csrfKey instanceof Uint8Array)||c.csrfKey.length!==32||c.syntheticKey.every((v,i)=>v===c.csrfKey[i])||!closed(c.assets,['html','js','css'])||Object.values(c.assets).some(v=>typeof v!=='string'))return null;
  const u=new URL(c.allowedOrigin);if(u.protocol!=='https:'||u.origin!==c.allowedOrigin||u.username||u.password)return null;
  return Object.freeze({...c,syntheticKey:new Uint8Array(c.syntheticKey),csrfKey:new Uint8Array(c.csrfKey),assets:Object.freeze({...c.assets})});
 }catch{return null;}
}
function cookie(raw:string|null):SessionCredential|null {
 if(!raw)return null;if(encoder.encode(raw).length>4096)throw Error('cookie');
 const selected=raw.split(';').map(x=>x.trim()).filter(x=>x.split('=')[0]===cookieName);
 if(!selected.length)return null;if(selected.length!==1)throw Error('cookie');
 const m=selected[0].match(/^__Host-patched-fixture-session=([a-f0-9]{32})\.([a-f0-9]{64})$/);if(!m)throw Error('cookie');
 return {sessionID:m[1],accessToken:m[2]};
}
function csrfMessage(p:AuthorizedPrincipal,s:Row,credential:SessionCredential,origin:string):Uint8Array {
 const fields=[p.accountID,p.sessionID,sha256(encoder.encode(credential.accessToken)),origin,String(s.created_at),String(s.expires_at)].map(x=>encoder.encode(x));
 const domain=encoder.encode('im.patched.web-csrf.v1'),bytes=new Uint8Array(domain.length+fields.reduce((n,b)=>n+4+b.length,0));bytes.set(domain);let at=domain.length;
 for(const field of fields){new DataView(bytes.buffer).setUint32(at,field.length,false);at+=4;bytes.set(field,at);at+=field.length;}return bytes;
}
async function csrfKey(c:AccountWebComposition):Promise<CryptoKey>{return crypto.subtle.importKey('raw',c.csrfKey as Uint8Array<ArrayBuffer>,{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);}
async function body(request:Request):Promise<unknown>{
 const reader=request.body?.getReader(),chunks:Uint8Array[]=[];let size=0;
 if(reader)while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>2048){await reader.cancel();throw 413;}chunks.push(part.value);}
 const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}
 try{return strictJSON(bytes,2048);}catch{throw 400;}
}
function condition(table:'account_guard'|'trial_markers',row:Row):SQLCondition {
 const columns=table==='account_guard'?['account_id','account_revision','commit_nonce']:['email_hmac','original_deleted_at','expires_at'];
 return {sql:`EXISTS(SELECT 1 FROM ${table} WHERE ${columns.map(k=>`${k} IS ?`).join(' AND ')})`,args:columns.map(k=>row[k])};
}
async function state(c:AccountWebComposition,now:number,p:AuthorizedPrincipal,s:Row,credential:SessionCredential):Promise<Response> {
 const db=c.db,read=async(sql:string,...args:(string|number|null)[])=>db.prepare(sql).bind(...args).first<Row>();
 const account=await read('SELECT * FROM accounts WHERE account_id=?',p.accountID),guard=await read('SELECT * FROM account_guard WHERE account_id=?',p.accountID),source=await read('SELECT * FROM entitlement_sources WHERE account_id=?',p.accountID);
 if(!account||!guard||!revision(guard.account_revision)||!revision(account.entitlement_revision)||!revision(account.activation_revision))return refused(503);
 const marker=await read('SELECT * FROM trial_markers WHERE email_hmac=?',account.email_hmac);
 const loaded=await loadEntitlementSnapshot(db,p.accountID,now);if(loaded.outcome!=='loaded')return refused(503);
 const selection=planSourceSelection(loaded.snapshot),billing=billingSnapshotConditions(loaded.snapshot);if(!selection||!billing)return refused(503);
 // Capture exactly the source-owned rows validated by A2.list, through its one
 // transactional four-table read. This private observer supplies no authority.
 let captures:Row[][]|undefined;
 const listDB=new Proxy(db,{get(target,key){if(key==='batch')return async(statements:D1PreparedStatement[])=>{const result=await target.batch<Row>(statements);if(statements.length===4)captures=result.map(r=>r.results);return result;};const value=Reflect.get(target,key);return typeof value==='function'?value.bind(target):value;}});
 const listing:ActivationListResult=await new ActivationService({db:listDB,now:()=>now,randomBytes:c.randomBytes,marker:'PAT-2644-synthetic',syntheticKey:c.syntheticKey,requiredSessionKind:'web',p256Verifier:{marker:'PAT-2644-synthetic',verify:async()=>false}}).list(credential);
 if(listing.status!==200||!captures||captures.length!==4)return refused(503);
 const conditions:SQLCondition[]=[p.condition,snapshot('sessions',s),snapshot('accounts',account),condition('account_guard',guard),source?snapshot('entitlement_sources',source):{sql:'NOT EXISTS(SELECT 1 FROM entitlement_sources WHERE account_id=?)',args:[p.accountID]},marker?condition('trial_markers',marker):{sql:'NOT EXISTS(SELECT 1 FROM trial_markers WHERE email_hmac=?)',args:[account.email_hmac]},...billing];
 for(const [i,table] of ['accounts','lease_heads','activations','activation_slots'].entries()){
  const rows=captures[i];if(!Array.isArray(rows)||rows.length>100)return refused(503);
  conditions.push({sql:`(SELECT COUNT(*) FROM ${table} WHERE account_id=?)=?`,args:[p.accountID,rows.length]},...rows.map(r=>snapshot(table,r)));
 }
 if(conditions.length>1024||conditions.some(x=>x.args.length>100))return refused(503);
 const checked=await db.batch<{valid:number}>(conditions.map(x=>db.prepare(`SELECT 1 AS valid WHERE (${x.sql})`).bind(...x.args)));
 if(checked.length!==conditions.length||checked.some(x=>!x.success||x.results.length!==1||x.results[0].valid!==1))return refused(503);
 const trial=decideTrial({now,trialStartedAt:source?.trial_started_at??null,trialEndsAt:source?.trial_ends_at??null,betaInvited:source?.beta_invited===1,betaEndsAt:source?.beta_ends_at??null,revoked:false,marker:marker?{originalDeletedAt:marker.original_deleted_at,expiresAt:marker.expires_at}:null});
 const trialAvailable=trial.outcome==='started';
 const reason=trialAvailable?null:trial.outcome==='trial-unavailable-during-beta'?'activeBeta':source?.trial_started_at!==null&&source?.trial_started_at!==undefined?'used':marker?'retainedMarker':'verificationRequired';
 const endsAt=selection.state==='paid'?selection.paidThrough:selection.state==='grace'?selection.graceDeadline:selection.state==='beta'?source?.beta_ends_at??null:selection.state==='trial'?selection.expiresAt:null;
 const key=await csrfKey(c),csrfToken=hex(new Uint8Array(await crypto.subtle.sign('HMAC',key,csrfMessage(p,s,credential,c.allowedOrigin) as Uint8Array<ArrayBuffer>)));
 return json(200,{outcome:'account',accountRevision:guard.account_revision,entitlementRevision:account.entitlement_revision,activationRevision:account.activation_revision,serverNow:now,sessionExpiresAt:s.expires_at,reauthRequired:p.authenticatedAt<=now-600,csrfToken,licence:{state:selection.state,endsAt,trialAvailable,trialUnavailableReason:reason},slots:{limit:listing.body.limit,used:listing.body.used,macs:listing.body.activations}});
}
export function createAccountWebHandler(composition?:AccountWebComposition):(request:Request)=>Promise<Response> {
 const c=copyComposition(composition);
 return async(request:Request)=>{
  if(!c)return refused(503);
  try{
   const now=c.now();if(!time(now))return refused(503);
   const u=new URL(request.url);if(u.origin!==c.allowedOrigin||u.username||u.password||request.url.includes('?')||request.url.includes('#')||u.pathname.includes('%'))return refused(400);
   if([...request.headers.keys()].some(k=>k==='authorization'||k.startsWith('x-fixture-')))return refused(400);
   const path=u.pathname;let route:string,target:string|undefined;
   if([root,root+'/state',root+'/account.js',root+'/account.css',root+'/trial',root+'/logout'].includes(path))route=path.slice(root.length);
   else {const m=path.match(/^\/__fixture\/web\/account\/macs\/([a-f0-9]{32})\/deactivate$/);if(!m)return refused(404);route='/deactivate';target=m[1];}
   const mutation=['/trial','/logout','/deactivate'].includes(route);if(request.method!==(mutation?'POST':'GET'))return refused(405);
   if(!mutation&&route!=='/state'){const kind=route==='/account.js'?'js':route==='/account.css'?'css':'html';return new Response(c.assets[kind],{status:200,headers:{...security,'Content-Type':kind==='js'?'text/javascript; charset=utf-8':kind==='css'?'text/css; charset=utf-8':'text/html; charset=utf-8'}});}
   let credential:SessionCredential|null;try{credential=cookie(request.headers.get('Cookie'));}catch{return refused(400);}if(!credential)return refused(401);
   const d={db:c.db,now:()=>now,randomBytes:c.randomBytes,syntheticKey:c.syntheticKey,requiredSessionKind:'web' as const,delivery:async()=>{throw Error('no delivery');}};
   const auth=new AuthService(d),principal=await auth.authorize(credential,{kind:'ordinary'});if(!principal)return refused(401);
   const s=await c.db.prepare('SELECT * FROM sessions WHERE session_id=?').bind(credential.sessionID).first<Row>();if(!s)return refused(401);
   const activation=new ActivationService({...d,marker:'PAT-2644-synthetic',p256Verifier:{marker:'PAT-2644-synthetic',verify:async()=>false}});
   if(!mutation)return await state(c,now,principal,s,credential);
   if(request.headers.get('Origin')!==c.allowedOrigin)return refused(403);
   const wire=request.headers.get('X-CSRF-Token');if(!wire||!/^[a-f0-9]{64}$/.test(wire))return refused(403);
   const signature=Uint8Array.from(wire.match(/../g)!,x=>parseInt(x,16));if(!await crypto.subtle.verify('HMAC',await csrfKey(c),signature,csrfMessage(principal,s,credential,c.allowedOrigin) as Uint8Array<ArrayBuffer>))return refused(403);
   if(request.headers.get('Content-Type')!=='application/json')return refused(400);
   const input=await body(request);
   if(route==='/logout'){
    if(!closed(input,[]))return refused(400);
    const result=await auth.logout(credential);return json(result.status,result.body,result.status===200?{'Set-Cookie':`${cookieName}=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT`}:{});
   }
   const keys=route==='/trial'?['expectedAccountRevision','requestID']:['expectedAccountRevision','expectedActivationRevision','requestID'];
   if(!closed(input,keys)||!revision(input.expectedAccountRevision)||!id(input.requestID)||(route==='/deactivate'&&(!revision(input.expectedActivationRevision)||input.expectedActivationRevision<1)))return refused(400);
   if(route==='/trial'&&principal.authenticatedAt<=now-600)return json(401,{outcome:'reauthRequired'});
   const bytes=c.randomBytes(16);if(!(bytes instanceof Uint8Array)||bytes.length!==16)return refused(503);
   const guard={accountID:principal.accountID,accountRevision:input.expectedAccountRevision,commitNonce:hex(bytes)};
   if(route==='/trial'){
    const canonical=JSON.stringify({route:root+'/trial',expectedAccountRevision:input.expectedAccountRevision,requestID:input.requestID});
    const result=await new TrialService({...d,marker:'PAT-2643-synthetic'}).startResult({credential,guard,requestID:input.requestID,requestHash:sha256(encoder.encode('im.patched.web-trial.v1\0'+canonical))});return json(result.status,result.body);
   }
   const action=encode(encoder.encode(JSON.stringify({requestID:input.requestID,activationID:target,expectedRevision:input.expectedActivationRevision})));
   const result=await activation.deactivate({credential,guard,body:encoder.encode(JSON.stringify({action}))},target!);return json(result.status,result.body);
  }catch(error){return refused(error===413?413:error===400?400:503);}
 };
}
