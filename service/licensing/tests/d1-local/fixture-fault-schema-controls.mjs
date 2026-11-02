// PAT-2675 independent frozen preparation. Native execution requires parent release.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {createFixtureFaultSchemaOwner,FixtureFaultSchemaInfrastructureError} from './fixture-fault-schema.mjs';
import {fixtureFaultSchemaControlRuntime} from './fixture-fault-schema-control-runtime.mjs';
const catalogue=JSON.parse(readFileSync(new URL('./fixture-fault-schema-catalogue.json',import.meta.url),'utf8'));
// Exact complete finite native CONTROL query vocabulary, not source compatibility.
const Q=Object.freeze({
 p3:"SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE substr(name,1,8)='support_' OR substr(tbl_name,1,8)='support_' OR substr(name,1,9)='operator_' OR substr(tbl_name,1,9)='operator_' ORDER BY type,name LIMIT 34",
 inventory:'SELECT type,name,tbl_name,rootpage,sql FROM sqlite_schema ORDER BY type,name LIMIT 100',
 count:'SELECT count(*) n FROM sqlite_schema WHERE type=? AND name=?',
 exists:'SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type=? AND name=?) present',
 immediate:'SELECT CASE WHEN changes()=1 THEN 1 ELSE json(\'\') END',
 final:"SELECT CASE WHEN (SELECT count(*) FROM sqlite_schema WHERE type='trigger')=? AND NOT EXISTS(SELECT 1 FROM sqlite_master WHERE type='trigger' AND name=?) AND (SELECT count(*) FROM sentinel WHERE id=?)=1 THEN 1 ELSE json('') END",
 insertSelect:"INSERT INTO fault_probe (id,value) SELECT ?,? WHERE NOT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='trigger' AND name=?)",
});
const supportIgnore='CREATE TRIGGER operator_test_required BEFORE INSERT ON support_commit BEGIN SELECT RAISE(IGNORE); END';
const supportAbort="CREATE TRIGGER operator_test_required BEFORE INSERT ON support_commit BEGIN SELECT RAISE(ABORT,'operator fault'); END";
const b4='CREATE TRIGGER notices_test_fault BEFORE INSERT ON billing_notice_receipt BEGIN SELECT RAISE(IGNORE); END';
const rawInventory='SELECT type,name,tbl_name,rootpage,sql FROM sqlite_schema ORDER BY type,name LIMIT 100';
// Independent expansion transcribed from original frozen action loops; never catalogue-driven.
function expectedCatalogue(){
 const all=new Set(),names=new Set();
 function trigger(name,op,table,message,when){for(const mode of ['IGNORE','ABORT']){names.add(name);all.add(`CREATE TRIGGER ${name} BEFORE ${op} ON ${table}${when?' WHEN '+when:''} BEGIN SELECT RAISE(${mode}${mode==='ABORT'?",'"+message+"'":''}); END`);}}
 const common=[['account_guard','UPDATE'],['account_nonce_history','INSERT'],['account_audit','INSERT'],['support_request','UPDATE'],['support_human_use','INSERT'],['support_audit','INSERT'],['support_commit','INSERT']];
 const stages=[['accounts/UPDATE','activation_slots/DELETE','activations/UPDATE','lease_heads/UPDATE','operator_confirmations/INSERT'],['challenges/UPDATE','request_limits/INSERT','support_rate/INSERT','support_delivery/INSERT'],['billing_reconcile/UPDATE','billing_lifecycle_commit/INSERT'],['billing_renewal_stop/INSERT','billing_stop_cause/INSERT','billing_lifecycle_commit/INSERT'],['support_refund/INSERT','support_stop_obligation/INSERT','billing_renewal_stop/INSERT','billing_lifecycle_commit/INSERT']];
 for(const stage of stages)for(const [table,op] of [...common,...stage.map(x=>x.split('/'))])trigger('operator_test_required',op,table,'operator fault');
 for(const table of ['support_rate','support_lookup','support_audit','support_commit'])trigger('operator_test_lookup','INSERT',table,'operator lookup fault');
 trigger('operator_test_prepare','INSERT','support_commit','operator prepare fault');
 for(const action of ['resendSignInCode','initiateRefund'])for(const stage of ['claim','result'])for(const table of ['support_audit','support_commit',action==='resendSignInCode'?'support_delivery':'support_refund']){
  const when=table==='support_audit'?`NEW.event='${stage==='claim'?'providerDispatch':'providerResult'}'`:table==='support_commit'?`NEW.kind='${stage==='claim'?'dispatch':'result'}'`:`NEW.state='${stage==='claim'?'dispatching':'accepted'}'`;
  trigger('operator_test_dispatch',table==='support_audit'||table==='support_commit'?'INSERT':'UPDATE',table,'operator dispatch fault',when);
 }
 trigger('operator_test_activation','UPDATE','challenges','operator challenge result fault','NEW.superseded_at IS NULL');
 for(const [table,op] of [['account_guard','UPDATE'],['account_nonce_history','INSERT'],['account_audit','INSERT'],['billing_lifecycle_commit','INSERT'],['accounts','UPDATE']])trigger('operator_test_source_dispatch',op,table,'source dispatch fault');
 trigger('operator_test_obligation_result','UPDATE','support_stop_obligation','obligation result fault',"NEW.state='closed'");
 trigger('operator_test_capacity_result','INSERT','support_commit','capacity result lost',"NEW.kind='result'");
 const claim=[['account_guard','UPDATE'],['accounts','UPDATE'],['account_nonce_history','INSERT'],['account_audit','INSERT'],['billing_reminder','INSERT'],['billing_notice_dispatch','INSERT'],['billing_notice_commit','INSERT']];
 const source=[['billing_reconcile','INSERT'],['billing_snapshot','INSERT'],['billing_entity_version','INSERT'],['billing_subscription','INSERT'],['billing_notice_head','INSERT'],['billing_lifecycle_commit','INSERT']];
 const result=[['billing_notice_receipt','INSERT'],['billing_notice_contact','INSERT']];
 for(const [table,event] of [...claim,...source,...result])for(const actual of table.startsWith('billing_notice_')||table==='billing_reminder'?['INSERT','UPDATE']:[event])trigger('notices_test_fault_'+actual.toLowerCase(),actual,table,'synthetic required-write failure');
 all.add(b4);names.add('notices_test_fault');
 return {creates:[...all].sort(),drops:[...[...names].map(n=>`DROP TRIGGER "${n}"`),'DROP TRIGGER operator_test_capacity_result','DROP TRIGGER notices_test_fault'].sort()};
}
test('closed 129 CREATE and 13 DROP bytes independently match original fixture expansion',()=>{
 const expected=expectedCatalogue();assert.equal(expected.creates.length,129);assert.equal(expected.drops.length,13);
 assert.deepEqual(catalogue.creates.map(x=>x.sql).sort(),expected.creates);assert.deepEqual(catalogue.drops.map(x=>x.sql).sort(),expected.drops);
 assert.equal(new Set(catalogue.creates.map(x=>x.id)).size,129);assert.equal(new Set(catalogue.creates.map(x=>x.name)).size,11);
});
async function owned(fn){const r=await fixtureFaultSchemaControlRuntime();try{await fn(r);}finally{await r.dispose();}}
async function seed(r){for(const sql of ['CREATE TABLE sentinel (id TEXT PRIMARY KEY,value INTEGER)','CREATE TABLE fault_probe (id TEXT PRIMARY KEY,value TEXT)','CREATE TABLE support_commit (id TEXT PRIMARY KEY,kind TEXT)','CREATE TABLE billing_notice_receipt (id TEXT PRIMARY KEY,operation TEXT)','CREATE TABLE support_delivery (id TEXT PRIMARY KEY,state TEXT)'])await r.setup(sql);}
function sourceObserver(db){const events=[],map=new WeakMap();function wrap(p,sql,bindings=[]){const s={bind(...values){return wrap(p.bind(...values),sql,values);}};for(const method of ['all','first','raw','run'])s[method]=async(...args)=>{events.push({method,sql,bindings,args});try{return await p[method](...args);}catch(error){events.push({method:'error',sql,message:String(error)});throw error;}};map.set(s,{p,sql,bindings});return s;}return {events,db:{prepare(sql){return wrap(db.prepare(sql),sql);},async batch(items){events.push({method:'batch',entries:items.map((s,index)=>({...map.get(s),p:undefined,index}))});return db.batch(items.map(s=>map.get(s)?.p??s));}}};}
async function projected(r){const owner=createFixtureFaultSchemaOwner();const generation=owner.beginGeneration(r.db);const observed=sourceObserver(generation.projectedDB);return {owner,generation,...observed};}
const rows=async(db,sql,...args)=>(await db.prepare(sql).bind(...args).all()).results;
const infrastructure=e=>e instanceof FixtureFaultSchemaInfrastructureError;
async function refuses(fn){await assert.rejects(async()=>fn(),infrastructure);}
async function tuple(r,name){const all=await r.rawRows(rawInventory);return all.find(x=>x.name===name);}
function literal(value){return value===null?'NULL':typeof value==='number'?String(value):"'"+value.replaceAll("'","''")+"'";}
// Independent native expected SQL, using only observed real tuples, not helper internals.
function expectedSQL(sql,tuples){const predicate=tuples.map(t=>'('+['type','name','tbl_name','rootpage','sql'].map(k=>k+' IS '+literal(t[k])).join(' AND ')+')').join(' OR ');return sql.replaceAll(/\bsqlite_(?:schema|master)\b/g,'(SELECT type,name,tbl_name,rootpage,sql FROM main.sqlite_schema WHERE NOT ('+predicate+'))');}
function attemptsSince(r,index){return r.events.slice(index).filter(x=>x.phase==='native');}

