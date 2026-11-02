// PAT-2645 single-owner local workerd/D1 harness; no app SQL/debug route.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,realpathSync,mkdirSync,mkdtempSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHmac} from 'node:crypto';
export const service=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(resolve(service,'package.json'));
const mfPackage=require('miniflare');
const esbuild=require('esbuild');
const allowlist=['tests/d1-local/fixture.sql','migrations/0001_accounts.sql','migrations/0003_billing.sql'] as const;
export function migrationStatements(file:string):string[]{
 assert.ok((allowlist as readonly string[]).includes(file),'migration not explicitly allowed');
 const sql=readFileSync(resolve(service,file),'utf8').replace(/^\s*--.*$/mg,'');
 let quoted=false;for(let i=0;i<sql.length;i++){if(sql[i]==="'"){if(quoted&&sql[i+1]==="'"){i++;continue;}quoted=!quoted;}if(sql[i]===';')assert.equal(quoted,false,'quoted semicolon unsupported');}assert.equal(quoted,false);
 assert.ok(!/\bTRIGGER\b|\/\*|["`\[\]]/i.test(sql.replace(/'(?:[^']|'')*'/g,'')),'migration syntax outside reviewed subset');
 return sql.split(';').map(s=>s.trim()).filter(Boolean);
}
export interface RuntimeOptions {now?:number;keyByte?:number;attemptSeed?:number;fixedAttempt?:string;configured?:boolean;markers?:Record<string,string>}
export const billingTables=['billing_event_conflict','billing_webhook_quarantine','billing_webhook_audit','billing_inbox_commit','billing_webhook_delivery','billing_event','billing_webhook_body'];
export async function billingRuntime(){
 assert.equal(process.version,'v24.21.0');
 const versions=Object.fromEntries(['miniflare','esbuild','workerd'].map(name=>[name,require(name+'/package.json').version]));
 assert.deepEqual(versions,{miniflare:'5.20261006.1-alpha',esbuild:'0.28.2',workerd:'1.20261006.1'});
 const root=realpathSync(resolve(service,'../..')),build=resolve(root,'.build');mkdirSync(build,{recursive:true});assert.equal(realpathSync(build),build);
 const run=mkdtempSync(resolve(build,'billing-owned-'));assert.equal(realpathSync(run),run);assert.equal(dirname(run),build);
 mkdirSync(resolve(run,'home'),{mode:0o700});
 const config=JSON.parse(readFileSync(resolve(service,'wrangler.jsonc'),'utf8'));
 assert.deepEqual(config.vars,{ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'});
 assert.deepEqual(config.d1_databases,[{binding:'FIXTURE_DB',database_name:'licensing-local-fixture',database_id:'00000000-0000-0000-0000-000000000000',remote:false}]);
 let mf:any,db:any,origin='',deniedOutbound=0,logs:string[]=[],active:RuntimeOptions={};
 const logger=new mfPackage.Log(mfPackage.LogLevel.VERBOSE);
 logger.logWithLevel=(_level:number,message:string)=>{logs.push(String(message));};
 logger.error=(error:Error)=>{logs.push(String(error));};
 async function bundle(options:RuntimeOptions){
 const composition=options.configured===false?'undefined':`{config:{fixture:'PAT-2645-synthetic',environment:'synthetic-sandbox',hmacKey:new Uint8Array(32).fill(${options.keyByte??66}),prices:{GBP:'fixture-price-gbp-annual',USD:'fixture-price-usd-annual'}},adapters:{now:()=>${JSON.stringify(options.now??1700000000)},attemptID:()=>${options.fixedAttempt?JSON.stringify(options.fixedAttempt):"(++attempt).toString(16).padStart(32,'0')"},fetch:async()=>{throw new Error('BILLING-ADAPTER-OUTBOUND-DENIED');}}}`;
 const output=await esbuild.build({stdin:{contents:`import {fixtureApplicationFetch} from './src/index.ts';let attempt=${options.attemptSeed??0};const composition=${composition};export default {fetch(request,env){return fixtureApplicationFetch(request,env,composition);}};`,resolveDir:service,sourcefile:'billing-test-composition.ts'},bundle:true,write:false,format:'esm',platform:'browser',target:'es2022',logLevel:'silent'});return output.outputFiles[0].text;
 }
 async function boot(options:RuntimeOptions={},overrideScript?:string){
  active=options;const script=overrideScript??await bundle(options);
  // Miniflare launches workerd under only these local, non-secret values.
  const saved={...process.env};for(const name of Object.keys(process.env))delete process.env[name];
  Object.assign(process.env,{PATH:dirname(process.execPath)+':/usr/bin:/bin:/usr/sbin:/sbin',HOME:resolve(run,'home'),TMPDIR:run,WRANGLER_SEND_METRICS:'false',CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV:'false'});
  try {
   mf=new mfPackage.Miniflare(mfPackage.convertV4MiniflareOptions({name:'pat2645-billing-owned',modules:true,script,compatibilityDate:config.compatibility_date,bindings:options.markers??config.vars,d1Databases:{FIXTURE_DB:config.d1_databases[0].database_id},resourcePersistencePath:resolve(run,'state'),host:'127.0.0.1',port:0,cf:false,log:logger,handleStructuredLogs:(entry:unknown)=>{logs.push(JSON.stringify(entry));},outboundService:()=>{deniedOutbound++;throw Error('BILLING-RUNTIME-OUTBOUND-DENIED');}}));
   origin=(await mf.ready).origin;assert.equal(new URL(origin).hostname,'127.0.0.1');db=await mf.getD1Database('FIXTURE_DB');
  } finally {for(const name of Object.keys(process.env))delete process.env[name];Object.assign(process.env,saved);}
 }
 try {await boot();for(const migration of allowlist)await db.batch(migrationStatements(migration).map(sql=>db.prepare(sql)));}
 catch(error){if(mf)await mf.dispose();throw error;}
 async function rows(sql:string,...args:unknown[]){return (await db.prepare(sql).bind(...args).all()).results as any[];}
 async function snapshot(productiveOnly=false){
  const tables=(await rows("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name")).map(r=>r.name).filter(name=>!productiveOnly||!name.startsWith('billing_'));
  return (await db.batch(tables.map(name=>db.prepare(`SELECT * FROM "${name}" ORDER BY 1,2`)))).map((result:any,i:number)=>({table:tables[i],rows:result.results}));
 }
 return {run,versions,get db(){return db;},get origin(){return origin;},get deniedOutbound(){return deniedOutbound;},get logs(){return [...logs];},
  rows,snapshot,
  async restart(options:RuntimeOptions=active){await mf.dispose();await boot(options);},
  async reset(){for(const trigger of await rows("SELECT name FROM sqlite_master WHERE type='trigger'")){assert.match(trigger.name,/^billing_test_/);await db.prepare(`DROP TRIGGER "${trigger.name}"`).run();}await db.batch(billingTables.map(table=>db.prepare(`DELETE FROM ${table}`)));await mf.dispose();await boot();},
  async canary(){await mf.dispose();await boot({},"export default {async fetch(){for(const method of ['log','info','warn','error','debug'])console[method]('BILLING-CONSOLE-'+method+'-CONTROL');return fetch('https://billing-outbound.invalid/');}}");const response=await fetch(origin,{headers:{Connection:'close'},signal:AbortSignal.timeout(10000)});assert.equal(response.status,500);assert.equal(deniedOutbound,1);for(const method of ['log','info','warn','error','debug'])assert.ok(logs.join('\n').includes('BILLING-CONSOLE-'+method+'-CONTROL'),'workerd console '+method+' capture control');await mf.dispose();await boot();},
  async post(body:Uint8Array,options:{timestamp?:number;signature?:string;headers?:Record<string,string>;path?:string;method?:string}={}){
   const t=options.timestamp??1700000000;const signature=options.signature??`t=${t};v1=${createHmac('sha256',new Uint8Array(32).fill(66)).update(`PAT-2645\n${t}\n`).update(body).digest('hex')}`;
   const response=await fetch(origin+(options.path??'/__fixture/billing/webhook'),{method:options.method??'POST',headers:{Connection:'close','Content-Type':'application/json','X-Patched-Fixture-Signature':signature,...options.headers},body:options.method==='GET'?undefined:new Uint8Array(body).buffer,redirect:'error',signal:AbortSignal.timeout(10000)});
   const text=await response.text();return {status:response.status,headers:Object.fromEntries(response.headers),text,body:JSON.parse(text)};
  },
  async dispose(){await mf.dispose();assert.equal(realpathSync(run),run);assert.equal(dirname(run),build);writeFileSync(resolve(run,'runtime.log'),logs.join('\n')+'\n');writeFileSync(resolve(run,'metadata.json'),JSON.stringify({versions,run,deniedOutbound,migrations:allowlist},null,2)+'\n');},
 };
}
