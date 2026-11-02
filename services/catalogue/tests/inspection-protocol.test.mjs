import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { decodeJobV2, encodeJobV2 } from '../protocol/job-v2.mjs';
import { decodeEvidenceV2, encodeEvidenceV2, compareEvidenceBinding } from '../protocol/evidence-v2.mjs';

// All fake producers below are check-only and independent of the modules under test.
// Golden UTF8 and hashes are literals in expected.json, never recomputed expectations.
const fixture = name => readFileSync(new URL(`../protocol/fixtures/inspection-v2/${name}`, import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const wire = value => Buffer.from(JSON.stringify(value));
const clone = value => structuredClone(value);
const typedPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const intrinsic = Object.fromEntries(['buffer','byteOffset','byteLength'].map(key => [key,Object.getOwnPropertyDescriptor(typedPrototype,key).get]));
// Test snapshots must also bypass deliberately poisoned byte accessors.
const snapshotBytes = bytes => Buffer.from(new Uint8Array(intrinsic.buffer.call(bytes), intrinsic.byteOffset.call(bytes), intrinsic.byteLength.call(bytes)));
const emptySHA = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const flags = {
  scope: 'fixture-only', authenticated: false, policyAccepted: false,
  freshOSValidation: false, publicationAllowed: false, installationAllowed: false,
};
const ids = ['codesign-integrity', 'codesign-identity', 'gatekeeper', 'notarisation', 'container-integrity', 'cleanup'];
const at = (record, path) => path ? path.split('.').reduce((value, key) => value[key], record) : record;
const set = (record, path, value) => {
  const keys = path.split('.'); const last = keys.pop(); at(record, keys.join('.'))[last] = value;
};
const job = () => JSON.parse(fixture('job.json'));
const evidence = () => JSON.parse(fixture('evidence.json'));
const kinds = [
  { name: 'job', make: job, decode: decodeJobV2, encode: encodeJobV2, key: 'job', reason: 'invalid-job' },
  { name: 'evidence', make: evidence, decode: decodeEvidenceV2, encode: encodeEvidenceV2, key: 'report', reason: 'invalid-evidence' },
];
function authority(result, keys) {
  assert.deepEqual(Object.keys(result).sort(), [...keys, ...Object.keys(flags)].sort());
  for (const [key, expected] of Object.entries(flags)) assert.equal(result[key], expected, key);
}
function accepts(kind, bytes, expected = JSON.parse(Buffer.from(bytes).toString())) {
  const snapshot = snapshotBytes(bytes); const result = kind.decode(bytes);
  // Phase A deliberately fails here, not at import, syntax or fixture loading.
  assert.equal(result.status, 'valid');
  authority(result, ['status', kind.key, 'byteDigest']);
  assert.deepEqual(result[kind.key], expected);
  assert.equal(result.byteDigest, hash(snapshot));
  assert.deepEqual(snapshotBytes(bytes), snapshot, 'input bytes unchanged');
  return result;
}
function encoded(kind, record) {
  const result = kind.encode(record);
  assert.equal(result.status, 'encoded');
  authority(result, ['status', 'bytes', 'byteDigest']);
  assert.ok(result.bytes instanceof Uint8Array);
  assert.equal(result.byteDigest, hash(result.bytes));
  return result;
}
function refuses(kind, bytes) {
  const result = kind.decode(bytes);
  assert.equal(result.status, 'invalid'); assert.equal(result.reason, kind.reason);
  authority(result, ['status', 'reason']);
}
function encodeRefuses(kind, record) {
  const result = kind.encode(record);
  assert.equal(result.status, 'refused'); assert.equal(result.reason, kind.reason);
  authority(result, ['status', 'reason']);
}
const good = (kind, name, mutate) => test(`${kind.name} accepts ${name}`, () => {
  const value = kind.make(); mutate(value); accepts(kind, wire(value), value); encoded(kind, value);
});
const bad = (kind, name, mutate) => test(`${kind.name} refuses ${name}`, () => {
  const value = kind.make(); mutate(value); refuses(kind, wire(value)); encodeRefuses(kind, value);
});
function invalid(kind, path, values) {
  for (const [i, value] of values.entries()) bad(kind, `${path} invalid case ${i} ${JSON.stringify(value)}`, record => set(record, path, value));
}
function match(jobBytes, reportBytes) {
  const result = compareEvidenceBinding(jobBytes, reportBytes);
  assert.equal(result.status, 'matched'); authority(result, ['status']); return result;
}
function mismatch(jobBytes, reportBytes) {
  const result = compareEvidenceBinding(jobBytes, reportBytes);
  assert.equal(result.status, 'refused'); assert.equal(result.reason, 'binding-mismatch');
  authority(result, ['status', 'reason']);
}
function rebind(jobBytes, report = evidence()) {
  report.jobDescriptorSHA256 = hash(jobBytes); return wire(report);
}
const vectors = JSON.parse(fixture('expected.json')).vectors;
for (const kind of kinds) {
  const vector = vectors.find(v => v.name === kind.name);
  test(`${kind.name} independent literal fixture integrity`, () => {
    const raw = fixture(vector.file);
    assert.equal(raw.length, vector.byteLength); assert.equal(hash(raw), vector.sha256);
    assert.equal(raw.toString('utf8'), vector.encodedUTF8);
    assert.deepEqual(JSON.parse(vector.encodedUTF8), kind.make());
  });
  test(`${kind.name} golden decode`, () => accepts(kind, fixture(vector.file)));
  test(`${kind.name} golden deterministic compact encoding`, () => {
    const value = kind.make(); const original = clone(value);
    const result = encoded(kind, value);
    assert.equal(Buffer.from(result.bytes).toString('utf8'), vector.encodedUTF8);
    assert.equal(result.byteDigest, vector.sha256);
    assert.deepEqual(value, original);
    accepts(kind, result.bytes, original);
  });
  test(`${kind.name} deterministic encoding ignores object insertion order`, () => {
    const reverse = value => Array.isArray(value) ? value.map(reverse) : value && typeof value === 'object'
      ? Object.fromEntries(Object.entries(value).reverse().map(([k, v]) => [k, reverse(v)])) : value;
    const result = encoded(kind, reverse(kind.make()));
    assert.equal(Buffer.from(result.bytes).toString(), vector.encodedUTF8);
  });
  test(`${kind.name} decoded records and encoded bytes are independently owned`, () => {
    const raw = fixture(vector.file); const a = accepts(kind, raw); const b = accepts(kind, raw);
    assert.notStrictEqual(a[kind.key], b[kind.key]); assert.notStrictEqual(a[kind.key].artifact, b[kind.key].artifact);
    a[kind.key].artifact.length = 999; assert.equal(b[kind.key].artifact.length, 12345);
    if (kind.name === 'evidence') {
      assert.notStrictEqual(a.report.observations, b.report.observations);
      a.report.observations[0].stdout.length = 33; assert.equal(b.report.observations[0].stdout.length, 0);
    }
    const value = kind.make(); const x = encoded(kind, value); const y = encoded(kind, value);
    assert.notStrictEqual(x.bytes, y.bytes); x.bytes.fill(0);
    assert.equal(Buffer.from(y.bytes).toString(), vector.encodedUTF8);
    value.artifact.length = 44; assert.equal(Buffer.from(y.bytes).toString(), vector.encodedUTF8);
    raw.fill(0); assert.equal(b[kind.key].artifact.length, 12345);
  });
  test(`${kind.name} null-prototype/frozen data records accepted`, () => {
    const nullRecords = value => Array.isArray(value) ? value.map(nullRecords) : value && typeof value === 'object'
      ? Object.assign(Object.create(null), Object.fromEntries(Object.entries(value).map(([k,v]) => [k,nullRecords(v)]))) : value;
    const value = nullRecords(kind.make()); Object.freeze(value); Object.freeze(value.artifact);
    assert.equal(Buffer.from(encoded(kind, value).bytes).toString(), vector.encodedUTF8);
  });
}

// Every record boundary is closed, and every declared field is required.
function recordPaths(value, path = '') {
  if (!value || typeof value !== 'object') return [];
  return [...(Array.isArray(value) ? [] : [path]), ...Object.entries(value).flatMap(([k,v]) => recordPaths(v, path ? `${path}.${k}` : k))];
}
const prohibited = ['extra', '__proto__', 'constructor', 'toJSON', 'command', 'args', 'script', 'path', 'bucket', 'key', 'lease', 'token', 'authenticated', 'policyAccepted', 'freshOSValidation', 'publicationAllowed', 'installationAllowed', 'approved', 'notarised', 'verdict', 'outputBytes'];
for (const kind of kinds) {
  for (const path of recordPaths(kind.make())) {
    for (const key of Object.keys(at(kind.make(), path))) bad(kind, `required ${path || 'root'}.${key}`, record => { delete at(record, path)[key]; });
    for (const key of prohibited) bad(kind, `closed ${path || 'root'}.${key}`, record => {
      Object.defineProperty(at(record, path), key, { value: true, enumerable: true });
    });
    if (path) invalid(kind, path, [null, [], '', true, 1]);
  }
  for (const value of [null, [], '', 1, true, false]) test(`${kind.name} invalid root ${JSON.stringify(value)}`, () => {
    refuses(kind, wire(value)); encodeRefuses(kind, value);
  });
  invalid(kind, 'schema', [1, 3, '2', null, true, {}, []]);
  invalid(kind, 'kind', ['', 'inspection', kind.name === 'job' ? 'inspection-observations' : 'inspection-job', null, 2, true]);
  invalid(kind, 'architecture', ['', 'ARM64', 'universal', 'amd64', null, 1, {}, []]);
  good(kind, 'x86_64 architecture', r => { r.architecture = 'x86_64'; });
  invalid(kind, 'jobID', ['', 'a'.repeat(36), '01234567-89AB-cdef-0123-456789abcdef', '01234567-89ab-cdef-0123-456789abcdeg', '{01234567-89ab-cdef-0123-456789abcdef}', null, 1]);
  good(kind, 'UUID has no version/variant authority', r => { r.jobID = '00000000-0000-0000-0000-000000000000'; });
  const identifiers = ['routeID', 'policyVersion', 'checkerVersion', ...(kind.name === 'evidence' ? ['osVersion','osBuild'] : [])];
  for (const path of identifiers) {
    invalid(kind, path, ['', '-a', '_a', '.a', 'a/b', 'a b', 'a'.repeat(65), null, true, 3, [], {}]);
    good(kind, `${path} length one`, r => set(r, path, '0'));
    good(kind, `${path} length 64 and permitted punctuation`, r => set(r, path, `A${'a'.repeat(59)}._-9`));
    for (const value of ['a\u0000b','a\u001fb','a\u007fb','a\u0085b','a\u00a0b','a\u200bb','a\u202eb','a\u2066b','a\ufeffb','a\ud800','a\udfffb','é','🧪']) invalid(kind, path, [value]);
  }
  for (const path of ['routeDigest','policyDigest','artifact.sha256', ...(kind.name === 'evidence' ? ['jobDescriptorSHA256', ...ids.flatMap((_, i) => [`observations.${i}.stdout.sha256`,`observations.${i}.stderr.sha256`])] : [])]) {
    invalid(kind, path, ['', 'a'.repeat(63), 'a'.repeat(65), 'A'.repeat(64), 'g'.repeat(64), null, 1, [], {}]);
  }
  invalid(kind, 'checkerSourceSHA', ['', 'a'.repeat(39), 'a'.repeat(41), 'A'.repeat(40), 'g'.repeat(40), null, 1, [], {}]);
}

// Integers are exact lexical tokens on decode, not values rounded by JSON.parse.
for (const kind of kinds) {
  const integers = [['artifact.length',1,1099511627776], ...(kind.name === 'evidence' ? [
    ['startedAt',0,Number.MAX_SAFE_INTEGER], ['finishedAt',0,Number.MAX_SAFE_INTEGER],
    ...ids.flatMap((_, i) => [[`observations.${i}.stdout.length`,0,1048576],[`observations.${i}.stderr.length`,0,1048576]]),
  ] : [])];
  for (const [path,min,max] of integers) {
    invalid(kind, path, [-1, min ? 0 : -2, max + 1, 1.5, true, null, '1', {}, []]);
    for (const value of [-0, NaN, Infinity, -Infinity, 1n, undefined]) test(`${kind.name} ${path} non-JSON encoder ${String(value)}`, () => {
      const record = kind.make(); set(record,path,value); encodeRefuses(kind,record);
    });
    for (const token of ['-0','-1','1.0','1e0','1E+0','0.0000000000000000001','1.00000000000000001','9007199254740993','01','+1','NaN','Infinity']) test(`${kind.name} ${path} lexical ${token}`, () => {
      const record=kind.make(); set(record,path,'RAW_INTEGER_TOKEN');
      refuses(kind,Buffer.from(JSON.stringify(record).replace('"RAW_INTEGER_TOKEN"',token)));
    });
  }
  good(kind, 'artifact minimum length', r => { r.artifact.length=1; });
  good(kind, 'artifact maximum length', r => { r.artifact.length=1099511627776; });
}
const E = kinds[1];
good(E, 'zero equal times', r => { r.startedAt=r.finishedAt=0; });
good(E, 'maximum safe equal times', r => { r.startedAt=r.finishedAt=Number.MAX_SAFE_INTEGER; });
good(E, 'maximum duration', r => { r.finishedAt=r.startedAt+86400; });
bad(E, 'negative duration', r => { r.finishedAt=r.startedAt-1; });
bad(E, 'duration exceeds 86400', r => { r.finishedAt=r.startedAt+86401; });
invalid(E, 'observations', [null, {}, '', true, 6, []]);
bad(E, 'five observations', r => { r.observations.pop(); });
bad(E, 'seven observations', r => { r.observations.push(clone(r.observations[0])); });
bad(E, 'reordered observations', r => { r.observations.reverse(); });
for (let i=0;i<6;i++) {
  const p=`observations.${i}`;
  invalid(E,`${p}.checkID`,['', 'arbitrary-command', ids[(i+1)%6], null, 1]);
  invalid(E,`${p}.outcome`,['', 'passed', 'approved', 'failed', null, true, 0]);
  for(const [field,values] of [['exitCode',[-1,256,1.5,true,'0',{},[]]],['signal',[0,-1,65,1.5,true,'1',{},[]]]]) {
    for(const value of values) bad(E,`${p}.${field} invalid ${JSON.stringify(value)}`,r=>{r.observations[i].outcome='completed';r.observations[i].exitCode=null;r.observations[i].signal=null;r.observations[i][field]=value;});
    for(const token of ['-0','1.0','1e0','9007199254740993']) test(`${p}.${field} raw ${token}`,()=>{
      const r=evidence();r.observations[i].outcome='completed';r.observations[i].exitCode=null;r.observations[i].signal=null;r.observations[i][field]='RAW_INTEGER_TOKEN';
      refuses(E,Buffer.from(JSON.stringify(r).replace('"RAW_INTEGER_TOKEN"',token)));
    });
    for(const value of [-0,NaN,Infinity,1n,undefined]) test(`${p}.${field} encoder non-JSON ${String(value)}`,()=>{
      const r=evidence();r.observations[i][field]=value;encodeRefuses(E,r);
    });
  }
  for(const code of [0,1,255]) good(E,`${p} completed exit ${code}`,r=>{r.observations[i].outcome='completed';r.observations[i].exitCode=code;r.observations[i].signal=null;});
  for(const signal of [1,15,64]) good(E,`${p} completed signal ${signal}`,r=>{r.observations[i].outcome='completed';r.observations[i].exitCode=null;r.observations[i].signal=signal;});
  bad(E,`${p} completed no termination`,r=>{r.observations[i].outcome='completed';r.observations[i].exitCode=r.observations[i].signal=null;});
  bad(E,`${p} completed two terminations`,r=>{r.observations[i].outcome='completed';r.observations[i].exitCode=0;r.observations[i].signal=15;});
  good(E,`${p} unavailable preserved`,r=>{r.observations[i]={checkID:ids[i],outcome:'unavailable',exitCode:null,signal:null,stdout:{sha256:emptySHA,length:0},stderr:{sha256:emptySHA,length:0}};});
  for(const field of ['exitCode','signal','stdout','stderr']) bad(E,`${p} unavailable populated ${field}`,r=>{
    r.observations[i]={checkID:ids[i],outcome:'unavailable',exitCode:null,signal:null,stdout:{sha256:emptySHA,length:0},stderr:{sha256:emptySHA,length:0}};
    r.observations[i][field]=field==='exitCode'?0:field==='signal'?1:{sha256:'a'.repeat(64),length:1};
  });
  for(const output of ['stdout','stderr']) {
    bad(E,`${p}.${output} zero length inconsistent SHA`,r=>{r.observations[i][output]={sha256:'a'.repeat(64),length:0};});
    good(E,`${p}.${output} maximum bounded unverified output`,r=>{r.observations[i].outcome='completed';r.observations[i].exitCode=1;r.observations[i].signal=null;r.observations[i][output]={sha256:'a'.repeat(64),length:1048576};});
  }
}
good(E,'all six unavailable remain observations',r=>{r.observations=r.observations.map(o=>({checkID:o.checkID,outcome:'unavailable',exitCode:null,signal:null,stdout:{sha256:emptySHA,length:0},stderr:{sha256:emptySHA,length:0}}));});
good(E,'all six exit zero confer no trust',r=>{r.observations.forEach(o=>{o.outcome='completed';o.exitCode=0;o.signal=null;});});

// URL validation is local syntax only. No network or source/redirect approval.
const badURLs = [
  '', 'http://example.test/a', 'HTTPS://example.test/a', '//example.test/a',
  'https://', 'https:///a', 'https://user@example.test/a', 'https://user:pass@example.test/a',
  'https://example.test:80/a', 'https://example.test:0443/a', 'https://example.test:/a',
  'https://example.test/a?x=1', 'https://example.test/a#part', 'https://example.test?', 'https://example.test#',
  'https://example.test./a', 'https://.example.test/a', 'https://example..test/a',
  'https://-example.test/a', 'https://example-.test/a', 'https://exa_mple.test/a',
  'https://éxample.test/a', 'https://example.test/é', 'https://example.test/a b',
  ' https://example.test/a', 'https://example.test/a\n', 'https://example.test/\\a',
  'https://example.test/\u0000', 'https://example.test/\u007f', 'https://example.test/\u00a0',
  'https://example.test/\u200b', 'https://example.test/\u202e', 'https://example.test/\ud800',
  'https://example.test/.', 'https://example.test/..', 'https://example.test/a/../b',
  'https://example.test/%2e', 'https://example.test/.%2E', 'https://example.test/%2e.',
  'https://example.test/%2E%2e/', 'https://example.test/a/%2e/b',
  'https://example.test/%', 'https://example.test/%2', 'https://example.test/%gg',
  'https://127.0.0.1/a', 'https://[::1]/a', 'https://[2001:db8::1]/a',
  'https://127.1/a', 'https://2130706433/a', 'https://0177.0.0.1/a', 'https://0x7f000001/a',
  'https://0x7f.1/a', 'https://0/a',
  `https://${'a'.repeat(64)}.test/a`, `https://${['a'.repeat(63),'b'.repeat(63),'c'.repeat(63),'d'.repeat(62)].join('.')}/a`,
  `https://example.test/${'a'.repeat(2049-21)}`, null, 1, true, [], {},
];
const goodURLs = [
  'https://example.test', 'https://example.test/', 'https://EXAMPLE.test:443/a',
  'https://localhost/a', 'https://a', 'https://a-b.example/a', 'https://xn--example.test/a',
  'https://example.test//a///b', 'https://example.test/a%20b', 'https://example.test/%7e/%7E',
  'https://example.test/..a/.../%2efoo', 'https://example.test/%252e/%2f/%5C/%00',
  `https://${'a'.repeat(63)}.test/a`, `https://${['a'.repeat(63),'b'.repeat(63),'c'.repeat(63),'d'.repeat(61)].join('.')}/a`,
  `https://example.test/${'a'.repeat(2048-21)}`,
];
for(const kind of kinds) {
  const path=kind.name==='job'?'sourceURL':'finalSourceURL';
  invalid(kind,path,badURLs);
  for(const [i,url] of goodURLs.entries()) good(kind,`${path} exact spelling ${i}`,r=>set(r,path,url));
  test(`${kind.name} exact 2048 byte URL retained`,()=>{
    const r=kind.make(); const u=`https://example.test/${'x'.repeat(2048-'https://example.test/'.length)}`;
    assert.equal(Buffer.byteLength(u),2048);set(r,path,u);accepts(kind,wire(r),r);encoded(kind,r);
  });
  bad(kind,`${path} 2049 byte URL`,r=>set(r,path,`https://example.test/${'x'.repeat(2049-'https://example.test/'.length)}`));
}

// Strict JSON and exact raw byte bounds. A valid bounded object plus ordinary
// JSON whitespace exercises the inclusive 64KiB limit without unknown fields.
for(const kind of kinds) {
  for(const count of [65535,65536]) test(`${kind.name} valid JSON at ${count} byte boundary`,()=>{
    const raw=fixture(`${kind.name}.json`);const padded=Buffer.concat([Buffer.from(' \n\t'),raw,Buffer.alloc(count-raw.length-3,32)]);
    assert.equal(padded.length,count);assert.deepEqual(JSON.parse(padded),kind.make());accepts(kind,padded,kind.make());
  });
  test(`${kind.name} 65537 bytes of otherwise valid JSON refused`,()=>{
    const raw=fixture(`${kind.name}.json`);const padded=Buffer.concat([raw,Buffer.alloc(65537-raw.length,32)]);
    assert.equal(padded.length,65537);assert.deepEqual(JSON.parse(padded),kind.make());refuses(kind,padded);
  });
  test(`${kind.name} raw whitespace has distinct exact digest`,()=>{
    const raw=fixture(`${kind.name}.json`);const padded=Buffer.concat([Buffer.from('\n '),raw,Buffer.from('\t\r\n')]);
    const a=accepts(kind,raw);const b=accepts(kind,padded);assert.notEqual(a.byteDigest,b.byteDigest);assert.deepEqual(a[kind.key],b[kind.key]);
  });
  const raw=fixture(`${kind.name}.json`).toString();
  const invalidWires=[
    '', ' ', '{', 'null', '[]', `${raw}true`, `${raw},`, `\ufeff${raw}`,
    raw.replace('"schema":2','"schema":2,"schema":2'),
    raw.replace('"schema":2','"schema":2,"\\u0073chema":2'),
    raw.replace('"artifact":{','"artifact":{"sha256":"'+'a'.repeat(64)+'",'),
    raw.replace('"routeID":','"unknown":null,"routeID":'),
    raw.replace('"routeID":','"__proto__":{},"routeID":'),
    raw.replace('"routeID":"fixture.route-1"','"routeID":"\\ud800"'),
    raw.replace('"routeID":"fixture.route-1"','"routeID":"\\udfff"'),
    raw.replace('"routeID":"fixture.route-1"','"routeID":"raw\nnewline"'),
    raw.replace('"routeID":"fixture.route-1"','"routeID":"\\x41"'),
    raw.replace('"schema":2','"schema":2,'),
    raw.replace('"artifact":{',`"artifact":${'['.repeat(17)}0${']'.repeat(17)},"unused":{`),
  ];
  for(const [i,value] of invalidWires.entries())test(`${kind.name} strict JSON rejection ${i}`,()=>refuses(kind,Buffer.from(value)));
  for(const value of [Buffer.from([0xc0,0xaf]),Buffer.from([0xed,0xa0,0x80]),Buffer.from([0xff]),Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),Buffer.from(raw)])])test(`${kind.name} strict UTF8 ${value.toString('hex').slice(0,16)}`,()=>refuses(kind,value));
  test(`${kind.name} escaped ordinary string and key forms accepted`,()=>{
    const escaped=Buffer.from(raw.replace('"schema"','"\\u0073chema"').replace('fixture.route-1','fixture\\u002eroute-1'));
    accepts(kind,escaped,kind.make());
  });
  if(kind.name==='evidence')test('evidence duplicate output descriptor key refused',()=>{
    refuses(kind,Buffer.from(raw.replace('"stdout":{','"stdout":{"length":0,')));
  });
}

