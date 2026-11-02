import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { parseStrictJSON } from '../protocol/strict-json.mjs';
import {
  encodeCoverageReport, decodeCoverageReport, encodeCoverageDeletion, decodeCoverageDeletion,
} from '../coverage/protocol.mjs';

const fixtureURL = new URL('../../../Fixtures/CoverageWire/', import.meta.url);
const read = name => readFileSync(new URL(name, fixtureURL));
const digests = JSON.parse(read('literal-digests.json'));
const utf8 = text => new TextEncoder().encode(text);
const text = bytes => new TextDecoder('utf-8', { fatal: true }).decode(bytes);
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const copy = value => JSON.parse(JSON.stringify(value));
const report = () => JSON.parse(read('report-minimal.json'));
const deletion = () => JSON.parse(read('deletion.json'));
const flags = {
  scope: 'fixture-only', requestSent: false, userConsentVerified: false,
  inventoryVerified: false, sourceApproved: false, deletionPerformed: false,
  cataloguePublished: false,
};
const keys = ['status', 'reason', 'value', 'bytes', 'sha256', ...Object.keys(flags)].sort();
function receipt(result) {
  assert.deepEqual(Object.keys(result).sort(), keys, 'closed receipt fields');
  for (const [key, value] of Object.entries(flags)) assert.equal(result[key], value, key);
}
function refused(fn, value) {
  let result;
  assert.doesNotThrow(() => { result = fn(value); }, 'generic refusal must not throw');
  receipt(result);
  assert.deepEqual(result, {
    status: 'refused', reason: 'invalid-coverage', value: null, bytes: null, sha256: null, ...flags,
  });
}
function accepted(fn, input, status, expectedValue, expectedBytes) {
  const result = fn(input);
  receipt(result);
  assert.equal(result.status, status, 'valid literal fixture must succeed');
  assert.equal(result.reason, null);
  assert.deepEqual(result.value, expectedValue);
  assert.ok(result.bytes instanceof Uint8Array);
  assert.deepEqual(Array.from(result.bytes), Array.from(expectedBytes), 'exact independent wire bytes');
  assert.equal(result.sha256, digest(expectedBytes), 'SHA-256 of exact returned snapshot');
  return result;
}

// This is a setup control, independent of all four source stubs. It should pass
// on Phase A, while the separately named positive codec tests meaningfully fail.
test('SETUP: literal bytes/digests and unchanged strict-parser contract', () => {
  for (const name of ['report-minimal.json', 'report-unicode.json', 'report-ten.json', 'deletion.json']) {
    const bytes = read(name);
    assert.equal(bytes.byteLength, digests[name].bytes);
    assert.equal(digest(bytes), digests[name].sha256);
    assert.equal(bytes.at(-1), 125, 'no newline');
    assert.deepEqual(parseStrictJSON(bytes, { maximumBytes: 16384, maximumDepth: 16 }), JSON.parse(bytes));
  }
  const parser = readFileSync(new URL('../protocol/strict-json.mjs', import.meta.url));
  assert.equal(digest(parser), digests['strict-json.mjs'].sha256);
  assert.throws(() => parseStrictJSON(utf8('{}'), { maximumBytes: 512, maximumDepth: 4 }));
  assert.throws(() => parseStrictJSON(utf8('{"x":1,"x":2}'), { maximumBytes: 512, maximumDepth: 16 }));
  assert.throws(() => parseStrictJSON(Uint8Array.of(0xff), { maximumBytes: 512, maximumDepth: 16 }));
  assert.throws(() => parseStrictJSON(utf8('"\\ud800"'), { maximumBytes: 512, maximumDepth: 16 }));
  assert.equal(parseStrictJSON(utf8('[[[[[0]]]]]'), { maximumBytes: 512, maximumDepth: 16 })[0][0][0][0][0], 0);
});

