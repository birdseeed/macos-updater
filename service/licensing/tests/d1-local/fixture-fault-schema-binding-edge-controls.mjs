// Independent additive native controls. Parent owns execution and repair-round accounting.
// Values are checked against actual raw D1 SQL results, never observer records.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {createFixtureFaultSchemaOwner,FixtureFaultSchemaInfrastructureError} from './fixture-fault-schema.mjs';
import {fixtureFaultSchemaControlRuntime} from './fixture-fault-schema-control-runtime.mjs';
const catalogue=JSON.parse(readFileSync(new URL('./fixture-fault-schema-catalogue.json',import.meta.url),'utf8'));
const create='CREATE TRIGGER operator_test_required BEFORE INSERT ON support_commit BEGIN SELECT RAISE(IGNORE); END';
const drop='DROP TRIGGER "operator_test_required"';
const sql='SELECT typeof(?) AS kind, hex(?) AS value';
const inventory='SELECT type,name,tbl_name,rootpage,sql FROM sqlite_schema ORDER BY type,name LIMIT 100';
async function owned(fn){
 assert.ok(catalogue.creates.some(entry=>entry.sql===create));
 assert.ok(catalogue.drops.some(entry=>entry.sql===drop));
 const runtime=await fixtureFaultSchemaControlRuntime();
 try{
  await runtime.setup('CREATE TABLE support_commit (id TEXT PRIMARY KEY,kind TEXT)');
  const raw=runtime.db,generation=createFixtureFaultSchemaOwner().beginGeneration(raw);
  await fn({runtime,raw,generation,db:generation.projectedDB});
 }finally{await runtime.dispose();}
}
async function revision(context,present){
 await context.generation.executeFixtureDDL(present?create:drop);
 const actual=(await context.runtime.rawRows(inventory)).filter(row=>row.name==='operator_test_required');
 assert.equal(actual.length,present?1:0,'fixture revision changes actual native schema');
 if(present)assert.equal(actual[0].sql,create);
 assert.equal((await context.db.prepare(inventory).all()).results.some(row=>row.name==='operator_test_required'),false);
}
function bind(db,value){return db.prepare(sql).bind(value,value);}
const ordinary={
 Buffer(){const value=Buffer.from([1,2]);return {value,mutate(){value[0]=9;},expected:{kind:'blob',value:'0102'}};},
 offsetUint8Array(){const bytes=new Uint8Array([99,1,2,88]),value=bytes.subarray(1,3);return {value,mutate(){bytes.fill(9);},expected:{kind:'blob',value:'0102'}};},
 Uint16Array(){const value=new Uint16Array([1,2]);return {value,mutate(){value.fill(9);},expected:{kind:'blob',value:'0102'}};},
 DataView(){const bytes=new Uint8Array([99,1,2,88]),value=new DataView(bytes.buffer,1,2);return {value,mutate(){bytes.fill(9);},expected:{kind:'blob',value:''}};},
};
for(const [name,make] of Object.entries(ordinary))test(name+' keeps native mapping through CREATE and DROP replay',()=>owned(async context=>{
 const a=make(),b=make(),native=bind(context.raw,a.value),wrapped=bind(context.db,b.value);
 a.mutate();b.mutate();
 for(const phase of ['initial','CREATE','DROP']){
  if(phase!=='initial')await revision(context,phase==='CREATE');
  const expected=await native.first();assert.deepEqual(expected,a.expected,phase+' raw native mapping');
  assert.deepEqual(await wrapped.first(),expected,phase+' wrapped bound result');
  assert.deepEqual((await wrapped.all()).results,(await native.all()).results,phase+' all');
  assert.deepEqual(await wrapped.raw({columnNames:true}),await native.raw({columnNames:true}),phase+' raw');
 }
}));
test('booleans null string and numbers keep actual native binding compatibility across revisions',()=>owned(async context=>{
 const values=[true,false,null,'binding-edge',0,42,-7,1.25];
 const saved=values.map(value=>({native:bind(context.raw,value),wrapped:bind(context.db,value)}));
 const initial=await Promise.all(saved.map(pair=>pair.native.first()));
 for(const phase of ['initial','CREATE','DROP']){
  if(phase!=='initial')await revision(context,phase==='CREATE');
  for(const [index,pair] of saved.entries()){
   const expected=await pair.native.first();assert.deepEqual(expected,initial[index]);
   assert.deepEqual(await pair.wrapped.first(),expected,phase+' '+String(values[index]));
  }
 }
}));
function detached(make){const buffer=new ArrayBuffer(4),value=make(buffer);structuredClone(buffer,{transfer:[buffer]});return value;}
function outcome(db,make){
 try{return {phase:'accepted',statement:bind(db,make())};}
 catch(error){return {phase:'bind',name:error.name,message:String(error.message)};}
}
test('detached buffers and views and SAB-backed views retain initial native bind rejection timing and errors',()=>owned(async context=>{
 const invalid={
  detachedArrayBuffer:()=>detached(buffer=>buffer),
  detachedUint8Array:()=>detached(buffer=>new Uint8Array(buffer)),
  detachedDataView:()=>detached(buffer=>new DataView(buffer)),
  sharedUint8Array:()=>new Uint8Array(new SharedArrayBuffer(4)),
 };
 for(const [name,make] of Object.entries(invalid)){
  const expected=outcome(context.raw,make);
  assert.equal(expected.phase,'bind',name+' actual native must synchronously reject');
  assert.deepEqual(outcome(context.db,make),expected,name+' rejection name/message/phase');
 }
}));
const exotic={
 numericAccessor(){const value=[1,2];Object.defineProperty(value,'0',{get(){return 1;},enumerable:true,configurable:true});return value;},
 customViewMetadata(){const value=new Uint8Array([1,2]);Object.defineProperty(value,'constructor',{value:Uint8Array});return value;},
};
test('ordinary numeric accessor and custom view metadata preserve initial parity and explicitly refuse accepted replay',()=>owned(async context=>{
 const accepted=[];
 for(const [name,make] of Object.entries(exotic)){
  const expected=outcome(context.raw,make),actual=outcome(context.db,make);
  assert.equal(actual.phase,expected.phase,name+' initial native acceptance timing');
  if(expected.phase==='bind'){assert.deepEqual(actual,expected,name+' initial rejection parity');continue;}
  const nativeResult=await expected.statement.first();
  assert.deepEqual(await actual.statement.first(),nativeResult,name+' initial native SQL result');
  accepted.push({name,native:expected.statement,wrapped:actual.statement,nativeResult});
 }
 // Refusal applies iff that original native bind succeeded. No proxy or
 // arbitrary global-intrinsic authentication claim is part of this control.
 for(const present of [true,false]){
  await revision(context,present);
  for(const pair of accepted){
   assert.deepEqual(await pair.native.first(),pair.nativeResult,pair.name+' native statement remains usable');
   const refuses=error=>error instanceof FixtureFaultSchemaInfrastructureError&&error.name==='FixtureFaultSchemaInfrastructureError'&&error.message==='Exotic native binding cannot be replayed after fixture revision';
   await assert.rejects(()=>pair.wrapped.first(),refuses,pair.name+' revision replay');
   assert.throws(()=>pair.wrapped.bind(1,1),refuses,pair.name+' chained bind on stale statement');
  }
 }
}));
