import {preservedPinnedSignatureLiveProofBytes} from '../../../scripts/lib/pinned-signature-live-proof-preservation.mjs';
import {preservedUnstapledLiveProofSHA256} from '../../../scripts/lib/unstapled-live-proof-preservation.mjs';
import {preservedArtifactSizeSHA256} from '../../../scripts/lib/artifact-size-preservation.mjs';
import {preservedPackageSHA256} from '../../../scripts/lib/package-registration-preservation.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createPublicKey, verify} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {verifyCatalogue, compareVersions, encodePayload} from '../protocol/catalogue-v2.mjs';
import {parseStrictJSON} from '../protocol/strict-json.mjs';
import {readFixture,key,sha256,clone,bytesOf,message,signBytes,signRawFixtureMessage,envelopeFor,wrap,payload,emptyPayload,withdrawalPayload,trust,context,input,checkpoint,change} from './catalogue-fixture-support.mjs';

const resultKeys = ['status','reason','scope','installationAuthorized','publicationAuthority','freshOSValidation','payloadSHA256','sequence','catalogue','checkpoint'].sort();
function authority(r) {
  assert.deepEqual(Object.keys(r).sort(),resultKeys);
  assert.equal(r.scope,'fixture-only');
  for(const key of ['installationAuthorized','publicationAuthority','freshOSValidation']) assert.equal(r[key],false,key);
}
function accepts(args,p,status='verified') {
  const snapshot=clone(args); const originalEnvelope=args.envelopeBytes; const r=verifyCatalogue(args);
  authority(r); assert.equal(r.status,status); assert.equal(r.reason,null);
  const raw=Buffer.from(JSON.parse(Buffer.from(args.envelopeBytes).toString()).payload,'base64');
  assert.equal(r.payloadSHA256,sha256(raw)); assert.equal(r.sequence,p.sequence);
  assert.deepEqual(r.catalogue,p);
  assert.deepEqual(r.checkpoint,{catalogueID:p.catalogueID,sequence:p.sequence,payloadSHA256:sha256(raw)});
  assert.equal(args.envelopeBytes,originalEnvelope,'does not replace envelope bytes');
  assert.deepEqual(clone(args),snapshot,'does not mutate arguments'); return r;
}
function refuses(args,reason) {
  const r=verifyCatalogue(args); authority(r); assert.equal(r.status,'refused'); assert.equal(r.reason,reason);
  for(const k of ['payloadSHA256','sequence','catalogue','checkpoint']) assert.equal(r[k],null,k);
}
const badPayload=(name,mutate,reason='invalid-payload')=>test(name,()=>{const p=payload();mutate(p);refuses(input(p),reason);});
const badInput=(name,mutate,reason)=>test(name,()=>{const i=input();mutate(i);refuses(i,reason);});
const badEnvelope=(name,mutate)=>test(name,()=>{const e=envelopeFor(bytesOf(payload()));mutate(e);const i=input();i.envelopeBytes=bytesOf(e);refuses(i,'invalid-envelope');});
const positive=(name,mutate=()=>{},adjust=()=>{})=>test(name,()=>{const p=payload();mutate(p);const i=input(p);adjust(i);accepts(i,p);});

