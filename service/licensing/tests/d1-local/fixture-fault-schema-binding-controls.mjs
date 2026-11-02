// Independent additive PAT-2675 regression preparation. Parent owns native execution.
// Expected values come from actual native D1 results, never observer binding records.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {createFixtureFaultSchemaOwner} from './fixture-fault-schema.mjs';
import {fixtureFaultSchemaControlRuntime} from './fixture-fault-schema-control-runtime.mjs';
const catalogue=JSON.parse(readFileSync(new URL('./fixture-fault-schema-catalogue.json',import.meta.url),'utf8'));
const create='CREATE TRIGGER operator_test_required BEFORE INSERT ON support_commit BEGIN SELECT RAISE(IGNORE); END';
const drop='DROP TRIGGER "operator_test_required"';
const select='SELECT hex(?) value';
const inventory='SELECT type,name,tbl_name,rootpage,sql FROM sqlite_schema ORDER BY type,name LIMIT 100';
const variants={
 Uint8Array(){const value=new Uint8Array([1,2]);return {value,mutate(){value[0]=9;}};},
 ArrayBuffer(){const bytes=new Uint8Array([1,2]);return {value:bytes.buffer,mutate(){bytes[0]=9;}};},
 numericArray(){const value=[1,2];return {value,mutate(){value[0]=9;}};},
};
async function owned(fn){const runtime=await fixtureFaultSchemaControlRuntime();try{await fn(runtime);}finally{await runtime.dispose();}}
async function seed(runtime){
 await runtime.setup('CREATE TABLE support_commit (id TEXT PRIMARY KEY,kind TEXT)');
 await runtime.setup('CREATE TABLE binding_probe (side TEXT,value TEXT)');
}
function paired(raw,projected,make,sql=select){
 const a=make(),b=make();
 // Rebinding must retain native last-bind behaviour, independently of either input.
 const native=raw.prepare(sql).bind(new Uint8Array([7,8])).bind(a.value);
 const wrapped=projected.prepare(sql).bind(new Uint8Array([7,8])).bind(b.value);
 return {native,wrapped,mutate(){a.mutate();b.mutate();}};
}
async function hiddenFixture(runtime,projected,present){
 const raw=(await runtime.rawRows(inventory)).filter(row=>row.name==='operator_test_required');
 assert.equal(raw.length,present?1:0,'DDL must actually change native schema');
 if(present)assert.equal(raw[0].sql,create);
 assert.equal((await projected.prepare(inventory).all()).results.some(row=>row.name==='operator_test_required'),false);
}
for(const [name,make] of Object.entries(variants))test(name+' native bind bytes survive mutation and CREATE/DROP revisions',()=>owned(async runtime=>{
 assert.ok(catalogue.creates.some(entry=>entry.sql===create));
 assert.ok(catalogue.drops.some(entry=>entry.sql===drop));
 await seed(runtime);
 const raw=runtime.db,generation=createFixtureFaultSchemaOwner().beginGeneration(runtime.db),db=generation.projectedDB;
 const saved=paired(raw,db,make);
 const insertion=paired(raw,db,make,'INSERT INTO binding_probe (side,value) SELECT \'saved\',hex(?)');
 saved.mutate();insertion.mutate();
 const nativeBefore=await saved.native.first('value');
 assert.equal(nativeBefore,'0102','owned host/native bind must snapshot original bytes');
 assert.equal(await saved.wrapped.first('value'),nativeBefore,'empty registry preserves original bytes');
 await generation.executeFixtureDDL(create);
 await hiddenFixture(runtime,db,true);
 // Soft assertions collect every method discrepancy in this one native owner.
 const failures=[];
 async function check(label,fn){try{await fn();}catch(error){failures.push({label,message:String(error)});}}
 await check('CREATE first',async()=>assert.equal(await saved.wrapped.first('value'),await saved.native.first('value')));
 await check('CREATE all',async()=>{
  const expected=(await saved.native.all()).results;assert.deepEqual(expected,[{value:'0102'}]);
  assert.deepEqual((await saved.wrapped.all()).results,expected);
 });
 await check('CREATE raw',async()=>{
  const expected=await saved.native.raw({columnNames:true});assert.deepEqual(expected,[['value'],['0102']]);
  assert.deepEqual(await saved.wrapped.raw({columnNames:true}),expected);
 });
 await check('CREATE run',async()=>{
  const native=await insertion.native.run(),wrapped=await insertion.wrapped.run();
  assert.equal(native.meta.changes,1);assert.equal(wrapped.meta.changes,native.meta.changes);
  const actual=await runtime.rawRows('SELECT value FROM binding_probe ORDER BY rowid');
  assert.equal(actual[0].value,'0102');assert.equal(actual[1].value,actual[0].value);
 });
 // Prepare a new pair while a fixture is registered, then remove it. This tests
 // another revision from a bound statement whose original projection was nonempty.
 const throughDrop=paired(raw,db,make);throughDrop.mutate();
 assert.equal(await throughDrop.native.first('value'),'0102');
 await generation.executeFixtureDDL(drop);
 await hiddenFixture(runtime,db,false);
 await check('DROP retained batch',async()=>{
  const native=await raw.batch([saved.native,throughDrop.native]);
  assert.deepEqual(native.map(result=>result.results),[[{value:'0102'}],[{value:'0102'}]]);
  const wrapped=await db.batch([saved.wrapped,throughDrop.wrapped]);
  assert.deepEqual(wrapped.map(result=>result.results),native.map(result=>result.results));
 });
 assert.deepEqual(failures,[],name+' must preserve actual native binding results across revisions');
}));
function bindOutcome(db,value){
 try{db.prepare(select).bind(value);return {phase:'accepted'};}
 catch(error){return {phase:'bind',name:error.name,message:String(error.message)};}
}
test('invalid native bindings retain synchronous bind rejection before and after revisions',()=>owned(async runtime=>{
 await seed(runtime);const raw=runtime.db,generation=createFixtureFaultSchemaOwner().beginGeneration(runtime.db),db=generation.projectedDB;
 const invalid=[()=>undefined,()=>({}),()=>[256]];
 for(const phase of ['empty','CREATE','DROP']){
  if(phase==='CREATE')await generation.executeFixtureDDL(create);
  if(phase==='DROP')await generation.executeFixtureDDL(drop);
  for(const make of invalid){
   const expected=bindOutcome(raw,make());
   assert.equal(expected.phase,'bind','native invalid value must throw during bind');
   assert.deepEqual(bindOutcome(db,make()),expected,phase+' must preserve native invalid-bind timing/error');
  }
 }
}));
