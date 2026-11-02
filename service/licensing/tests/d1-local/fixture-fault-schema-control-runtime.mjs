// Independently owned native TEST MACHINERY. Imports no application worker/source.
import assert from 'node:assert/strict';
import {createRequire, syncBuiltinESMExports} from 'node:module';
import {mkdirSync,mkdtempSync,realpathSync,statfsSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const service=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(resolve(service,'package.json'));
const cp=require('node:child_process');
const nativeWorker="export default {fetch(){return new Response('fixture-control-only',{status:404});}}";
const canaryWorker="export default {fetch(){return fetch('https://fixture-fault-schema-outbound.invalid/');}}";
export async function fixtureFaultSchemaControlRuntime() {
  assert.equal(process.version,'v24.21.0');
  assert.equal(cp.execFileSync('npm',['--version'],{encoding:'utf8'}).trim(),'11.19.0');
  const versions=Object.fromEntries(['miniflare','esbuild','workerd'].map(n=>[n,require(n+'/package.json').version]));
  assert.deepEqual(versions,{miniflare:'5.20261006.1-alpha',esbuild:'0.28.2',workerd:'1.20261006.1'});
  const root=realpathSync(resolve(service,'../..')),build=resolve(root,'.build');
  mkdirSync(build,{recursive:true}); assert.equal(realpathSync(build),build);
  const disk=statfsSync(build);assert.ok(disk.bavail*disk.bsize>=5242880*1024,'5 GiB storage margin required');
  const run=mkdtempSync(resolve(build,'fixture-fault-schema-owned-'));
  assert.equal(realpathSync(run),run);assert.equal(dirname(run),build);
  mkdirSync(resolve(run,'home'),{mode:0o700});
  const events=[],diagnostics=[];let recordedBytes=0,mf,raw,disposed=false,generation=0,nativeLaunches=0,outboundDenied=0;
  const record=e=>{const s=JSON.stringify(e);recordedBytes+=Buffer.byteLength(s);if(recordedBytes>8*1024*1024)throw Error('CONTROL-OBSERVER-OVERFLOW');events.push(Object.freeze(e));};
  const statements=new WeakMap();
  function observe(db) {
    function wrap(statement,sql,bindings=[]) {
      const out={bind(...values){return wrap(statement.bind(...values),sql,values);}};
      for(const method of ['all','first','raw','run'])out[method]=async(...args)=>{
        record({phase:'native',method,sql,sqlBytes:Buffer.byteLength(sql),bindings,bindingTypes:bindings.map(value=>value===null?'null':ArrayBuffer.isView(value)?value.constructor.name:typeof value),generation,args});
        try{const result=await statement[method](...args);record({phase:'native-result',method,generation,result});return result;}catch(error){record({phase:'native-error',method,sql,generation,message:String(error)});throw error;}
      };
      statements.set(out,{statement,sql,bindings,generation});return Object.freeze(out);
    }
    return Object.freeze({prepare(sql){return wrap(db.prepare(sql),sql);},async batch(batch){
      const entries=batch.map((s,index)=>{const e=statements.get(s);assert.ok(e&&e.generation===generation,'native sink foreign/stale statement');return {...e,index};});
      record({phase:'native-batch',generation,count:entries.length});
      for(const e of entries)record({phase:'native',method:'batch',generation,index:e.index,sql:e.sql,sqlBytes:Buffer.byteLength(e.sql),bindings:e.bindings,bindingTypes:e.bindings.map(value=>value===null?'null':ArrayBuffer.isView(value)?value.constructor.name:typeof value)});
      try{const result=await db.batch(entries.map(e=>e.statement));record({phase:'native-batch-result',generation,result});return result;}catch(error){record({phase:'native-error',method:'batch',generation,message:String(error)});throw error;}
    }});
  }
  async function boot(script=nativeWorker) {
    assert.ok(!mf,'overlapping native owner');generation++;
    const saved={...process.env},originalSpawn=cp.spawn;
    for(const k of Object.keys(process.env))delete process.env[k];
    const allowed={PATH:dirname(process.execPath)+':/usr/bin:/bin:/usr/sbin:/sbin',HOME:resolve(run,'home'),TMPDIR:run,WRANGLER_SEND_METRICS:'false',CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV:'false'};
    Object.assign(process.env,allowed);
    cp.spawn=function(command,args,options){
      if(/(?:^|[/\\])workerd(?:\.exe)?$/.test(String(command))){
        nativeLaunches++;
        // Override actual child env: no caller credentials/preload survive.
        options={...options,env:{...allowed}};
        record({phase:'launch',generation,environmentKeys:Object.keys(options.env).sort()});
      }
      return originalSpawn.call(this,command,args,options);
    };syncBuiltinESMExports();
    try {
      const pkg=require('miniflare');
      const log=new pkg.Log(pkg.LogLevel.ERROR);
      log.logWithLevel=(_level,message)=>{if(diagnostics.length>=128)throw Error('CONTROL-LOG-OVERFLOW');diagnostics.push(String(message).slice(0,4096));};
      mf=new pkg.Miniflare(pkg.convertV4MiniflareOptions({name:'pat2675-fixture-fault-schema-control',modules:true,script,compatibilityDate:'2026-10-06',host:'127.0.0.1',port:0,cf:false,log,d1Databases:{FIXTURE_DB:'00000000-0000-0000-0000-000000000000'},resourcePersistencePath:resolve(run,'state'),outboundService(){outboundDenied++;throw Error('CONTROL-OUTBOUND-DENIED');}}));
      assert.equal(new URL((await mf.ready).origin).hostname,'127.0.0.1');
      raw=await mf.getD1Database('FIXTURE_DB');
    } finally {cp.spawn=originalSpawn;syncBuiltinESMExports();for(const k of Object.keys(process.env))delete process.env[k];Object.assign(process.env,saved);}
  }
  async function stop(){raw=undefined;if(mf){const old=mf;mf=undefined;await old.dispose();}}
  async function dispose(){if(disposed)return;await stop();disposed=true;assert.equal(realpathSync(run),run);writeFileSync(resolve(run,'native-observations.json'),JSON.stringify({versions,nativeLaunches,outboundDenied,events,diagnostics},null,2)+'\n');}
  try{await boot();}catch(error){await dispose();throw error;}
  return Object.freeze({run,versions,get generation(){return generation;},get events(){return events.slice();},get launches(){return nativeLaunches;},get outboundDenied(){return outboundDenied;},get db(){assert.ok(raw,'disposed runtime');return observe(raw);},
    async rawRows(sql,...bindings){assert.ok(raw);record({phase:'setup-read',sql,bindings,generation});return (await raw.prepare(sql).bind(...bindings).all()).results;},
    async setup(sql,...bindings){assert.ok(raw);record({phase:'setup-write',sql,bindings,generation});return raw.prepare(sql).bind(...bindings).run();},
    async restart(){assert.ok(!disposed);await stop();try{await boot();}catch(error){await dispose();throw error;}},
    async outboundCanary(){assert.ok(!disposed);await stop();try{await boot(canaryWorker);const response=await mf.dispatchFetch('http://localhost/');assert.equal(response.status,500);await response.arrayBuffer();}finally{await stop();await boot();}},dispose});
}