// Hostile caller object and byte storage checks. A refusal must not execute
// arbitrary getters, conversion methods, Proxy traps or typed-array overrides.
const trapNames=['get','set','has','ownKeys','getPrototypeOf','getOwnPropertyDescriptor','defineProperty','deleteProperty','isExtensible','preventExtensions','setPrototypeOf'];
function hostileProxy(target,counter) {
  return new Proxy(target,Object.fromEntries(trapNames.map(name=>[name,()=>{counter.calls++;throw new Error(`Proxy trap ${name}`);}])));
}
for(const kind of kinds) {
  for(const value of [undefined,null,'{}',new ArrayBuffer(4),new DataView(new ArrayBuffer(4)),new Uint16Array([1]),new Int8Array([1]),new Uint8ClampedArray([1]),[1,2],{},1,1n,()=>{}])test(`${kind.name} refuses nonbyte ${Object.prototype.toString.call(value)}`,()=>refuses(kind,value));
  test(`${kind.name} detached byte buffer refuses`,()=>{
    const bytes=Uint8Array.from(fixture(`${kind.name}.json`));structuredClone(bytes.buffer,{transfer:[bytes.buffer]});refuses(kind,bytes);
  });
  test(`${kind.name} shared backing refuses`,()=>{
    const bytes=new Uint8Array(new SharedArrayBuffer(65536));bytes.set(fixture(`${kind.name}.json`));refuses(kind,bytes);
    refuses(kind,Buffer.from(new SharedArrayBuffer(16)));
  });
  test(`${kind.name} Proxy/revoked byte callers refuse without traps`,()=>{
    const counter={calls:0};refuses(kind,hostileProxy(Uint8Array.from(fixture(`${kind.name}.json`)),counter));
    const revoked=Proxy.revocable(new Uint8Array(0),{});revoked.revoke();refuses(kind,revoked.proxy);assert.equal(counter.calls,0);
  });
  test(`${kind.name} byte subview includes no outside backing bytes`,()=>{
    const raw=fixture(`${kind.name}.json`);const backing=Buffer.concat([Buffer.from('NOT JSON'),raw,Buffer.from('TRAILING GARBAGE')]);
    accepts(kind,new Uint8Array(backing.buffer,backing.byteOffset+8,raw.length),kind.make());
  });
  test(`${kind.name} poisoned byte subclass uses intrinsic copy`,()=>{
    let calls=0;const fail=()=>{calls++;throw new Error('byte callback');};
    class Bytes extends Uint8Array { static get [Symbol.species]() { return fail(); } }
    const bytes=new Bytes(fixture(`${kind.name}.json`));
    for(const key of ['buffer','byteOffset','byteLength','length','constructor','slice','subarray','values',Symbol.iterator,Symbol.toStringTag])Object.defineProperty(bytes,key,{get:fail});
    accepts(kind,bytes,kind.make());assert.equal(calls,0);
  });
  for(const path of recordPaths(kind.make())) {
    for(const form of ['getter','nonenumerable','symbol','class','proxy','cycle','toJSON'])test(`${kind.name} encoder ${path||'root'} rejects ${form} without callbacks`,()=>{
      const record=kind.make();let calls=0;const fail=()=>{calls++;throw new Error('caller callback');};const target=at(record,path);
      let replacement=target;
      if(form==='getter') {const key=Object.keys(target)[0];Object.defineProperty(target,key,{get:fail,enumerable:true,configurable:true});}
      if(form==='nonenumerable')Object.defineProperty(target,Object.keys(target)[0],{enumerable:false});
      if(form==='symbol')target[Symbol('hidden')]=1;
      if(form==='class') {class Record {} replacement=Object.assign(new Record(),target);}
      if(form==='proxy')replacement=new Proxy(target,Object.fromEntries(trapNames.map(name=>[name,fail])));
      if(form==='cycle')target.extra=record;
      if(form==='toJSON')target.toJSON=fail;
      if(path)set(record,path,replacement);
      encodeRefuses(kind,path?record:replacement);assert.equal(calls,0);
    });
  }
  test(`${kind.name} revoked record Proxy returns typed refusal`,()=>{
    const {proxy,revoke}=Proxy.revocable(kind.make(),{});revoke();encodeRefuses(kind,proxy);
  });
  test(`${kind.name} coercion-bearing field refused without callbacks`,()=>{
    let calls=0;const r=kind.make();r.routeID={toString(){calls++;throw new Error('coercion');},[Symbol.toPrimitive](){calls++;throw new Error('coercion');}};
    encodeRefuses(kind,r);assert.equal(calls,0);
  });
}
for(const form of ['hole','extra','symbol','getter','nonenumerable','subclass','prototype','proxy','cycle','huge'])test(`evidence observations array rejects ${form} without callbacks`,()=>{
  const r=evidence();let calls=0;const fail=()=>{calls++;throw new Error('array callback');};
  if(form==='hole')delete r.observations[2];
  if(form==='extra')r.observations.extra=1;
  if(form==='symbol')r.observations[Symbol('hidden')]=1;
  if(form==='getter')Object.defineProperty(r.observations,'2',{get:fail});
  if(form==='nonenumerable')Object.defineProperty(r.observations,'2',{enumerable:false});
  if(form==='subclass'){class Observations extends Array {}r.observations=Observations.from(r.observations);}
  if(form==='prototype')Object.setPrototypeOf(r.observations,null);
  if(form==='proxy')r.observations=new Proxy(r.observations,Object.fromEntries(trapNames.map(name=>[name,fail])));
  if(form==='cycle')r.observations[0]=r.observations;
  if(form==='huge')r.observations.length=4294967295;
  encodeRefuses(E,r);assert.equal(calls,0);
});