for (const name of ['report-minimal.json', 'report-unicode.json', 'report-ten.json', 'deletion.json']) {
  const isDeletion = name === 'deletion.json';
  const encode = isDeletion ? encodeCoverageDeletion : encodeCoverageReport;
  const decode = isDeletion ? decodeCoverageDeletion : decodeCoverageReport;
  test(`POSITIVE literal encode ${name}`, () => {
    const bytes = read(name); const value = JSON.parse(bytes);
    const before = copy(value);
    const result = accepted(encode, value, 'encoded', value, bytes);
    assert.notEqual(result.value, value);
    if (!isDeletion) {
      assert.notEqual(result.value.apps, value.apps);
      assert.notEqual(result.value.apps[0], value.apps[0]);
      value.apps[0].displayName = 'Changed';
      assert.deepEqual(result.value, before);
    } else {
      value.deletionSecret = 'f'.repeat(64);
      assert.deepEqual(result.value, before);
    }
    assert.deepEqual(Array.from(result.bytes), Array.from(bytes));
    const second = accepted(encode, before, 'encoded', before, bytes);
    result.bytes[0] ^= 1;
    assert.deepEqual(Array.from(second.bytes), Array.from(bytes), 'fresh bytes each call');
    assert.notEqual(second.value, result.value);
  });
  test(`POSITIVE literal decode ${name} and input detachment`, () => {
    const bytes = read(name); const input = new Uint8Array(bytes);
    const expected = JSON.parse(bytes);
    const result = accepted(decode, input, 'validated', expected, bytes);
    input.fill(0);
    assert.deepEqual(Array.from(result.bytes), Array.from(bytes));
    assert.deepEqual(result.value, expected);
    const second = accepted(decode, Buffer.from(bytes), 'validated', expected, bytes);
    result.bytes.fill(0);
    assert.deepEqual(Array.from(second.bytes), Array.from(bytes));
  });
}

test('POSITIVE encoder sorts a copy with exact ASCII case-sensitive IDs', () => {
  const bytes = read('report-unicode.json'); const expected = JSON.parse(bytes);
  const value = copy(expected); value.apps.reverse();
  const before = copy(value);
  accepted(encodeCoverageReport, value, 'encoded', expected, bytes);
  assert.deepEqual(value, before, 'input order never mutates');
  const r = report();
  r.apps = [{ bundleID: 'a.b', displayName: 'Upper', version: null }, { bundleID: 'A.b', displayName: 'Lower', version: null }];
  const literal = utf8('{"apps":[{"bundleID":"A.b","displayName":"Lower","version":null},{"bundleID":"a.b","displayName":"Upper","version":null}],"disclosureVersion":1,"reportID":"00000000-0000-4000-8000-000000000001","schema":"coverage-report-v1"}');
  accepted(encodeCoverageReport, r, 'encoded', JSON.parse(text(literal)), literal);
});

test('POSITIVE null-prototype records are primitive-copied', () => {
  const value = Object.assign(Object.create(null), report());
  value.apps = value.apps.map(app => Object.assign(Object.create(null), app));
  accepted(encodeCoverageReport, value, 'encoded', report(), read('report-minimal.json'));
});

for (const [label, name] of [['128 ASCII scalars', 'x'.repeat(128)], ['128 astral scalars/512 UTF8 bytes', '🧪'.repeat(128)], ['quoted braces depth preflight', 'Braces [{ " }]'], ['combining text preserved', 'e\u0301']]) {
  test(`POSITIVE ${label}`, () => {
    const value = report(); value.apps[0].displayName = name; value.apps[0].version = name;
    // Independent construction from the frozen field layout, never codec output.
    const literal = utf8('{"apps":[{"bundleID":"com.example.app","displayName":' + JSON.stringify(name) + ',"version":' + JSON.stringify(name) + '}],"disclosureVersion":1,"reportID":"00000000-0000-4000-8000-000000000001","schema":"coverage-report-v1"}');
    accepted(encodeCoverageReport, value, 'encoded', value, literal);
    accepted(decodeCoverageReport, literal, 'validated', value, literal);
  });
}

test('POSITIVE bundle ID at 255 ASCII bytes and hyphen/digit components', () => {
  const value = report(); value.apps[0].bundleID = 'a.'.concat('x'.repeat(253));
  const literal = utf8('{"apps":[{"bundleID":"a.' + 'x'.repeat(253) + '","displayName":"Example App","version":null}],"disclosureVersion":1,"reportID":"00000000-0000-4000-8000-000000000001","schema":"coverage-report-v1"}');
  accepted(encodeCoverageReport, value, 'encoded', value, literal);
  accepted(decodeCoverageReport, literal, 'validated', value, literal);
  const short = report(); short.apps[0].bundleID = '1.-';
  const shortWire = utf8('{"apps":[{"bundleID":"1.-","displayName":"Example App","version":null}],"disclosureVersion":1,"reportID":"00000000-0000-4000-8000-000000000001","schema":"coverage-report-v1"}');
  accepted(encodeCoverageReport, short, 'encoded', short, shortWire);
});

