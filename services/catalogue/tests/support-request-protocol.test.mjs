import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { decodeSupportRequest, encodeSupportRequest } from '../protocol/support-request-v1.mjs';
import { parseStrictJSON } from '../protocol/strict-json.mjs';

const fixture = name => readFileSync(new URL(`../protocol/fixtures/support-request-v1/${name}`, import.meta.url));
const copy = value => structuredClone(value);
const minimal = () => JSON.parse(fixture('valid-minimal.json'));
const observed = () => JSON.parse(fixture('valid-observed.json'));
const bytes = value => Buffer.from(JSON.stringify(value));
const hash = value => createHash('sha256').update(value).digest('hex');
const at = (value, path) => path ? path.split('.').reduce((v, key) => v[key], value) : value;
const set = (value, path, replacement) => {
  const parts = path.split('.'); const key = parts.pop(); at(value, parts.join('.'))[key] = replacement;
};
const authorityKeys = ['scope', 'requestSent', 'ownershipVerified', 'userConsentVerified', 'sourceApproved'];
function authority(result, operation) {
  assert.deepEqual(Object.keys(result).sort(), [
    'status', 'reason', ...authorityKeys, 'requestSHA256',
    operation === 'decode' ? 'request' : 'requestBytes',
  ].sort());
  assert.equal(result.scope, 'fixture-only');
  for (const key of authorityKeys.slice(1)) assert.equal(result[key], false, key);
}
function accepts(raw, expected = JSON.parse(Buffer.from(raw).toString('utf8'))) {
  const snapshot = Buffer.from(raw);
  const result = decodeSupportRequest(raw);
  // Intentionally first: Phase A must fail at a meaningful validated-status assertion.
  assert.equal(result.status, 'validated');
  authority(result, 'decode'); assert.equal(result.reason, null);
  assert.equal(result.requestSHA256, hash(snapshot));
  assert.deepEqual(result.request, expected);
  assert.deepEqual(Buffer.from(raw), snapshot, 'decode leaves input bytes untouched');
  return result;
}
function refuses(raw) {
  const result = decodeSupportRequest(raw);
  authority(result, 'decode'); assert.equal(result.status, 'refused');
  assert.equal(result.reason, 'invalid-request');
  assert.equal(result.request, null); assert.equal(result.requestSHA256, null);
}
function encoded(value) {
  const result = encodeSupportRequest(value);
  assert.equal(result.status, 'encoded'); authority(result, 'encode');
  assert.equal(result.reason, null); assert.ok(result.requestBytes instanceof Uint8Array);
  assert.equal(result.requestSHA256, hash(result.requestBytes));
  return result;
}
function encodeRefuses(value) {
  const result = encodeSupportRequest(value);
  authority(result, 'encode'); assert.equal(result.status, 'refused');
  assert.equal(result.reason, 'invalid-request');
  assert.equal(result.requestBytes, null); assert.equal(result.requestSHA256, null);
}
const positive = (name, mutate, factory = observed) => test(name, () => {
  const value = factory(); mutate(value); accepts(bytes(value), value); encoded(value);
});
const negative = (name, mutate, factory = observed) => test(name, () => {
  const value = factory(); mutate(value); refuses(bytes(value)); encodeRefuses(value);
});
const invalidField = (path, values) => {
  for (const [index, value] of values.entries()) negative(`${path} rejects case ${index}`, p => set(p, path, value));
};
const vectors = JSON.parse(fixture('expected.json')).vectors;
for (const vector of vectors) {
  test(`golden ${vector.name}: validated without authority`, () => accepts(fixture(vector.file)));
  test(`golden ${vector.name}: exact independent fixture hashes and UTF8`, () => {
    const raw = fixture(vector.file); const canonical = Buffer.from(vector.encodedUTF8);
    assert.equal(raw.byteLength, vector.inputByteLength); assert.equal(hash(raw), vector.inputSHA256);
    assert.equal(canonical.byteLength, vector.encodedByteLength); assert.equal(hash(canonical), vector.encodedSHA256);
    assert.deepEqual(JSON.parse(raw), JSON.parse(canonical));
    const result = encoded(JSON.parse(raw));
    assert.equal(Buffer.from(result.requestBytes).toString(), vector.encodedUTF8);
    assert.equal(result.requestSHA256, vector.encodedSHA256);
    accepts(result.requestBytes, JSON.parse(raw));
  });
}

