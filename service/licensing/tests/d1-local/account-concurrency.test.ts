// Actual local D1/workerd only. Runtime fixture controls are synthetic facts, never authority.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { accountRuntime } from './account-runtime.ts';
const service = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const source = JSON.parse(readFileSync(resolve(service,'wrangler.jsonc'),'utf8'));
assert.deepEqual(source.vars,{ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'});
assert.deepEqual(source.d1_databases,[{binding:'FIXTURE_DB',database_name:'licensing-local-fixture',database_id:'00000000-0000-0000-0000-000000000000',remote:false}]);
assert.equal(source.workers_dev,false); assert.equal(source.preview_urls,false); assert.equal(source.account_id,undefined); assert.equal(source.routes,undefined); assert.equal(source.env,undefined);

let output='';
const runtime=await accountRuntime({onLog:message=>{output+=message;}});
const run=runtime.run;
async function d1(args:string[]):Promise<void>{
 if(args[0]==='--file'){
  assert.equal(args.length,2);assert.equal(args[1],resolve(service,'migrations','0001_accounts.sql'));
  const sql=readFileSync(args[1],'utf8').replace(/^\s*--.*$/mg,'');
  let quoted=false;for(let i=0;i<sql.length;i++){if(sql[i]==="'"){if(quoted&&sql[i+1]==="'"){i++;continue;}quoted=!quoted;}if(sql[i]===';')assert.equal(quoted,false,'quoted semicolon unsupported');}assert.equal(quoted,false);
  assert.ok(!/\bTRIGGER\b|\/\*|["`\[\]]/i.test(sql.replace(/'(?:[^']|'')*'/g,'')),'migration syntax outside reviewed subset');
  await runtime.db.batch(sql.split(';').map(s=>s.trim()).filter(Boolean).map(s=>runtime.db.prepare(s)));
 }else{assert.equal(args.length,2);assert.equal(args[0],'--command');await runtime.db.prepare(args[1]).run();}
}
async function rows(sql:string):Promise<Record<string,unknown>[]>{return (await runtime.db.prepare(sql).all()).results;}
async function count(table: string): Promise<number> { assert.match(table,/^(accounts|account_guard|sessions|challenges|account_audit|used_refresh_tokens|account_requests|request_limits)$/); return Number((await rows(`SELECT COUNT(*) AS n FROM ${table}`))[0].n); }
async function snapshot(): Promise<unknown> { return Promise.all(['accounts','account_guard','sessions','challenges','account_audit','used_refresh_tokens','account_requests'].map(async t=>(await rows(`SELECT * FROM ${t} ORDER BY 1`)))); }

const origin=runtime.origin; const initial=1791734400; const code='01234567'; let emailCounter=0; let requestCounter=0; let ipCounter=0;
function email(): string { return `case${++emailCounter}@example.invalid`; }
async function post(route:string, input:unknown, now=initial, delivery='capture', key='PAT-2642-synthetic', seed=(++requestCounter).toString(16).padStart(32,'0')) {
 const response=await fetch(origin+'/__fixture/accounts/'+route,{method:'POST',headers:{'Connection':'close','Content-Type':'application/json','x-fixture-now':String(now),'x-fixture-delivery':delivery,'x-fixture-key':key,'x-fixture-seed':seed},body:JSON.stringify(input),redirect:'error',signal:AbortSignal.timeout(10000)});
 assert.ok(response.status<500,`unexpected infrastructure/refusal failure ${route}: ${response.status}`);
 return {status:response.status,body:await response.json() as Record<string,unknown>};
}
async function request(address:string,purpose='app-sign-in',now=initial,binding?:unknown,sourceIP=`192.0.${Math.floor(++ipCounter/250)}.${ipCounter%250+1}`) {
 const result=await post('request',{email:address,purpose,sourceIP,...(binding?{binding}:{})},now); assert.equal(result.status,202);assert.deepEqual(Object.keys(result.body).sort(),['challengeID','outcome']);assert.equal(result.body.outcome,'accepted');assert.match(String(result.body.challengeID),/^[a-f0-9]{32}$/);return String(result.body.challengeID);
}
async function consume(challengeID:string,purpose='app-sign-in',now=initial,binding?:unknown,attemptCode=code) { return post('consume',{challengeID,purpose,code:attemptCode,...(binding?{binding}:{})},now); }
async function signedIn(address=email(),purpose='app-sign-in',now=initial) { const challenge=await request(address,purpose,now);const result=await consume(challenge,purpose,now);assert.equal(result.status,200);assert.equal(result.body.outcome,'signed-in');assert.match(String(result.body.accountID),/^[a-f0-9]{32}$/);assert.match(String(result.body.sessionID),/^[a-f0-9]{32}$/);assert.match(String(result.body.accessToken),/^[a-f0-9]{64}$/);assert.deepEqual(Object.keys(result.body).sort(),(purpose==='app-sign-in'?['outcome','accountID','sessionID','accessToken','accessExpiresAt','expiresAt','refreshToken']:['outcome','accountID','sessionID','accessToken','accessExpiresAt','expiresAt']).sort());return result.body; }
function credential(s:Record<string,unknown>) { return {sessionID:s.sessionID,accessToken:s.accessToken}; }
function binding(s:Record<string,unknown>) { return {accountID:s.accountID,sessionID:s.sessionID}; }
async function refusedConsume(challenge:string,purpose='app-sign-in',now=initial,b?:unknown,c=code) { const r=await consume(challenge,purpose,now,b,c);assert.equal(r.status,401);assert.deepEqual(r.body,{outcome:'refused'}); }
try {
 await d1(['--file',resolve(service,'migrations/0001_accounts.sql')]);
 assert.equal((await count('accounts')),0); assert.equal((await count('sessions')),0);
 await test('request alone creates no account/session and returns generic fresh challenges',async()=>{
  const before=[(await count('accounts')),(await count('sessions'))];const address=email();const a=await request(address);const b=await request(address);assert.notEqual(a,b);assert.deepEqual([(await count('accounts')),(await count('sessions'))],before);await refusedConsume(a);await refusedConsume(b); // second request is email-limited, both are unconsumable
 });
 await test('sequential repeated request entropy refuses uniformly and preserves the initial usable challenge',async()=>{
  const knownAddress=email();await signedIn(knownAddress);const address=email();const seed='a'.repeat(32);
  const headers={'Connection':'close','Content-Type':'application/json','x-fixture-now':String(initial),'x-fixture-delivery':'capture','x-fixture-key':'PAT-2642-synthetic','x-fixture-seed':seed};
  const send=async(recipient:string)=>{const response=await fetch(origin+'/__fixture/accounts/request',{method:'POST',headers,body:JSON.stringify({email:recipient,purpose:'app-sign-in',sourceIP:'203.0.113.210'}),redirect:'error',signal:AbortSignal.timeout(10000)});return {status:response.status,body:await response.json() as Record<string,unknown>};};
  const accounts=(await count('accounts'));const sessions=(await count('sessions'));const first=await send(address);assert.equal(first.status,202);assert.deepEqual(Object.keys(first.body).sort(),['challengeID','outcome']);assert.equal(first.body.outcome,'accepted');const challenge=String(first.body.challengeID);assert.match(challenge,/^[a-f0-9]{32}$/);
  const before=(await snapshot());const limits=(await rows('SELECT * FROM request_limits ORDER BY request_id'));
  for(const recipient of [address,email(),knownAddress]){const collision=await send(recipient);assert.equal(collision.status,503);assert.deepEqual(collision.body,{outcome:'refused'});assert.equal(Object.hasOwn(collision.body,'challengeID'),false);assert.deepEqual((await snapshot()),before);assert.deepEqual((await rows('SELECT * FROM request_limits ORDER BY request_id')),limits);}
  assert.equal((await count('accounts')),accounts);assert.equal((await count('sessions')),sessions);const results=await Promise.all(Array.from({length:6},()=>consume(challenge)));assert.equal(results.filter(r=>r.status===200).length,1);assert.equal(results.filter(r=>r.status===401).length,5);assert.equal((await count('accounts')),accounts+1);assert.equal((await count('sessions')),sessions+1);
 });
 await test('concurrent repeated request entropy admits exactly one fresh challenge and refuses every collision',async()=>{
  const address=email();const seed='b'.repeat(32);const accounts=(await count('accounts'));const sessions=(await count('sessions'));const challenges=(await count('challenges'));
  const headers={'Connection':'close','Content-Type':'application/json','x-fixture-now':String(initial),'x-fixture-delivery':'capture','x-fixture-key':'PAT-2642-synthetic','x-fixture-seed':seed};
  const results=await Promise.all(Array.from({length:8},async()=>{const response=await fetch(origin+'/__fixture/accounts/request',{method:'POST',headers,body:JSON.stringify({email:address,purpose:'app-sign-in',sourceIP:'203.0.113.211'}),redirect:'error',signal:AbortSignal.timeout(10000)});return {status:response.status,body:await response.json() as Record<string,unknown>};}));
  assert.equal(results.filter(r=>r.status===202).length,1);assert.equal(results.filter(r=>r.status===503).length,7);for(const collision of results.filter(r=>r.status===503)){assert.deepEqual(collision.body,{outcome:'refused'});assert.equal(Object.hasOwn(collision.body,'challengeID'),false);}
  const winner=results.find(r=>r.status===202)!.body;assert.deepEqual(Object.keys(winner).sort(),['challengeID','outcome']);assert.equal(winner.outcome,'accepted');const challenge=String(winner.challengeID);assert.match(challenge,/^[a-f0-9]{32}$/);assert.equal((await count('challenges')),challenges+1);assert.equal((await rows(`SELECT COUNT(*) AS n FROM request_limits WHERE request_id='${challenge}'`))[0].n,1);assert.equal((await count('accounts')),accounts);assert.equal((await count('sessions')),sessions);
  const consumed=await Promise.all(Array.from({length:8},()=>consume(challenge)));assert.equal(consumed.filter(r=>r.status===200).length,1);assert.equal(consumed.filter(r=>r.status===401).length,7);assert.equal((await count('accounts')),accounts+1);assert.equal((await count('sessions')),sessions+1);
 });
 await test('N-way consume commits exactly one session, consume nonce, guard and audit',async()=>{
  const address=email();const c=await request(address);const before=(await count('sessions'));const results=await Promise.all(Array.from({length:12},()=>consume(c)));
  assert.equal(results.filter(r=>r.status===200).length,1);assert.equal(results.filter(r=>r.status===401).length,11);assert.equal((await count('sessions')),before+1);
  const winner=results.find(r=>r.status===200)!.body;assert.match(String(winner.sessionID),/^[a-f0-9]{32}$/);assert.match(String(winner.accountID),/^[a-f0-9]{32}$/);
  const challenge=(await rows(`SELECT * FROM challenges WHERE challenge_id='${c}'`))[0];assert.ok(challenge.consume_nonce);assert.equal(challenge.consumed_at,initial);
  const session=(await rows(`SELECT * FROM sessions WHERE session_id='${winner.sessionID}'`))[0];assert.equal(session.commit_nonce,challenge.consume_nonce);
  const guard=(await rows(`SELECT * FROM account_guard WHERE account_id='${winner.accountID}'`))[0];assert.equal(guard.commit_nonce,challenge.consume_nonce);
  const audit=(await rows(`SELECT * FROM account_audit WHERE account_id='${winner.accountID}'`));assert.equal(audit.length,1);assert.equal(audit[0].commit_nonce,challenge.consume_nonce);
 });
 await test('same-email concurrent sign-ins create one account with purpose-separated sessions',async()=>{
  const address=email();const a=await request(address,'app-sign-in');const b=await request(address,'web-sign-in',initial+60);const accounts=(await count('accounts'));const sessions=(await count('sessions'));const results=await Promise.all([consume(a,'app-sign-in',initial+60),consume(b,'web-sign-in',initial+60)]);
  assert.deepEqual(results.map(r=>r.status),[200,200]);assert.equal(results[0].body.accountID,results[1].body.accountID);assert.equal((await count('accounts')),accounts+1);assert.equal((await count('sessions')),sessions+2);
 });
 await test('concurrent replacement challenges leave at most the latest eligible one consumable',async()=>{
  const address=email();const first=await request(address);const next=await Promise.all(Array.from({length:6},()=>request(address,'app-sign-in',initial+60)));await refusedConsume(first,'app-sign-in',initial+60);
  const results=await Promise.all(next.map(c=>consume(c,'app-sign-in',initial+60)));assert.ok(results.filter(r=>r.status===200).length<=1);const fresh=await request(address,'app-sign-in',initial+120);assert.equal((await consume(fresh,'app-sign-in',initial+120)).status,200);
 });
 await test('expiry boundary refuses at ten minutes and preserves account/session counts',async()=>{
  const c=await request(email());const before=[(await count('accounts')),(await count('sessions'))];await refusedConsume(c,'app-sign-in',initial+600);assert.deepEqual([(await count('accounts')),(await count('sessions'))],before);
  const d=await request(email());assert.equal((await consume(d,'app-sign-in',initial+599)).status,200);
 });
 await test('five wrong attempts exhaust challenge; sixth correct cannot create session',async()=>{
  const c=await request(email());const before=(await count('sessions'));for(let i=0;i<5;i++)await refusedConsume(c,'app-sign-in',initial,undefined,'99999999');await refusedConsume(c);assert.equal((await count('sessions')),before);assert.equal((await rows(`SELECT wrong_attempts FROM challenges WHERE challenge_id='${c}'`))[0].wrong_attempts,5);
 });
 await test('wrong purpose/unknown challenge refuse without creating accounts',async()=>{
  const c=await request(email());const before=(await count('accounts'));await refusedConsume(c,'web-sign-in');await refusedConsume('0'.repeat(32));assert.equal((await count('accounts')),before);assert.equal((await consume(c)).status,200);
 });
 await test('same address lowercases but dots and plus aliases never merge accounts',async()=>{
  const local=`alias${++emailCounter}`;const a=await signedIn(`${local}+one@example.invalid`);const b=await signedIn(`${local}@example.invalid`);const c=await signedIn(`${local}.one@example.invalid`);assert.equal(new Set([a.accountID,b.accountID,c.accountID]).size,3);
  const d=await signedIn(` ${local.toUpperCase()}@EXAMPLE.INVALID `,'app-sign-in',initial+60);assert.equal(d.accountID,b.accountID);
 });
 await test('reauth binds current account/session and only changes authentication timestamp',async()=>{
  const address=email();const s=await signedIn(address);const other=await signedIn();const beforeSessions=(await count('sessions'));const beforeAccounts=(await count('accounts'));const original=(await rows(`SELECT * FROM sessions WHERE session_id='${s.sessionID}'`))[0];
  const c=await request(address,'app-reauth',initial+60,binding(s));await refusedConsume(c,'app-reauth',initial+61,binding(other));const ok=await consume(c,'app-reauth',initial+61,binding(s));assert.equal(ok.status,200);assert.deepEqual(ok.body,{outcome:'reauthenticated'});
  assert.equal((await count('sessions')),beforeSessions);assert.equal((await count('accounts')),beforeAccounts);const after=(await rows(`SELECT * FROM sessions WHERE session_id='${s.sessionID}'`))[0];assert.equal(after.authenticated_at,initial+61);
  const consumed=(await rows(`SELECT consume_nonce FROM challenges WHERE challenge_id='${c}'`))[0];const audit=(await rows(`SELECT * FROM account_audit WHERE account_id='${s.accountID}' AND action='reauth'`));assert.equal(audit.length,1);assert.equal(audit[0].commit_nonce,consumed.consume_nonce);
  for(const field of ['session_id','account_id','kind','created_at','access_hmac','access_expires_at','refresh_hmac','refresh_expires_at','expires_at'])assert.equal(after[field],original[field]);
 });
 await test('revoked or changed target session refuses pending reauth without partial write',async()=>{
  const address=email();const s=await signedIn(address);const c=await request(address,'app-reauth',initial+60,binding(s));assert.equal((await post('logout',credential(s),initial+61)).status,200);const before=(await snapshot());await refusedConsume(c,'app-reauth',initial+62,binding(s));assert.deepEqual((await snapshot()),before);
 });
 await test('app access expires at 15 minutes; refresh rotates and retry revokes winner',async()=>{
  const s=await signedIn();assert.equal((await post('authenticate',credential(s),initial+899)).status,200);assert.equal((await post('authenticate',credential(s),initial+900)).status,401);
  const r=await post('refresh',{sessionID:s.sessionID,refreshToken:s.refreshToken},initial+900);assert.equal(r.status,200);assert.notEqual(r.body.refreshToken,s.refreshToken);assert.notEqual(r.body.accessToken,s.accessToken);
  assert.equal((await post('authenticate',credential(s),initial+900)).status,401);assert.equal((await post('authenticate',credential({...r.body,sessionID:s.sessionID}),initial+900)).status,200);
  assert.equal((await post('refresh',{sessionID:s.sessionID,refreshToken:s.refreshToken},initial+901)).status,401);assert.equal((await post('authenticate',credential({...r.body,sessionID:s.sessionID}),initial+901)).status,401);
  assert.equal((await post('refresh',{sessionID:s.sessionID,refreshToken:r.body.refreshToken},initial+901)).status,401);
 });
 await test('N-way refresh never leaves two valid refresh tokens',async()=>{
  const s=await signedIn();const results=await Promise.all(Array.from({length:8},()=>post('refresh',{sessionID:s.sessionID,refreshToken:s.refreshToken},initial+1)));assert.equal(results.filter(r=>r.status===200).length,1);assert.equal(results.filter(r=>r.status===401).length,7);const row=(await rows(`SELECT revoked_at FROM sessions WHERE session_id='${s.sessionID}'`))[0];assert.equal(row.revoked_at,initial+1);
 });
 await test('older than immediate previous refresh replay still revokes',async()=>{
  const s=await signedIn();const a=await post('refresh',{sessionID:s.sessionID,refreshToken:s.refreshToken},initial+1);assert.equal(a.status,200);const b=await post('refresh',{sessionID:s.sessionID,refreshToken:a.body.refreshToken},initial+2);assert.equal(b.status,200);
  assert.equal((await post('refresh',{sessionID:s.sessionID,refreshToken:s.refreshToken},initial+3)).status,401);assert.equal((await post('authenticate',credential({...b.body,sessionID:s.sessionID}),initial+3)).status,401);
 });
 await test('app refresh expires at 90 days idle and web never extends 12h absolute expiry',async()=>{
  const s=await signedIn();assert.equal((await post('refresh',{sessionID:s.sessionID,refreshToken:s.refreshToken},initial+90*86400)).status,401);
  const w=await signedIn(email(),'web-sign-in');assert.equal(w.refreshToken,undefined);assert.equal((await post('authenticate',credential(w),initial+43199)).status,200);assert.equal((await post('authenticate',credential(w),initial+43200)).status,401);
  assert.equal((await post('refresh',{sessionID:w.sessionID,refreshToken:'0'.repeat(64)},initial+1)).status,401);
 });
 await test('wrong session/account copied tokens never authenticate or revoke foreign session',async()=>{
  const a=await signedIn();const b=await signedIn();assert.equal((await post('authenticate',{sessionID:b.sessionID,accessToken:a.accessToken})).status,401);assert.equal((await post('refresh',{sessionID:b.sessionID,refreshToken:a.refreshToken})).status,401);assert.equal((await post('authenticate',credential(b))).status,200);assert.equal((await post('authenticate',credential(a))).status,200);
 });
 await test('account mutation CAS winner writes exactly one audit/dependent row fenced to nonce',async()=>{
  const s=await signedIn();const guard=(await rows(`SELECT * FROM account_guard WHERE account_id='${s.accountID}'`))[0];const results=await Promise.all(Array.from({length:10},(_,i)=>post('mutate',{accountID:s.accountID,expectedRevision:guard.account_revision,nonce:`race-${i}`})));
  assert.equal(results.filter(r=>r.status===200).length,1);assert.equal(results.filter(r=>r.status===409).length,9);const current=(await rows(`SELECT * FROM account_guard WHERE account_id='${s.accountID}'`))[0];assert.equal(current.account_revision,Number(guard.account_revision)+1);
  const audits=(await rows(`SELECT * FROM account_audit WHERE account_id='${s.accountID}' AND action='account-mutation'`));const requests=(await rows(`SELECT * FROM account_requests WHERE account_id='${s.accountID}'`));assert.equal(audits.length,1);assert.equal(requests.length,1);assert.equal(audits[0].commit_nonce,current.commit_nonce);assert.equal(requests[0].commit_nonce,current.commit_nonce);
 });
 await test('stale guard and reused nonce never leak dependent writes',async()=>{
  const s=await signedIn();const g=(await rows(`SELECT * FROM account_guard WHERE account_id='${s.accountID}'`))[0];assert.equal((await post('mutate',{accountID:s.accountID,expectedRevision:g.account_revision,nonce:'once'})).status,200);const before=(await snapshot());assert.equal((await post('mutate',{accountID:s.accountID,expectedRevision:g.account_revision,nonce:'loser'})).status,409);assert.equal((await post('mutate',{accountID:s.accountID,expectedRevision:Number(g.account_revision)+1,nonce:'once'})).status,409);assert.deepEqual((await snapshot()),before);
 });
 await test('audit and required dependent failure roll back account CAS atomically',async()=>{
  const s=await signedIn();for(const flag of ['failAudit','failDependency']) {const g=(await rows(`SELECT * FROM account_guard WHERE account_id='${s.accountID}'`))[0];const before=(await snapshot());assert.equal((await post('mutate',{accountID:s.accountID,expectedRevision:g.account_revision,nonce:flag,[flag]:true})).status,409);assert.deepEqual((await snapshot()),before);}
 });
 await test('consume audit failure rolls back consume/account/session then valid retry succeeds',async()=>{
  const c=await request(email());(await d1(['--command',"CREATE TRIGGER fixture_fail_signin_audit BEFORE INSERT ON account_audit WHEN NEW.action='sign-in' BEGIN SELECT RAISE(ABORT,'fixture audit denied'); END;"]));
  try { const before=(await snapshot());await refusedConsume(c);assert.deepEqual((await snapshot()),before); } finally {(await d1(['--command','DROP TRIGGER fixture_fail_signin_audit;']));}
  assert.equal((await consume(c)).status,200);
 });
 await test('email minute/hour/day ceilings return fresh generic challenges and prevent extra sends',async()=>{
  const address=email();const first=await request(address);const suppressed=await request(address);assert.notEqual(first,suppressed);await refusedConsume(suppressed);
  for(let i=1;i<5;i++)await request(address,'app-sign-in',initial+i*60,undefined,`192.0.2.${10+i}`);
  const limit=await request(address,'app-sign-in',initial+300,undefined,'192.0.2.30');await refusedConsume(limit,'app-sign-in',initial+300);
  for(let i=5;i<20;i++)await request(address,'app-sign-in',initial+Math.floor(i/5)*3600+(i%5)*60,undefined,`198.51.100.${i}`);
  const daily=await request(address,'app-sign-in',initial+4*3600,undefined,'198.51.100.100');await refusedConsume(daily,'app-sign-in',initial+4*3600);const h=(await rows(`SELECT email_hmac FROM challenges WHERE challenge_id='${daily}'`))[0].email_hmac;assert.equal((await rows(`SELECT COUNT(*) AS n FROM request_limits WHERE email_hmac='${h}' AND sent=1`))[0].n,20);
 });
 await test('IP hourly/daily ceiling independent of normalized email',async()=>{
  const ip='203.0.113.80';for(let i=0;i<30;i++)await request(email(),'app-sign-in',initial,undefined,ip);
  for(const address of ['existing@example.invalid','unknown@example.invalid']){const r=await post('request',{email:address,purpose:'app-sign-in',sourceIP:ip});assert.equal(r.status,429);assert.deepEqual(r.body,{outcome:'refused'});}
  const dayIP='203.0.113.81';for(let i=0;i<100;i++)await request(email(),'app-sign-in',initial+Math.floor(i/25)*3600,undefined,dayIP);
  assert.equal((await post('request',{email:email(),purpose:'app-sign-in',sourceIP:dayIP},initial+4*3600)).status,429);
 });
 await test('undeliverable and database-failed requests stay indistinguishable and no account created',async()=>{
  const before=(await count('accounts'));const r=await post('request',{email:email(),purpose:'app-sign-in',sourceIP:'203.0.113.120'},initial,'refuse');assert.equal(r.status,202);assert.deepEqual(Object.keys(r.body).sort(),['challengeID','outcome']);await refusedConsume(String(r.body.challengeID));assert.equal((await count('accounts')),before);
  (await d1(['--command',"CREATE TRIGGER fixture_fail_request BEFORE INSERT ON challenges BEGIN SELECT RAISE(ABORT,'fixture request denied'); END;"]));
  try{const r=await post('request',{email:email(),purpose:'app-sign-in',sourceIP:'203.0.113.121'});assert.equal(r.status,202);assert.deepEqual(Object.keys(r.body).sort(),['challengeID','outcome']);}finally{(await d1(['--command','DROP TRIGGER fixture_fail_request;']));}
 });
 await test('storage and audit/logs contain no code/raw tokens/email/source IP',async()=>{
  const address=email();const s=await signedIn(address);const persisted=JSON.stringify((await snapshot()));for(const value of [code,String(s.accessToken),String(s.refreshToken),address,'192.0.2.1']){assert.equal(persisted.includes(value),false);assert.equal(output.includes(value),false);}
  assert.match(String(s.accessToken),/^[a-f0-9]{64}$/);assert.match(String(s.refreshToken),/^[a-f0-9]{64}$/);
 });
 await test('repeated fixture entropy/nonce collision refuses with no second grant',async()=>{
  const s=await signedIn();const g=(await rows(`SELECT * FROM account_guard WHERE account_id='${s.accountID}'`))[0];const payload={accountID:s.accountID,expectedRevision:g.account_revision,nonce:'collision'};assert.equal((await post('mutate',payload,initial,'capture','PAT-2642-synthetic','f'.repeat(32))).status,200);const before=(await snapshot());assert.equal((await post('mutate',{...payload,expectedRevision:Number(g.account_revision)+1},initial,'capture','PAT-2642-synthetic','f'.repeat(32))).status,409);assert.deepEqual((await snapshot()),before);
 });
 await test('non-synthetic recipient gets generic accepted response but never a usable challenge',async()=>{
  const before=(await count('accounts'));const r=await post('request',{email:`external${++emailCounter}@example.com`,purpose:'app-sign-in',sourceIP:'203.0.113.200'});assert.equal(r.status,202);assert.deepEqual(Object.keys(r.body).sort(),['challengeID','outcome']);await refusedConsume(String(r.body.challengeID));assert.equal((await count('accounts')),before);
 });
 await test('reauth rejects same-account changed session, wrong app/web purpose, and unknown session',async()=>{
  const address=email();const a=await signedIn(address);const b=await signedIn(address,'app-sign-in',initial+60);assert.equal(a.accountID,b.accountID);
  const c=await request(address,'app-reauth',initial+120,binding(a));const before=(await snapshot());await refusedConsume(c,'app-reauth',initial+120,binding(b));await refusedConsume(c,'web-reauth',initial+120,binding(a));assert.deepEqual((await snapshot()),before);
  assert.equal((await consume(c,'app-reauth',initial+120,binding(a))).status,200);
  const unknown={accountID:a.accountID,sessionID:'0'.repeat(32)};const d=await request(address,'app-reauth',initial+240,unknown);const later=(await snapshot());await refusedConsume(d,'app-reauth',initial+240,unknown);assert.deepEqual((await snapshot()),later);
 });
 await test('N-way email and IP send limits are persisted atomically',async()=>{
  const address=email();const requests=await Promise.all(Array.from({length:20},()=>post('request',{email:address,purpose:'app-sign-in',sourceIP:'203.0.113.180'})));assert.equal(requests.filter(r=>r.status===202).length,20);assert.equal(new Set(requests.map(r=>r.body.challengeID)).size,20);
  const h=(await rows(`SELECT email_hmac FROM challenges WHERE challenge_id='${requests[0].body.challengeID}'`))[0].email_hmac;assert.equal((await rows(`SELECT COUNT(*) AS n FROM request_limits WHERE email_hmac='${h}' AND sent=1`))[0].n,1);
  const ip='203.0.113.181';const ipResults=await Promise.all(Array.from({length:40},()=>post('request',{email:email(),purpose:'app-sign-in',sourceIP:ip})));assert.equal(ipResults.filter(r=>r.status===202).length,30);assert.equal(ipResults.filter(r=>r.status===429).length,10);
  const first=ipResults.find(r=>r.status===202)!;const row=(await rows(`SELECT email_hmac FROM challenges WHERE challenge_id='${first.body.challengeID}'`))[0];const ipHash=(await rows(`SELECT ip_hmac FROM request_limits WHERE email_hmac='${row.email_hmac}'`))[0].ip_hmac;assert.equal((await rows(`SELECT COUNT(*) AS n FROM request_limits WHERE ip_hmac='${ipHash}'`))[0].n,30);assert.equal((await rows(`SELECT COUNT(*) AS n FROM request_limits WHERE ip_hmac='${ipHash}' AND sent=1`))[0].n,30);
 });
 await test('repeated entropy during consume or refresh never mints a second token set',async()=>{
  const a=await request(email());const b=await request(email());const seed='d'.repeat(32);const input=(challengeID:string)=>({challengeID,purpose:'app-sign-in',code});const first=await post('consume',input(a),initial,'capture','PAT-2642-synthetic',seed);assert.equal(first.status,200);const before=(await snapshot());const collision=await post('consume',input(b),initial,'capture','PAT-2642-synthetic',seed);assert.equal(collision.status,401);assert.deepEqual((await snapshot()),before);
  const s=await signedIn();const t=await signedIn();const refreshSeed='e'.repeat(32);const one=await post('refresh',{sessionID:s.sessionID,refreshToken:s.refreshToken},initial+1,'capture','PAT-2642-synthetic',refreshSeed);assert.equal(one.status,200);const rotated=(await snapshot());const two=await post('refresh',{sessionID:t.sessionID,refreshToken:t.refreshToken},initial+1,'capture','PAT-2642-synthetic',refreshSeed);assert.equal(two.status,401);assert.deepEqual((await snapshot()),rotated);
 });
 await test('web reauth preserves absolute deadline and creates no session',async()=>{
  const address=email();const w=await signedIn(address,'web-sign-in');const c=await request(address,'web-reauth',initial+43100,binding(w));const before=(await rows(`SELECT * FROM sessions WHERE session_id='${w.sessionID}'`))[0];const sessions=(await count('sessions'));const ok=await consume(c,'web-reauth',initial+43100,binding(w));assert.equal(ok.status,200);assert.deepEqual(ok.body,{outcome:'reauthenticated'});assert.equal((await count('sessions')),sessions);const after=(await rows(`SELECT * FROM sessions WHERE session_id='${w.sessionID}'`))[0];assert.equal(after.authenticated_at,initial+43100);assert.equal(after.expires_at,before.expires_at);assert.equal(after.access_expires_at,before.access_expires_at);assert.equal((await post('authenticate',credential(w),initial+43200)).status,401);
 });
 console.log(`Local emulator only; no remote atomicity, real identity/mail or product authority. Exclusive state: ${run}`);
}finally{
 await runtime.dispose();
}
