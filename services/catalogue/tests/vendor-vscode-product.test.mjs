import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import * as installed from '../discovery/vendor/installed-metadata.mjs';

// Independent Phase A proposal. Synthetic VS Code-style fixture, no vendor I/O.
const product = () => ({applicationName:'code',darwinBundleIdentifier:'com.microsoft.VSCode',
  updateUrl:'https://update.code.visualstudio.com',quality:'stable'});
const sha = b => createHash('sha256').update(b).digest('hex');
const fixture = () => ({schemaVersion:'installed-vscode-source-fixture-v1',
  observation:{metadataDisposition:'observed',claimedBundleIdentifier:'com.microsoft.VSCode',
    productDisposition:'observed',productBytes:Buffer.from(JSON.stringify(product()))},
  context:{productId:'microsoft-vscode',bundleId:'com.microsoft.VSCode',channel:'stable',architecture:'arm64'},
  sourcePolicy:{productId:'microsoft-vscode',bundleId:'com.microsoft.VSCode',applicationName:'code',
    updateUrl:'https://update.code.visualstudio.com',channel:'stable',architecture:'arm64'}});
function discover(i) {
  // Existing module imports successfully: missing feature is an assertion, not an import error.
  assert.equal(typeof installed.discoverInstalledVSCodeSource,'function','PAT2732 missing bounded product.json source projection');
  return installed.discoverInstalledVSCodeSource(i);
}
function inert(r) {
  assert.equal(r.scope,'fixture-only');
  for(const k of ['verificationAllowed','installationAllowed','publicationAllowed'])assert.equal(r[k],false);
  assert.equal(r.candidate,null,'source claim cannot fabricate a release/artifact candidate');
  for(const k of ['nativeEvidence','publisherVerified','availableVersion','artifactURL'])assert.equal(Object.hasOwn(r,k),false);
}
function refused(i,status='unsupported') {
  const r=discover(i);inert(r);assert.equal(r.status,status);assert.equal(r.sourceClaim,null);assert.match(r.reason,/\S/);
}
function replace(i,p) { i.observation.productBytes=Buffer.from(JSON.stringify(p));return i; }
test('literal stable VS Code-style bytes produce only exact source claim',()=>{
  const i=fixture(),before=structuredClone(i),r=discover(i);inert(r);
  assert.equal(r.status,'source-claim');assert.equal(r.reason,null);
  assert.deepEqual(r.sourceClaim,{format:'vscode-product-subset-v1',updateUrl:'https://update.code.visualstudio.com',
    applicationName:'code',claimedBundleIdentifier:'com.microsoft.VSCode',channel:'stable',architecture:'arm64',
    metadataSha256:sha(i.observation.productBytes)});
  assert.deepEqual(structuredClone(i),before);
  r.sourceClaim.updateUrl='mutated';assert.equal(discover(i).sourceClaim.updateUrl,'https://update.code.visualstudio.com');
});
test('ordinary inert unrelated product fields never execute or change routing',()=>{
  const i=replace(fixture(),{...product(),nameLong:'Visual Studio Code',unrelated:{script:'$(touch /tmp/not-executed)'}});
  assert.equal(discover(i).status,'source-claim');
});
for(const value of ['unavailable','malformed','refused']) {
  test('explicit product disposition '+value,()=>{const i=fixture();i.observation.productDisposition=value;refused(i,value==='unavailable'?'unknown':'unsupported');});
  test('explicit application disposition '+value,()=>{const i=fixture();i.observation.metadataDisposition=value;refused(i,value==='unavailable'?'unknown':'unsupported');});
}
for(const value of [null,Buffer.alloc(0),Buffer.alloc(65537),Buffer.from([0xc3,0x28]),Buffer.from('{'),Buffer.from('null'),Buffer.from('[]'),Buffer.from('{"updateUrl":"a","updateUrl":"b"}'),Buffer.from('\ufeff{}'),Buffer.from('{"x":"\\u0000"}')]) {
  test('malformed absent or oversized bytes '+String(value).slice(0,25),()=>{const i=fixture();i.observation.productBytes=value;refused(i);});
}
for(const [key,value] of [['quality','beta'],['quality','insider'],['quality','unknown'],['quality',null],['channel','beta'],['channel','unknown'],['updateUrl',null],['updateUrl',{dynamic:true}],['applicationName','codium'],['darwinBundleIdentifier','com.attacker.Code']]) {
  test('routing field refusal '+key+' '+JSON.stringify(value),()=>{const p=product();p[key]=value;refused(replace(fixture(),p));});
}
for(const key of ['updateUrl','quality','applicationName','darwinBundleIdentifier'])test('required field '+key,()=>{const p=product();delete p[key];refused(replace(fixture(),p));});
for(const value of ['http://update.code.visualstudio.com','https://user:pass@update.code.visualstudio.com',
  'https://127.0.0.1','https://localhost','https://update.code.visualstudio.com/#x','https://update.code.visualstudio.com/?channel=beta',
  'https://update.code.visualstudio.com/${quality}','https://update.code.visualstudio.com/../other',
  'https://update.code.visualstudio.com.evil.test','https://update.code.visualstudio.com\\evil','file:///tmp/update',
  'https://update.code.visualstudio.com\n','https://update.code.visualstudio.com/'+'a'.repeat(2049)]) {
  test('unsafe unapproved or dynamic endpoint '+JSON.stringify(value),()=>{const p=product();p.updateUrl=value;refused(replace(fixture(),p));});
}
for(const key of ['productId','bundleId','channel','architecture'])for(const value of [null,'','unknown','x64'])test('independent context exact '+key+' '+value,()=>{const i=fixture();i.context[key]=value;refused(i);});
test('installed bundle cannot borrow independent identity',()=>{const i=fixture();i.observation.claimedBundleIdentifier='com.other';refused(i);});
test('raw bytes are bounded plain unshared bytes, never paths or executable accessors',()=>{
  for(const value of ['Contents/Resources/app/product.json',new Uint8Array(new SharedArrayBuffer(10)),Object.create(null)]){const i=fixture();i.observation.productBytes=value;refused(i);}
  const i=fixture();let reads=0;Object.defineProperty(i.observation.productBytes,'byteLength',{get(){reads++;throw Error('accessor ran');}});refused(i);assert.equal(reads,0);
});
test('closed outer contracts reject getters, extras, missing fields and forged authority',()=>{
  for(const pick of [i=>i,i=>i.observation,i=>i.context,i=>i.sourcePolicy])for(const kind of ['getter','extra','missing','symbol']){
    const i=fixture(),r=pick(i),k=Object.keys(r)[0];let reads=0;
    if(kind==='getter')Object.defineProperty(r,k,{get(){reads++;throw Error('getter ran');},enumerable:true});
    if(kind==='extra')r.installationAllowed=true;if(kind==='missing')delete r[k];if(kind==='symbol')r[Symbol('x')]=true;
    refused(i);assert.equal(reads,0);
  }
});
test('literal metadata mutation changes only retained byte digest',()=>{
  const i=fixture(),a=discover(i);i.observation.productBytes=Buffer.concat([i.observation.productBytes,Buffer.from('\n')]);
  const b=discover(i);assert.equal(b.status,'source-claim');assert.notEqual(a.sourceClaim.metadataSha256,b.sourceClaim.metadataSha256);
});

