import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {preservedPackageSHA256} from '../../../scripts/lib/package-registration-preservation.mjs';

// Independent literal authority, never computed from the preservation helper.
const originalSHA = '8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699';
const predecessorSHA = '1bdfbe0bc438e7383bb92f432bcd43a1825bb2001228ad9babe15dfc818f4558';
const candidateSHA = 'ce5dae62dfa109f3823dc2b38175ca92155beec89f0667ea0b72f0e3ae54a7c5';
const fixture = name => readFileSync(new URL(`../../../Fixtures/OwnedProcess/package-registration/${name}`, import.meta.url));
const predecessor = fixture('Package.predecessor.swift');
const candidate = fixture('Package.owned-process.swift');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const header = '    targets: [\n';
const first = '        .testTarget(name: "PatchedOwnedProcessTests", dependencies: ["PatchedDisposableProof"],\n';
const second = '                    path: "Tests/PatchedOwnedProcessTests"),\n';
const registration = first + second;
const count = (text, literal) => text.split(literal).length - 1;
const text = candidate.toString('utf8');
function changed(before, after) {
  assert.equal(count(text, before), 1, 'mutation anchor occurs exactly once');
  const result = Buffer.from(text.replace(before, after));
  assert.notDeepEqual(result, candidate, 'negative differs from approved candidate');
  assert.notDeepEqual(result, predecessor, 'negative is not approved predecessor');
  return result;
}
function accepts(bytes) {
  const input = Buffer.from(bytes), before = Buffer.from(input);
  assert.equal(preservedPackageSHA256(input), originalSHA);
  assert.deepEqual(input, before, 'acceptance preserves input bytes');
}
function refuses(value) {
  // Every negative independently proves the newly registered candidate works.
  // An always-refusing stub therefore cannot pass the negative checks.
  accepts(candidate);
  const before = Buffer.isBuffer(value) ? Buffer.from(value) : null;
  assert.throws(() => preservedPackageSHA256(value), TypeError);
  if (before) assert.deepEqual(value, before, 'refusal preserves input bytes');
}

test('owned-process package fixtures retain independent exact digests and UTF-8 bytes', () => {
  assert.equal(digest(predecessor), predecessorSHA);
  assert.equal(digest(candidate), candidateSHA);
  for (const bytes of [predecessor, candidate]) {
    assert.deepEqual(Buffer.from(bytes.toString('utf8')), bytes);
    assert.equal(bytes.includes(Buffer.from('\r')), false);
    assert.equal(bytes.includes(Buffer.from([0])), false);
    assert.equal(bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])), false);
  }
});
test('only the exact two lines directly after the unique targets header are additive', () => {
  const old = predecessor.toString('utf8');
  assert.equal(count(old, header), 1);
  assert.equal(count(text, header), 1);
  assert.equal(count(old, registration), 0);
  assert.equal(count(text, registration), 1);
  assert.equal(count(text, header + registration), 1);
  for (const line of [first, second]) {
    assert.equal(count(old, line), 0);
    assert.equal(count(text, line), 1);
  }
  assert.deepEqual(Buffer.from(text.replace(header + registration, header)), predecessor);
  assert.deepEqual(Buffer.from(old.replace(header, header + registration)), candidate);
});
test('approved predecessor remains accepted without input mutation', () => accepts(predecessor));
test('new exact owned-process registration returns the historical digest', () => accepts(candidate));
test('removing the entire new block is accepted as the exact approved predecessor', () => {
  const removed = Buffer.from(text.replace(header + registration, header));
  assert.deepEqual(removed, predecessor);
  assert.equal(digest(removed), predecessorSHA);
  accepts(removed);
});

const mutations = [
  ['existing package name', changed('    name: "PatchedProof",', '    name: "ChangedProof",')],
  ['existing platform', changed('platforms: [.macOS(.v13)]', 'platforms: [.macOS(.v14)]')],
  ['new target name', changed(first, first.replace('PatchedOwnedProcessTests', 'OtherTests'))],
  ['new dependency', changed(first, first.replace('PatchedDisposableProof', 'PatchedCore'))],
  ['extra new dependency', changed(first, first.replace('["PatchedDisposableProof"]', '["PatchedDisposableProof", "PatchedCore"]'))],
  ['missing new dependency', changed(first, first.replace('["PatchedDisposableProof"]', '[]'))],
  ['new path', changed(second, second.replace('Tests/PatchedOwnedProcessTests', 'Tests/Other'))],
  ['first line indent', changed(first, first.slice(1))],
  ['second line indent', changed(second, second.slice(1))],
  ['new whitespace', changed(first, first.replace('dependencies:', 'dependencies :'))],
  ['missing first line', changed(first, '')],
  ['missing second line', changed(second, '')],
  ['duplicated block', changed(registration, registration + registration)],
  ['duplicated first line', changed(first, first + first)],
  ['duplicated second line', changed(second, second + second)],
  ['reversed lines', changed(registration, second + first)],
  ['moved off header', changed(header + registration, header + '\n' + registration)],
  ['moved block to end', Buffer.from(text.replace(registration, '') + registration)],
  ['unknown product', changed('    products: [\n', '    products: [\n        .library(name: "Unknown", targets: ["Unknown"]),\n')],
  ['unknown target', changed(header, header + '        .target(name: "Unknown"),\n')],
  ['CRLF', Buffer.from(text.replaceAll('\n', '\r\n'))],
  ['BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), candidate])],
  ['NUL', Buffer.concat([candidate, Buffer.from([0])])],
  ['invalid UTF-8', Buffer.concat([candidate, Buffer.from([0xc3, 0x28])])],
  ['trailing data', Buffer.concat([candidate, Buffer.from('// extra\n')])],
  ['trailing newline', Buffer.concat([candidate, Buffer.from('\n')])],
  ['missing final byte', candidate.subarray(0, candidate.length - 1)],
  ['over 64 KiB', Buffer.concat([candidate, Buffer.alloc(64 * 1024)])],
];
for (const [name, bytes] of mutations) test(`owned-process registration refuses mutation: ${name}`, () => {
  assert.notDeepEqual(bytes, candidate);
  assert.notDeepEqual(bytes, predecessor);
  refuses(bytes);
});
for (const [name, value] of [
  ['undefined', undefined], ['null', null], ['string', text],
  ['Uint8Array', new Uint8Array(candidate)], ['object', {bytes: candidate}],
  ['empty Buffer', Buffer.alloc(0)],
]) test(`owned-process registration refuses invalid input: ${name}`, () => refuses(value));
