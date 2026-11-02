// PAT-2652 frozen supplement: actual source, binding and native runtime controls.
import assert from 'node:assert/strict';
import {createRequire, syncBuiltinESMExports} from 'node:module';
import {readFileSync, realpathSync} from 'node:fs';
import {dirname, resolve, relative, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
const service=resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const root=realpathSync(resolve(service,'../..')), build=resolve(root,'.build');
const require=createRequire(resolve(service,'package.json'));
const esbuild=require('esbuild'), mf=require('miniflare'), cp=require('node:child_process');
const esbuildModule=require.cache[require.resolve('esbuild')], mfModule=require.cache[require.resolve('miniflare')];
const originalSpawn=cp.spawn, originalEsbuild=esbuildModule.exports, originalMF=mfModule.exports;
const savedEnvironment={...process.env};
const sentinel='PAT-2652-private-environment-canary';
const inputs=new Set(); let nativeLaunches=0, outboundCalls=0, outboundDenials=0;
const runtimes=[], retainedLogs=[]; let r, seed=0;
// Intercept the real build result; helper-reported source lists are insufficient.
esbuildModule.exports={...esbuild, async build(options){
 const result=await esbuild.build({...options,metafile:true});
 assert.ok(result.metafile?.inputs,'actual esbuild metafile required');
 for(const input of Object.keys(result.metafile.inputs))inputs.add(resolve(options.absWorkingDir??process.cwd(),input));
 return result;
}};
// Observe the real native worker's outbound-service call and actual denial.
mfModule.exports={...mf, convertV4MiniflareOptions(options){
  assert.equal(typeof options.outboundService,'function','native outbound denial required');
  const deny=options.outboundService;
  return mf.convertV4MiniflareOptions({...options,outboundService:async(...args)=>{
   outboundCalls++;
   assert.equal(new URL(args[0].url).hostname,'account-outbound.invalid');
   try {await deny(...args);} catch(error){outboundDenials++;throw error;}
   assert.fail('native outbound service permitted the request');
  }});
}};
cp.spawn=function(command,args,options){
 if(/(?:^|[/\\])workerd(?:\.exe)?$/.test(String(command))){
  nativeLaunches++;
  assert.ok(options?.env,'explicit workerd environment required');
  for(const [name,value] of Object.entries(options.env)){
   assert.ok(!/^(?:CLOUDFLARE_(?:API|ACCOUNT|TOKEN)|CF_API_|AWS_|GITHUB_TOKEN|GH_TOKEN|OPENAI_API_KEY|PAT2652_ENV_CANARY)/.test(name),'credential environment inherited');
   assert.ok(!String(value).includes(sentinel),'private environment inherited');
  }
 }
 return originalSpawn.call(this,command,args,options);
};
syncBuiltinESMExports(); process.env.PAT2652_ENV_CANARY=sentinel;
const tables=['accounts','account_guard','sessions','challenges','account_audit','used_refresh_tokens','account_requests'];
const markers={ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'};
async function rows(sql,...args){return (await r.db.prepare(sql).bind(...args).all()).results;}
async function snapshot(){return Promise.all(tables.map(t=>rows(`SELECT * FROM ${t} ORDER BY 1`)));}
async function post(route,body){
 const response=await fetch(r.origin+'/__fixture/accounts/'+route,{method:'POST',headers:{Connection:'close','Content-Type':'application/json','x-fixture-now':'1791734400','x-fixture-delivery':'capture','x-fixture-key':'PAT-2642-synthetic','x-fixture-seed':(++seed).toString(16).padStart(32,'0')},body:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(10000)});
 return {status:response.status,body:await response.json()};
}
async function migrate(){
 // Exact accepted migration has no triggers; whole trigger SQL remains db.exec elsewhere.
 const sql=readFileSync(resolve(service,'migrations/0001_accounts.sql'),'utf8').replace(/^\s*--.*$/mg,'');
 await r.db.batch(sql.split(';').map(s=>s.trim()).filter(Boolean).map(s=>r.db.prepare(s)));
}
async function start(accountRuntime){
 r=await accountRuntime();runtimes.push(r);
 assert.equal(realpathSync(r.run),r.run);assert.equal(dirname(r.run),build);
 assert.match(relative(build,r.run),/^account-owned-[^/]+$/);
 assert.ok(!isAbsolute(relative(build,r.run)));
 assert.equal(new URL(r.origin).hostname,'127.0.0.1');
 assert.deepEqual(r.versions,{miniflare:'5.20261006.1-alpha',esbuild:'0.28.2',workerd:'1.20261006.1'});
 for(const name of ['index','auth','store'])assert.ok(inputs.has(resolve(service,`src/${name}.ts`)),`actual ${name}.ts absent from bundle`);
 await migrate();
}
try {
 // Missing future module is preparation incompleteness, never ownership red.
 const {accountRuntime}=await import('./account-runtime.ts');
 await start(accountRuntime);const firstRun=r.run;
 const email='supplement@example.invalid', ip='192.0.2.230';
 const requested=await post('request',{email,purpose:'app-sign-in',sourceIP:ip});
 assert.equal(requested.status,202);assert.deepEqual(Object.keys(requested.body).sort(),['challengeID','outcome']);
 assert.equal(requested.body.outcome,'accepted');assert.match(requested.body.challengeID,/^[a-f0-9]{32}$/);
 const challenge=requested.body.challengeID;
 assert.equal((await rows('SELECT challenge_id FROM challenges WHERE challenge_id=?',challenge))[0].challenge_id,challenge);
 await r.db.prepare('UPDATE challenges SET superseded_at=? WHERE challenge_id=?').bind(1791734400,challenge).run();
 const beforeRefusal=await snapshot();
 assert.deepEqual(await post('consume',{challengeID:challenge,purpose:'app-sign-in',code:'01234567'}),{status:401,body:{outcome:'refused'}});
 assert.deepEqual(await snapshot(),beforeRefusal);
 await r.db.exec('CREATE TABLE account_control (id INTEGER PRIMARY KEY, value INTEGER NOT NULL); INSERT INTO account_control VALUES (1,73);');
 await assert.rejects(r.db.batch([r.db.prepare('UPDATE account_control SET value=74 WHERE id=1'),r.db.prepare('INSERT INTO account_control VALUES (2,75)'),r.db.prepare('INSERT INTO account_control VALUES (1,76)')]),/UNIQUE constraint failed: account_control.id/);
 assert.deepEqual(await rows('SELECT * FROM account_control ORDER BY id'),[{id:1,value:73}]);
 await r.restart();assert.equal(r.run,firstRun);
 assert.deepEqual(await rows('SELECT * FROM account_control ORDER BY id'),[{id:1,value:73}]);
 assert.deepEqual(await snapshot(),beforeRefusal);
 await r.restart({markers:{ENVIRONMENT:'local-fixture',PROVIDER_MODE:'fake'}});
 const beforeMissing=await snapshot();
 const missing=await post('request',{email:'missing@example.invalid',purpose:'app-sign-in',sourceIP:ip});
 assert.equal(missing.status,503);assert.equal(missing.body.outcome,'refused');
 assert.deepEqual(await snapshot(),beforeMissing);
 await r.restart({markers});
 for(const route of ['/__fixture/sql','/__fixture/accounts/sql','/__fixture/accounts/not-a-route']){
  const response=await fetch(r.origin+route,{method:'POST',headers:{Connection:'close'},body:'SELECT * FROM accounts',signal:AbortSignal.timeout(10000)});
  assert.equal(response.status,404,'unrecognised SQL/debug route');
 }
 const canary=await r.outboundCanary();assert.equal(canary.status,500);
 assert.equal(outboundCalls,1);assert.equal(outboundDenials,1);
 // Canary restores the real source worker and the same persisted binding.
 assert.deepEqual(await rows('SELECT * FROM account_control ORDER BY id'),[{id:1,value:73}]);
 assert.equal((await post('consume',{challengeID:challenge,purpose:'app-sign-in',code:'01234567'})).status,401);
 await r.dispose();retainedLogs.push(...r.logs);runtimes.pop();
 await start(accountRuntime);assert.notEqual(r.run,firstRun);
 assert.deepEqual(await rows('SELECT challenge_id FROM challenges'),[]);
 assert.deepEqual(await rows("SELECT name FROM sqlite_master WHERE name='account_control'"),[]);
 assert.equal(nativeLaunches,7,'one native workerd per explicit boot required');
 const allLogs=[...retainedLogs,...r.logs].join('\n');
 for(const value of [sentinel,email,ip,'01234567'])assert.ok(!allLogs.includes(value),'private fixture/environment value logged');
 console.log('ACCOUNT-RUNTIME-CONTROLS passed');
} finally {
 try {for(const runtime of runtimes.reverse())await runtime.dispose();}
 finally {cp.spawn=originalSpawn;syncBuiltinESMExports();esbuildModule.exports=originalEsbuild;mfModule.exports=originalMF;for(const name of Object.keys(process.env))delete process.env[name];Object.assign(process.env,savedEnvironment);}
}