const invalidReports = [
  ['empty apps', r => { r.apps = []; }],
  ['eleven apps', r => { r.apps = Array.from({ length: 11 }, (_, i) => ({ ...r.apps[0], bundleID: `com.example.a${i}` })); }],
  ['duplicate identity despite different text', r => { r.apps.push({ ...r.apps[0], displayName: 'Other', version: '2' }); }],
  ['wrong schema', r => { r.schema = 'fixture-support-request-v1'; }],
  ['missing schema', r => { delete r.schema; }],
  ['root unknown', r => { r.extra = null; }],
  ['missing app version', r => { delete r.apps[0].version; }],
  ['wrong disclosure', r => { r.disclosureVersion = 2; }],
  ['boolean disclosure', r => { r.disclosureVersion = true; }],
  ['string disclosure', r => { r.disclosureVersion = '1'; }],
  ['negative zero disclosure', r => { r.disclosureVersion = -0; }],
  ['nonarray apps', r => { r.apps = {}; }],
  ['null app', r => { r.apps[0] = null; }],
  ['array app', r => { r.apps[0] = []; }],
  ['numeric name', r => { r.apps[0].displayName = 1; }],
  ['undefined version', r => { r.apps[0].version = undefined; }],
  ['number version', r => { r.apps[0].version = 1; }],
];
for (const key of ['notes', 'vendorURL', 'path', 'email', 'account', 'device', 'hardwareUUID', 'signingIdentity', 'consent', '__proto__']) {
  invalidReports.push([`private/unknown app field ${key}`, r => { Object.defineProperty(r.apps[0], key, { value: 'private', enumerable: true }); }]);
  invalidReports.push([`private/unknown root field ${key}`, r => { Object.defineProperty(r, key, { value: 'private', enumerable: true }); }]);
}
for (const name of ['', 'x'.repeat(129), '🧪'.repeat(129), '\ud800', '\udfff', 'a\u0000b', 'a\u001fb', 'a\u007fb', 'a\u0085b', 'a\u009fb', 'a/b', 'a\\b', 'name@example', 'a+b@example.org', 'prefix https:thing', 'mailto:thing', 'a+b.c-d:thing']) {
  for (const field of ['displayName', 'version']) invalidReports.push([`invalid ${field} ${JSON.stringify(name)}`, r => { r.apps[0][field] = name; }]);
}
for (const id of ['', 'a', 'ab', 'abc', '.a', 'a.', 'a..b', 'a_b.c', 'é.x', 'a/b.c', 'a.b '.trimEnd() + ' ', 'a.'.concat('x'.repeat(254))]) {
  invalidReports.push([`invalid bundleID ${JSON.stringify(id)}`, r => { r.apps[0].bundleID = id; }]);
}
for (const id of ['00000000-0000-4000-8000-00000000000A', '00000000-0000-1000-8000-000000000001', '00000000-0000-4000-7000-000000000001', '00000000-0000-4000-c000-000000000001', '00000000000040008000000000000001', null, 1]) {
  invalidReports.push([`invalid UUID ${id}`, r => { r.reportID = id; }]);
}
for (const [label, mutate] of invalidReports) test(`REFUSE report object ${label}`, () => {
  const value = report(); mutate(value); refused(encodeCoverageReport, value);
  // JSON conversion is test-owned and only used for primitive invalid vectors.
  refused(decodeCoverageReport, utf8(JSON.stringify(value)));
});

for (const [label, mutate] of [
  ['missing secret', d => { delete d.deletionSecret; }],
  ['unknown field', d => { d.schema = 'coverage-report-v1'; }],
  ['uppercase secret', d => { d.deletionSecret = 'A'.repeat(64); }],
  ['short secret', d => { d.deletionSecret = 'a'.repeat(63); }],
  ['long secret', d => { d.deletionSecret = 'a'.repeat(65); }],
  ['nonhex secret', d => { d.deletionSecret = 'g'.repeat(64); }],
  ['null secret', d => { d.deletionSecret = null; }],
  ['wrong UUID', d => { d.reportID = '00000000-0000-4000-0000-000000000001'; }],
]) test(`REFUSE deletion ${label}`, () => {
  const value = deletion(); mutate(value);
  refused(encodeCoverageDeletion, value); refused(decodeCoverageDeletion, utf8(JSON.stringify(value)));
});