// Positive tests run against the real public API; Phase A refuses them meaningfully.
for(const name of ['empty','one-entry','withdrawal','whitespace']) test(`golden ${name}: verified without authority`,()=>{
 const raw=readFixture(`${name}.payload.json`);const p=JSON.parse(raw);const i=input(p);i.envelopeBytes=readFixture(`${name}.envelope.json`);accepts(i,p);
});
test('goldens independently reproduce with Node crypto',()=>{
 const corpus=JSON.parse(readFixture('golden-vectors.json'));
 assert.deepEqual(corpus.vectors.map(v=>v.name),['empty','one-entry','withdrawal','whitespace']);
 const pub=createPublicKey({key:Buffer.concat([Buffer.from('302a300506032b6570032100','hex'),Buffer.from(key.publicKeyBase64,'base64')]),format:'der',type:'spki'});
 for(const v of corpus.vectors){const b=readFixture(v.payloadFile);const env=JSON.parse(readFixture(v.envelopeFile));
  assert.equal(sha256(b),v.payloadSHA256);assert.equal(message(b).toString('base64'),v.messageBase64);
  assert.equal(signBytes(b).toString('base64'),v.signatureBase64);assert.equal(env.signature,v.signatureBase64);
  assert.equal(verify(null,message(b),pub,Buffer.from(v.signatureBase64,'base64')),true);
  assert.equal(verify(null,b,pub,Buffer.from(v.signatureBase64,'base64')),false);
 }
});
positive('multiple sorted releases for one product',p=>{const e=clone(p.entries[0]);e.identity.releaseID='release-0002';p.entries.push(e);});
positive('entry and distinct withdrawal together',p=>{p.withdrawals=withdrawalPayload().withdrawals;p.withdrawals[0].releaseID='release-0000';});
positive('all supported installer policy combinations',p=>{p.entries[0].installer={method:'pkg',version:'v2',interaction:'defer',restart:'ask',coordination:'exclusive-app'};});
positive('zip-app method',p=>{p.entries[0].installer.method='zip-app';});
positive('URL host is separate from redirectHosts',p=>{p.entries[0].source.redirectHosts=[];});
positive('URL raw @ in path and query',p=>{p.entries[0].source.url='https://downloads.example.test/a@b?who=c@d';});
for(const url of ['https://example.test','https://example.test:443/x','https://example.test:1/x','https://example.test:65535/x','https://xn--bcher-kva.example/x','https://example.test/a%20b']) positive(`URL syntax accepts ${url}`,p=>{p.entries[0].source.url=url;});
positive('exactly64 byte opaque IDs',p=>{p.catalogueID='A'.repeat(64);p.keyID='K'.repeat(64);},i=>{const e=JSON.parse(i.envelopeBytes);e.keyID='K'.repeat(64);i.envelopeBytes=bytesOf(e);i.trust.catalogueID='A'.repeat(64);i.trust.keyID='K'.repeat(64);});
positive('maximum safe sequence',p=>{p.sequence=Number.MAX_SAFE_INTEGER;});
positive('artifact and evidence upper lengths',p=>{p.entries[0].artifact.byteLength=8589934592;p.entries[0].evidence.byteLength=4194304;});
positive('time equality valid at freshness limits',p=>{p.entries[0].source.observedAt=p.issuedAt-86400;p.entries[0].evidence.verifiedAt=p.issuedAt-255600;p.entries[0].evidence.validUntil=p.expiresAt;});
positive('issuedAt exactly now plus300',p=>{},i=>{i.context.now-=300;});
positive('expiresAt one second after now',p=>{},i=>{i.context.now=1800003599;});
positive('maximum48 hour lifetime',p=>{p.expiresAt=p.issuedAt+172800;p.entries[0].evidence.validUntil=p.expiresAt;});
positive('minimum positive lengths',p=>{p.entries[0].artifact.byteLength=1;p.entries[0].evidence.byteLength=1;});
positive('maximumOS equals minimumOS by padded comparison',p=>{p.entries[0].compatibility.maximumOS='13';});
positive('one architecture',p=>{p.entries[0].compatibility.architectures=['x86_64'];});
positive('minimum build equality',()=>{},i=>{i.context.clientBuild=100;});
for(const count of [1000,1001]) test(`entries count ${count}`,()=>{const p=payload();p.entries=Array.from({length:count},(_,i)=>{const e=clone(p.entries[0]);e.identity.releaseID=`r${String(i).padStart(4,'0')}`;return e;});count===1000?accepts(input(p),p):refuses(input(p),'invalid-payload');});
for(const count of [1000,1001]) test(`withdrawals count ${count}`,()=>{const p=emptyPayload();p.withdrawals=Array.from({length:count},(_,i)=>({productID:'p',releaseID:`r${String(i).padStart(4,'0')}`,artifactSHA256:'a'.repeat(64),reason:'withdrawn',effectiveAt:p.issuedAt}));count===1000?accepts(input(p),p):refuses(input(p),'invalid-payload');});

