// Future-only, parent-selected adapters over an accepted normal GREEN compiled copy.
// No product/runtime/HTTP option is introduced. Missing anchors are setup failures.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,realpathSync,lstatSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../../../..'),service=resolve(root,'service/licensing');
const require=createRequire(resolve(service,'package.json')),hash=x=>createHash('sha256').update(x).digest('hex');
const modes=['missingOrigin','bypassCSRF','unsafeText','optimisticRemoval'];
const additive=['src/web/account.ts','src/web/session.ts','web/account/index.html','web/account/account.js','web/account/account.css','tests/unit/account.test.ts','tests/d1-local/account-web-entry.ts','tests/d1-local/account-web-runtime.ts','tests/d1-local/account-web-runtime-controls.mjs','tests/d1-local/account-web-source-api.ts','tests/d1-local/account-web.test.ts','tests/browser/account-web.test.mjs','tests/browser/native-chrome-cdp.mjs','tests/browser/account-web-mutants.mjs'].map(p=>'service/licensing/'+p);
function hashes(){const tracked=execFileSync('git',['ls-files','-z'],{cwd:root,encoding:'utf8'}).split('\0').filter(Boolean);return Object.fromEntries([...new Set([...tracked,...additive])].sort().map(path=>[path,hash(readFileSync(resolve(root,path)))]));}
function closed(value,keys){assert.ok(value&&typeof value==='object'&&!Array.isArray(value),'MUTANT-SETUP object');assert.deepEqual(Reflect.ownKeys(value).sort(),keys.slice().sort(),'MUTANT-SETUP closed fields');}
export function installCompiledVariant(mode){
 assert.ok(modes.includes(mode),'MUTANT-SETUP fixed mode only');
 // Parent copies these two frozen evidence adapters to these fixed owned paths
 // only after normal product GREEN. No caller-selected path or source is read.
 const anchorPath=resolve(root,'.build/account-web-parent-mutant-anchors.json'),greenPath=resolve(root,'.build/account-web-parent-green.json');
 for(const file of [anchorPath,greenPath]){assert.equal(realpathSync(file),file);assert.ok(lstatSync(file).isFile());assert.equal(lstatSync(file).isSymbolicLink(),false);}
 const anchors=JSON.parse(readFileSync(anchorPath,'utf8')),green=JSON.parse(readFileSync(greenPath,'utf8'));
 closed(anchors,['marker','variants']);assert.equal(anchors.marker,'PAT-2649-parent-mutant-anchors');closed(anchors.variants,modes);
 closed(green,['marker','outcome','compiledSHA256','sourceAndCheckHashes','runtimeFixture']);assert.equal(green.marker,'PAT-2649-parent-normal-green');assert.equal(green.outcome,'passed');
 closed(green.runtimeFixture,['marker','allowedOrigin','now','entropySeed']);assert.equal(green.runtimeFixture.marker,'PAT-2649-account-runtime-synthetic');
 const before=hashes();assert.deepEqual(before,green.sourceAndCheckHashes,'MUTANT-SETUP current source/check tree differs from accepted normal GREEN');
 const adapter=anchors.variants[mode];closed(adapter,['candidateSHA256','search','replacement','searchSHA256','replacementSHA256']);
 assert.equal(adapter.candidateSHA256,green.compiledSHA256);assert.equal(typeof adapter.search,'string');assert.ok(adapter.search.length>0);assert.equal(typeof adapter.replacement,'string');assert.notEqual(adapter.search,adapter.replacement);assert.equal(hash(adapter.search),adapter.searchSHA256);assert.equal(hash(adapter.replacement),adapter.replacementSHA256);
 const module=require.cache[require.resolve('esbuild')]??(require('esbuild'),require.cache[require.resolve('esbuild')]),original=module.exports;
 let transformed,receipt,calls=0,registered=false;
 module.exports={...original,async build(options){const result=await original.build(options);
  const entries=options.entryPoints??[];if(entries.length===1&&resolve(entries[0])===resolve(service,'tests/d1-local/account-web-entry.ts')){
   assert.equal(options.absWorkingDir,service);assert.equal(options.write,false);assert.equal(result.outputFiles.length,1);calls++;assert.equal(calls,1,'MUTANT-SETUP exactly one web compilation');
   const normal=result.outputFiles[0].text;assert.equal(hash(normal),adapter.candidateSHA256,'MUTANT-SETUP candidate compiled hash');
   assert.equal(normal.split(adapter.search).length-1,1,'MUTANT-SETUP transform anchor must match exactly once');
   transformed=normal.replace(adapter.search,adapter.replacement);assert.notEqual(transformed,normal);receipt={mode,candidateSHA256:hash(normal),transformedSHA256:hash(transformed),searchSHA256:adapter.searchSHA256,replacementSHA256:adapter.replacementSHA256};
   return {...result,outputFiles:[{...result.outputFiles[0],contents:Buffer.from(transformed),text:transformed}]};
  }return result;
 }};
 return {fixture:Object.freeze({...green.runtimeFixture}),registerOwner(owner){assert.equal(registered,false);registered=true;assert.equal(calls,1,'MUTANT-SETUP real fixed web build intercepted');assert.equal(realpathSync(owner.run),owner.run);assert.equal(dirname(owner.run),resolve(root,'.build'));writeFileSync(resolve(owner.run,'account-web-compiled-mutant.mjs'),transformed,{flag:'wx'});writeFileSync(resolve(owner.run,'account-web-mutant-receipt.json'),JSON.stringify(receipt)+'\n',{flag:'wx'});},dispose(){module.exports=original;assert.equal(calls,1,'MUTANT-SETUP transform was actually exercised');assert.equal(registered,true);assert.deepEqual(hashes(),before,'mutant changed tracked source/check/fixture bytes');}};
}
