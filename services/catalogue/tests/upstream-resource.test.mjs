import test from 'node:test';
import assert from 'node:assert/strict';
import { boundedData } from '../discovery/upstream/contracts.mjs';
import { ingestSnapshot } from '../discovery/upstream/snapshot.mjs';
import { snapshot, bootstrapOptions, nextOptions, labelBytes, path, sha, complete } from './upstream-fixtures.mjs';

function longPathInput(length) {
  const input=snapshot(), prefix='fragments/labels/', name='a'.repeat(length-prefix.length-3), changedPath=prefix+name+'.sh';
  const bytes=Buffer.from(labelBytes().toString().replace('literal-valid)',name+')'));
  Object.assign(input.manifest.inventory.find(x=>x.path===path),{path:changedPath,sha256:sha(bytes),byteLength:bytes.length});
  Object.assign(input.payloads.find(x=>x.path===path),{path:changedPath,bytes});
  return input;
}
test('fixture path metadata is admitted at 1024 bytes and refused at 1025 before retention',()=>{
  const valid=complete(ingestSnapshot(longPathInput(1024),bootstrapOptions()));
  assert.equal(valid.labels.find(x=>x.path.length===1024).status,'extracted');
  const result=ingestSnapshot(longPathInput(1025),bootstrapOptions());
  assert.equal(result.status,'refused'); assert.equal(result.reason,'path-limit'); assert.equal(result.checkpoint,null);
});
test('128 MiB snapshot/checkpoint preflight rejects giant strings before canonical hashing or copied output',()=>{
  const oversized='x'.repeat(128*1024*1024+1), input=snapshot(); input.manifest.attribution=oversized;
  const rejected=ingestSnapshot(input,bootstrapOptions());
  assert.equal(rejected.status,'refused'); assert.equal(rejected.reason,'state-limit'); assert.equal(rejected.checkpoint,null);
  const previous=complete(ingestSnapshot(snapshot(),bootstrapOptions()));
  previous.labels[0].bytesBase64=oversized;
  const prior=ingestSnapshot(snapshot(),nextOptions(previous));
  assert.equal(prior.status,'refused'); assert.equal(prior.reason,'state-limit'); assert.equal(prior.checkpoint,previous);
});
test('snapshot metadata preflight stops deeply nested or cyclic shapes without invoking getters',()=>{
  const deep=snapshot(); let cursor=deep.manifest;
  for(let i=0;i<40;i++){cursor.extra={};cursor=cursor.extra;}
  const result=ingestSnapshot(deep,bootstrapOptions()); assert.equal(result.status,'refused'); assert.equal(result.reason,'state-limit');
  const cyclic=snapshot();cyclic.manifest.extra=cyclic.manifest;
  assert.equal(ingestSnapshot(cyclic,bootstrapOptions()).status,'refused');
  const accessor=snapshot(); let invoked=false;
  Object.defineProperty(accessor.manifest,'extra',{enumerable:true,get(){invoked=true;throw new Error('must not run');}});
  assert.equal(ingestSnapshot(accessor,bootstrapOptions()).status,'refused'); assert.equal(invoked,false);
});
test('escaped JSON byte preflight counts control expansion without allocating escaped strings',()=>{
  const heavy='\0'.repeat(512);
  assert.ok(Buffer.byteLength(heavy)<1024);
  assert.throws(()=>boundedData(heavy,1024),/state-limit/);
  const exact='\n"\\';
  assert.equal(boundedData(exact,8),8);
  assert.throws(()=>boundedData(exact,7),/state-limit/);
});