// Exact-byte binding compares every declared matching field separately. A
// syntactically valid unsigned observation still establishes no provenance.
test('golden job and report bind without authority',()=>match(fixture('job.json'),fixture('evidence.json')));
test('binding accepts Buffer/Uint8Array mixtures without mutation',()=>{
  const j=Uint8Array.from(fixture('job.json'));const e=fixture('evidence.json');const beforeJ=clone(j);const beforeE=Uint8Array.from(e);
  match(j,e);assert.deepEqual(j,beforeJ);assert.deepEqual(Uint8Array.from(e),beforeE);
});
const bindingChanges=[['jobID','aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'],['routeID','another-route'],['routeDigest','e'.repeat(64)],['policyVersion','another-policy'],['policyDigest','e'.repeat(64)],['checkerVersion','another-checker'],['checkerSourceSHA','e'.repeat(40)],['architecture','x86_64'],['artifact.sha256','e'.repeat(64)],['artifact.length',12346]];
for(const [path,value] of bindingChanges) {
  test(`binding rejects individual report ${path} mismatch`,()=>{const r=evidence();set(r,path,value);mismatch(fixture('job.json'),wire(r));});
  test(`binding rejects individual job ${path} mismatch even with updated exact-byte digest`,()=>{
    const j=job();set(j,path,value);const raw=wire(j);mismatch(raw,rebind(raw));
  });
  test(`binding accepts consistent independently produced ${path} data`,()=>{
    const j=job();const r=evidence();set(j,path,value);set(r,path,value);const raw=wire(j);match(raw,rebind(raw,r));
  });
}
test('binding rejects wrong job descriptor digest',()=>{const r=evidence();r.jobDescriptorSHA256='e'.repeat(64);mismatch(fixture('job.json'),wire(r));});
test('binding rejects byte-distinct whitespace with unchanged report',()=>{
  const raw=Buffer.concat([Buffer.from(' \n'),fixture('job.json'),Buffer.from('\t')]);
  assert.deepEqual(JSON.parse(raw),job());mismatch(raw,fixture('evidence.json'));
});
test('binding accepts exact original whitespace when report names those bytes',()=>{
  const raw=Buffer.concat([Buffer.from(' \n'),fixture('job.json'),Buffer.from('\t')]);match(raw,rebind(raw));
});
test('binding accepts report whitespace without mutating it',()=>{
  const report=Buffer.concat([Buffer.from('\n'),fixture('evidence.json'),Buffer.from(' ')]);const before=Buffer.from(report);
  match(fixture('job.json'),report);assert.deepEqual(report,before);
});
test('binding neither normalises nor approves changed URL',()=>{
  const j=job();j.sourceURL='https://OTHER.example.test:443/new%20path';const raw=wire(j);match(raw,rebind(raw));
});
for(const [path,value] of [['finalSourceURL','https://another.example.test/unapproved'],['osVersion','inventedOS'],['osBuild','inventedBuild'],['startedAt',1799999999],['finishedAt',1800000040],['observations.0.exitCode',255]])test(`binding preserves non-authoritative ${path}`,()=>{
  const r=evidence();set(r,path,value);match(fixture('job.json'),wire(r));
});
test('all unavailable report still matches only caller claims',()=>{
  const r=evidence();r.observations.forEach(o=>{o.outcome='unavailable';o.exitCode=o.signal=null;o.stdout=o.stderr={sha256:emptySHA,length:0};});
  match(fixture('job.json'),wire(r));
});
for(const badBytes of [undefined,null,'{}',Buffer.from('{}'),Buffer.from('{'),new Uint16Array([1])])test(`binding malformed arguments ${Object.prototype.toString.call(badBytes)}`,()=>{
  mismatch(badBytes,fixture('evidence.json'));mismatch(fixture('job.json'),badBytes);mismatch(badBytes,badBytes);
});
test('binding hostile byte Proxies never invoke traps',()=>{
  const counter={calls:0};const j=hostileProxy(fixture('job.json'),counter);const e=hostileProxy(fixture('evidence.json'),counter);
  mismatch(j,fixture('evidence.json'));mismatch(fixture('job.json'),e);mismatch(j,e);assert.equal(counter.calls,0);
});
test('binding does not mistake swapped formats for matching data',()=>mismatch(fixture('evidence.json'),fixture('job.json')));

