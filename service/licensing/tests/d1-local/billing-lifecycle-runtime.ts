// PAT-2646 combined single-owner local workerd/D1 harness; no app SQL/debug route.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,realpathSync,mkdirSync,mkdtempSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHmac,createHash} from 'node:crypto';
import {setImmediate as yieldToRuntime} from 'node:timers/promises';
export const service=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(resolve(service,'package.json'));
const mfPackage=require('miniflare');
const esbuild=require('esbuild');
const allowlist=['tests/d1-local/fixture.sql','migrations/0001_accounts.sql','migrations/0002_activations.sql','migrations/0003_billing.sql','migrations/0003b_billing_lifecycle.sql'] as const;
export function migrationStatements(file:string):string[]{
 assert.ok((allowlist as readonly string[]).includes(file),'migration not explicitly allowed');
 const sql=readFileSync(resolve(service,file),'utf8').replace(/^\s*--.*$/mg,'');
 let quoted=false;for(let i=0;i<sql.length;i++){if(sql[i]==="'"){if(quoted&&sql[i+1]==="'"){i++;continue;}quoted=!quoted;}if(sql[i]===';')assert.equal(quoted,false,'quoted semicolon unsupported');}assert.equal(quoted,false);
 assert.ok(!/\bTRIGGER\b|\/\*|["`\[\]]/i.test(sql.replace(/'(?:[^']|'')*'/g,'')),'migration syntax outside reviewed subset');
 return sql.split(';').map(s=>s.trim()).filter(Boolean);
}
export interface RuntimeOptions {now?:number;configured?:boolean;markers?:Record<string,string>;snapshot?:unknown;stopOutcome?:'accepted'|'ambiguous'|'rejected';fixedNonce?:number;seed?:number;throwStop?:boolean;billing?:boolean}
export const lifecycleTables=['billing_subscription','billing_existing_transaction','billing_reconcile','billing_event_consumed','billing_snapshot','billing_entity_version','billing_period','billing_period_end','billing_restoration','billing_adjustment','billing_dispute','billing_grace','billing_grace_void','billing_renewal_stop','billing_stop_cause','billing_lifecycle_request','billing_review_confirmation','billing_lifecycle_commit'];
export const account='a'.repeat(32),nonce='1'.repeat(32),hash='a'.repeat(64),session='b'.repeat(32),token='c'.repeat(64),environment='synthetic-sandbox';
export const config={fixture:'PAT-2646-synthetic',environment,prices:{GBP:'fixture-price-gbp-annual',USD:'fixture-price-usd-annual'},annual:{interval:'year',frequency:1,quantity:1,unitAmount:1999,taxInclusive:true}};
export async function lifecycleRuntime(initial:RuntimeOptions={}){
 assert.equal(process.version,'v24.21.0');
 const cp=require('node:child_process');assert.equal(cp.execFileSync('npm',['--version'],{encoding:'utf8'}).trim(),'11.19.0');
 const versions=Object.fromEntries(['miniflare','esbuild','workerd'].map(name=>[name,require(name+'/package.json').version]));
 assert.deepEqual(versions,{miniflare:'5.20261006.1-alpha',esbuild:'0.28.2',workerd:'1.20261006.1'});
 const root=realpathSync(resolve(service,'../..')),build=resolve(root,'.build');mkdirSync(build,{recursive:true});assert.equal(realpathSync(build),build);
 const run=mkdtempSync(resolve(build,'lifecycle-owned-'));assert.equal(realpathSync(run),run);assert.equal(dirname(run),build);
 mkdirSync(resolve(run,'home'),{mode:0o700});
 const wranglerConfig=JSON.parse(readFileSync(resolve(service,'wrangler.jsonc'),'utf8'));
 assert.deepEqual(wranglerConfig.vars,{ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'});
 assert.deepEqual(wranglerConfig.d1_databases,[{binding:'FIXTURE_DB',database_name:'licensing-local-fixture',database_id:'00000000-0000-0000-0000-000000000000',remote:false}]);
 let mf:any,db:any,origin='',deniedOutbound=0,logs:string[]=[],active:RuntimeOptions=initial;const digests:string[]=[];let bytes=0;let expectedOutbound=0;const batches:Readonly<{statementCount:number;maxBindings:number}>[]=[];
 const prepared=new WeakMap<object,{statement:any;bindings:number}>();
 const wrapStatement=(statement:any,bindings=0):any=>{const proxy=new Proxy(statement,{get(target,key){if(key==='bind')return (...args:unknown[])=>wrapStatement(target.bind(...args),args.length);const value=Reflect.get(target,key);return typeof value==='function'?value.bind(target):value;}});prepared.set(proxy,{statement,bindings});return proxy;};
 // Synchronous proxy preparation can starve idle-socket cleanup. Yield before
 // dispatch, preserving the complete atomic batch without a retry or split.
 const measuredDB=()=>new Proxy(db,{get(target,key){if(key==='prepare')return (sql:string)=>wrapStatement(target.prepare(sql));if(key==='batch')return async(statements:any[])=>{const captured=statements.map(x=>prepared.get(x));batches.push(Object.freeze({statementCount:statements.length,maxBindings:Math.max(0,...captured.map(x=>x?.bindings??0))}));const batchStatements=statements.map((x,i)=>captured[i]?.statement??x);await yieldToRuntime();return target.batch(batchStatements);};const value=Reflect.get(target,key);return typeof value==='function'?value.bind(target):value;}});
 const logger=new mfPackage.Log(mfPackage.LogLevel.VERBOSE);
 logger.logWithLevel=(_level:number,message:string)=>{const s=String(message).slice(0,4096);if(bytes+s.length<=65536){bytes+=s.length;logs.push(s);}};
 logger.error=(error:Error)=>{const s=String(error).slice(0,4096);if(bytes+s.length<=65536){bytes+=s.length;logs.push(s);}};
 async function bundle(options:RuntimeOptions){
 const lifecycle=options.configured===false?'undefined':`{marker:'PAT-2646-synthetic',config:${JSON.stringify(config)},now:()=>${options.now??1790899200},randomBytes:length=>new Uint8Array(length).fill(${options.fixedNonce??'(++entropy)%255||1'}),syntheticKey:new Uint8Array(32).fill(66),provider:{marker:'PAT-2646-provider-synthetic',async read(command){console.log('LIFECYCLE-PROVIDER-READ');return ${options.snapshot===undefined?"{outcome:'unavailable'}":`{outcome:'snapshot',bytes:new TextEncoder().encode(${JSON.stringify(JSON.stringify(options.snapshot))})}`};},async stopRenewal(command){console.log('LIFECYCLE-PROVIDER-STOP');${options.throwStop?"throw Error('synthetic lost acknowledgement');":`return {outcome:'${options.stopOutcome??'accepted'}'};`}}}}`;
 const billing=options.billing?`{config:{fixture:'PAT-2645-synthetic',environment:'synthetic-sandbox',hmacKey:new Uint8Array(32).fill(66),prices:{GBP:'fixture-price-gbp-annual',USD:'fixture-price-usd-annual'}},adapters:{now:()=>${options.now??1790899200},attemptID:()=>(++entropy).toString(16).padStart(32,'0'),fetch:async()=>{throw Error('private fake outbound denial');}}}`:'undefined';
 const output=await esbuild.build({stdin:{contents:`import {fixtureApplicationFetch} from './src/index.ts';let entropy=${options.seed??32};const lifecycle=${lifecycle};const billing=${billing};export default {fetch(request,env){return fixtureApplicationFetch(request,env,billing,lifecycle);}};`,resolveDir:service,sourcefile:'lifecycle-test-composition.ts'},bundle:true,write:false,format:'esm',platform:'browser',target:'es2022',logLevel:'silent'});
 const script=output.outputFiles[0].text;digests.push(createHash('sha256').update(script).digest('hex'));return script;
 }
 async function boot(options:RuntimeOptions={},overrideScript?:string){
  active=options;const script=overrideScript??await bundle(options);
  // Miniflare launches workerd under only these local, non-secret values.
  const saved={...process.env};for(const name of Object.keys(process.env))delete process.env[name];
  Object.assign(process.env,{PATH:dirname(process.execPath)+':/usr/bin:/bin:/usr/sbin:/sbin',HOME:resolve(run,'home'),TMPDIR:run,WRANGLER_SEND_METRICS:'false',CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV:'false'});
  try {
   mf=new mfPackage.Miniflare(mfPackage.convertV4MiniflareOptions({name:'pat2646-lifecycle-owned',modules:true,script,compatibilityDate:wranglerConfig.compatibility_date,bindings:options.markers??wranglerConfig.vars,d1Databases:{FIXTURE_DB:wranglerConfig.d1_databases[0].database_id},resourcePersistencePath:resolve(run,'state'),host:'127.0.0.1',port:0,cf:false,log:logger,handleStructuredLogs:(entry:unknown)=>{logs.push(JSON.stringify(entry));},outboundService:()=>{deniedOutbound++;throw Error('LIFECYCLE-RUNTIME-OUTBOUND-DENIED');}}));
   origin=(await mf.ready).origin;assert.equal(new URL(origin).hostname,'127.0.0.1');db=await mf.getD1Database('FIXTURE_DB');
  } finally {for(const name of Object.keys(process.env))delete process.env[name];Object.assign(process.env,saved);}
 }
 try {await boot(initial);for(const migration of allowlist)await db.batch(migrationStatements(migration).map(sql=>db.prepare(sql)));}
 catch(error){if(mf)await mf.dispose();throw error;}
 async function rows(sql:string,...args:unknown[]){return (await db.prepare(sql).bind(...args).all()).results as any[];}
 async function snapshot(productiveOnly=false){
  const tables=(await rows("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name")).map(r=>r.name).filter(name=>!productiveOnly||!name.startsWith('billing_'));
  return (await db.batch(tables.map(name=>db.prepare(`SELECT * FROM "${name}" ORDER BY 1,2`)))).map((result:any,i:number)=>({table:tables[i],rows:result.results}));
 }
 return {run,versions,get db(){return measuredDB();},get batches(){return [...batches];},get origin(){return origin;},get deniedOutbound(){return deniedOutbound;},get logs(){return [...logs];},
  rows,snapshot,
  async restart(options:RuntimeOptions=active){await mf.dispose();await boot(options);},
  async reset(options:RuntimeOptions=initial){
   for(const trigger of await rows("SELECT name FROM sqlite_master WHERE type='trigger'")){assert.match(trigger.name,/^lifecycle_test_/);await db.prepare(`DROP TRIGGER "${trigger.name}"`).run();}
   const order=['billing_restoration','billing_grace_void','billing_grace','billing_review_confirmation','billing_period_end','billing_adjustment','billing_dispute','billing_period','billing_event_consumed','billing_stop_cause','billing_renewal_stop','billing_lifecycle_request','billing_entity_version','billing_snapshot','billing_reconcile','billing_existing_transaction','billing_lifecycle_commit','billing_subscription'];
   await db.batch(order.map(table=>db.prepare(`DELETE FROM ${table}`)));
   await db.batch(['billing_inbox_commit','billing_webhook_audit','billing_webhook_quarantine','billing_event_conflict','billing_webhook_delivery','billing_event','billing_webhook_body'].map(table=>db.prepare(`DELETE FROM ${table}`)));
   await db.batch(['device_requests','device_request_tombstones','operator_confirmations','device_challenges','activation_slots','activations','lease_heads','used_refresh_tokens','sessions','trial_requests','retention_rows','account_requests','account_audit','account_nonce_history','entitlement_sources','account_guard','accounts'].map(table=>db.prepare(`DELETE FROM ${table}`)));
   await mf.dispose();await boot(options);
  },
  async canary(){const before=deniedOutbound;await mf.dispose();await boot({},"export default {async fetch(){for(const method of ['log','info','warn','error','debug'])console[method]('LIFECYCLE-CONSOLE-'+method+'-CONTROL');return fetch('https://lifecycle-outbound.invalid/');}}");const response=await fetch(origin,{headers:{Connection:'close'},signal:AbortSignal.timeout(10000)});assert.equal(response.status,500);assert.equal(deniedOutbound,before+1);expectedOutbound++;for(const method of ['log','info','warn','error','debug'])assert.ok(logs.join('\n').includes('LIFECYCLE-CONSOLE-'+method+'-CONTROL'),'workerd console '+method+' capture control');await mf.dispose();await boot();},
  async postBilling(input:unknown){
   const bytes=new TextEncoder().encode(JSON.stringify(input));const time=active.now??1790899200;
   const signature=`t=${time};v1=${createHmac('sha256',new Uint8Array(32).fill(66)).update(`PAT-2645\n${time}\n`).update(bytes).digest('hex')}`;
   const response=await fetch(origin+'/__fixture/billing/webhook',{method:'POST',headers:{Connection:'close','Content-Type':'application/json','X-Patched-Fixture-Signature':signature},body:bytes,redirect:'error',signal:AbortSignal.timeout(10000)});return {status:response.status,body:await response.json() as any};
  },
  async sourceAPI(){
   const file=resolve(run,'lifecycle-source-api.mjs');
   const result=await esbuild.build({stdin:{contents:"export {BillingLifecycle} from './src/billing/reconcile.ts';export {AuthService} from './src/auth.ts';export {TrialService} from './src/entitlements.ts';export {ActivationService} from './src/activations.ts';export * from './src/entitlementPlans.ts';",resolveDir:service,sourcefile:'lifecycle-source-api.ts'},bundle:true,write:false,format:'esm',platform:'node',target:'es2022',logLevel:'silent'});
   writeFileSync(file,result.outputFiles[0].text);return import(new URL('file://'+file).href);
  },
  async post(route:string,input:unknown,method='POST'){
   const response=await fetch(origin+'/__fixture/lifecycle/'+route,{method,headers:{Connection:'close','Content-Type':'application/json'},body:method==='GET'?undefined:JSON.stringify(input),redirect:'error',signal:AbortSignal.timeout(10000)});
   const text=await response.text();return {status:response.status,headers:Object.fromEntries(response.headers),text,body:JSON.parse(text)};
  },
  async seed(ledger:any,now=1790899200,kind='app'){
   const ah=createHmac('sha256',new Uint8Array(32).fill(66)).update('im.patched.access.v1\0'+token).digest('hex');
   await db.batch([
    db.prepare('INSERT INTO accounts VALUES (?,?,?,NULL,?,0)').bind(account,'e'.repeat(64),now-100,ledger.account.entitlementRevision),
    db.prepare('INSERT INTO account_guard VALUES (?,1,?)').bind(account,nonce),
    db.prepare('INSERT INTO entitlement_sources VALUES (?,?,?,?,?)').bind(account,ledger.entitlementSources.trialStartedAt,ledger.entitlementSources.trialEndsAt,Number(ledger.entitlementSources.betaInvited),ledger.entitlementSources.betaEndsAt),
    db.prepare('INSERT INTO sessions VALUES (?,?,?,NULL,?,?,?,?,?,?,?,NULL,?)').bind(session,account,kind,now-10,now-100,ah,now+900,kind==='app'?'d'.repeat(64):null,kind==='app'?now+86400:null,now+86400,nonce)
   ]);
   // Seed in explicit FK order. No service mapping-creation route exists.
   const order=['billing_subscription','billing_existing_transaction','billing_reconcile','billing_snapshot','billing_entity_version','billing_period','billing_adjustment','billing_dispute','billing_period_end','billing_review_confirmation','billing_restoration','billing_grace','billing_grace_void','billing_renewal_stop','billing_stop_cause','billing_lifecycle_request','billing_event_consumed','billing_lifecycle_commit'];
   for(const table of order)for(const original of ledger[table]??[]){const row={...original};if(table==='billing_reconcile'){row.claimed_wanted=null;row.claim_fence=null;row.claim_expires_at=null;}if(table==='billing_lifecycle_commit')await db.prepare('INSERT OR IGNORE INTO account_nonce_history VALUES (?,?)').bind(account,row.commit_nonce).run();const keys=Object.keys(row);await db.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(()=>'?').join(',')})`).bind(...Object.values(row)).run();}
  },
  async dispose(){await mf.dispose();assert.equal(deniedOutbound,expectedOutbound,'zero unexpected outbound attempts beyond explicit real canary');assert.equal(realpathSync(run),run);assert.equal(dirname(run),build);writeFileSync(resolve(run,'runtime.log'),logs.join('\n')+'\n');writeFileSync(resolve(run,'metadata.json'),JSON.stringify({versions,run,deniedOutbound,migrations:allowlist,sourceBundleSHA256:digests},null,2)+'\n');},
 };
}
