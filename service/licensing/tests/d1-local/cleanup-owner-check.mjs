// Actual-process ownership check, independent of the account runtime implementation.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {mkdirSync,mkdtempSync,readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verify} from './cleanup-preservation.mjs';
import {staticControls,nativeControls} from './cleanup-runtime-controls.mjs';
const here=dirname(fileURLToPath(import.meta.url)),service=resolve(here,'../..'),root=resolve(service,'../..');
const require=createRequire(resolve(service,'package.json'));
const mode=process.argv[2]??'suite';
if(mode==='runtime-controls'){ await nativeControls(); }else if(mode==='control-child'){
 const {Miniflare,convertV4MiniflareOptions,Log,LogLevel}=require('miniflare');
 const run=process.env.TMPDIR;
 const options={modules:true,script:"export default {async fetch(request,env){const r=await env.FIXTURE_DB.prepare('SELECT n FROM ownership_control').first();return Response.json(r);}}",compatibilityDate:'2026-10-06',d1Databases:{FIXTURE_DB:'00000000-0000-0000-0000-000000000000'},resourcePersistencePath:resolve(run,'state'),host:'127.0.0.1',port:0,cf:false,log:new Log(LogLevel.NONE),outboundService:()=>{throw Error('CONTROL-OUTBOUND-DENIED');}};
 let mf;
 try {
  mf=new Miniflare(convertV4MiniflareOptions(options));
  const origin=(await mf.ready).origin,db=await mf.getD1Database('FIXTURE_DB');
  await db.exec('CREATE TABLE ownership_control (n INTEGER); INSERT INTO ownership_control VALUES (73);');
  assert.deepEqual(await (await fetch(origin,{headers:{Connection:'close'},signal:AbortSignal.timeout(10000)})).json(),{n:73});
  // A genuinely launched Wrangler child overlaps an actual, live direct workerd.
  const config=resolve(run,'wrangler.json');writeFileSync(config,JSON.stringify({name:'account-owner-control',main:resolve(service,'src/index.ts'),compatibility_date:'2026-10-06',workers_dev:false,preview_urls:false,d1_databases:[{binding:'FIXTURE_DB',database_name:'licensing-local-fixture',database_id:'00000000-0000-0000-0000-000000000000',remote:false}]}));
  const result=spawnSync(process.execPath,[resolve(service,'node_modules/wrangler/wrangler-dist/cli.js'),'d1','execute','FIXTURE_DB','--local','--config',config,'--persist-to',resolve(run,'state'),'--command','SELECT 1;'],{encoding:'utf8',timeout:30000,env:{PATH:process.env.PATH,CI:'true',WRANGLER_SEND_METRICS:'false'}});
  assert.equal(result.error,undefined);assert.equal(result.status,86);assert.match(result.stderr,/ACCOUNT-OWNER-OVERLAP/);
  // Disposal removes the real process; a fresh owner subsequently reaches persisted D1.
  await mf.dispose();mf=new Miniflare(convertV4MiniflareOptions(options));
  const next=(await mf.ready).origin;
  assert.deepEqual(await (await fetch(next,{headers:{Connection:'close'},signal:AbortSignal.timeout(10000)})).json(),{n:73});
 } finally {if(mf)await mf.dispose();}
 console.log('ACCOUNT-OWNER controls: real D1/HTTP positive, deliberate owner-launch overlap refused, disposed-owner restart/persistence positive');
}else{
 assert.ok(['suite','controls'].includes(mode),'unknown account owner check mode');
 const original=readFileSync(resolve(here,'cleanup.test.ts'),'utf8');verify(original);
 if(mode==='controls')staticControls();
 const build=resolve(root,'.build');mkdirSync(build,{recursive:true});const run=mkdtempSync(resolve(build,'cleanup-owner-observer-'));
 const log=resolve(run,'events.jsonl');writeFileSync(log,'');mkdirSync(resolve(run,'home'));
 const env={PATH:process.env.PATH,HOME:resolve(run,'home'),TMPDIR:run,CI:'true',WRANGLER_SEND_METRICS:'false',CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV:'false',PAT_ACCOUNT_OWNER_LOG:log};
 const target=mode==='controls'?[fileURLToPath(import.meta.url),'control-child']:[resolve(here,'cleanup.test.ts')];
 const result=spawnSync(process.execPath,['--require',resolve(here,'cleanup-owner-observer.cjs'),...target],{cwd:root,env,detached:true,encoding:'utf8',timeout:180000,maxBuffer:4*1024*1024,killSignal:'SIGKILL'});
 if(result.error&&result.pid){try{process.kill(-result.pid,'SIGKILL');}catch(error){if(error.code!=='ESRCH')throw error;}}
 writeFileSync(resolve(run,'stdout.log'),result.stdout??'');writeFileSync(resolve(run,'stderr.log'),result.stderr??'');
 const events=readFileSync(log,'utf8').trim().split('\n').filter(Boolean).map(line=>JSON.parse(line));
 assert.equal(result.error,undefined,'owner check launch/timeout failure is not meaningful red');
 assert.ok(events.some(e=>e.kind==='workerd'&&['spawned','nested-launch'].includes(e.action)),'observer must witness an actual native workerd launch');
 console.log(`Cleanup owner ${mode}: ${events.length} bounded process events; artifacts ${run}`);
 if(mode==='controls'){
  assert.equal(result.status,0,result.stderr);assert.ok(events.some(e=>e.action==='overlap'&&e.active===2));
  assert.equal(events.filter(e=>e.kind==='workerd'&&e.action==='spawned').length,2);
  assert.equal(events.filter(e=>e.kind==='workerd'&&e.action==='exited').length,2);
  process.stdout.write(result.stdout);

 }else{
  const overlap=events.some(e=>e.action==='overlap'&&e.active===2);
  if(overlap){
   assert.ok(events.some(e=>e.kind==='wrangler-dev'&&e.action==='spawned')||events.some(e=>e.kind==='workerd'&&e.action==='spawned'));
   assert.notEqual(result.status,0);assert.match((result.stdout??'')+'\n'+(result.stderr??''),/ACCOUNT-OWNER-OVERLAP/);
   assert.ok(events.some(e=>e.kind==='wrangler-dev'&&e.action==='exited')||events.some(e=>e.kind==='workerd'&&e.action==='exited'),'live owner must be cleaned after refusal');
   console.error('ACCOUNT-OWNER-OVERLAP: independently observed actual owner launch while previous owner PID was live; infrastructure red, not historical SQLITE_BUSY reproduction');
   process.exitCode=86;
  }else{
   assert.equal(result.status,0,result.stderr);assert.ok(events.some(e=>e.kind==='workerd'&&e.action==='spawned'),'single-owner suite must use direct workerd');
   assert.equal(events.filter(e=>e.action==='spawned').length,1,'cleanup suite must launch exactly one owner');
   assert.equal(events.filter(e=>e.kind==='workerd'&&e.action==='exited').length,1,'cleanup suite direct workerd must exit exactly once');
   assert.equal(events.filter(e=>['wrangler-dev','wrangler-d1'].includes(e.kind)&&['launched','spawned'].includes(e.action)).length,0,'successful cleanup suite must launch no Wrangler owner');
   process.stdout.write(result.stdout);
  }
 }
}