// Closed object shapes, at every level. Unknown data must never widen authority.
const records=['','entries.0','entries.0.identity','entries.0.release','entries.0.compatibility','entries.0.source','entries.0.artifact','entries.0.evidence','entries.0.installer'];
const at=(o,path)=>path?path.split('.').reduce((v,k)=>v[k],o):o;
for(const path of records){
 badPayload(`unknown field at ${path||'payload'}`,p=>{at(p,path).unrecognised=true;});
 const sample=at(payload(),path);
 for(const k of Object.keys(sample)) badPayload(`required ${path||'payload'}.${k}`,p=>{delete at(p,path)[k];});
}
for(const k of Object.keys(withdrawalPayload().withdrawals[0])) test(`withdrawal required ${k}`,()=>{const p=withdrawalPayload();delete p.withdrawals[0][k];refuses(input(p),'invalid-payload');});
test('withdrawal unknown field',()=>{const p=withdrawalPayload();p.withdrawals[0].extra=true;refuses(input(p),'invalid-payload');});
for(const k of Object.keys(envelopeFor(bytesOf(payload())))) badEnvelope(`envelope required ${k}`,e=>{delete e[k];});
for(const [k,v] of [['extra',true],['algorithm','HS256'],['schema','fixture-catalogue-envelope-v1'],['keyID',5],['signature',''],['payload',''],['installAllowed',true]]) badEnvelope(`envelope invalid ${k} ${v}`,e=>{e[k]=v;});
for(const [path,values] of [
 ['schema',['fixture-catalogue-v1',null]],['domain',['im.patched.catalogue.v1','im.patched.catalogue.v2\0']],
 ['catalogueID',['','-bad','a'.repeat(65),'é','a/b','a b']],['keyID',['','bad/key','a'.repeat(65)]],
 ['policyDigest',['A'.repeat(64),'0'.repeat(63),'g'.repeat(64),null]],
 ['entries',[null,{},'[]']],['withdrawals',[null,{}]],
 ['entries.0.identity.productID',['','-x','é','a'.repeat(65)]],
 ['entries.0.identity.releaseID',['','a/b']],['entries.0.identity.edition',['','-x']],['entries.0.identity.generation',['','-x']],
 ['entries.0.identity.bundleID',['single','a..b','.ab','ab.','a_b.c','é.x','a.'.repeat(128)+'a']],
 ['entries.0.identity.teamID',['TESTTEAM0','TESTTEAM001','testteam01','TESTTEAM_1']],
 ['entries.0.identity.channel',['beta','STABLE']],['entries.0.release.comparator',['semver','numeric-dotted-u32-v2',null]],
 ['entries.0.compatibility.platform',['macos','Windows']],['entries.0.compatibility.minimumOS',['13.00','-1']],
 ['entries.0.compatibility.maximumOS',['12.9','bad',0]],['entries.0.compatibility.architectures',[[],['arm64','arm64'],['x86_64','arm64'],['ARM64'],['arm64','riscv'],null]],
 ['entries.0.source.routeID',['','-bad']],['entries.0.source.routeVersion',['','v 1']],
 ['entries.0.artifact.sha256',['A'.repeat(64),'a'.repeat(63)]],['entries.0.evidence.sha256',['z'.repeat(64)]],
 ['entries.0.evidence.policyVersion',['']],['entries.0.evidence.checkerVersion',['-x']],['entries.0.evidence.environmentVersion',['a/b']],
 ['entries.0.installer.method',['shell','dmg','DMG-APP']],['entries.0.installer.version',['','a/b']],
 ['entries.0.installer.interaction',['silent','none']],['entries.0.installer.restart',['force','defer']],['entries.0.installer.coordination',['none','shared-app']],
])for(const [index,v]of values.entries())badPayload(`invalid field ${path} case${index}`,p=>change(p,path,v));
badPayload('signed installAllowed refuses',p=>{p.installAllowed=true;});
badPayload('signed entitlement refuses',p=>{p.entitlement='paid';});
const numericPaths=['sequence','minimumClientBuild','issuedAt','expiresAt','entries.0.source.observedAt','entries.0.artifact.byteLength','entries.0.evidence.byteLength','entries.0.evidence.verifiedAt','entries.0.evidence.validUntil'];
for(const path of numericPaths)for(const v of [-1,1.5,Number.MAX_SAFE_INTEGER+1,'1',null,true])badPayload(`unsafe numeric ${path} ${String(v)}`,p=>change(p,path,v));
for(const path of ['sequence','minimumClientBuild','entries.0.artifact.byteLength','entries.0.evidence.byteLength'])badPayload(`positive-only ${path}`,p=>change(p,path,0));
badPayload('artifact over8GiB',p=>{p.entries[0].artifact.byteLength=8589934593;});
badPayload('evidence over4MiB',p=>{p.entries[0].evidence.byteLength=4194305;});
for(const v of [1,3])badPayload(`unknown minimum protocol ${v}`,p=>{p.minimumClientProtocol=v;},'unsupported-client');
for(const v of ['2',null,2.5])badPayload(`malformed minimum protocol ${v}`,p=>{p.minimumClientProtocol=v;});
for(const [name,mutate]of [
 ['expiry equality',p=>{p.expiresAt=p.issuedAt;}],['expiry before issue',p=>{p.expiresAt=p.issuedAt-1;}],
 ['lifetime over48h',p=>{p.expiresAt=p.issuedAt+172801;}],['source future',p=>{p.entries[0].source.observedAt=p.issuedAt+1;}],
 ['source older than24h',p=>{p.entries[0].source.observedAt=p.issuedAt-86401;}],['evidence verified future',p=>{p.entries[0].evidence.verifiedAt=p.issuedAt+1;}],
 ['evidence expires at issue',p=>{p.entries[0].evidence.validUntil=p.issuedAt;}],['evidence lifetime over72h',p=>{p.entries[0].evidence.validUntil=p.entries[0].evidence.verifiedAt+259201;}],
 ['catalogue outlives evidence',p=>{p.entries[0].evidence.validUntil=p.expiresAt-1;}],
])badPayload(`time: ${name}`,mutate,'invalid-time');
badInput('issue301 seconds in future',i=>{i.context.now-=301;},'invalid-time');
badInput('expiresAt equality is expired',i=>{i.context.now=1800003600;},'invalid-time');
badInput('long expired',i=>{i.context.now=1800003601;},'invalid-time');

// Raw URL syntax, not a fetch or SSRF claim.
for(const [idx,url]of ['http://example.test/x','HTTPS://example.test/x','https:example.test','https:/example.test','https:///example.test','https://EXAMPLE.test','https://%65xample.test','https://a@b.test/x','https://@example.test','https://a:b@example.test','https://example.test/#','https://example.test/#x','https://example.test/\\x','https://example.test/a b','https://example.test/\tx',' https://example.test','https://example.test\n','https://127.0.0.1','https://2130706433','https://[::1]','https://a..test','https://-a.test','https://a-.test','https://example.test.','https://例子.test','https://a_b.test','https://example.test:','https://example.test:0','https://example.test:0443','https://example.test:65536','https://example.test:+443','https://example.test:4.43'].entries())badPayload(`URL refuses case${idx}`,p=>{p.entries[0].source.url=url;});
for(const hosts of [['a.test','a.test'],['z.test','a.test'],['A.test'],['*.test'],['a.test.'],['a.test:443'],['127.0.0.1'],['[::1]'],['a'.repeat(64)+'.test'],['-a.test'],['a-.test'],['a..test'],['é.test'],Array.from({length:17},(_,i)=>`a${String(i).padStart(2,'0')}.test`),null])badPayload(`redirectHosts refuses ${JSON.stringify(hosts)}`,p=>{p.entries[0].source.redirectHosts=hosts;});
positive('16 redirect hosts',p=>{p.entries[0].source.redirectHosts=Array.from({length:16},(_,i)=>`a${String(i).padStart(2,'0')}.test`);});
for(const length of [2048,2049]) test(`URL byte limit ${length}`,()=>{const p=payload();p.entries[0].source.url='https://example.test/'+ 'x'.repeat(length-21);assert.equal(Buffer.byteLength(p.entries[0].source.url),length-0);length===2048?accepts(input(p),p):refuses(input(p),'invalid-payload');});
for(const [name,mutate]of [
 ['duplicate releases',p=>{p.entries.push(clone(p.entries[0]));}],['unsorted releases',p=>{const e=clone(p.entries[0]);e.identity.releaseID='aaa';p.entries.push(e);}],
 ['release withdrawal conflict',p=>{p.withdrawals=withdrawalPayload().withdrawals;}],
 ['duplicate withdrawals',p=>{p.entries=[];const w=withdrawalPayload().withdrawals[0];p.withdrawals=[w,clone(w)];}],
 ['unsorted withdrawals',p=>{p.entries=[];const w=withdrawalPayload().withdrawals[0];p.withdrawals=[w,{...w,releaseID:'aaa'}];}],
 ['withdrawal future',p=>{p.entries=[];p.withdrawals=withdrawalPayload().withdrawals;p.withdrawals[0].effectiveAt=p.issuedAt+1;}],
])badPayload(name,mutate,name==='withdrawal future'?'invalid-time':'invalid-payload');
for(const [k,v]of [['productID','-bad'],['releaseID',''],['artifactSHA256','A'.repeat(64)],['reason','bad reason'],['effectiveAt',-1],['effectiveAt',1.5],['effectiveAt',Number.MAX_SAFE_INTEGER+1]])test(`withdrawal invalid ${k} ${v}`,()=>{const p=withdrawalPayload();p.withdrawals[0][k]=v;refuses(input(p),'invalid-payload');});