const minimal = text(read('report-minimal.json'));
const malformed = [
  ['leading whitespace', ' ' + minimal], ['trailing newline', minimal + '\n'],
  ['BOM', '\ufeff' + minimal], ['trailing value', minimal + '{}'],
  ['different root key order', '{"schema":"coverage-report-v1","apps":' + minimal.split('"apps":')[1].split(',"disclosureVersion"')[0] + ',"disclosureVersion":1,"reportID":"00000000-0000-4000-8000-000000000001"}'],
  ['duplicate decoded root key', minimal.replace('"schema":', '"schema":"coverage-report-v1","sch\\u0065ma":')],
  ['duplicate app key', minimal.replace('"bundleID":', '"bundleID":"com.example.app","bundleID":')],
  ['escaped ASCII key', minimal.replace('"apps"', '"\\u0061pps"')],
  ['escaped Unicode text', text(read('report-unicode.json')).replace('Café', 'Caf\\u00e9')],
  ['lone high surrogate', minimal.replace('Example App', '\\ud800')],
  ['lone low surrogate', minimal.replace('Example App', '\\udfff')],
  ['fraction', minimal.replace('"disclosureVersion":1', '"disclosureVersion":1.0')],
  ['exponent', minimal.replace('"disclosureVersion":1', '"disclosureVersion":1e0')],
  ['negative zero', minimal.replace('"disclosureVersion":1', '"disclosureVersion":-0')],
  ['leading zero', minimal.replace('"disclosureVersion":1', '"disclosureVersion":01')],
  ['unsafe integer', minimal.replace('"disclosureVersion":1', '"disclosureVersion":9007199254740992')],
  ['depth five', '[[[[[0]]]]]'], ['depth sixteen', '['.repeat(16) + '0' + ']'.repeat(16)],
  ['unknown depth five', minimal.replace('"version":null', '"version":null,"extra":[[[[0]]]]')],
  ['unclosed string', '"unterminated'], ['trailing comma', minimal.replace('null}', 'null,}')],
  ['nonobject root', 'null'], ['root array', '[]'], ['empty object', '{}'],
];
for (const [label, wire] of malformed) test(`REFUSE wire ${label}`, () => refused(decodeCoverageReport, utf8(wire)));

test('REFUSE noncanonical app ordering and nested key ordering', () => {
  const original = JSON.parse(read('report-unicode.json'));
  original.apps.reverse(); refused(decodeCoverageReport, utf8(JSON.stringify(original)));
  refused(decodeCoverageReport, utf8(minimal.replace('{"bundleID":"com.example.app","displayName":"Example App","version":null}', '{"version":null,"displayName":"Example App","bundleID":"com.example.app"}')));
  const d = deletion(); refused(decodeCoverageDeletion, utf8(JSON.stringify({ reportID: d.reportID, deletionSecret: d.deletionSecret })));
});

for (const [label, bytes] of [
  ['invalid UTF8', Uint8Array.of(0xff)], ['overlong UTF8', Uint8Array.of(0xc0, 0xaf)],
  ['encoded surrogate', Uint8Array.of(0xed, 0xa0, 0x80)], ['truncated UTF8', Uint8Array.of(0xf0, 0x9f, 0xa7)],
  ['report over 16384', new Uint8Array(16385)], ['deletion over 512', new Uint8Array(513)],
]) test(`REFUSE bytes ${label}`, () => {
  refused(decodeCoverageReport, bytes); refused(decodeCoverageDeletion, bytes);
});

