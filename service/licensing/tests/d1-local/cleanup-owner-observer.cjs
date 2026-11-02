// Independent account-suite process observer. Never records arguments, SQL or environment.
'use strict';
const cp = require('node:child_process');
const {appendFileSync} = require('node:fs');
const {basename} = require('node:path');
const {syncBuiltinESMExports} = require('node:module');
const log = process.env.PAT_ACCOUNT_OWNER_LOG;
if (!log) throw Error('ACCOUNT-OWNER observer requires a private event log');
let events = 0;
function event(kind, active, action) {
 if (++events > 256) throw Error('ACCOUNT-OWNER event bound exceeded');
 appendFileSync(log, JSON.stringify({kind, active, action})+'\n');
}
function alive(pid) { try {process.kill(pid, 0); return true;} catch(e) {if(e.code==='ESRCH')return false;throw e;} }
const inherited = Number(process.env.PAT_ACCOUNT_OWNER_ACTIVE_PID || 0);
if (process.env.PAT_ACCOUNT_OWNER_ENTRY) {
 const kind=process.env.PAT_ACCOUNT_OWNER_ENTRY;
 event(kind, inherited && alive(inherited)?2:1, 'launched');
 if (inherited && alive(inherited)) {
  process.stderr.write('ACCOUNT-OWNER-OVERLAP: actual D1 owner launcher overlaps a live owner; infrastructure refusal (not historical SQLITE_BUSY reproduction)\n');
  process.exit(86);
 }
}
const owners=new Map();
function liveOwners() {return [...owners.keys()].filter(pid=>alive(pid));}
function classify(command,args) {
 if (basename(String(command))==='workerd') return 'workerd';
 if (Array.isArray(args) && args[0]?.endsWith('/wrangler/wrangler-dist/cli.js')) {
  if(args[1]==='dev' && args.includes('--local'))return 'wrangler-dev';
  if(args[1]==='d1' && args[2]==='execute' && args.includes('--local'))return 'wrangler-d1';
 }
 return null;
}
function instrument(options,kind,active) {
 const env={...(options?.env??process.env)};
 env.NODE_OPTIONS=`--require=${JSON.stringify(__filename)}`;
 env.PAT_ACCOUNT_OWNER_LOG=log;
 env.PAT_ACCOUNT_OWNER_ENTRY=kind;
 if(active)env.PAT_ACCOUNT_OWNER_ACTIVE_PID=String(active);else delete env.PAT_ACCOUNT_OWNER_ACTIVE_PID;
 return {...options,env};
}
const originalSpawn=cp.spawn, originalSync=cp.spawnSync;
cp.spawn=function(command,args,options) {
 const kind=classify(command,args);
 if(!kind)return originalSpawn.call(this,command,args,options);
 // Wrangler owns its nested native workerd. Only direct workerd creates another owner here.
 if(kind==='workerd' && process.env.PAT_ACCOUNT_OWNER_ENTRY) {
  const child=originalSpawn.call(this,command,args,options);event(kind,1,'nested-launch');return child;
 }
 const active=liveOwners();
 const child=originalSpawn.call(this,command,args,kind==='workerd'?options:instrument(options,kind,active[0]));
 if(child.pid){
  owners.set(child.pid,kind);event(kind,active.length+1,'spawned');
  child.once('exit',()=>{owners.delete(child.pid);event(kind,liveOwners().length,'exited');});
 }
 if(active.length && kind==='workerd') {
  child.kill('SIGKILL');event(kind,active.length+1,'overlap');
  throw Error('ACCOUNT-OWNER-OVERLAP: actual workerd launch overlaps a live owner');
 }
 return child;
};
cp.spawnSync=function(command,args,options) {
 const kind=classify(command,args);
 if(!kind)return originalSync.call(this,command,args,options);
 const active=liveOwners();
 if(kind==='workerd')throw Error('ACCOUNT-OWNER: unsupported synchronous workerd launch');
 const result=originalSync.call(this,command,args,instrument(options,kind,active[0]));
 if(!result.pid)throw Error('ACCOUNT-OWNER: owner child did not launch');
 event(kind,active.length+1,result.status===86?'overlap':'completed');
 return result;
};
syncBuiltinESMExports();