// Version grammar and numerical comparison: invalid aliases never compare equal.
const invalidVersions=['','01','1.00','+1','-1','1.','1..2','.1','1e2','1 2','١','１','4294967296','1.2.3.4.5.6.7.8.9',1,null,{},[],true];
for(const [idx,v]of invalidVersions.entries()){
 test(`comparator refuses malformed left/right ${idx}`,()=>{for(const [l,r]of [[v,'1'],['1',v],[v,v]])assert.deepEqual(compareVersions(l,r),{status:'refused',reason:'invalid-version'});});
 badPayload(`release version invalid ${idx}`,p=>{p.entries[0].release.version=v;});
}
for(const [l,r,order]of [['1','1.0',0],['1.0.0','1',0],['1.2','1.10',-1],['4294967295','4294967294',1],['0','0.0',0],['1.2.3.4.5.6.7.8','1.2.3.4.5.6.7.9',-1],['2','1.999',1]])test(`compare ${l} to ${r}`,()=>{assert.deepEqual(compareVersions(l,r),{status:'compared',order});assert.deepEqual(compareVersions(r,l),{status:'compared',order:order===0?0:-order});});

// Exact byte cryptography and strict JSON parsing.
for(const [field,values]of [['signature',['AA','='.repeat(88),'A'.repeat(88),'A'.repeat(88)+'\n','A'.repeat(86)+'-_']],['payload',['e30','e30===',' e30=','e30=\n','e30_']]])for(const [idx,v]of values.entries())badEnvelope(`noncanonical base64 ${field} ${idx}`,e=>{e[field]=v;});
badEnvelope('canonical base64 wrong signature length63',e=>{e.signature=Buffer.alloc(63).toString('base64');});
badEnvelope('canonical base64 wrong signature length65',e=>{e.signature=Buffer.alloc(65).toString('base64');});
test('canonical pad bits required',()=>{const e=envelopeFor(bytesOf(payload()));const s=e.signature;const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';const pos=s.length-3;e.signature=s.slice(0,pos)+alphabet[alphabet.indexOf(s[pos])+1]+s.slice(pos+1);assert.deepEqual(Buffer.from(e.signature,'base64'),Buffer.from(s,'base64'));const i=input();i.envelopeBytes=bytesOf(e);refuses(i,'invalid-envelope');});
for(const name of ['signature','payload']) test(`cryptographic ${name} tamper`,()=>{const e=envelopeFor(bytesOf(payload()));if(name==='signature'){const b=Buffer.from(e.signature,'base64');b[0]^=1;e.signature=b.toString('base64');}else{const p=payload();p.sequence+=1;e.payload=bytesOf(p).toString('base64');}const i=input();i.envelopeBytes=bytesOf(e);refuses(i,'invalid-signature');});
test('signature over raw payload without domain refuses',()=>{const e=envelopeFor(bytesOf(payload()));e.signature=signRawFixtureMessage(bytesOf(payload())).toString('base64');const i=input();i.envelopeBytes=bytesOf(e);refuses(i,'invalid-signature');});
test('reserialisation does not repair whitespace signature',()=>{const e=JSON.parse(readFixture('whitespace.envelope.json'));e.payload=bytesOf(payload()).toString('base64');const i=input();i.envelopeBytes=bytesOf(e);refuses(i,'invalid-signature');});
test('ordinary envelope whitespace permitted',()=>{const i=input();i.envelopeBytes=Buffer.from(' \n'+JSON.stringify(JSON.parse(i.envelopeBytes),null,2)+'\t');accepts(i,payload());});
const parserBad=[
 ['duplicate key','{"x":1,"x":2}'],['escaped duplicate alias','{"schema":1,"\\u0073chema":2}'],
 ['nested escaped duplicate','{"x":{"a":1,"\\u0061":2}}'],['BOM','\ufeff{}'],['trailing data','{}{}'],['trailing junk','{}x'],
 ['lone high surrogate','{"x":"\\ud800"}'],['lone low surrogate','{"x":"\\udc00"}'],['key lone surrogate','{"\\ud800":1}'],
 ['raw unescaped control','{"x":"\u0001"}'],['nonfinite number','{"x":1e309}'],['leading zero','{"x":01}'],
 ['trailing comma','{"x":1,}'],['comment','{/*x*/}'],['depth17','['.repeat(17)+'0'+']'.repeat(17)],
];
for(const [name,raw]of parserBad){
 test(`strict parser refuses ${name}`,()=>assert.throws(()=>parseStrictJSON(Buffer.from(raw),{maximumBytes:1048576,maximumDepth:16}),SyntaxError));
 test(`signed payload parser refuses ${name}`,()=>{const i=input();i.envelopeBytes=wrap(Buffer.from(raw));refuses(i,'invalid-payload');});
 test(`envelope parser refuses ${name}`,()=>{const i=input();i.envelopeBytes=Buffer.from(raw);refuses(i,'invalid-envelope');});
}
for(const hex of ['c0af','eda080','ff','f4908080','e282'])for(const where of ['payload','envelope'])test(`${where} fatal UTF8 ${hex}`,()=>{const bytes=Buffer.concat([Buffer.from('{"x":"'),Buffer.from(hex,'hex'),Buffer.from('"}')]);const i=input();i.envelopeBytes=where==='payload'?wrap(bytes):bytes;refuses(i,where==='payload'?'invalid-payload':'invalid-envelope');});
for(const fixture of JSON.parse(readFixture('invalid-examples.json')).cases)test(`bounded parser fixture ${fixture.name}`,()=>{assert.throws(()=>parseStrictJSON(Buffer.from(fixture.hex,'hex'),{maximumBytes:1048576,maximumDepth:16}),SyntaxError);});
for(const [name,raw,expected]of [['whitespace',' \n {"a":[true,false,null,1,100],"b":"\\ud83d\\ude00"}\t',{a:[true,false,null,1,100],b:'😀'}],['depth16','['.repeat(16)+'0'+']'.repeat(16),JSON.parse('['.repeat(16)+'0'+']'.repeat(16))],['prototype key','{"__proto__":{"poison":true}}',JSON.parse('{"__proto__":{"poison":true}}')]])test(`strict parser accepts ${name}`,()=>{const result=parseStrictJSON(Buffer.from(raw),{maximumBytes:1048576,maximumDepth:16});assert.equal(JSON.stringify(result),JSON.stringify(expected));assert.equal({}.poison,undefined);});
for(const maximumBytes of [1,2])test(`strict parser byte bound ${maximumBytes}`,()=>{if(maximumBytes===1)assert.throws(()=>parseStrictJSON(Buffer.from('{}'),{maximumBytes,maximumDepth:16}),SyntaxError);else assert.equal(JSON.stringify(parseStrictJSON(Buffer.from('{}'),{maximumBytes,maximumDepth:16})),'{}');});
for(const size of [1048576,1048577])test(`decoded payload exact byte boundary ${size}`,()=>{const p=emptyPayload();const b=bytesOf(p);const raw=Buffer.concat([b,Buffer.alloc(size-b.length,32)]);const i=input(p);i.envelopeBytes=wrap(raw);size===1048576?accepts(i,p):refuses(i,'invalid-envelope');});
for(const size of [2097152,2097153])test(`envelope exact byte boundary ${size}`,()=>{const p=emptyPayload();const i=input(p);i.envelopeBytes=Buffer.concat([i.envelopeBytes,Buffer.alloc(size-i.envelopeBytes.length,32)]);size===2097152?accepts(i,p):refuses(i,'invalid-envelope');});
// Keep schema-valid duplicate aliases to distinguish strict parsing from unknown-key rejection.
for(const where of ['payload','envelope'])test(`valid ${where} shape with escaped duplicate refuses`,()=>{const i=input();if(where==='payload'){const raw=bytesOf(payload()).toString().replace('"sequence":2','"sequence":2,"\\u0073equence":2');i.envelopeBytes=wrap(Buffer.from(raw));}else{i.envelopeBytes=Buffer.from(Buffer.from(i.envelopeBytes).toString().replace('"algorithm":"Ed25519"','"algorithm":"Ed25519","\\u0061lgorithm":"Ed25519"'));}refuses(i,where==='payload'?'invalid-payload':'invalid-envelope');});

// Injected authority: exact records, bounded key ranges and no silent reset.
for(const which of ['trust','context','previous']){
 const fields=which==='trust'?Object.keys(trust()):which==='context'?Object.keys(context()):Object.keys(checkpoint(payload()));
 for(const field of fields)badInput(`${which} missing ${field}`,i=>{if(which==='previous'){i.previous=checkpoint(payload());i.bootstrap=false;}delete i[which][field];},`invalid-${which==='previous'?'history':which}`);
 badInput(`${which} unknown field`,i=>{if(which==='previous'){i.previous=checkpoint(payload());i.bootstrap=false;}i[which].extra=true;},`invalid-${which==='previous'?'history':which}`);
 for(const value of [null,[],3,'record']){if(which==='previous'&&value===null)continue;badInput(`${which} invalid record ${JSON.stringify(value)}`,i=>{i[which]=value;if(which==='previous')i.bootstrap=false;},`invalid-${which==='previous'?'history':which}`);}
}
for(const field of ['now','clientProtocol','clientBuild'])for(const value of [-1,1.5,'2',null,Number.MAX_SAFE_INTEGER+1])badInput(`context ${field} invalid ${value}`,i=>{i.context[field]=value;},'invalid-context');
badInput('zero build refuses',i=>{i.context.clientBuild=0;},'invalid-context');
badInput('old client build refuses',i=>{i.context.clientBuild=99;},'unsupported-client');
for(const value of [1,3])badInput(`unsupported client protocol ${value}`,i=>{i.context.clientProtocol=value;},'unsupported-client');
for(const field of ['firstSequence','lastSequence'])for(const value of [0,-1,1.5,'1',null,Number.MAX_SAFE_INTEGER+1])badInput(`trust ${field} invalid ${value}`,i=>{i.trust[field]=value;},'invalid-trust');
badInput('inverted trust sequence range',i=>{i.trust.firstSequence=5;i.trust.lastSequence=4;},'invalid-trust');
badInput('trust retired must be boolean',i=>{i.trust.retired='false';},'invalid-trust');
badInput('retired trust refuses',i=>{i.trust.retired=true;},'retired-key');
badInput('below key firstSequence',i=>{i.trust.firstSequence=3;},'sequence-out-of-range');
badInput('above key lastSequence',i=>{i.trust.lastSequence=1;},'sequence-out-of-range');
positive('key exact sequence bounds',()=>{},i=>{i.trust.firstSequence=2;i.trust.lastSequence=2;});
for(const value of ['',key.publicKeyBase64.slice(0,-1),key.publicKeyBase64+'\n',Buffer.alloc(31).toString('base64'),Buffer.alloc(33).toString('base64'),null])badInput(`trust invalid public key ${value}`,i=>{i.trust.publicKeyBase64=value;},'invalid-trust');
for(const which of ['catalogueID','keyID']){
 badInput(`trust mismatched ${which}`,i=>{i.trust[which]='different';},'untrusted-key');
 badInput(`trust invalid ${which}`,i=>{i.trust[which]='-invalid';},'invalid-trust');
}
badInput('envelope key mismatches payload',i=>{const e=JSON.parse(i.envelopeBytes);e.keyID='other-key';i.envelopeBytes=bytesOf(e);},'untrusted-key');
badPayload('signed catalogue mismatch',p=>{p.catalogueID='other-catalogue';},'untrusted-key');
badPayload('signed key mismatch',p=>{p.keyID='other-key';},'untrusted-key');
badInput('different valid length public key does not verify',i=>{i.trust.publicKeyBase64=Buffer.alloc(32,1).toString('base64');},'invalid-signature');
badInput('null previous requires explicit bootstrap',i=>{i.bootstrap=false;},'bootstrap-required');
badInput('bootstrap cannot replace previous',i=>{i.previous=checkpoint(payload());},'bootstrap-conflict');
for(const field of ['envelopeBytes','trust','context','previous','bootstrap'])badInput(`input missing ${field}`,i=>{delete i[field];},'invalid-input');
badInput('input unknown field',i=>{i.extra=true;},'invalid-input');
for(const value of [undefined,null,{},'true',1])badInput(`invalid bootstrap ${String(value)}`,i=>{i.bootstrap=value;},'invalid-input');
for(const value of [null,{},[],5,'json',new ArrayBuffer(5)])badInput(`invalid envelope byte type ${String(value)}`,i=>{i.envelopeBytes=value;},'invalid-input');
for(const value of [undefined,null,[],5,'input'])test(`invalid top input ${String(value)}`,()=>refuses(value,'invalid-input'));
for(const [field,value]of [['catalogueID','different'],['catalogueID','-bad'],['sequence',0],['sequence',1.5],['sequence',Number.MAX_SAFE_INTEGER+1],['payloadSHA256','A'.repeat(64)],['payloadSHA256','bad']])badInput(`history invalid ${field} ${value}`,i=>{i.previous=checkpoint(payload());i.bootstrap=false;i.previous[field]=value;},'invalid-history');
badInput('rollback refuses',i=>{i.previous={...checkpoint(payload()),sequence:3};i.bootstrap=false;},'rollback');
badInput('same sequence different hash refuses',i=>{i.previous={...checkpoint(payload()),payloadSHA256:'d'.repeat(64)};i.bootstrap=false;},'equivocation');
test('same exact bytes duplicate with unchanged checkpoint',()=>{const p=payload();const i=input(p);i.previous=checkpoint(p);i.bootstrap=false;const r=accepts(i,p,'duplicate');assert.deepEqual(r.checkpoint,i.previous);assert.notEqual(r.checkpoint,i.previous);r.checkpoint.sequence=99;assert.equal(i.previous.sequence,2);});
test('whitespace signed bytes at same sequence are equivocation',()=>{const i=input();i.envelopeBytes=readFixture('whitespace.envelope.json');i.previous=checkpoint(payload());i.bootstrap=false;refuses(i,'equivocation');});
test('higher sequence advances after full validation',()=>{const p=payload();const i=input(p);i.previous=checkpoint(emptyPayload());i.bootstrap=false;accepts(i,p);});
for(const defect of ['expired','retired','signature'])test(`duplicate still checks ${defect}`,()=>{const i=input();i.previous=checkpoint(payload());i.bootstrap=false;if(defect==='expired')i.context.now=1800003600;if(defect==='retired')i.trust.retired=true;if(defect==='signature'){const e=JSON.parse(i.envelopeBytes);e.signature=Buffer.alloc(64).toString('base64');i.envelopeBytes=bytesOf(e);}refuses(i,{expired:'invalid-time',retired:'retired-key',signature:'invalid-signature'}[defect]);});
test('outputs are deep copies and do not carry mutation across calls',()=>{const p=payload();const i=input(p);const r=accepts(i,p);r.catalogue.entries[0].artifact.byteLength=7;r.catalogue.entries.push({});r.checkpoint.sequence=99;accepts(i,p);assert.equal(p.entries[0].artifact.byteLength,1024);});
for(const field of ['trust','context'])test(`no accessor callback in ${field}`,()=>{const i=input();let called=false;Object.defineProperty(i[field],'extra',{enumerable:true,get(){called=true;throw Error('must not call');}});refuses(i,`invalid-${field}`);assert.equal(called,false);});
test('input accessor is refused without callback',()=>{const i=input();let called=false;Object.defineProperty(i,'bootstrap',{enumerable:true,get(){called=true;return true;}});refuses(i,'invalid-input');assert.equal(called,false);});

// Deterministic encoder is fixture-only and cannot authorise or sign.
test('encoder matches exact sorted golden payload bytes',()=>{const p=payload();const before=clone(p);assert.deepEqual(Buffer.from(encodePayload(p)),readFixture('one-entry.payload.json'));assert.deepEqual(p,before);const reversed=Object.fromEntries(Object.entries(p).reverse());assert.deepEqual(Buffer.from(encodePayload(reversed)),readFixture('one-entry.payload.json'));});
for(const value of [undefined,NaN,Infinity,()=>1])test(`encoder refuses non-JSON value ${String(value)}`,()=>{const p=payload();p.sequence=value;assert.throws(()=>encodePayload(p),TypeError);});
test('encoder rejects unsorted arrays rather than repairing identities',()=>{const p=payload();p.entries.push(clone(p.entries[0]));assert.throws(()=>encodePayload(p),TypeError);});
test('encoder rejects accessor without invoking callback',()=>{const p=payload();let called=false;Object.defineProperty(p,'sequence',{enumerable:true,get(){called=true;return 2;}});assert.throws(()=>encodePayload(p),TypeError);assert.equal(called,false);});
test('v1 sources checks fixtures and historical package bytes preserve exact reviewed shell additions',()=>{const manifest=JSON.parse(readFixture('frozen-v1-sha256.json'));assert.ok(Object.keys(manifest).length>=15);for(const [path,digest]of Object.entries(manifest)){const url=new URL('../../../'+path,import.meta.url);assert.equal((path==='Package.swift'?preservedPackageSHA256(readFileSync(url)):path==='Tests/PatchedOperatorTests/LiveCatalogueProof.swift'?preservedUnstapledLiveProofSHA256(path,preservedPinnedSignatureLiveProofBytes(path,readFileSync(url))):['Sources/PatchedCore/CatalogueVerifier.swift','Sources/PatchedOperator/CatalogueSigning.swift','Tests/PatchedCoreChecks/CatalogueChecks.swift','Tests/PatchedCoreChecks/main.swift'].includes(path)?preservedArtifactSizeSHA256(path,readFileSync(url)):sha256(readFileSync(url))),digest,path);}});
test('descriptive schema closes payload envelope and entry shapes',()=>{const schema=JSON.parse(readFileSync(new URL('../protocol/catalogue-v2.schema.json',import.meta.url)));assert.equal(schema.$schema,'https://json-schema.org/draft/2020-12/schema');for(const name of ['envelope','payload','entry','identity','release','compatibility','source','artifact','evidence','installer','withdrawal']){assert.equal(schema.$defs[name].additionalProperties,false,name);assert.deepEqual([...schema.$defs[name].required].sort(),Object.keys(schema.$defs[name].properties).sort(),name);}});

for(const prefix of ['im.patched.catalogue.v2','im.patched.catalogue.v1\0','im.patched.catalogue.v2\0\0'])test(`signature refuses wrong domain separator ${JSON.stringify(prefix)}`,()=>{const b=bytesOf(payload());const e=envelopeFor(b);e.signature=signRawFixtureMessage(Buffer.concat([Buffer.from(prefix),b])).toString('base64');const i=input();i.envelopeBytes=bytesOf(e);refuses(i,'invalid-signature');});
positive('UInt32 and eight-component release limit',p=>{p.entries[0].release.version='4294967295.0.1.2.3.4.5.6';});
positive('zero-valued version components',p=>{p.entries[0].release.version='0.0';});
positive('source and evidence observed exactly at issue',p=>{p.entries[0].source.observedAt=p.issuedAt;p.entries[0].evidence.verifiedAt=p.issuedAt;});
positive('exact72 hour evidence validity',p=>{p.entries[0].evidence.validUntil=p.entries[0].evidence.verifiedAt+259200;});
for(const length of [253,254])test(`DNS hostname byte boundary ${length}`,()=>{const host=['a'.repeat(63),'b'.repeat(63),'c'.repeat(63),'d'.repeat(length-192)].join('.');assert.equal(host.length,length);const p=payload();p.entries[0].source.url=`https://${host}/`;length===253?accepts(input(p),p):refuses(input(p),'invalid-payload');});
for(const length of [253,254])test(`redirect hostname byte boundary ${length}`,()=>{const host=['a'.repeat(63),'b'.repeat(63),'c'.repeat(63),'d'.repeat(length-192)].join('.');const p=payload();p.entries[0].source.redirectHosts=[host];length===253?accepts(input(p),p):refuses(input(p),'invalid-payload');});
for(const length of [255,256])test(`bundleID byte boundary ${length}`,()=>{const p=payload();p.entries[0].identity.bundleID='a.'+'b'.repeat(length-2);length===255?accepts(input(p),p):refuses(input(p),'invalid-payload');});
for(const length of [2048,2049])test(`URL UTF8 bytes rather than characters ${length}`,()=>{const p=payload();p.entries[0].source.url='https://example.test/'+ 'é'.repeat(1000)+'x'.repeat(length-2021);assert.equal(Buffer.byteLength(p.entries[0].source.url),length);length===2048?accepts(input(p),p):refuses(input(p),'invalid-payload');});
for(const pth of ['trust','context'])test(`${pth} symbol field refuses`,()=>{const i=input();i[pth][Symbol('extra')]=1;refuses(i,`invalid-${pth}`);});
test('custom input prototype refuses',()=>{const i=input();Object.setPrototypeOf(i,{extension:true});refuses(i,'invalid-input');});
test('null-prototype input records work',()=>{const p=payload();const i=input(p);i.trust=Object.assign(Object.create(null),i.trust);i.context=Object.assign(Object.create(null),i.context);const r=verifyCatalogue(Object.assign(Object.create(null),i));authority(r);assert.equal(r.status,'verified');assert.deepEqual(r.catalogue,p);});
test('safe integer decoded exponent notation refuses',()=>{const p=payload();const raw=bytesOf(p).toString().replace('"sequence":2','"sequence":2e0');const i=input(p);i.envelopeBytes=wrap(Buffer.from(raw));refuses(i,'invalid-payload');});
test('nonfinite signed JSON refuses before schema coercion',()=>{const i=input();i.envelopeBytes=wrap(Buffer.from(bytesOf(payload()).toString().replace('"sequence":2','"sequence":1e309')));refuses(i,'invalid-payload');});
test('zero timestamps are structurally allowed with a live injected now',()=>{const p=emptyPayload();p.issuedAt=0;p.expiresAt=1;const i=input(p);i.context.now=0;accepts(i,p);});
test('array order retained by encoder',()=>{const p=payload();const e=clone(p.entries[0]);e.identity.releaseID='release-0002';p.entries.push(e);const result=JSON.parse(Buffer.from(encodePayload(p)));assert.deepEqual(result.entries.map(e=>e.identity.releaseID),['release-0001','release-0002']);});
for(const token of ['-0','-1','1.0','1e0','1E0','1e+0','1e-0','1.00000000000000001','9007199254740991.1','9007199254740993','0.00000000000000001','01']){
 test(`strict numeric token refuses ${token}`,()=>assert.throws(()=>parseStrictJSON(Buffer.from(`{"x":${token}}`),{maximumBytes:1024,maximumDepth:16}),SyntaxError));
 test(`signed rounded/noninteger token refuses ${token}`,()=>{const i=input();i.envelopeBytes=wrap(Buffer.from(bytesOf(payload()).toString().replace('"sequence":2',`"sequence":${token}`)));refuses(i,'invalid-payload');});
}

test('Node independently verifies Swift signatures and rejects key/domain/tamper',()=>{
 const output=JSON.parse(readFileSync(new URL('../../../.build/catalogue-protocol-swift-vectors.json',import.meta.url)));
 const corpus=JSON.parse(readFixture('golden-vectors.json'));
 assert.deepEqual(output.map(v=>v.name),corpus.vectors.map(v=>v.name));
 const publicKey=raw=>createPublicKey({key:Buffer.concat([Buffer.from('302a300506032b6570032100','hex'),raw]),format:'der',type:'spki'});
 const correct=publicKey(Buffer.from(key.publicKeyBase64,'base64'));
 const incorrect=publicKey(Buffer.alloc(32,1));
 for(const v of output){
  const golden=corpus.vectors.find(g=>g.name===v.name);
  assert.equal(v.publicKeyBase64,key.publicKeyBase64);assert.equal(v.messageBase64,golden.messageBase64);
  const msg=Buffer.from(v.messageBase64,'base64'),sig=Buffer.from(v.signatureBase64,'base64');assert.equal(sig.length,64);
  assert.equal(verify(null,msg,correct,sig),true,`${v.name} Swift signature`);
  assert.equal(verify(null,msg,incorrect,sig),false,`${v.name} wrong key`);
  assert.equal(verify(null,readFixture(golden.payloadFile),correct,sig),false,`${v.name} wrong domain`);
  assert.equal(verify(null,Buffer.concat([msg,Buffer.from(' ')]),correct,sig),false,`${v.name} tamper`);
 }
});

test('public key nonzero base64 padding bits refuse',()=>{const i=input();const original=i.trust.publicKeyBase64;const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';const pos=original.length-2;i.trust.publicKeyBase64=original.slice(0,pos)+alphabet[alphabet.indexOf(original[pos])+1]+original.slice(pos+1);assert.deepEqual(Buffer.from(i.trust.publicKeyBase64,'base64'),Buffer.from(original,'base64'));refuses(i,'invalid-trust');});
test('payload nonzero base64 padding bits refuse without changing decoded bytes',()=>{let b=bytesOf(emptyPayload());while(b.length%3!==1)b=Buffer.concat([b,Buffer.from(' ')]);const e=envelopeFor(b);const original=e.payload;const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';const pos=original.length-3;e.payload=original.slice(0,pos)+alphabet[alphabet.indexOf(original[pos])+1]+original.slice(pos+1);assert.deepEqual(Buffer.from(e.payload,'base64'),b);const i=input();i.envelopeBytes=bytesOf(e);refuses(i,'invalid-envelope');});
