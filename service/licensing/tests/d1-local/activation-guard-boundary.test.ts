// Independent local D1 operator guard boundary proof. Synthetic fixture authority only.
// Separate from frozen repair checks; no source/gate edits or production claims.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createECDH,createHash,createHmac} from 'node:crypto';
import {localRuntime} from './runtime.ts';

const rt=await localRuntime();
const now=1791734400, max=Number.MAX_SAFE_INTEGER;
let serial=50000, emails=0;
const id=()=> (++serial).toString(16).padStart(32,'0');
const digest=(bytes:Uint8Array)=>createHash('sha256').update(bytes).digest('hex');
const headers=(marker='PAT-2644-synthetic')=>({'x-fixture-key':marker,'x-fixture-now':String(now),'x-fixture-seed':id(),'x-fixture-delivery':'capture'});
async function account(){
 const email=`operator-boundary-${++emails}@example.invalid`, purpose='app-sign-in';
 const r=await rt.post('/__fixture/accounts/request',{email,purpose,sourceIP:`192.0.2.${emails}`},headers('PAT-2642-synthetic'));
 assert.equal(r.status,202,'setup real S1a request');
 const c=await rt.post('/__fixture/accounts/consume',{challengeID:r.body.challengeID,purpose,code:'01234567'},headers('PAT-2642-synthetic'));
 assert.equal(c.status,200,'setup real S1a session');
 return c.body;
}
async function seed(s:any){
 const scalar=Buffer.alloc(32);scalar.writeUInt32BE(++serial,28);
 const ec=createECDH('prime256v1');ec.setPrivateKey(scalar);
 const publicKey=ec.getPublicKey(), activationID=id(), hash=digest(publicKey), nonce='boundary-seed-'+id();
 await rt.db.batch([
  rt.db.prepare('INSERT INTO lease_heads(activation_id,account_id,device_key_sha256,activation_revision,sequence,commit_nonce) VALUES(?,?,?,1,0,?)').bind(activationID,s.accountID,hash,nonce),
  rt.db.prepare('INSERT INTO activations(activation_id,account_id,public_key,display_name,generation,created_at,commit_nonce) VALUES(?,?,?,?,1,?,?)').bind(activationID,s.accountID,publicKey,'Synthetic Boundary Mac',now,nonce),
  rt.db.prepare('INSERT INTO activation_slots VALUES(?,1,?,?,?)').bind(s.accountID,activationID,hash,nonce),
 ]);
 return {activationID};
}
async function inputAt(revision:number){
 const s=await account(), t=await seed(s);
 await rt.db.prepare('UPDATE account_guard SET account_revision=? WHERE account_id=?').bind(revision,s.accountID).run();
 assert.equal((await rt.rows('SELECT account_revision FROM account_guard WHERE account_id=?',s.accountID))[0].account_revision,revision,'setup boundary is exactly stored');
 const guard={accountID:s.accountID,accountRevision:revision,commitNonce:'operator-boundary-'+id()};
 const descriptorSHA256=digest(Buffer.from('PAT-2644 synthetic operator boundary descriptor '+t.activationID));
 const confirmationID=id(), requestID=id();
 const claims={marker:'PAT-2644-operator-synthetic',operatorID:id(),sessionID:id(),accountID:s.accountID,activationID:t.activationID,activationRevision:1,accountRevision:revision,purpose:'deactivateActivation',descriptorSHA256,confirmationID,authenticatedAt:now,expiresAt:now+300};
 const bytes=Buffer.from(JSON.stringify(claims));
 const mac=createHmac('sha256',Buffer.alloc(32,9)).update(Buffer.from('operator\0')).update(bytes).digest('base64');
 const credential=Buffer.from(JSON.stringify({claims:bytes.toString('base64'),mac})).toString('base64');
 return {s,t,input:{credential,guard,activationID:t.activationID,expectedRevision:1,requestID,descriptorSHA256,confirmationID}};
}
const invoke=(input:unknown,adapter='PAT-2644-hmac-v1')=>rt.post('/__fixture/activations/operatorDeactivate',input,{...headers(),...(adapter?{'x-fixture-operator-adapter':adapter}:{})});
async function evidence(s:any){
 const rows=async(table:string)=>rt.rows(`SELECT * FROM ${table} WHERE account_id=? ORDER BY 1`,s.accountID);
 return {guard:await rows('account_guard'),account:await rows('accounts'),head:await rows('lease_heads'),metadata:await rows('activations'),slots:await rows('activation_slots'),confirmations:await rows('operator_confirmations'),audit:await rows('account_audit'),nonces:await rows('account_nonce_history')};
}
try{
 await test('BOUNDARY SETUP actual D1 rollback, commit, restart, environment and outbound denial',async()=>{
  const before=await rt.snapshot();
  assert.equal((await rt.post('/__fixture/rollback',{})).status,409);
  assert.deepEqual(await rt.snapshot(),before);
  assert.equal((await rt.post('/__fixture/commit',{})).status,200);
  const committed=await rt.snapshot();
  await rt.restart();assert.deepEqual(await rt.snapshot(),committed);
  await rt.restart({ENVIRONMENT:'wrong'});assert.equal((await rt.post('/__fixture/commit',{})).status,503);
  await rt.restart();await rt.canary();assert.deepEqual(await rt.snapshot(),committed);
 });
 await test('BOUNDARY missing operator adapter and invalid domain HMAC refuse without any mutation',async()=>{
  const {input}=await inputAt(max-1),before=await rt.snapshot();
  assert.equal((await invoke(input,'')).status,401);
  assert.deepEqual(await rt.snapshot(),before);
  const envelope=JSON.parse(Buffer.from(input.credential,'base64').toString());
  envelope.mac=createHmac('sha256',Buffer.alloc(32,9)).update(Buffer.from('wrong-domain\0')).update(Buffer.from(envelope.claims,'base64')).digest('base64');
  assert.equal((await invoke({...input,credential:Buffer.from(JSON.stringify(envelope)).toString('base64')})).status,401);
  assert.deepEqual(await rt.snapshot(),before);
 });
 await test('BOUNDARY valid MAX-1 operator control commits exactly MAX, one audit, released slot',async()=>{
  const {s,t,input}=await inputAt(max-1),before=await evidence(s);
  const untouched=['sessions','entitlement_sources','trial_markers','device_requests','device_request_tombstones','device_challenges'];
  const protectedBefore=await Promise.all(untouched.map(table=>rt.rows(`SELECT * FROM ${table} ORDER BY 1,2`)));
  const r=await invoke(input),after=await evidence(s);
  console.log('OPERATOR_SAFE_BOUNDARY',JSON.stringify({response:r,before,after}));
  assert.equal(r.status,200);assert.equal(r.body.outcome,'released');assert.equal(r.body.activationID,t.activationID);
  assert.equal(after.guard[0].account_revision,max);assert.ok(Number.isSafeInteger(after.guard[0].account_revision));
  assert.equal(after.guard[0].commit_nonce,input.guard.commitNonce);
  assert.equal(after.head[0].activation_revision,2);assert.equal(after.head[0].released_at,now);
  assert.equal(after.head[0].sequence,before.head[0].sequence);
  assert.equal(after.head[0].max_grant_permitted_until,before.head[0].max_grant_permitted_until);
  assert.equal(after.metadata[0].release_reason,'operatorDeactivated');assert.deepEqual(after.slots,[]);
  assert.equal(after.account[0].activation_revision,before.account[0].activation_revision+1);
  assert.equal(after.account[0].entitlement_revision,before.account[0].entitlement_revision);
  assert.equal(after.audit.length,before.audit.length+1);
  assert.equal(after.audit.at(-1).action,'activation.operatorReleased');assert.equal(after.audit.at(-1).account_revision,max);
  assert.equal(after.confirmations.length,1);assert.equal(after.confirmations[0].confirmation_id,input.confirmationID);
  assert.equal(after.nonces.length,before.nonces.length+1);
  assert.deepEqual(await Promise.all(untouched.map(table=>rt.rows(`SELECT * FROM ${table} ORDER BY 1,2`))),protectedBefore);
  assert.deepEqual(await rt.rows('PRAGMA foreign_key_check'),[]);
 });
 await test('BOUNDARY MAX operator request refuses409 with complete snapshot unchanged',async()=>{
  const {s,input}=await inputAt(max),before=await rt.snapshot(),stateBefore=await evidence(s);
  const r=await invoke(input),after=await rt.snapshot(),stateAfter=await evidence(s);
  console.log('OPERATOR_MAX_BOUNDARY',JSON.stringify({response:r,snapshotUnchanged:JSON.stringify(before)===JSON.stringify(after),before:stateBefore,after:stateAfter,afterGuardIsSafeInteger:Number.isSafeInteger(stateAfter.guard[0].account_revision)}));
  assert.equal(r.status,409,'MAX guard cannot increment safely and must refuse');
  assert.deepEqual(after,before,'boundary refusal changes no dependent table');
 });
}finally{
 console.log('OPERATOR_BOUNDARY_RUNTIME_RECEIPT',JSON.stringify({node:process.version,versions:rt.versions,oneOwner:true,realLoopback:true,deniedOutbound:rt.deniedOutbound}));
 await rt.dispose();
}