// Shape and privacy: enumerate every object boundary, required key and private field.
const recordPaths = ['', 'app', 'app.displayName', 'app.bundleID', 'app.version', 'app.vendorURL', 'consent'];
const privateFields = [
  'attachments', 'path', 'username', 'inventory', 'licenceID', 'deviceID',
  'accountID', 'email', 'logs', 'paidEntitlement', 'trial', 'retentionDays',
  'status', 'requestSent', 'ownershipVerified', 'userConsentVerified', 'sourceApproved',
  '__proto__', 'constructor', 'toJSON',
];
for (const path of recordPaths) {
  for (const field of Object.keys(at(observed(), path))) negative(`required ${path || 'root'}.${field}`, p => { delete at(p, path)[field]; });
  for (const field of privateFields) negative(`closed ${path || 'root'} refuses ${field}`, p => {
    Object.defineProperty(at(p, path), field, { value: 'fixture-private', enumerable: true });
  });
  for (const replacement of [null, [], true, 'object', 0]) {
    if (!path) continue;
    // Null is the explicit allowed spelling only for these optional observations.
    if (replacement === null && ['app.bundleID', 'app.version', 'app.vendorURL'].includes(path)) continue;
    negative(`object ${path} rejects ${JSON.stringify(replacement)}`, p => set(p, path, replacement));
  }
}
for (const root of [null, [], 'request', 1, true, false]) test(`root refuses ${JSON.stringify(root)}`, () => {
  refuses(bytes(root)); encodeRefuses(root);
});
invalidField('schema', ['', 'support-request-v1', 'fixture-support-request-v2', null, 1]);
invalidField('clientRequestID', [
  '', '00000000-0000-4000-8000-00000000000', '00000000-0000-4000-8000-0000000000000',
  '00000000-0000-1000-8000-000000000001', '00000000-0000-4000-7000-000000000001',
  '00000000-0000-4000-c000-000000000001', '00000000-0000-4000-A000-000000000001',
  '{00000000-0000-4000-8000-000000000001}', '00000000-0000-4000-8000-00000000000g', null, 4,
]);
for (const variant of ['8', '9', 'a', 'b']) positive(`UUIDv4 variant ${variant}`, p => { p.clientRequestID = `00000000-0000-4000-${variant}000-000000000001`; });
for (const path of ['submittedAt', 'consent.presentedAt', 'consent.acceptedAt']) {
  invalidField(path, [-1, 1.5, Number.MAX_SAFE_INTEGER + 1, null, true, '1800000000']);
  test(`${path} encoder rejects negative zero and nonfinite numbers`, () => {
    for (const n of [-0, Infinity, -Infinity, NaN]) { const p = observed(); set(p, path, n); encodeRefuses(p); }
  });
}
positive('zero times are inert injected records', p => { p.submittedAt = p.consent.presentedAt = p.consent.acceptedAt = 0; });
positive('maximum safe times', p => { p.submittedAt = p.consent.presentedAt = p.consent.acceptedAt = Number.MAX_SAFE_INTEGER; });
positive('all time bounds may be equal', p => { p.consent.presentedAt = p.consent.acceptedAt = p.submittedAt; });
negative('consent accepted before presentation', p => { p.consent.acceptedAt = p.consent.presentedAt - 1; });
negative('consent accepted after submission', p => { p.consent.acceptedAt = p.submittedAt + 1; });
negative('consent presented after submission', p => { p.consent.presentedAt = p.submittedAt + 1; });
invalidField('consent.schema', ['consent-v1', null, true]);
invalidField('consent.purpose', ['marketing', 'coverage-research ', null, true]);
invalidField('consent.destination', ['other-service', 'https://example.test', null, true]);

