// Test-owned one-runtime harness. No SQL route is exposed by the application.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,realpathSync,mkdirSync,mkdtempSync,rmSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
export const service=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(resolve(service,'package.json'));
const {Miniflare,Log,LogLevel,convertV4MiniflareOptions}=require('miniflare');
const esbuild=require('esbuild');
export function migrationStatements(file:string):string[]{
 assert.ok(['tests/d1-local/fixture.sql','migrations/0001_accounts.sql','migrations/0002_activations.sql'].includes(file));
 const sql=readFileSync(resolve(service,file),'utf8').replace(/^\s*--.*$/mg,'');
 assert.ok(!/\bTRIGGER\b|\/\*|[\"`\[\]]/i.test(sql.replace(/'(?:[^']|'')*'/g,'')),'unsupported migration syntax');
 // Current reviewed DDL contains single quoted literals but no quoted semicolons.
 let quoted=false;for(let i=0;i<sql.length;i++){if(sql[i]==="'"){if(quoted&&sql[i+1]==="'"){i++;continue;}quoted=!quoted;}if(sql[i]===';')assert.equal(quoted,false,'quoted semicolon refused');}assert.equal(quoted,false,'unterminated quote refused');
 return sql.split(';').map(s=>s.trim()).filter(Boolean);
}
export async function localRuntime(a2=true){
 assert.equal(process.version,'v24.21.0');
 assert.equal(require('miniflare/package.json').version,'5.20261006.1-alpha');assert.equal(require('esbuild/package.json').version,'0.28.2');assert.equal(require('workerd/package.json').version,'1.20261006.1');
 const root=realpathSync(resolve(service,'../..')),build=resolve(root,'.build');mkdirSync(build,{recursive:true});assert.equal(realpathSync(build),build);
 const run=mkdtempSync(resolve(build,'a2-owned-'));assert.equal(realpathSync(run),run);
 const config=JSON.parse(readFileSync(resolve(service,'wrangler.jsonc'),'utf8'));
 assert.deepEqual(config.vars,{ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'});
 assert.deepEqual(config.d1_databases,[{binding:'FIXTURE_DB',database_name:'licensing-local-fixture',database_id:'00000000-0000-0000-0000-000000000000',remote:false}]);
 const bundled=await esbuild.build({entryPoints:[resolve(service,'src/index.ts')],bundle:true,write:false,format:'esm',platform:'browser',target:'es2022',logLevel:'silent'});
 let mf:any,db:any,origin='',deniedOutbound=0;
 async function boot(bindings=config.vars,script=bundled.outputFiles[0].text){
  mf=new Miniflare(convertV4MiniflareOptions({modules:true,script,compatibilityDate:config.compatibility_date,bindings,d1Databases:{FIXTURE_DB:config.d1_databases[0].database_id},resourcePersistencePath:resolve(run,'state'),name:'a2-fixture',host:'127.0.0.1',port:0,cf:false,log:new Log(LogLevel.NONE),outboundService:()=>{deniedOutbound++;throw Error('outbound denied');}}));
  origin=(await mf.ready).origin;assert.equal(new URL(origin).hostname,'127.0.0.1');db=await mf.getD1Database('FIXTURE_DB');
 }
 try {await boot();
 for(const file of ['tests/d1-local/fixture.sql','migrations/0001_accounts.sql',...(a2?['migrations/0002_activations.sql']:[])])await db.batch(migrationStatements(file).map(sql=>db.prepare(sql)));}catch(error){if(mf)await mf.dispose();rmSync(run,{recursive:true});throw error;}
 return {
  run,versions:Object.fromEntries(['miniflare','esbuild','workerd'].map(n=>[n,require(n+'/package.json').version])),
  get db(){return db;},get origin(){return origin;},get deniedOutbound(){return deniedOutbound;},
  async canary(){await mf.dispose();await boot(config.vars,"export default {async fetch(){return fetch('https://fixture-outbound.invalid/');}}");const r=await fetch(origin,{headers:{Connection:'close'},signal:AbortSignal.timeout(10000)});assert.equal(r.status,500);assert.equal(deniedOutbound,1);await mf.dispose();await boot();},
  async restart(bindings?:unknown){await mf.dispose();await boot(bindings);},
  async post(path:string,input:unknown,headers:Record<string,string>={}){const r=await fetch(origin+path,{method:'POST',headers:{Connection:'close','Content-Type':'application/json',...headers},body:JSON.stringify(input),redirect:'error',signal:AbortSignal.timeout(10000)});return {status:r.status,body:await r.json() as any};},
  async rows(sql:string,...args:unknown[]){return (await db.prepare(sql).bind(...args).all()).results as any[];},
  async snapshot(){const tables=(await db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name").all()).results.map((r:any)=>r.name);return (await db.batch(tables.map((t:string)=>db.prepare(`SELECT * FROM "${t}" ORDER BY 1,2`)))).map((r:any,i:number)=>({table:tables[i],rows:r.results}));},
  async dispose(){await mf.dispose();assert.equal(dirname(run),build);assert.equal(realpathSync(run),run);rmSync(run,{recursive:true});},
 };
}
