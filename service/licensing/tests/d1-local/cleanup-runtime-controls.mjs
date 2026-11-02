// Independent controls: static preservation canaries and future native lifecycle obligations.
import assert from 'node:assert/strict';
import {readFileSync,existsSync,mkdirSync,mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import Module,{createRequire} from 'node:module';
import cp from 'node:child_process';
import {verify,verifyProtected} from './cleanup-preservation.mjs';
const here=dirname(fileURLToPath(import.meta.url)),service=resolve(here,'../..'),root=resolve(service,'../..');
const require=createRequire(resolve(service,'package.json')),ts=require('typescript/unstable/ast'),{API}=require('typescript/unstable/sync');
export function staticControls(){
 verify(readFileSync(resolve(here,'cleanup.test.ts'),'utf8'));
 // Build the positive canary exclusively from the frozen original, never a Phase B candidate.
 const baseline=JSON.parse(readFileSync(resolve(here,'cleanup-preservation-baseline.json'),'utf8')),original=baseline.originalSource;
 assert.equal(createHash('sha256').update(original).digest('hex'),baseline.originalSHA256,'Phase A static controls require exact original suite');
 let positive=original;
 // Parse exact original source; the API does not execute test code.
 const build=resolve(root,'.build');mkdirSync(build,{recursive:true});const dir=mkdtempSync(resolve(build,'cleanup-positive-')),file=resolve(dir,'original.ts');writeFileSync(file,original);
 const api=new API();
 const view=api.updateSnapshot({openFiles:[file]});
 let source=view.getDefaultProjectForFile(file)?.program.getSourceFile(file);
 // No candidate implementation supplies the baseline.
 if(!source){view.dispose();api.close();rmSync(dir,{recursive:true});throw Error('cleanup static canary AST unavailable');}
 const edits=[];
 function visit(n,parent){
  if(ts.isFunctionDeclaration(n)&&['rows','count','snapshot','guard','start','deletion','cleanup'].includes(n.name?.text))edits.push([n.getStart(source),n.getStart(source),'async ']);
  if(ts.isCallExpression(n)&&ts.isIdentifier(n.expression)&&['rows','count','snapshot','guard'].includes(n.expression.text)){
   const a=n.getStart(source),b=n.end;
   // Default initializers are replaced with the precisely selected leading resolution below.
   const p=parent;
   const inDefault=p?.kind===ts.SyntaxKind.Parameter&&p.name.getText(source)==='g';
   const inMap=original.slice(Math.max(0,a-3),a)==='t=>';
   if(!inDefault&&!inMap){edits.push([a,a,'(await '],[b,b,')']);}
  }
  n.forEachChild(c=>visit(c,n));
 }
 try{visit(source);}finally{view.dispose();api.close();rmSync(dir,{recursive:true});}
 for(const [a,b,value] of edits.sort((a,b)=>b[0]-a[0]))positive=positive.slice(0,a)+value+positive.slice(b);
 positive=positive.replace('count(table: string): number','count(table: string): Promise<number>').replace('snapshot(): unknown','snapshot(): Promise<unknown>').replace('nonce=\'n\'+(++requestCounter)):Record<string,unknown>','nonce=\'n\'+(++requestCounter)):Promise<Record<string,unknown>>');
 positive=positive.replace("g=guard(s),requestHash='f'.repeat(64)){return", "g=undefined,requestHash='f'.repeat(64)){if(g===undefined) g=await guard(s);return").replace('g=guard(s)){return','g=undefined){if(g===undefined) g=await guard(s);return');
 positive=positive.replace("return ['accounts','account_guard','sessions','challenges','account_audit','account_requests','entitlement_sources','trial_markers','trial_requests','lease_heads','retention_rows','account_nonce_history'].map(t=>rows(`SELECT * FROM ${t} ORDER BY 1`));", "return await Promise.all(['accounts','account_guard','sessions','challenges','account_audit','account_requests','entitlement_sources','trial_markers','trial_requests','lease_heads','retention_rows','account_nonce_history'].map(t=>rows(`SELECT * FROM ${t} ORDER BY 1`)));");
 assert.notEqual(positive,original);assert.doesNotThrow(()=>verify(positive),'precise async plumbing positive');
 const mutants=[
  ['assertion changed',original.replace('assert.equal(result.status,202)','assert.equal(result.status,200)')],
  ['assertion removed',original.replace('assert.equal(result.status,202);','')],
  ['case deleted',original.replace("test('real sign-in", "removedTest('real sign-in")],
  ['race narrowed',original.replace('length:10','length:9')],
  ['boundary case loop narrowed',original.replace('[-1,0,1]','[-1,1]')],
  ['protection case loop narrowed',original.replace("['maxGrant','intent'","['intent'")],
  ['SQL table changed',original.replace('SELECT * FROM entitlement_sources','SELECT * FROM accounts')],
  ['snapshot order',positive.replace("['accounts','account_guard','sessions'","['sessions','account_guard','accounts'")],
  ['snapshot SQL order',positive.replace('ORDER BY 1','ORDER BY 2')],
  ['trigger changed',original.replace('synthetic audit denied','weakened audit')],
  ['missing snapshot await',positive.replace('(await snapshot())','snapshot()')],
  ['missing count await',positive.replace("(await count('accounts'))","count('accounts')")],
  ['missing guard await',positive.replace('(await guard(s))','guard(s)')],
  ['missing rows await',positive.replace("(await rows(`SELECT * FROM account_guard WHERE account_id='${s.accountID}'`))","rows(`SELECT * FROM account_guard WHERE account_id='${s.accountID}'`)")],
  ['default guard null semantics',positive.replace('if(g===undefined)','if(!g)')],
  ['default counter changed',positive.replace("requestID='r'+(++requestCounter)","requestID='r'+(requestCounter++)")],
  ['counter seed changed',original.replace("seed=(++requestCounter)","seed=(requestCounter++)")],
  ['async outside allowlist',original.replace('function credential(', 'async function credential(')],
  ['Promise truthiness',positive.replace('assert.ok(head);','assert.ok(snapshot());')],
  ['unaggregated snapshot',positive.replace('return await Promise.all([\'accounts\'', 'return ([\'accounts\'')],
 ];
 for(const [name,mutant] of mutants){assert.notEqual(mutant,name.startsWith('missing')?positive:original,'mutant must differ: '+name);assert.throws(()=>verify(mutant),'must reject '+name);}
 const baselinePath=resolve(here,'cleanup-preservation-baseline.json');
 const corruptions=[
  ['original SHA field',b=>{b.originalSHA256='0'.repeat(64);}],
  ['original source bytes',b=>{b.originalSource+='\n// corrupt original\n';}],
  ['original AST contract',b=>{b.contract.expandedCaseCount=30;}],
 ];
 for(const [label,mutate] of corruptions){
  const copy=structuredClone(baseline);mutate(copy);const virtual=JSON.stringify(copy);let supplied=false;
  assert.throws(()=>verifyProtected((path,...args)=>{
   if(resolve(String(path))===baselinePath){supplied=true;return args[0]==='utf8'?virtual:Buffer.from(virtual);}
   return readFileSync(path,...args);
  }),undefined,'fixture integrity corruption refused: '+label);
  assert.ok(supplied,'actual verifier consumed injected fixture baseline: '+label);
 }
 const futurePaths=['AGENTS.md','scripts/verify-service.sh','service/licensing/src/auth.ts','service/licensing/src/entitlements.ts','service/licensing/migrations/0001_accounts.sql'];
 for(const target of futurePaths){
  const path=resolve(root,target),virtual=Buffer.from('independently approved future file change canary');
  assert.ok(baseline.protectedSHA256[target],'future-file canary covered by publication receipt: '+target);
  assert.doesNotThrow(()=>verifyProtected((input,...args)=>resolve(String(input))===path?virtual:readFileSync(input,...args)),
   'unrelated approved future source may evolve: '+target);
 }
 console.log('Cleanup static controls: precise plumbing and '+futurePaths.length+' future-file canaries accepted; '+mutants.length+' semantic/await mutants and '+corruptions.length+' fixture-integrity mutants refused');
}
const hashFile=path=>existsSync(path)?createHash('sha256').update(readFileSync(path)).digest('hex'):null;
export async function nativeControls(){
 const localPaths=[resolve(root,'local.db'),resolve(service,'local.db')],before=localPaths.map(hashFile);
 const sentinel='cleanup-env-private-sentinel',savedSentinel=process.env.PAT_CLEANUP_PRIVATE_SENTINEL;process.env.PAT_CLEANUP_PRIVATE_SENTINEL=sentinel;
 const spawn=cp.spawn,load=Module._load,inputs=new Set();let nativeLaunches=0;
 cp.spawn=function(command,args,options){
  if(/(?:^|[/\\])workerd(?:\.exe)?$/.test(String(command))){
   nativeLaunches++;const env=options?.env;assert.ok(env,'explicit native launch environment');
   assert.equal(env.PAT_CLEANUP_PRIVATE_SENTINEL,undefined,'sentinel scrubbed before native launch');
   for(const key of Object.keys(env))assert.ok(!/TOKEN|SECRET|PASSWORD|ACCESS_KEY|CREDENTIAL|ACCOUNT_ID|PRIVATE|DOTENV/.test(key),'native environment credential key refused');
   assert.equal(env.NODE_OPTIONS,undefined);assert.equal(env.WRANGLER_SEND_METRICS,'false');assert.equal(env.CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV,'false');
   assert.ok(env.HOME.startsWith(resolve(root,'.build')+'/')&&env.HOME.endsWith('/home'));assert.ok(env.TMPDIR.startsWith(resolve(root,'.build')+'/'));
  }
  return spawn.call(this,command,args,options);
 };
 Module._load=function(name,...args){const value=load.call(this,name,...args);if(name!=='esbuild')return value;
  // A plain facade leaves the accepted runtime and original module exports unchanged.
  return {...value,async build(options){const result=await value.build({...options,metafile:true});for(const path of Object.keys(result.metafile.inputs))inputs.add(resolve(service,path));return result;}};
 };
 let runtime,other;
 try{
  const {cleanupRuntime}=await import('./cleanup-runtime.ts');
  runtime=await cleanupRuntime();
  assert.deepEqual(await runtime.rows('SELECT COUNT(*) AS n FROM accounts'),[{n:0}]);
  // The exact original migration must have been installed once by the runtime adapter.
  const schema=await runtime.rows("SELECT name,sql FROM sqlite_schema WHERE type='table' ORDER BY name");
  // Exact native D1 metadata object is infrastructure, not migration/product schema.
  assert.deepEqual(schema.filter(r=>r.name==='_cf_METADATA'),[{name:'_cf_METADATA',sql:"CREATE TABLE _cf_METADATA (\n        key INTEGER PRIMARY KEY,\n        value BLOB\n      )"}],'exact pinned native D1 metadata table');
  const {DatabaseSync}=require('node:sqlite'),reference=new DatabaseSync(':memory:');
  try{reference.exec(readFileSync(resolve(service,'migrations/0001_accounts.sql'),'utf8'));
   const expected=reference.prepare("SELECT name,sql FROM sqlite_schema WHERE type='table' ORDER BY name").all();
   const userRows=rows=>JSON.parse(JSON.stringify(rows.filter(r=>r.name!=='_cf_KV'&&r.name!=='_cf_METADATA'&&!r.name.startsWith('sqlite_'))));
   assert.deepEqual(userRows(schema),userRows(expected),'exact original migration table definitions');
   const indexes=await runtime.rows("SELECT name,sql FROM sqlite_schema WHERE type='index' AND sql IS NOT NULL ORDER BY name");
   assert.deepEqual(userRows(indexes),userRows(reference.prepare("SELECT name,sql FROM sqlite_schema WHERE type='index' AND sql IS NOT NULL ORDER BY name").all()),'exact original migration indexes');
  }finally{reference.close();}
  for(const file of ['index.ts','auth.ts','entitlements.ts','store.ts','leases.ts','retention.ts'])assert.ok(inputs.has(resolve(service,'src',file)),'actual esbuild input '+file);
  const now=1791734400;
  const headers={'Connection':'close','Content-Type':'application/json','x-fixture-key':'PAT-2642-synthetic','x-fixture-now':String(now),'x-fixture-seed':'a'.repeat(32),'x-fixture-delivery':'capture'};
  const response=await fetch(runtime.origin+'/__fixture/accounts/request',{method:'POST',headers,body:JSON.stringify({email:'cleanup-control@example.invalid',purpose:'app-sign-in',sourceIP:'192.0.2.73'}),signal:AbortSignal.timeout(10000)});
  assert.equal(response.status,202);const challenge=await response.json();assert.ok(challenge.challengeID);
  assert.equal((await runtime.rows('SELECT COUNT(*) AS n FROM challenges'))[0].n,1,'HTTP and direct binding share state');
  const fixtureMarkers={ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'};
  await runtime.restart({markers:{...fixtureMarkers,FIXTURE_MARKER:'wrong-marker'}});
  const wrongMarker=await fetch(runtime.origin+'/__fixture/accounts/request',{method:'POST',headers,body:'{}',signal:AbortSignal.timeout(10000)});assert.equal(wrongMarker.status,503);assert.deepEqual(await wrongMarker.json(),{fixture:'PAT-2639-local-only',outcome:'refused'});
  await runtime.restart({markers:fixtureMarkers});
  const missing=await fetch(runtime.origin+'/__fixture/licensing/start',{method:'POST',headers:{Connection:'close'},body:'{}',signal:AbortSignal.timeout(10000)});assert.equal(missing.status,503);assert.deepEqual(await missing.json(),{outcome:'refused'});
  const noSigning=await fetch(runtime.origin+'/__fixture/licensing/start',{method:'POST',headers:{...headers,'x-fixture-key':'PAT-2643-synthetic'},body:'{}',signal:AbortSignal.timeout(10000)});assert.equal(noSigning.status,503);assert.deepEqual(await noSigning.json(),{outcome:'refused'});
  assert.equal((await runtime.rows('SELECT COUNT(*) AS n FROM challenges'))[0].n,1);
  const trigger="CREATE TRIGGER s1b_fail_audit BEFORE INSERT ON account_audit WHEN NEW.action='trial-start' BEGIN SELECT RAISE(ABORT,'synthetic audit denied'); END;";
  await runtime.execute(trigger);
  assert.equal((await runtime.rows("SELECT sql FROM sqlite_schema WHERE name='s1b_fail_audit'"))[0].sql,trigger.slice(0,-1));
  const tables=['accounts','account_guard','sessions','challenges','account_audit','account_requests','entitlement_sources','trial_markers','trial_requests','lease_heads','retention_rows','account_nonce_history'];
  const snapshot=()=>Promise.all(tables.map(t=>runtime.rows(`SELECT * FROM ${t} ORDER BY 1`)));
  await runtime.execute("INSERT INTO accounts(account_id,email_hmac,created_at) VALUES('cleanup-control-account','cleanup-control-hmac',1);");
  const prior=await snapshot();
  await assert.rejects(()=>runtime.db.batch([
   runtime.db.prepare("INSERT INTO request_limits VALUES ('cleanup-control','synthetic-email','synthetic-ip',1,1)"),
   runtime.db.prepare("INSERT INTO account_audit(audit_id,account_id,action,account_revision,commit_nonce,created_at) VALUES('cleanup-control-audit','cleanup-control-account','trial-start',0,'control',1)")
  ]),/synthetic audit denied/);
  assert.deepEqual(await snapshot(),prior,'native atomic trigger failure rollback');
  assert.deepEqual(await runtime.rows("SELECT * FROM request_limits WHERE request_id='cleanup-control'"),[]);
  await runtime.execute('DROP TRIGGER s1b_fail_audit;');
  await runtime.restart();assert.equal((await runtime.rows('SELECT COUNT(*) AS n FROM challenges'))[0].n,1);
  const outbound=await runtime.outboundCanary();assert.ok(outbound.status>=500);assert.equal((await runtime.rows('SELECT COUNT(*) AS n FROM challenges'))[0].n,1);
  for(const value of [sentinel,'cleanup-control@example.invalid','192.0.2.73','01234567','Patched-L1-TEST-ONLY-KEY-SEED-01'])assert.ok(!runtime.logs.join('\n').includes(value),'private value in logs');
  assert.ok(Buffer.byteLength(runtime.logs.join('\n'))<=65536);
  const retained=runtime.db;await runtime.dispose();
  assert.equal(JSON.parse(readFileSync(resolve(runtime.run,'metadata.json'),'utf8')).deniedOutbound,1,'real native outbound denial callback observed exactly once');
  const persistedLog=readFileSync(resolve(runtime.run,'runtime.log'),'utf8');assert.ok(Buffer.byteLength(persistedLog)<=65536+runtime.logs.length+1);for(const value of [sentinel,'cleanup-control@example.invalid','192.0.2.73','01234567','Patched-L1-TEST-ONLY-KEY-SEED-01'])assert.ok(!persistedLog.includes(value),'private value in retained log');
  assert.throws(()=>runtime.db);assert.throws(()=>runtime.origin);await assert.rejects(async()=>retained.prepare('SELECT 1').all(),/poisoned stub/);
  other=await cleanupRuntime();assert.equal((await other.rows('SELECT COUNT(*) AS n FROM challenges'))[0].n,0);await other.dispose();other=undefined;
  assert.ok(nativeLaunches>=7,'actual native lifecycle launches required');
 }finally{if(other)await other.dispose();if(runtime)await runtime.dispose();cp.spawn=spawn;Module._load=load;if(savedSentinel===undefined)delete process.env.PAT_CLEANUP_PRIVATE_SENTINEL;else process.env.PAT_CLEANUP_PRIVATE_SENTINEL=savedSentinel;assert.deepEqual(localPaths.map(hashFile),before,'ordinary local.db hashes unchanged');}
 console.log('Cleanup native controls passed');
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 if(process.argv.includes('--static'))staticControls();else await nativeControls();
}