for (const field of ['displayName', 'bundleID', 'version', 'vendorURL']) {
  invalidField(`app.${field}.provenance`, ['independentlyVerified', 'verified', '', null, true]);
  for (const provenance of ['userSupplied', 'locallyObserved']) {
    const action = field === 'vendorURL' && provenance === 'locallyObserved' ? negative : positive;
    action(`${field} provenance ${provenance}`, p => { p.app[field].provenance = provenance; });
  }
}
for (const field of ['bundleID', 'version', 'vendorURL']) positive(`explicit null ${field}`, p => { p.app[field] = null; });
for (const field of ['displayName', 'version']) {
  invalidField(`app.${field}.value`, ['', null, 1, false, [], {}, 'a'.repeat(129), '🧪'.repeat(129), '\ud800', '\udfff']);
  for (const value of ['a'.repeat(128), '🧪'.repeat(128), 'é'.repeat(128), '版本 β / 2026 preview']) {
    positive(`${field} scalar and byte boundary ${Buffer.byteLength(value)}`, p => { p.app[field].value = value; });
  }
  for (const code of [...Array(32).keys(), ...Array.from({ length: 33 }, (_, i) => 127 + i)]) {
    negative(`${field} control U+${code.toString(16)}`, p => { p.app[field].value = `a${String.fromCharCode(code)}b`; });
  }
}
invalidField('app.bundleID.value', ['', 'single', '.two', 'two.', 'two..parts', 'two/parts', 'two_parts.test', 'é.test', 'two parts.test', 'a.'.repeat(128), 1, null]);
positive('bundleID exact 255 bytes', p => { p.app.bundleID.value = `a.${'b'.repeat(253)}`; });
negative('bundleID 256 bytes', p => { p.app.bundleID.value = `a.${'b'.repeat(254)}`; });
positive('bundleID descriptive case and hyphens retained', p => { p.app.bundleID.value = '-Fixture-.EXAMPLE.App-2'; });

positive('notes empty literal string', p => { p.notes = ''; });
positive('notes explicit null', p => { p.notes = null; });
positive('notes scalar ceiling', p => { p.notes = 'a'.repeat(1000); });
positive('notes exact byte ceiling with multibyte scalars', p => { p.notes = '🧪'.repeat(512); });
positive('notes exactly 1000 scalars and 2048 bytes', p => { p.notes = '🧪'.repeat(349) + 'é' + 'a'.repeat(650); });
positive('notes markup, quotes, tab, LF, personal-looking literal text stay inert', p => { p.notes = '<img src=x onerror="alert(1)">\n\tFixture Person /Users/fixture'; });
invalidField('notes', ['a'.repeat(1001), '🧪'.repeat(513), '🧪'.repeat(512) + 'a', 'é'.repeat(999) + '🧪'.repeat(2), '\ud800', '\udfff', 1, false, [], {}]);
for (const code of [...Array(32).keys(), ...Array.from({ length: 33 }, (_, i) => 127 + i)].filter(c => ![9, 10].includes(c))) {
  negative(`notes rejects control U+${code.toString(16)}`, p => { p.notes = `a${String.fromCharCode(code)}b`; });
}

