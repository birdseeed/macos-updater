// Actual local D1/workerd only. Runtime fixture controls are synthetic facts, never authority.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';
// Evidence execution supplies the absolute service path as argv[2]; repo tests use their ordinary location.
const service = process.argv[2] ? realpathSync(process.argv[2]) : resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const root = realpathSync(resolve(service,'../..'));
const build = resolve(root,'.build'); mkdirSync(build,{recursive:true}); assert.equal(realpathSync(build),build);
const run = mkdtempSync(resolve(build,'licensing-s1b-d1-'));
const source = JSON.parse(readFileSync(resolve(service,'wrangler.jsonc'),'utf8'));
assert.deepEqual(source.vars,{ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'});
assert.deepEqual(source.d1_databases,[{binding:'FIXTURE_DB',database_name:'licensing-local-fixture',database_id:'00000000-0000-0000-0000-000000000000',remote:false}]);
assert.equal(source.workers_dev,false); assert.equal(source.preview_urls,false); assert.equal(source.account_id,undefined); assert.equal(source.routes,undefined); assert.equal(source.env,undefined);
const config = resolve(run,'wrangler.json'); writeFileSync(config,JSON.stringify({...source,main:resolve(service,'src/index.ts')}));
const cli = resolve(service,'node_modules/wrangler/wrangler-dist/cli.js');
const env = {PATH:process.env.PATH,TMPDIR:run,XDG_CONFIG_HOME:resolve(run,'config'),WRANGLER_SEND_METRICS:'false',CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV:'false',CI:'true',NO_COLOR:'1'};
const common = ['--config',config,'--persist-to',resolve(run,'state')];
function d1(args: string[]): string {
 const result = spawnSync(process.execPath,[cli,'d1','execute','FIXTURE_DB','--local',...common,...args],{cwd:run,env,encoding:'utf8',timeout:30000,killSignal:'SIGKILL'});
 assert.equal(result.status,0,`D1 command failed: ${result.stderr}\n${result.stdout}`); return result.stdout;
}
function rows(sql: string): Record<string,unknown>[] { const output=JSON.parse(d1(['--command',sql,'--json'])); assert.equal(output.length,1); assert.equal(output[0].success,true); return output[0].results; }
function count(table: string): number { assert.match(table,/^(accounts|account_guard|sessions|challenges|account_audit|used_refresh_tokens|account_requests|request_limits)$/); return Number(rows(`SELECT COUNT(*) AS n FROM ${table}`)[0].n); }
// Include every application table, including rate limits and used refresh receipts.
function snapshot(): unknown { return ['accounts','account_guard','sessions','challenges','account_audit','used_refresh_tokens','account_requests','request_limits','entitlement_sources','trial_markers','trial_requests','lease_heads','retention_rows','account_nonce_history'].map(t=>{const columns=rows(`PRAGMA table_info(${t})`).map(c=>`"${c.name}"`).join(',');return rows(`SELECT * FROM ${t} ORDER BY ${columns}`);}); }
function guard(s:Record<string,unknown>,nonce='n'+(++requestCounter)):Record<string,unknown> {const g=rows(`SELECT * FROM account_guard WHERE account_id='${s.accountID}'`)[0];return {accountID:s.accountID,accountRevision:g.account_revision,commitNonce:nonce};}
function start(s:Record<string,unknown>,requestID='r'+(++requestCounter),now=initial,g=guard(s),requestHash='f'.repeat(64)){return post('s1b/start',{credential:credential(s),guard:g,requestID,requestHash},now);}
function deletion(s:Record<string,unknown>,now=initial){return post('s1b/delete',{credential:credential(s),guard:guard(s)},now);}
function cleanup(s:Record<string,unknown>,now:number,dryRun=false,g=guard(s)){return post('s1b/cleanup',{guard:g,limit:100,dryRun},now);}
d1(['--file',resolve(service,'migrations/0001_accounts.sql')]);
assert.equal(count('accounts'),0); assert.equal(count('sessions'),0);
let output='';
const child=spawn(process.execPath,[cli,'dev','--local',...common,'--ip','127.0.0.1','--port','0','--inspector-port','0','--show-interactive-dev-session=false'],{cwd:run,env,stdio:['ignore','pipe','pipe']});
child.stdout.on('data',b=>{output+=b;});child.stderr.on('data',b=>{output+=b;});
let origin=''; const initial=1791734400; const code='01234567'; let emailCounter=0; let requestCounter=0; let ipCounter=0;
function email(): string { return `case${++emailCounter}@example.invalid`; }
async function post(route:string, input:unknown, now=initial, delivery='capture', key='PAT-2642-synthetic', seed=(++requestCounter).toString(16).padStart(32,'0')) {
 const response=await fetch(origin+(route.startsWith('s1b/')?'/__fixture/licensing/'+route.slice(4):'/__fixture/accounts/'+route),{method:'POST',headers:{'Connection':'close','Content-Type':'application/json','x-fixture-now':String(now),'x-fixture-delivery':delivery,'x-fixture-key':route.startsWith('s1b/')?'PAT-2643-synthetic':key,'x-fixture-seed':seed,...(route.startsWith('s1b/')?{'x-fixture-signing-seed':Buffer.from('Patched-L1-TEST-ONLY-KEY-SEED-01').toString('base64')}:{})},body:JSON.stringify(input),redirect:'error',signal:AbortSignal.timeout(10000)});

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
 const deadline=Date.now()+30000;
 while(Date.now()<deadline) { origin=output.match(/Ready on (http:\/\/127\.0\.0\.1:\d+)/)?.[1]??'';if(origin)break;assert.equal(child.exitCode,null,`worker exited ${output}`);await new Promise(r=>setTimeout(r,100)); }
 assert.ok(origin,`worker not ready ${output}`);
 await test('ignored required session revocation refuses deletion and preserves every table; recovery revokes all sessions',async()=>{
  const address=email();const s=await signedIn(address);assert.equal((await start(s)).status,200);
  await signedIn(address,'app-sign-in',initial+60);
  assert.equal(rows(`SELECT COUNT(*) AS n FROM sessions WHERE account_id='${s.accountID}' AND revoked_at IS NULL`)[0].n,2);
  d1(['--command',"CREATE TRIGGER parent_ignore_revocation BEFORE UPDATE ON sessions WHEN NEW.revoked_at IS NOT NULL BEGIN SELECT RAISE(IGNORE); END;"]);
  try {const before=snapshot();const r=await deletion(s,initial+60);assert.notEqual(r.status,200);assert.deepEqual(r.body,{outcome:'refused'});assert.deepEqual(snapshot(),before);}
  finally {d1(['--command','DROP TRIGGER parent_ignore_revocation;']);}
  assert.equal((await deletion(s,initial+60)).status,200);
  const sessions=rows(`SELECT * FROM sessions WHERE account_id='${s.accountID}'`);assert.equal(sessions.length,2);assert.ok(sessions.every(row=>row.revoked_at===initial+60));
 });
 const later=initial+800*86400;
 async function protectedAccount(kind:'future'|'invalid') {
  const address=email();const old=await signedIn(address);assert.equal((await start(old)).status,200);
  const active=await signedIn(address,'app-sign-in',later);assert.equal(active.accountID,old.accountID);
  const max=kind==='future'?later+1:-1;
  d1(['--command',`INSERT INTO retention_rows(row_id,account_id,record_json,max_grant_permitted_until,pending_provider_intent,reconciliation_reference,approved_hold_requires_row,commit_nonce) VALUES('parent-${kind}-${requestCounter}','${active.accountID}','{"category":"challenge","createdAt":${initial}}',${max},0,0,0,'seed');`]);
  assert.ok(rows(`SELECT * FROM challenges WHERE email_hmac=(SELECT email_hmac FROM accounts WHERE account_id='${active.accountID}') AND created_at=${initial}`).length>0);
  assert.ok(rows(`SELECT * FROM trial_requests WHERE account_id='${active.accountID}' AND created_at=${initial}`).length>0);
  return active;
 }
 for(const kind of ['future','invalid'] as const) {
  await test(`retention row ${kind} max grant holds old actual histories during cleanup`,async()=>{
   const s=await protectedAccount(kind);const before=snapshot();const r=await cleanup(s,later);assert.equal(r.status,200);assert.equal(r.body.deleted,0);assert.deepEqual(snapshot(),before);
  });
  await test(`retention row ${kind} max grant refuses authenticated deletion without any mutation`,async()=>{
   const s=await protectedAccount(kind);const before=snapshot();const r=await deletion(s,later);assert.notEqual(r.status,200);assert.deepEqual(r.body,{outcome:'refused'});assert.deepEqual(snapshot(),before);
  });
 }
 console.log(`Parent fault boundaries: actual local D1 only; exclusive state: ${run}`);
}finally{
 child.kill('SIGTERM');await Promise.race([once(child,'exit'),new Promise(r=>setTimeout(r,3000))]);if(child.exitCode===null)child.kill('SIGKILL');writeFileSync(resolve(run,'wrangler.log'),output);
}