for (const [label, factory] of [
  ['own getter', hook => { const r = report(); Object.defineProperty(r, 'apps', { get: hook, enumerable: true }); return r; }],
  ['known nonenumerable field', () => { const r = report(); Object.defineProperty(r, 'schema', { value: r.schema, enumerable: false }); return r; }],
  ['setter descriptor', hook => { const r = report(); Object.defineProperty(r, 'schema', { set: hook, enumerable: true }); return r; }],
  ['app getter', hook => { const r = report(); Object.defineProperty(r.apps[0], 'version', { get: hook, enumerable: true }); return r; }],
  ['array element getter', hook => { const r = report(); Object.defineProperty(r.apps, '0', { get: hook, enumerable: true }); return r; }],
  ['root toJSON', hook => ({ ...report(), toJSON: hook })],
  ['nested toJSON', hook => { const r = report(); r.apps[0].toJSON = hook; return r; }],
  ['symbol coercion', hook => ({ ...report(), [Symbol.toPrimitive]: hook })],
  ['symbol extra', () => ({ ...report(), [Symbol('hidden')]: true })],
  ['nonenumerable extra', () => Object.defineProperty(report(), 'hidden', { value: 1 })],
  ['inherited extra', () => Object.assign(Object.create({ hidden: true }), report())],
  ['class record', () => Object.assign(new (class Report {})(), report())],
  ['boxed name', () => { const r = report(); r.apps[0].displayName = new String('Example App'); return r; }],
  ['sparse array', () => { const r = report(); r.apps = new Array(1); return r; }],
  ['decorated array', () => { const r = report(); r.apps.note = true; return r; }],
  ['array symbol', () => { const r = report(); r.apps[Symbol('x')] = true; return r; }],
  ['array nonenumerable', () => { const r = report(); Object.defineProperty(r.apps, 'hidden', { value: 1 }); return r; }],
  ['array subclass', () => { const r = report(); class Apps extends Array {} r.apps = Apps.of(r.apps[0]); return r; }],
  ['oversized sparse array', () => { const r = report(); r.apps = new Array(4294967295); return r; }],
  ['root proxy', hook => new Proxy(report(), { get: hook, ownKeys: hook, getPrototypeOf: hook, getOwnPropertyDescriptor: hook })],
  ['app proxy', hook => { const r = report(); r.apps[0] = new Proxy(r.apps[0], { get: hook, ownKeys: hook, getPrototypeOf: hook, getOwnPropertyDescriptor: hook }); return r; }],
  ['array proxy', hook => { const r = report(); r.apps = new Proxy(r.apps, { get: hook, ownKeys: hook, getPrototypeOf: hook, getOwnPropertyDescriptor: hook }); return r; }],
  ['revoked proxy', () => { const p = Proxy.revocable(report(), {}); p.revoke(); return p.proxy; }],
]) test(`REFUSE adversarial report ${label}; zero hooks`, () => {
  let calls = 0; const hook = () => { calls++; throw new Error('PRIVATE getter text'); };
  const value = factory(hook);
  refused(encodeCoverageReport, value);
  assert.equal(calls, 0);
});

for (const [label, factory] of [
  ['getter', hook => Object.defineProperty(deletion(), 'deletionSecret', { get: hook, enumerable: true })],
  ['proxy', hook => new Proxy(deletion(), { get: hook, ownKeys: hook, getPrototypeOf: hook, getOwnPropertyDescriptor: hook })],
  ['revoked', () => { const p = Proxy.revocable(deletion(), {}); p.revoke(); return p.proxy; }],
  ['toJSON', hook => ({ ...deletion(), toJSON: hook })],
  ['boxed', () => Object.assign(new String('private'), deletion())],
  ['symbol', () => ({ ...deletion(), [Symbol('extra')]: 1 })],
]) test(`REFUSE adversarial deletion ${label}; zero hooks`, () => {
  let calls = 0; const hook = () => { calls++; throw new Error('PRIVATE secret'); };
  refused(encodeCoverageDeletion, factory(hook)); assert.equal(calls, 0);
});