const validURLs = [
  'https://example.test', 'https://example.test/', 'https://example.test:1/path',
  'https://example.test:443/path', 'https://example.test:65535/path',
  'https://xn--bcher-kva.example/path', 'https://example.test/a@b',
  'https://example.test/a%20b', 'https://example.test/a%3Fb%23c',
  'https://example.test/a%2eb', 'https://example.test/.../x',
  'https://example.test/版本', 'https://example.test/Case-Sensitive',
  'https://example.test/a//b',
  `https://${'a'.repeat(63)}.test/x`,
  `https://${['a'.repeat(63), 'b'.repeat(63), 'c'.repeat(63), 'd'.repeat(61)].join('.')}/x`,
  `https://example.test/${'x'.repeat(2027)}`,
];
for (const url of validURLs) positive(`URL accepts and preserves ${url.length > 100 ? `boundary length ${url.length}` : url}`, p => { p.app.vendorURL.value = url; });
const invalidURLs = [
  '', 'http://example.test/', 'HTTPS://example.test/', 'https:example.test',
  'https:/example.test', 'https:///example.test', 'https://Example.test',
  'https://user@example.test', 'https://user:pass@example.test/',
  'https://example.test?token=fixture', 'https://example.test?',
  'https://example.test/path?x', 'https://example.test/#fragment', 'https://example.test/#',
  'https://example.test\\path', 'https://example.test/a b', ' https://example.test',
  'https://example.test\n', 'https://example.test/a\tb', 'https://example.test/a\u0085b',
  'https://%65xample.test/', 'https://example.test./', 'https://example..test/',
  'https://-example.test', 'https://example-.test', 'https://example_test/',
  'https://éxample.test/', 'https://example。test/', 'https://[::1]/',
  'https://127.0.0.1/', 'https://127.1/', 'https://2130706433/',
  'https://0x7f000001/', 'https://0177.0.0.1/', 'https://example.123/',
  'https://example.0x123/', 'https://example.09/', 'https://example.0/',
  'https://example.test:0/', 'https://example.test:65536/', 'https://example.test:0443/',
  'https://example.test:/', 'https://example.test:+443/', 'https://example.test:4e2/',
  'https://example.test:-1/', 'https://example.test:1.5/',
  'https://example.test/a/../b', 'https://example.test/./b',
  'https://example.test/%2e/b', 'https://example.test/a/.%2E/b',
  'https://example.test/%2e%2e/b', 'https://example.test/a/..',
  'https://example.test/a/%2E.', 'https://example.test/a/%2E%2E',
  'https://example.test/a/.', 'https://example.test/a/%2E',
  `https://${'a'.repeat(64)}.test/`,
  `https://${['a'.repeat(63), 'b'.repeat(63), 'c'.repeat(63), 'd'.repeat(62)].join('.')}/`,
  `https://example.test/${'x'.repeat(2028)}`,
  `https://example.test/${'x'.repeat(2029)}`,
  `https://example.test/${'🧪'.repeat(508)}`,
  null, 123,
];
for (const [i, url] of invalidURLs.entries()) negative(`URL refuses authority/repair/query/limit case ${i}`, p => { p.app.vendorURL.value = url; });

