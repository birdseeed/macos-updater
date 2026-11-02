import {AuthService,type AuthResult} from '../auth';
import type {AccountWebComposition} from './account';
const id=(x:unknown):x is string=>typeof x==='string'&&/^[a-f0-9]{32}$/.test(x);
const token=(x:unknown):x is string=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const time=(x:unknown):x is number=>typeof x==='number'&&Number.isSafeInteger(x)&&x>=0&&x<=253402300799;
const closed=(x:unknown,k:string[]):x is Record<string,unknown>=>!!x&&typeof x==='object'&&!Array.isArray(x)&&Reflect.ownKeys(x).length===k.length&&k.every(n=>Object.hasOwn(x,n));
const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
export async function issueConsumedWebSession(result:AuthResult,composition?:AccountWebComposition):Promise<Response> {
 const refuse=(status:number)=>Response.json({outcome:'refused'},{status,headers});
 try {
  const c=composition;
  if(!closed(c,['marker','db','now','randomBytes','syntheticKey','csrfKey','allowedOrigin','assets'])||c.marker!=='PAT-2649-account-web-synthetic'||!c.db||typeof c.now!=='function'||typeof c.randomBytes!=='function'||!(c.syntheticKey instanceof Uint8Array)||c.syntheticKey.length!==32||!(c.csrfKey instanceof Uint8Array)||c.csrfKey.length!==32||c.syntheticKey.every((v,i)=>v===c.csrfKey[i])||!closed(c.assets,['html','js','css'])||Object.values(c.assets).some(v=>typeof v!=='string'))return refuse(503);
  const origin=new URL(c.allowedOrigin);if(origin.protocol!=='https:'||origin.origin!==c.allowedOrigin||origin.username||origin.password)return refuse(503);
  const db=c.db,key=new Uint8Array(c.syntheticKey),randomBytes=c.randomBytes,clock=c.now;
  const now=clock();if(!time(now))return refuse(503);
  if(!closed(result,['status','body'])||result.status!==200||!closed(result.body,['outcome','accountID','sessionID','accessToken','accessExpiresAt','expiresAt']))return refuse(400);
  const b={...result.body};
  if(b.outcome!=='signed-in'||!id(b.accountID)||!id(b.sessionID)||!token(b.accessToken)||!time(b.accessExpiresAt)||!time(b.expiresAt))return refuse(400);
  const auth=new AuthService({db,now:()=>now,randomBytes,syntheticKey:key,requiredSessionKind:'web',delivery:async()=>{throw Error('delivery unavailable');}});
  const principal=await auth.authorize({sessionID:b.sessionID,accessToken:b.accessToken},{kind:'ordinary'});
  if(!principal||principal.accountID!==b.accountID)return refuse(401);
  const results=await db.batch<{valid:number}>([db.prepare(`SELECT 1 AS valid WHERE (${principal.condition.sql}) AND EXISTS(SELECT 1 FROM sessions WHERE session_id=? AND account_id=? AND access_expires_at=? AND expires_at=?)`).bind(...principal.condition.args,b.sessionID,b.accountID,b.accessExpiresAt,b.expiresAt)]);
  if(results.length!==1||!results[0].success||results[0].results.length!==1||results[0].results[0].valid!==1)return refuse(401);
  const cookie=`__Host-patched-fixture-session=${b.sessionID}.${b.accessToken}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=${b.expiresAt-now}; Expires=${new Date(b.expiresAt*1000).toUTCString()}`;
  return Response.json({outcome:'sessionIssued'},{status:200,headers:{...headers,'Set-Cookie':cookie}});
 }catch{return refuse(503);}
}