for (const [label, factory] of [
  ['string', () => minimal], ['array', () => Array.from(read('report-minimal.json'))],
  ['ArrayBuffer', () => new ArrayBuffer(8)], ['DataView', () => new DataView(new ArrayBuffer(8))],
  ['Uint16Array', () => new Uint16Array(8)], ['Int8Array', () => new Int8Array(8)],
  ['Uint8ClampedArray', () => new Uint8ClampedArray(8)],
  ['proxy', hook => new Proxy(new Uint8Array(read('report-minimal.json')), { get: hook, getPrototypeOf: hook, ownKeys: hook, getOwnPropertyDescriptor: hook })],
  ['revoked proxy', () => { const p = Proxy.revocable(new Uint8Array(8), {}); p.revoke(); return p.proxy; }],
  ['shared backing', () => new Uint8Array(new SharedArrayBuffer(256))],
  ['subclass', hook => { class Bytes extends Uint8Array { get byteLength() { return hook(); } } return new Bytes(read('report-minimal.json')); }],
  ['buffer accessor', hook => Object.defineProperty(new Uint8Array(read('report-minimal.json')), 'buffer', { get: hook })],
  ['byteLength accessor', hook => Object.defineProperty(new Uint8Array(read('report-minimal.json')), 'byteLength', { get: hook })],
  ['byteOffset accessor', hook => Object.defineProperty(new Uint8Array(read('report-minimal.json')), 'byteOffset', { get: hook })],
  ['iterator hook', hook => Object.defineProperty(new Uint8Array(read('report-minimal.json')), Symbol.iterator, { value: hook })],
  ['toJSON hook', hook => Object.defineProperty(new Uint8Array(read('report-minimal.json')), 'toJSON', { value: hook })],
  ['coercion hook', hook => Object.defineProperty(new Uint8Array(read('report-minimal.json')), Symbol.toPrimitive, { value: hook })],
  ['fake view', hook => ({ byteLength: 186, buffer: new ArrayBuffer(186), [Symbol.iterator]: hook })],
  ['detached view', () => { const value = new Uint8Array(8); structuredClone(value.buffer, { transfer: [value.buffer] }); return value; }],
]) test(`REFUSE adversarial bytes ${label}; zero hooks`, () => {
  let calls = 0; const hook = () => { calls++; throw new Error('PRIVATE byte hook'); };
  const value = factory(hook);
  refused(decodeCoverageReport, value); refused(decodeCoverageDeletion, value);
  assert.equal(calls, 0);
});

test('POSITIVE intrinsic offset/length bounds only expose the supplied owned view', () => {
  for (const [decode, name] of [[decodeCoverageReport, 'report-minimal.json'], [decodeCoverageDeletion, 'deletion.json']]) {
    const bytes = read(name); const backing = new Uint8Array(bytes.length + 6);
    backing.fill(255); backing.set(bytes, 3);
    const view = new Uint8Array(backing.buffer, 3, bytes.length);
    const result = accepted(decode, view, 'validated', JSON.parse(bytes), bytes);
    backing.fill(0);
    assert.deepEqual(Array.from(result.bytes), Array.from(bytes));
  }
});

test('receipt validation has no send/log/entropy/timer effects', () => {
  let calls = 0; const hook = () => { calls++; throw new Error('unexpected effect'); };
  const saved = { fetch: globalThis.fetch, setTimeout: globalThis.setTimeout, setInterval: globalThis.setInterval, log: console.log, warn: console.warn, error: console.error, random: Math.random };
  try {
    globalThis.fetch = hook; globalThis.setTimeout = hook; globalThis.setInterval = hook;
    console.log = hook; console.warn = hook; console.error = hook; Math.random = hook;
    const r = encodeCoverageReport(report()); receipt(r);
    const d = encodeCoverageDeletion(deletion()); receipt(d);
    const rd = decodeCoverageReport(new Uint8Array(read('report-minimal.json'))); receipt(rd);
    const dd = decodeCoverageDeletion(new Uint8Array(read('deletion.json'))); receipt(dd);
    refused(encodeCoverageReport, null); refused(decodeCoverageDeletion, null);
  } finally {
    globalThis.fetch = saved.fetch; globalThis.setTimeout = saved.setTimeout; globalThis.setInterval = saved.setInterval;
    console.log = saved.log; console.warn = saved.warn; console.error = saved.error; Math.random = saved.random;
  }
  assert.equal(calls, 0);
});

for (const [decode, name] of [[decodeCoverageReport, 'report-minimal.json'], [decodeCoverageDeletion, 'deletion.json']]) {
  test(`REFUSE valid canonical shared backing ${name}; input unchanged`, () => {
    const literal = read(name);
    const shared = new Uint8Array(new SharedArrayBuffer(literal.byteLength));
    shared.set(literal);
    const before = Array.from(shared);
    refused(decode, shared);
    assert.deepEqual(Array.from(shared), before, 'shared canonical input never mutates');
  });
}