// Raw bytes exercise the actual strict parser contract, not JSON.stringify repair.
const baseRaw = bytes(minimal()).toString();
for (const token of ['-0', '-1', '+1', '01', '1.0', '1e0', '1E1', '9007199254740992', '9007199254740991.1', 'Infinity', 'NaN', '999999999999999999999999999999999999']) {
  test(`number token refuses ${token}`, () => refuses(Buffer.from(baseRaw.replace('1800000000', token))));
}
const malformed = [
  '', ' ', '\ufeff' + baseRaw, baseRaw + '{}', baseRaw + 'null', baseRaw + 'garbage',
  baseRaw.slice(0, -1), baseRaw.replace('"notes":null', '"notes":null,'),
  baseRaw.replace('"notes":null', '"notes":"\\x20"'),
  baseRaw.replace('"notes":null', '"notes":"\\uD800"'),
  baseRaw.replace('"notes":null', '"notes":"\\uDFFF"'),
  baseRaw.replace('"notes":null', '"notes":"\\uD800x"'),
  baseRaw.replace('"notes":null', '"notes":"a\nb"'),
  baseRaw.replace('"notes":null', '"notes":undefined'),
  baseRaw.replace('"notes":null', '"notes":/*comment*/null'),
];
for (const [i, raw] of malformed.entries()) test(`strict JSON refusal ${i}`, () => refuses(Buffer.from(raw)));
for (const [i, raw] of [
  Buffer.concat([Buffer.from(baseRaw.slice(0, -1)), Buffer.from([0xc0, 0xaf]), Buffer.from('}')]),
  Buffer.from([0xff]), Buffer.from([0xed, 0xa0, 0x80]), Buffer.from([0xf4, 0x90, 0x80, 0x80]),
].entries()) test(`malformed UTF8 ${i}`, () => refuses(raw));
for (const [label, original, duplicate] of [
  ['root', '"notes":null', '"notes":null,"notes":null'],
  ['escaped root alias', '"notes":null', '"notes":null,"\\u006eotes":null'],
  ['app', '"bundleID":null', '"bundleID":null,"bundleID":null'],
  ['observation', '"value":"Fixture App"', '"value":"Fixture App","\\u0076alue":"Fixture App"'],
  ['consent', '"purpose":"coverage-research"', '"purpose":"coverage-research","purpose":"coverage-research"'],
]) test(`duplicate key ${label}`, () => refuses(Buffer.from(baseRaw.replace(original, duplicate))));
positive('escaped valid surrogate pair is a scalar', p => { p.app.displayName.value = '🧪'; });
test('raw escaped pair decodes without replacing exact bytes hash', () => {
  const raw = Buffer.from(baseRaw.replace('Fixture App', '\\ud83e\\uddea'));
  const p = minimal(); p.app.displayName.value = '🧪'; accepts(raw, p);
});
test('equivalent JSON whitespace changes exact input hash only', () => {
  const compact = accepts(Buffer.from(baseRaw)); const pretty = accepts(fixture('valid-minimal.json'));
  assert.deepEqual(compact.request, pretty.request); assert.notEqual(compact.requestSHA256, pretty.requestSHA256);
  assert.deepEqual(encoded(compact.request).requestBytes, encoded(pretty.request).requestBytes);
});
test('byte subarray ignores bytes outside the supplied view', () => {
  const wrapped = Buffer.concat([Buffer.from('garbage'), Buffer.from(baseRaw), Buffer.from('garbage')]);
  accepts(wrapped.subarray(7, 7 + Buffer.byteLength(baseRaw)), minimal());
});
for (const size of [8191, 8192, 8193, 1024 * 1024]) test(`input byte ceiling ${size}`, { timeout: 1000 }, () => {
  const raw = Buffer.from(baseRaw + ' '.repeat(size - Buffer.byteLength(baseRaw)));
  size <= 8192 ? accepts(raw, minimal()) : refuses(raw);
});
for (const depth of [16, 17, 500]) test(`strict resource depth ${depth}`, { timeout: 1000 }, () => {
  const raw = Buffer.from('['.repeat(depth) + '0' + ']'.repeat(depth));
  if (depth === 16) assert.doesNotThrow(() => parseStrictJSON(raw, { maximumBytes: 8192, maximumDepth: 16 }));
  else assert.throws(() => parseStrictJSON(raw, { maximumBytes: 8192, maximumDepth: 16 }));
  refuses(raw);
});
for (const value of [baseRaw, null, undefined, [], {}, new ArrayBuffer(8), new DataView(new ArrayBuffer(8)), new Uint16Array(4)]) {
  test(`decode rejects non-byte input ${Object.prototype.toString.call(value)}`, () => refuses(value));
}
test('decode accepts ordinary Uint8Array and Buffer', () => {
  accepts(new Uint8Array(Buffer.from(baseRaw)), minimal()); accepts(Buffer.from(baseRaw), minimal());
});
test('decode refuses shared backing memory', () => {
  const value = new Uint8Array(new SharedArrayBuffer(Buffer.byteLength(baseRaw))); value.set(Buffer.from(baseRaw)); refuses(value);
});
test('decode refuses detached memory', () => {
  const value = new Uint8Array(Buffer.from(baseRaw)); structuredClone(value.buffer, { transfer: [value.buffer] }); refuses(value);
});