// Check descriptive documents themselves, without pretending to run an engine.
for(const kind of kinds)test(`${kind.name} descriptive schema covers exact closed fields`,()=>{
  const schema=JSON.parse(readFileSync(new URL(`../protocol/${kind.name}-v2.schema.json`,import.meta.url)));
  assert.equal(schema.$schema,'https://json-schema.org/draft/2020-12/schema');assert.equal(schema.additionalProperties,false);
  assert.deepEqual(Object.keys(schema.properties),Object.keys(kind.make()));
  assert.deepEqual(schema.required,Object.keys(kind.make()));
  assert.equal(schema.$defs.artifact.additionalProperties,false);
  assert.deepEqual(schema.$defs.artifact.required,['sha256','length']);
  assert.match(schema.$comment,/65536/);assert.match(schema.$comment,/descriptive/i);
  if(kind.name==='evidence') {
    assert.equal(schema.$defs.observation.additionalProperties,false);assert.equal(schema.$defs.output.additionalProperties,false);
    assert.deepEqual(schema.properties.observations.prefixItems.map(p=>p.allOf[1].properties.checkID.const),ids);
    assert.equal(schema.properties.observations.minItems,6);assert.equal(schema.properties.observations.maxItems,6);
    assert.equal(schema.properties.observations.items,false);
  }
});