// Each duplicate fixture retains all other routing fields, so duplicate rejection
// cannot pass merely because an unrelated required field was absent.
for (const key of ['updateUrl','quality','applicationName','darwinBundleIdentifier']) {
  for (const spelling of ['literal','escaped']) test('routing duplicate rejects '+key+' '+spelling,()=>{
    const i=fixture(), p=product(), escaped=spelling==='escaped' ? '\\u'+key.charCodeAt(0).toString(16).padStart(4,'0')+key.slice(1) : key;
    const raw=JSON.stringify(p).slice(0,-1)+',"'+escaped+'":'+JSON.stringify(p[key])+'}';
    i.observation.productBytes=Buffer.from(raw);refused(i);
  });
}
test('nested duplicate keys refuse despite valid literal routing',()=>{
  const i=fixture();i.observation.productBytes=Buffer.from(JSON.stringify(product()).slice(0,-1)+',"unused":{"x":1,"x":2}}');refused(i);
});
test('independent policy cannot supply mismatched or unsupported identity and architecture',()=>{
  for(const [key,value] of [['productId','other'],['bundleId','com.other'],['applicationName','codium'],['updateUrl','https://other.example.com'],['channel','beta'],['architecture','x64']]){
    const i=fixture();i.sourcePolicy[key]=value;refused(i);
  }
  const i=fixture();i.context.architecture='x64';i.sourcePolicy.architecture='x64';refused(i);
});
test('byte views reject every shadowed intrinsic and custom property without evaluating getters',()=>{
  for(const key of ['buffer','byteLength','byteOffset','custom']){
    const i=fixture();let reads=0;Object.defineProperty(i.observation.productBytes,key,{get(){reads++;throw Error('getter ran');}});
    refused(i);assert.equal(reads,0);
  }
  for(const value of [new Uint8Array(Buffer.from(JSON.stringify(product()))),Buffer.from(JSON.stringify(product()))]){
    const i=fixture();i.observation.productBytes=value;assert.equal(discover(i).status,'source-claim');
  }
  const i=fixture();class CustomBytes extends Uint8Array {}i.observation.productBytes=new CustomBytes(Buffer.from(JSON.stringify(product())));refused(i);
});

// Known Darwin updater routing override lies outside this stable arm64 subset.
test('darwin universal asset override is unsupported despite complete stable fixture',()=>{
  const i=replace(fixture(),{...product(),darwinUniversalAssetId:'darwin-universal'});
  refused(i);
});
test('present null darwin universal asset override is unsupported despite complete stable fixture',()=>{
  const i=replace(fixture(),{...product(),darwinUniversalAssetId:null});
  refused(i);
});