// The encoder revalidates caller records. Passing a decoder result wrapper grants nothing.
test('encoder rejects decoder wrapper, arbitrary primitive and array', () => {
  for (const value of [decodeSupportRequest(bytes(minimal())), undefined, null, true, 'request', 1, [], () => minimal()]) encodeRefuses(value);
});
test('encoder recursively sorts exact golden keys, independent of insertion order', () => {
  const reorder = value => value && typeof value === 'object'
    ? Object.fromEntries(Object.entries(value).reverse().map(([k, v]) => [k, reorder(v)])) : value;
  for (const vector of vectors) {
    const p = JSON.parse(fixture(vector.file)); const shuffled = reorder(p);
    assert.equal(Buffer.from(encoded(shuffled).requestBytes).toString(), vector.encodedUTF8);
  }
});
test('encoder accepts null-prototype exact own-data records', () => {
  const convert = value => value && typeof value === 'object'
    ? Object.assign(Object.create(null), Object.fromEntries(Object.entries(value).map(([k, v]) => [k, convert(v)]))) : value;
  const value = convert(observed()); accepts(encoded(value).requestBytes, observed());
});
test('encoder does not mutate frozen own-data records', () => {
  const freeze = value => { if (value && typeof value === 'object') { Object.values(value).forEach(freeze); Object.freeze(value); } return value; };
  const p = freeze(observed()); const snapshot = copy(p); encoded(p); assert.deepEqual(p, snapshot);
});
test('decode and encode never alias input, output or repeated results', () => {
  const raw = bytes(observed()); const first = accepts(raw); const second = accepts(raw);
  assert.notEqual(first.request, second.request);
  for (const path of recordPaths.filter(Boolean)) assert.notEqual(at(first.request, path), at(second.request, path), path);
  first.request.app.displayName.value = 'changed'; raw.fill(0);
  assert.equal(second.request.app.displayName.value, observed().app.displayName.value);
  const p = observed(); const snapshot = copy(p); const a = encoded(p); const b = encoded(p);
  assert.deepEqual(p, snapshot); assert.notEqual(a.requestBytes, b.requestBytes);
  a.requestBytes.fill(0); assert.equal(Buffer.from(b.requestBytes).toString(), vectors[1].encodedUTF8);
  p.app.displayName.value = 'later'; assert.equal(Buffer.from(b.requestBytes).toString(), vectors[1].encodedUTF8);
});
for (const path of recordPaths) {
  test(`encoder rejects accessor without execution at ${path || 'root'}`, () => {
    const p = observed(); const obj = at(p, path); const key = Object.keys(obj)[0]; let calls = 0;
    Object.defineProperty(obj, key, { enumerable: true, get() { calls++; throw new Error('getter must not run'); } });
    encodeRefuses(p); assert.equal(calls, 0);
  });
  test(`encoder rejects setter-only at ${path || 'root'}`, () => {
    const p = observed(); const obj = at(p, path); const key = Object.keys(obj)[0]; let calls = 0;
    Object.defineProperty(obj, key, { enumerable: true, set() { calls++; } });
    encodeRefuses(p); assert.equal(calls, 0);
  });
  test(`encoder rejects symbols and hidden extras at ${path || 'root'}`, () => {
    for (const key of [Symbol('private'), 'hiddenPrivate']) {
      const p = observed(); Object.defineProperty(at(p, path), key, { value: 'fixture', enumerable: false }); encodeRefuses(p);
    }
  });
  test(`encoder requires enumerable fields at ${path || 'root'}`, () => {
    const p = observed(); const obj = at(p, path); Object.defineProperty(obj, Object.keys(obj)[0], { enumerable: false }); encodeRefuses(p);
  });
  test(`encoder rejects custom prototype and inherited fields at ${path || 'root'}`, () => {
    const p = observed(); const obj = at(p, path); Object.setPrototypeOf(obj, { custom: true }); encodeRefuses(p);
    const q = observed(); const target = at(q, path); const key = Object.keys(target)[0];
    Object.setPrototypeOf(target, { [key]: target[key] }); delete target[key]; encodeRefuses(q);
  });
  test(`encoder rejects toJSON callback at ${path || 'root'} without calling`, () => {
    const p = observed(); let calls = 0; at(p, path).toJSON = () => { calls++; throw new Error('toJSON must not run'); };
    encodeRefuses(p); assert.equal(calls, 0);
  });
  test(`encoder rejects Proxy at ${path || 'root'} without traps`, () => {
    let calls = 0; const trap = () => { calls++; throw new Error('Proxy trap must not run'); };
    const p = observed(); const proxy = new Proxy(at(p, path), { get: trap, ownKeys: trap, getPrototypeOf: trap, getOwnPropertyDescriptor: trap });
    if (path) { set(p, path, proxy); encodeRefuses(p); } else encodeRefuses(proxy);
    assert.equal(calls, 0);
  });
}
test('revoked Proxy refuses without throwing', () => {
  const { proxy, revoke } = Proxy.revocable(observed(), {}); revoke(); encodeRefuses(proxy); refuses(proxy);
});
test('byte Proxy refuses without traps', () => {
  let calls = 0; const trap = () => { calls++; throw new Error('byte trap must not run'); };
  refuses(new Proxy(bytes(minimal()), { get: trap, getPrototypeOf: trap })); assert.equal(calls, 0);
});
test('byte view accessor properties do not run', () => {
  const raw = bytes(minimal()); let calls = 0;
  for (const key of ['byteLength', 'byteOffset', 'buffer']) Object.defineProperty(raw, key, { get() { calls++; throw new Error('byte getter'); } });
  // Intrinsic view extraction is permitted; these caller properties are never read.
  const result = decodeSupportRequest(raw);
  assert.equal(calls, 0); assert.equal(result.status, 'validated');
  authority(result, 'decode'); assert.deepEqual(result.request, minimal());
  assert.equal(result.requestSHA256, hash(Buffer.from(baseRaw)));
});
test('byte extraction does not invoke caller iterators or conversions', () => {
  const raw = bytes(minimal()); let calls = 0;
  const trap = () => { calls++; throw new Error('byte callback must not run'); };
  raw[Symbol.iterator] = trap; raw.toString = trap; raw.valueOf = trap;
  const result = decodeSupportRequest(raw);
  assert.equal(calls, 0); assert.equal(result.status, 'validated');
  authority(result, 'decode'); assert.deepEqual(result.request, minimal());
  assert.equal(result.requestSHA256, hash(Buffer.from(baseRaw)));
});
test('encoder cycles, oversized objects, strings and deep objects refuse promptly', { timeout: 1000 }, () => {
  const cyclic = observed(); cyclic.app.displayName = cyclic; encodeRefuses(cyclic);
  const mutual = observed(); mutual.app.version.value = mutual.app; encodeRefuses(mutual);
  const wide = observed(); for (let i = 0; i < 10000; i++) wide[`extra${i}`] = i; encodeRefuses(wide);
  const long = observed(); long.notes = 'x'.repeat(1024 * 1024); encodeRefuses(long);
  const deep = observed(); let cursor = deep; for (let i = 0; i < 10000; i++) { cursor.extra = {}; cursor = cursor.extra; } encodeRefuses(deep);
});
test('encoder rejects invalid scalar wrappers without coercion callbacks', () => {
  let calls = 0; const value = { toString() { calls++; return 'Fixture App'; }, valueOf() { calls++; return 1; } };
  for (const path of ['notes', 'app.displayName.value', 'submittedAt']) { const p = observed(); set(p, path, value); encodeRefuses(p); }
  assert.equal(calls, 0);
});
test('descriptive schema is closed at every record and does not claim runtime validation', () => {
  const schema = JSON.parse(readFileSync(new URL('../protocol/support-request-v1.schema.json', import.meta.url)));
  assert.equal(schema.$schema, 'https://json-schema.org/draft/2020-12/schema');
  assert.match(schema.$comment, /Descriptive only/);
  let objects = 0;
  function walk(value) {
    if (!value || typeof value !== 'object') return;
    if (value.type === 'object') {
      objects++; assert.equal(value.additionalProperties, false);
      assert.deepEqual([...value.required].sort(), Object.keys(value.properties).sort());
    }
    for (const child of Object.values(value)) walk(child);
  }
  walk(schema); assert.equal(objects, 7);
});