test('independent native owner boot, rollback, persistence, environment, outbound denial, disposal',()=>owned(async r=>{
 await seed(r);await r.setup("INSERT INTO sentinel VALUES ('durable',73)");
 const db=r.db;await assert.rejects(db.batch([db.prepare("INSERT INTO sentinel VALUES ('rolled',74)"),db.prepare("INSERT INTO sentinel VALUES ('durable',75)")]));
 assert.deepEqual(await r.rawRows('SELECT * FROM sentinel'),[{id:'durable',value:73}]);const run=r.run;await r.restart();assert.equal(r.run,run);assert.deepEqual(await r.rawRows('SELECT * FROM sentinel'),[{id:'durable',value:73}]);
 await r.outboundCanary();assert.equal(r.outboundDenied,1);assert.deepEqual(await r.rawRows('SELECT * FROM sentinel'),[{id:'durable',value:73}]);
 assert.ok(r.launches>=4);for(const e of r.events.filter(e=>e.phase==='launch'))assert.deepEqual(e.environmentKeys,['CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV','HOME','PATH','TMPDIR','WRANGLER_SEND_METRICS']);
 await r.dispose();assert.throws(()=>r.db);
}));
test('empty registry preserves all native methods, SQL, bind types/order and single native batch',()=>owned(async r=>{
 await seed(r);const {db}=await projected(r);const sql='SELECT ? text,? num,? nil,? blob';const binds=['sqlite_schema',7,null,new Uint8Array([1,2])];
 for(const [method,args] of [['all',[]],['first',[]],['first',['text']],['raw',[]],['raw',[{columnNames:true}]],['run',[]]]){
  const index=r.events.length;
  const actual=await db.prepare(sql).bind(...binds)[method](...args);assert.strictEqual(actual,r.events.slice(index).find(e=>e.phase==='native-result').result);const emitted=attemptsSince(r,index);assert.equal(emitted.length,1);assert.equal(emitted[0].sql,sql);assert.deepEqual(emitted[0].bindings,binds);assert.deepEqual(emitted[0].args,args);
 }
 const index=r.events.length;const result=await db.batch([db.prepare('INSERT INTO fault_probe VALUES (?,?)').bind('a','x'),db.prepare('SELECT value FROM fault_probe WHERE id=?').bind('a')]);assert.equal(result.length,2);assert.equal(result[1].results[0].value,'x');const emitted=attemptsSince(r,index);assert.deepEqual(emitted.map(e=>e.bindings),[['a','x'],['a']]);assert.deepEqual(emitted.map(e=>e.index),[0,1]);assert.equal(r.events.slice(index).filter(x=>x.phase==='native-batch').length,1);
}));
test('verified P3/B4 real tuples remain raw and disappear before native SELECT COUNT EXISTS wrappers',()=>owned(async r=>{
 await seed(r);const {db,generation}=await projected(r);
 for(const [ddl,name] of [[supportIgnore,'operator_test_required'],[b4,'notices_test_fault']]){
  await generation.executeFixtureDDL(ddl);const installed=await tuple(r,name);assert.equal(installed.sql,ddl);assert.equal(installed.type,'trigger');assert.ok(Number.isSafeInteger(installed.rootpage));
 }
 const tuples=[await tuple(r,'operator_test_required'),await tuple(r,'notices_test_fault')];const raw=await r.rawRows(rawInventory);
 for(const [sql,args,expected] of [[Q.inventory,[],raw.filter(x=>!tuples.some(t=>t.name===x.name))],[Q.count,['trigger','operator_test_required'],[{n:0}]],[Q.exists,['trigger','notices_test_fault'],[{present:0}]]]){
  const index=r.events.length;assert.deepEqual(await rows(db,sql,...args),expected);const emitted=attemptsSince(r,index);assert.equal(emitted.length,1);assert.equal(emitted[0].sql,expectedSQL(sql,tuples));assert.deepEqual(emitted[0].bindings,args);
 }
 await db.prepare('INSERT INTO sentinel VALUES (?,?)').bind('assert',1).run();assert.equal((await rows(db,Q.final,0,'operator_test_required','assert')).length,1);
 await db.prepare(Q.insertSelect).bind('probe','original','operator_test_required').run();assert.deepEqual(await r.rawRows('SELECT * FROM fault_probe'),[{id:'probe',value:'original'}]);
 assert.deepEqual(await r.rawRows(rawInventory),raw);
}));
for(const [mode,ddl] of [['IGNORE',supportIgnore],['ABORT',supportAbort]])test('real '+mode+' target attempt and immediate required-changes native rollback',()=>owned(async r=>{
 await seed(r);const {db,generation,events}=await projected(r);await generation.executeFixtureDDL(ddl);const rawBefore=await r.rawRows(rawInventory);
 const target="INSERT INTO support_commit VALUES ('target','result')";
 if(mode==='IGNORE'){const index=r.events.length;const zero=await db.prepare(target).run();assert.equal(zero.meta.changes,0);assert.equal(attemptsSince(r,index)[0].sql,target);assert.deepEqual(await r.rawRows('SELECT * FROM support_commit'),[]);}
 const statements=["INSERT INTO sentinel VALUES ('rolled',1)",target,Q.immediate,Q.final];const index=r.events.length;
 await assert.rejects(db.batch(statements.map((s,i)=>i===3?db.prepare(s).bind(0,'operator_test_required','rolled'):db.prepare(s))),e=>!infrastructure(e)&&/operator fault|malformed JSON|JSON/i.test(String(e)));
 const emitted=attemptsSince(r,index);assert.equal(emitted.length,4);assert.deepEqual(emitted.map(e=>e.index),[0,1,2,3]);assert.equal(emitted[1].sql,target);assert.equal(emitted[2].sql,Q.immediate);assert.equal(r.events.slice(index).filter(e=>e.phase==='native-batch').length,1);assert.ok(events.some(e=>e.method==='batch'));
 assert.deepEqual(await r.rawRows('SELECT * FROM sentinel'),[]);assert.deepEqual(await r.rawRows('SELECT * FROM support_commit'),[]);assert.deepEqual(await r.rawRows(rawInventory),rawBefore);
}));
for(const kind of ['dispatch','result'])test('exact matching/nonmatching WHEN '+kind+' retains durable prior claim',()=>owned(async r=>{
 await seed(r);await r.setup("INSERT INTO sentinel VALUES ('prior-claim',1)");const {db,generation}=await projected(r);const ddl=`CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_commit WHEN NEW.kind='${kind}' BEGIN SELECT RAISE(IGNORE); END`;await generation.executeFixtureDDL(ddl);
 const other=kind==='result'?'dispatch':'result';assert.equal((await db.prepare('INSERT INTO support_commit VALUES (?,?)').bind('nonmatch',other).run()).meta.changes,1);
 const index=r.events.length;assert.equal((await db.prepare('INSERT INTO support_commit VALUES (?,?)').bind('matching',kind).run()).meta.changes,0);assert.equal(attemptsSince(r,index).length,1);
 await assert.rejects(db.batch([db.prepare("INSERT INTO sentinel VALUES ('result-batch',2)"),db.prepare('INSERT INTO support_commit VALUES (?,?)').bind('matching',kind),db.prepare(Q.immediate)]),e=>!infrastructure(e));assert.deepEqual(await r.rawRows('SELECT * FROM sentinel'),[{id:'prior-claim',value:1}]);assert.deepEqual(await r.rawRows('SELECT * FROM support_commit'),[{id:'nonmatch',kind:other}]);assert.equal((await tuple(r,'operator_test_dispatch')).sql,ddl);
}));
for(const variant of ['unregisteredExact','changedBody','changedWhen','changedTable','prefixOnly'])test('unregistered unknown trigger visible '+variant,()=>owned(async r=>{
 await seed(r);
 const unknown={unregisteredExact:b4,changedBody:"CREATE TRIGGER notices_test_fault BEFORE INSERT ON billing_notice_receipt BEGIN SELECT RAISE(ABORT,'different'); END",changedWhen:"CREATE TRIGGER notices_test_fault BEFORE INSERT ON billing_notice_receipt WHEN NEW.operation='other' BEGIN SELECT RAISE(IGNORE); END",changedTable:'CREATE TRIGGER notices_test_fault BEFORE INSERT ON fault_probe BEGIN SELECT RAISE(IGNORE); END',prefixOnly:'CREATE TRIGGER operator_test_unknown BEFORE INSERT ON fault_probe BEGIN SELECT RAISE(IGNORE); END'}[variant];
 await r.setup(unknown);const raw=await r.rawRows(rawInventory);const unknownTuple=raw.find(t=>t.sql===unknown);assert.ok(unknownTuple);const {db,generation}=await projected(r);await generation.executeFixtureDDL(supportIgnore);
 assert.equal((await rows(db,Q.exists,'trigger',unknownTuple.name))[0].present,1);assert.equal((await rows(db,Q.count,'trigger',unknownTuple.name))[0].n,1);assert.ok((await rows(db,Q.inventory)).some(t=>t.sql===unknown));
 const known=new Set(raw.filter(t=>t.type!=='trigger').map(t=>t.name));const strictRecognition=all=>all.every(t=>known.has(t.name));assert.equal(strictRecognition(await rows(db,Q.inventory)),false);
}));
test('native LIMIT34 displacement and unknown support/operator table view index visibility',()=>owned(async r=>{
 await seed(r);for(let i=0;i<28;i++)await r.setup(`CREATE TABLE support_unknown_${String(i).padStart(2,'0')} (id INTEGER)`);
 await r.setup('CREATE VIEW operator_unknown_view AS SELECT id FROM support_unknown_00');await r.setup('CREATE INDEX operator_unknown_index ON support_unknown_00(id)');
 const before=await r.rawRows(Q.p3);assert.equal(before.length,34);const {db,generation}=await projected(r);await generation.executeFixtureDDL(supportIgnore);
 const rawAfter=await r.rawRows(Q.p3);assert.equal(rawAfter.length,34);assert.ok(rawAfter.some(x=>x.name==='operator_test_required'));assert.notDeepEqual(rawAfter,before);
 const projectedRows=await rows(db,Q.p3);assert.deepEqual(projectedRows,before);assert.equal(projectedRows.length,34);for(const name of ['operator_unknown_view','operator_unknown_index'])assert.ok(projectedRows.some(x=>x.name===name));
 for(const type of ['table','view','index'])assert.equal((await rows(db,Q.exists,type,type==='table'?'support_unknown_27':type==='view'?'operator_unknown_view':'operator_unknown_index'))[0].present,1);
}));
test('DROP success/failure removes mask and forbids extra bytes/bindings/duplicate registration',()=>owned(async r=>{
 await seed(r);const {db,generation}=await projected(r);await generation.executeFixtureDDL(supportIgnore);await refuses(()=>generation.executeFixtureDDL(supportIgnore));
 for(const ddl of [supportIgnore+';',supportIgnore.replace('CREATE TRIGGER','CREATE TRIGGER IF NOT EXISTS'),'DROP TRIGGER operator_test_required','DROP TRIGGER "operator_test_required";'])await refuses(()=>generation.executeFixtureDDL(ddl));
 await refuses(()=>generation.executeFixtureDDL('DROP TRIGGER "operator_test_required"','extra-binding'));
 await generation.executeFixtureDDL('DROP TRIGGER "operator_test_required"');assert.equal(await tuple(r,'operator_test_required'),undefined);assert.equal((await rows(db,Q.count,'trigger','operator_test_required'))[0].n,0);
 await assert.rejects(generation.executeFixtureDDL('DROP TRIGGER "operator_test_required"'),e=>!infrastructure(e));assert.deepEqual(await rows(db,Q.inventory),await r.rawRows(rawInventory));
}));
test('invalidated raw same-name recreation is visible and stale wrappers cannot dispatch',()=>owned(async r=>{
 await seed(r);const {owner,generation,db}=await projected(r);await generation.executeFixtureDDL(supportIgnore);const stale=db.prepare(Q.inventory);generation.invalidate();
 await r.setup('DROP TRIGGER operator_test_required');await r.setup(supportIgnore);const next=owner.beginGeneration(r.db);
 await refuses(()=>stale.all());assert.deepEqual(await rows(next.projectedDB,Q.inventory),await r.rawRows(rawInventory));
}));
test('methods, foreign statement batches, mixed owners and overlapping generations refuse before dispatch',()=>owned(async r=>{
 await seed(r);const {owner,generation,db}=await projected(r);const other=createFixtureFaultSchemaOwner().beginGeneration(r.db);const own=db.prepare('SELECT ?').bind(1),foreign=other.projectedDB.prepare('SELECT ?').bind(2);
 assert.throws(()=>owner.beginGeneration(r.db),infrastructure);const index=r.events.length;
 await refuses(()=>db.batch([own,foreign]));await refuses(()=>db.batch([r.db.prepare('SELECT 1')]));assert.equal(attemptsSince(r,index).length,0);
 generation.invalidate();for(const method of ['all','first','raw','run'])await refuses(()=>own[method]());assert.throws(()=>own.bind(2),infrastructure);await refuses(()=>db.batch([own]));assert.throws(()=>db.prepare('SELECT 1'),infrastructure);
 const next=owner.beginGeneration(r.db);assert.equal((await rows(next.projectedDB,'SELECT 1 n'))[0].n,1);
}));
for(const sql of ["SELECT 'sqlite_schema and ''sqlite_master''' value -- sqlite_schema\n",'SELECT 1 /* FROM sqlite_schema */ value','SELECT 1 AS sqlite_schema_longer','SELECT 1 AS "sqlite_schema"','SELECT 1 AS `sqlite_master`','SELECT 1 AS [sqlite_schema]'])test('lexical nonrelation bytes stay exact '+JSON.stringify(sql),()=>owned(async r=>{
 await seed(r);const {generation,db}=await projected(r);await generation.executeFixtureDDL(supportIgnore);const index=r.events.length;await rows(db,sql);assert.equal(attemptsSince(r,index)[0].sql,sql);
}));
for(const [reason,sql] of Object.entries({quoted:'SELECT name FROM "sqlite_schema"',backtick:'SELECT name FROM `sqlite_schema`',bracket:'SELECT name FROM [sqlite_schema]',attached:'SELECT name FROM main.sqlite_schema',temp:'SELECT name FROM temp.sqlite_schema',cte:'WITH sqlite_schema AS (SELECT 1 name) SELECT name FROM sqlite_schema',shadow:'SELECT s.name FROM sqlite_schema AS s',unknown:'SELECT name FROM sqlite_schema',multiple:'SELECT 1; SELECT name FROM sqlite_schema',unclosedString:"SELECT 'sqlite_schema",unclosedComment:'SELECT 1 /* sqlite_schema',nesting:'SELECT '+ '('.repeat(129)+'1'+')'.repeat(129),tokens:'SELECT '+Array(65537).fill('1').join('+'),bytes:"SELECT '"+'x'.repeat(1048576)+"'"}))test('unsupported lexer/query form refuses infrastructure '+reason,()=>owned(async r=>{
 await seed(r);const {generation,db}=await projected(r);await generation.executeFixtureDDL(supportIgnore);const index=r.events.length;await refuses(()=>rows(db,sql));assert.equal(attemptsSince(r,index).length,0);
}));
test('source PRAGMA remains raw and unsupported source schema mutation refuses',()=>owned(async r=>{
 await seed(r);const {generation,db}=await projected(r);await generation.executeFixtureDDL(supportIgnore);const index=r.events.length;assert.deepEqual(await rows(db,'PRAGMA table_info(support_commit)'),await r.rawRows('PRAGMA table_info(support_commit)'));assert.equal(attemptsSince(r,index)[0].sql,'PRAGMA table_info(support_commit)');await refuses(()=>db.prepare('DROP TABLE support_commit').run());assert.ok(await tuple(r,'operator_test_required'));
}));
test('explicit same-owner single-use persisted B4 reopen retains actual fault until exact DROP',()=>owned(async r=>{
 await seed(r);const {owner,generation,db}=await projected(r);await generation.executeFixtureDDL(b4);const original=await tuple(r,'notices_test_fault');const stale=db.prepare(Q.inventory),receipt=generation.retireForKnownRestart();assert.ok(Object.isFrozen(receipt));assert.deepEqual(Object.keys(receipt),[]);await refuses(()=>stale.all());
 await r.restart();assert.deepEqual(await tuple(r,'notices_test_fault'),original);const next=owner.beginGeneration(r.db);await next.reopenKnownInstalledFixtures(receipt);assert.equal((await rows(next.projectedDB,Q.exists,'trigger','notices_test_fault'))[0].present,0);
 assert.equal((await next.projectedDB.prepare("INSERT INTO billing_notice_receipt VALUES ('target','result')").run()).meta.changes,0);await refuses(()=>next.reopenKnownInstalledFixtures(receipt));
 await next.executeFixtureDDL('DROP TRIGGER notices_test_fault');assert.equal(await tuple(r,'notices_test_fault'),undefined);assert.equal((await next.projectedDB.prepare("INSERT INTO billing_notice_receipt VALUES ('target','result')").run()).meta.changes,1);
}));
for(const variant of ['empty','copied','spread','json','foreign','older','missing','changed','withoutReceipt'])test('restart receipt adversary '+variant+' leaves raw visibility and cannot reinstall',()=>owned(async r=>{
 await seed(r);const {owner,generation}=await projected(r);await generation.executeFixtureDDL(b4);const receipt=generation.retireForKnownRestart();
 if(variant==='missing'||variant==='changed'){await r.setup('DROP TRIGGER notices_test_fault');if(variant==='changed')await r.setup(b4.replace('RAISE(IGNORE)',"RAISE(ABORT,'changed')"));}
 await r.restart();const next=(variant==='foreign'?createFixtureFaultSchemaOwner():owner).beginGeneration(r.db);
 if(variant==='older'){next.invalidate();const third=owner.beginGeneration(r.db);await refuses(()=>third.reopenKnownInstalledFixtures(receipt));assert.deepEqual(await rows(third.projectedDB,Q.inventory),await r.rawRows(rawInventory));return;}
 const bad=variant==='empty'?Object.freeze({}):variant==='copied'?Object.assign({},receipt):variant==='spread'?{...receipt}:variant==='json'?JSON.parse(JSON.stringify(receipt)):receipt;
 if(variant!=='withoutReceipt')await refuses(()=>next.reopenKnownInstalledFixtures(bad));
 assert.deepEqual(await rows(next.projectedDB,Q.inventory),await r.rawRows(rawInventory));if(variant==='missing')assert.equal(await tuple(r,'notices_test_fault'),undefined);
}));
for(const transition of ['reset','canary','dispose','sameObject'])test('explicit '+transition+' invalidation burns receipts and old statements',()=>owned(async r=>{
 await seed(r);const {owner,generation,db}=await projected(r);await generation.executeFixtureDDL(b4);const statement=db.prepare(Q.inventory);const receipt=generation.retireForKnownRestart();
 // Known restart is the sole preserving transition. A host reset/canary/dispose
 // explicitly invalidates the retired generation again, burning its receipt.
 generation.invalidate();
 if(transition==='reset'){await r.setup('DROP TRIGGER notices_test_fault');await r.restart();}else if(transition==='canary')await r.outboundCanary();else if(transition==='dispose'){await r.dispose();await refuses(()=>statement.all());return;}
 const next=owner.beginGeneration(r.db);await refuses(()=>next.reopenKnownInstalledFixtures(receipt));await refuses(()=>statement.all());assert.deepEqual(await rows(next.projectedDB,Q.inventory),await r.rawRows(rawInventory));
}));
test('refusing source outcome remains refusing, creates no data and native errors remain errors',()=>owned(async r=>{
 await seed(r);const {generation,db}=await projected(r);const refusingSource=async sourceDB=>{await rows(sourceDB,Q.count,'trigger','operator_test_required');return Object.freeze({outcome:'refused'});};
 assert.deepEqual(await refusingSource(db),{outcome:'refused'});await generation.executeFixtureDDL(supportIgnore);assert.deepEqual(await refusingSource(db),{outcome:'refused'});assert.deepEqual(await r.rawRows('SELECT * FROM fault_probe'),[]);assert.deepEqual(await r.rawRows('SELECT * FROM sentinel'),[]);
 await assert.rejects(db.prepare("SELECT json('')").all(),e=>!infrastructure(e));
}));
test('CREATE native failure never registers missing or already existing raw fixture',()=>owned(async r=>{
 await seed(r);await r.setup(b4);const {generation,db}=await projected(r);
 await assert.rejects(async()=>generation.executeFixtureDDL(b4),e=>!infrastructure(e));assert.equal((await rows(db,Q.exists,'trigger','notices_test_fault'))[0].present,1);
 const missing='CREATE TRIGGER operator_test_activation BEFORE UPDATE ON challenges WHEN NEW.superseded_at IS NULL BEGIN SELECT RAISE(IGNORE); END';
 const index=r.events.length;await assert.rejects(async()=>generation.executeFixtureDDL(missing),e=>!infrastructure(e));assert.ok(attemptsSince(r,index).some(x=>x.sql===missing),'real native attempted DDL required');assert.equal(await tuple(r,'operator_test_activation'),undefined);assert.deepEqual(await rows(db,Q.inventory),await r.rawRows(rawInventory));
}));