for (const kind of kinds) {
  for(const path of recordPaths(kind.make()))test(`${kind.name} duplicate key at ${path||'root'} refused`,()=>{
    const r=kind.make();const target=at(r,path);const key=Object.keys(target)[0];
    const duplicate=`{${JSON.stringify(key)}:${JSON.stringify(target[key])},${JSON.stringify(target).slice(1)}`;
    let raw;
    if(path){set(r,path,'RAW_DUPLICATE_RECORD');raw=JSON.stringify(r).replace('"RAW_DUPLICATE_RECORD"',duplicate);}
    else raw=duplicate;
    refuses(kind,Buffer.from(raw));
  });
  for(const token of ['2.0','2e0','2E+0','-0'])test(`${kind.name} schema token ${token} refused`,()=>{
    refuses(kind,Buffer.from(fixture(`${kind.name}.json`).toString().replace('"schema":2',`"schema":${token}`)));
  });
  for(const code of [...Array(33).keys(),...Array.from({length:33},(_,i)=>127+i)]) {
    bad(kind,`identifier forbidden codepoint ${code}`,r=>{r.routeID=`a${String.fromCharCode(code)}b`;});
    bad(kind,`URL forbidden codepoint ${code}`,r=>{r[kind.name==='job'?'sourceURL':'finalSourceURL']=`https://example.test/a${String.fromCharCode(code)}b`;});
  }
  test(`${kind.name} malformed UTF8 inside otherwise complete valid record refused`,()=>{
    const raw=fixture(`${kind.name}.json`);const marker=raw.indexOf('fixture.route-1');
    refuses(kind,Buffer.concat([raw.subarray(0,marker),Buffer.from([0xc0,0xaf]),raw.subarray(marker+2)]));
  });
  test(`${kind.name} resizable backing intrinsic copied and later resize cannot alter result`,()=>{
    const raw=fixture(`${kind.name}.json`);const backing=new ArrayBuffer(raw.length,{maxByteLength:65536});const view=new Uint8Array(backing);view.set(raw);
    const result=accepts(kind,view,kind.make());backing.resize(0);assert.deepEqual(result[kind.key],kind.make());assert.equal(result.byteDigest,hash(raw));
  });
  for(const value of [new Date(0),/fixture/,new String('fixture'),new Number(2),()=>{}])test(`${kind.name} exotic encoder root ${Object.prototype.toString.call(value)} refused`,()=>encodeRefuses(kind,value));
}
test('evidence repeated plain descriptor reference is cloned independently',()=>{
  const r=evidence();const descriptor={sha256:emptySHA,length:0};r.observations[0].stdout=descriptor;r.observations[0].stderr=descriptor;
  const result=encoded(E,r);const parsed=accepts(E,result.bytes,r).report;
  assert.notStrictEqual(parsed.observations[0].stdout,parsed.observations[0].stderr);
  descriptor.length=55;assert.equal(parsed.observations[0].stdout.length,0);
});
test('binding accepts 64KiB exact original job bytes',()=>{
  const raw=fixture('job.json');const padded=Buffer.concat([raw,Buffer.alloc(65536-raw.length,32)]);
  assert.equal(padded.length,65536);match(padded,rebind(padded));
});
test('binding refuses oversized exact-digest job even when the supplied digest matches',()=>{
  const raw=fixture('job.json');const padded=Buffer.concat([raw,Buffer.alloc(65537-raw.length,32)]);mismatch(padded,rebind(padded));
});
test('binding refuses inconsistent evidence even with otherwise matching fields',()=>{
  const r=evidence();r.observations[0].stdout={sha256:'a'.repeat(64),length:0};mismatch(fixture('job.json'),wire(r));
});

for(const kind of kinds) {
  test(`${kind.name} encoder setter-only property refused without callback`,()=>{
    let calls=0;const r=kind.make();Object.defineProperty(r,'routeID',{set(){calls++;},enumerable:true});encodeRefuses(kind,r);assert.equal(calls,0);
  });
  test(`${kind.name} encoder hidden extra property refused`,()=>{
    const r=kind.make();Object.defineProperty(r,'hidden',{value:1,enumerable:false});encodeRefuses(kind,r);
  });
}
test('binding refuses detached/shared/revoked byte views without exceptions',()=>{
  const detached=Uint8Array.from(fixture('job.json'));structuredClone(detached.buffer,{transfer:[detached.buffer]});
  const shared=new Uint8Array(new SharedArrayBuffer(4));const revoked=Proxy.revocable(new Uint8Array(0),{});revoked.revoke();
  for(const value of [detached,shared,revoked.proxy]) {mismatch(value,fixture('evidence.json'));mismatch(fixture('job.json'),value);}
});
