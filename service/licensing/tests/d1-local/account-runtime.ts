// PAT-2652: one exclusive local native owner, shared by HTTP and direct D1.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,realpathSync,mkdirSync,mkdtempSync,writeFileSync,lstatSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const service=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(resolve(service,'package.json'));
const mfPackage=require('miniflare'), esbuild=require('esbuild'), cp=require('node:child_process');
export interface AccountWebRuntimeFixture {
 marker:'PAT-2649-account-runtime-synthetic';allowedOrigin:string;now:number;entropySeed:string;
}
function webFixture(value:AccountWebRuntimeFixture):AccountWebRuntimeFixture {
 assert.ok(value&&typeof value==='object'&&!Array.isArray(value));
 assert.deepEqual(Object.keys(value).sort(),['allowedOrigin','entropySeed','marker','now']);
 assert.equal(value.marker,'PAT-2649-account-runtime-synthetic');
 assert.ok(Number.isSafeInteger(value.now)&&value.now>=0&&value.now<=253402300799);
 assert.match(value.entropySeed,/^(?!0{32}$)[a-f0-9]{32}$/);
 const u=new URL(value.allowedOrigin);
 assert.equal(u.protocol,'https:');assert.equal(u.hostname,'account.patched-fixture.invalid');
 assert.equal(u.origin,value.allowedOrigin);assert.ok(u.port&&Number(u.port)>=1&&Number(u.port)<=65535);
 return Object.freeze({...value});
}
export interface AccountRuntimeOptions {web?:AccountWebRuntimeFixture;onLog?:(message:string)=>void;markers?:Record<string,string>}
export interface AccountRuntime {
 readonly run:string;readonly origin:string;readonly db:any;
 readonly versions:Record<string,string>;readonly logs:string[];
 restart(options?:{markers?:Record<string,string>;web?:AccountWebRuntimeFixture|null}):Promise<void>;
 outboundCanary():Promise<{status:number}>;dispose():Promise<void>;
}
export async function accountRuntime(options:AccountRuntimeOptions={}):Promise<AccountRuntime>{
 assert.equal(process.version,'v24.21.0');
 assert.ok(Object.keys(options).every(k=>['onLog','markers','web'].includes(k)));
 let activeWeb=options.web===undefined?undefined:webFixture(options.web),webBuilds=0;
 const versions=Object.fromEntries(['miniflare','esbuild','workerd'].map(name=>[name,require(name+'/package.json').version]));
 assert.deepEqual(versions,{miniflare:'5.20261006.1-alpha',esbuild:'0.28.2',workerd:'1.20261006.1'});
 const root=realpathSync(resolve(service,'../..')),build=resolve(root,'.build');
 mkdirSync(build,{recursive:true});assert.equal(realpathSync(build),build);
 const run=mkdtempSync(resolve(build,'account-owned-'));assert.equal(realpathSync(run),run);assert.equal(dirname(run),build);
 mkdirSync(resolve(run,'home'),{mode:0o700});
 const config=JSON.parse(readFileSync(resolve(service,'wrangler.jsonc'),'utf8'));
 assert.deepEqual(config.vars,{ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'});
 assert.deepEqual(config.d1_databases,[{binding:'FIXTURE_DB',database_name:'licensing-local-fixture',database_id:'00000000-0000-0000-0000-000000000000',remote:false}]);
 assert.equal(config.workers_dev,false);assert.equal(config.preview_urls,false);assert.equal(config.account_id,undefined);assert.equal(config.routes,undefined);assert.equal(config.env,undefined);
 const logs:string[]=[];let logBytes=0;
 // Bound retained diagnostics; runtime never prints request bodies, SQL or env.
 const capture=(message:unknown)=>{const text=String(message).slice(0,4096);if(logBytes+text.length>65536)return;logBytes+=text.length;logs.push(text);options.onLog?.(text);};
 const logger=new mfPackage.Log(mfPackage.LogLevel.VERBOSE);
 logger.logWithLevel=(_level:number,message:string)=>capture(message);
 logger.error=(error:Error)=>capture(error);
 let mf:any,db:any,origin='',activeMarkers={...(options.markers??config.vars)},disposed=false,deniedOutbound=0;
 async function bundle(){
  if(activeWeb){
   const assets=new Map(['index.html','account.js','account.css'].map(name=>[name,resolve(service,'web/account',name)]));
   const result=await esbuild.build({absWorkingDir:service,entryPoints:[resolve(service,'tests/d1-local/account-web-entry.ts')],bundle:true,write:false,format:'esm',platform:'browser',target:'es2022',logLevel:'silent',define:{__PAT2649_ACCOUNT_RUNTIME__:JSON.stringify(activeWeb)},plugins:[{name:'fixed-account-assets',setup(build:any){
    build.onResolve({filter:/\?account-web-asset$/},(args:any)=>{
     const name=args.path.slice(0,-'?account-web-asset'.length);assert.ok(assets.has(name),'unknown fixed asset');
     assert.equal(resolve(args.importer),resolve(service,'tests/d1-local/account-web-entry.ts'));
     return {path:assets.get(name),namespace:'account-web-asset'};
    });
    build.onLoad({filter:/.*/,namespace:'account-web-asset'},(args:any)=>{
     assert.ok([...assets.values()].includes(args.path));
     for(const path of [resolve(service,'web'),resolve(service,'web/account'),args.path])assert.equal(lstatSync(path).isSymbolicLink(),false);
     assert.equal(realpathSync(args.path),args.path);assert.ok(lstatSync(args.path).isFile());
     return {contents:readFileSync(args.path,'utf8'),loader:'text'};
    });
   }}]});writeFileSync(resolve(run,`account-web-compiled-${++webBuilds}.mjs`),result.outputFiles[0].text,{flag:'wx'});return result.outputFiles[0].text;
  }
  const result=await esbuild.build({absWorkingDir:service,entryPoints:[resolve(service,'src/index.ts')],bundle:true,write:false,format:'esm',platform:'browser',target:'es2022',logLevel:'silent'});
  return result.outputFiles[0].text;
 }
 async function boot(script?:string){
  disposed=false;
  const source=script??await bundle();
  // Keep observer preload metadata on the parent for actual spawn instrumentation;
  // all child values come from this local allowlist, never credentials/dotenv.
  const saved={...process.env};for(const name of Object.keys(process.env))delete process.env[name];
  Object.assign(process.env,{PATH:dirname(process.execPath)+':/usr/bin:/bin:/usr/sbin:/sbin',HOME:resolve(run,'home'),TMPDIR:run,WRANGLER_SEND_METRICS:'false',CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV:'false'});
  for(const name of ['NODE_OPTIONS','PAT_ACCOUNT_OWNER_LOG'])if(saved[name]!==undefined)process.env[name]=saved[name];
  const originalSpawn=cp.spawn;
  cp.spawn=function(command:unknown,args:unknown,spawnOptions:any){
   if(/(?:^|[/\\])workerd(?:\.exe)?$/.test(String(command))){
    const env={...spawnOptions.env};delete env.NODE_OPTIONS;delete env.PAT_ACCOUNT_OWNER_LOG;
    spawnOptions={...spawnOptions,env};
   }
   return originalSpawn.call(this,command,args,spawnOptions);
  };
  try {
   mf=new mfPackage.Miniflare(mfPackage.convertV4MiniflareOptions({name:'pat2652-account-owned',modules:true,script:source,compatibilityDate:config.compatibility_date,bindings:activeMarkers,d1Databases:{FIXTURE_DB:config.d1_databases[0].database_id},resourcePersistencePath:resolve(run,'state'),host:'127.0.0.1',port:0,cf:false,log:logger,handleStructuredLogs:(entry:unknown)=>capture(JSON.stringify(entry)),outboundService:()=>{deniedOutbound++;throw Error('ACCOUNT-RUNTIME-OUTBOUND-DENIED');}}));
   origin=(await mf.ready).origin;assert.equal(new URL(origin).hostname,'127.0.0.1');db=await mf.getD1Database('FIXTURE_DB');disposed=false;
  } finally {cp.spawn=originalSpawn;for(const name of Object.keys(process.env))delete process.env[name];Object.assign(process.env,saved);}
 }
 async function stop(){if(mf){const owner=mf;await owner.dispose();mf=undefined;db=undefined;origin='';}}
 async function dispose(){if(disposed)return;await stop();disposed=true;assert.equal(realpathSync(run),run);assert.equal(dirname(run),build);writeFileSync(resolve(run,'runtime.log'),logs.join('\n')+'\n');writeFileSync(resolve(run,'metadata.json'),JSON.stringify({versions,deniedOutbound},null,2)+'\n');}
 try{await boot();}catch(error){await dispose();throw error;}
 return {run,versions,get db(){assert.ok(db,'account runtime disposed');return db;},get origin(){assert.ok(origin,'account runtime disposed');return origin;},get logs(){return [...logs];},
  async restart(next){
   assert.ok(next===undefined||Object.keys(next).every(k=>['markers','web'].includes(k)));
   const selected=next?.web===undefined?activeWeb:next.web===null?undefined:webFixture(next.web);
   await stop();activeWeb=selected;if(next?.markers!==undefined)activeMarkers={...next.markers};try{await boot();}catch(error){await dispose();throw error;}},
  async outboundCanary(){
   await stop();let status:number;
   try {await boot("export default {fetch(){return fetch('https://account-outbound.invalid/');}}");const response=await fetch(origin,{headers:{Connection:'close'},signal:AbortSignal.timeout(10000)});status=response.status;await response.arrayBuffer();}
   finally {await stop();await boot();}
   return {status};
  },dispose,
 };
}
