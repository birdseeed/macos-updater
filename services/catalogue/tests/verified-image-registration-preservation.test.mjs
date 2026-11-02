import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { reconstructPreVerifiedImageMain, reconstructPreVerifiedImageGuard } from '../../../scripts/checks/VerifiedImageRegistration.mjs';

// Independently authored PAT-2710 CHECK-MODIFIED contract. No source execution,
// image tool, Swift build, network or mutation is performed by these tests.
const mainPath = 'Tests/ArtifactInspectionChecks/main.swift';
const historicalCommit = 'bba4e242b75be91a73ae193dabc6befbcf2637e4';
const originalRawSHA256 = '49391a8effb74e3c348636c561c30318b487d1c2d7ded78e02ab12465dd0d2c0';
const originalNoCLTSHA256 = '190f638605f0d617b568b92f6cba44155bee1ec4872c521ab3aef7baa81d46f8';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
// Exact historical bytes are checked in so shallow exact-head/main CI needs no
// historical Git objects. The independent raw digest below pins this fixture.
const baseline = readFileSync(new URL('./fixtures/pre-verified-image-main.swift.txt', import.meta.url));
const current = readFileSync(new URL(`../../../${mainPath}`, import.meta.url));

// Literal bytes copied from the independently inspected Phase A additions.
// Five lines including final blank line, immediately after the import prelude.
const child = [
  '// CHECK-ADDED PAT-2710: inert child dispatch precedes ordinary registration.',
  'if CommandLine.arguments.dropFirst().first == "--verified-image-child" {',
  '    runVerifiedImageChild(Array(CommandLine.arguments.dropFirst()))',
  '}',
  '',
  ''
].join('\n');
// Fourteen lines including final blank line, after the existing ordinary
// addSizePolicyChecks() call and before the first existing for-pin case.
const registration = [
  '// CHECK-ADDED PAT-2710: same additive checks run focused and in the full gate.',
  'if Array(CommandLine.arguments.dropFirst()) == ["--verified-image"] {',
  '    cases.removeAll()',
  '    addVerifiedImageChecks()',
  '    var failures = 0',
  '    for (name, action) in cases {',
  '        do { try action(); print("PASS fixture: \\(name)") }',
  '        catch { failures += 1; print("FAIL fixture: \\(name): \\(error)") }',
  '    }',
  '    print("PAT-2710 verified image: \\(cases.count) cases, \\(failures) failures; no hdiutil or mount executed")',
  '    exit(failures == 0 ? 0 : 1)',
  '}',
  'addVerifiedImageChecks()',
  '',
  ''
].join('\n');
const importPrelude = 'import Foundation\nimport Darwin\nimport ArtifactInspection\n\n';
const registrationAnchor = 'addSizePolicyChecks()\n\nfor pin in FirefoxTargets.pins {';
const baselineText = baseline.toString('utf8');
const assembled = Buffer.from(baselineText
  .replace(importPrelude, importPrelude + child)
  .replace(registrationAnchor, 'addSizePolicyChecks()\n\n' + registration + 'for pin in FirefoxTargets.pins {'), 'utf8');
const currentText = current.toString('utf8');

function rejected(name, value) {
  test(name, () => {
    const before = Buffer.isBuffer(value) ? Buffer.from(value) : null;
    assert.throws(() => reconstructPreVerifiedImageMain(value), undefined, 'Changed/malformed input must refuse, never normalise');
    if (before) assert.deepEqual(value, before, 'Refusal must not mutate supplied bytes');
  });
}

test('historical raw main fixture is independently pinned to the inspected commit', () => {
  assert.equal(historicalCommit, 'bba4e242b75be91a73ae193dabc6befbcf2637e4');
  assert.ok(Buffer.isBuffer(baseline));
  assert.equal(digest(baseline), originalRawSHA256);
  assert.equal(baselineText.split(importPrelude).length, 2);
  assert.equal(baselineText.split(registrationAnchor).length, 2);
  assert.ok(!baselineText.includes('PAT-2710'));
});

test('current main contains exactly the two approved additions at the independent anchors', () => {
  assert.deepEqual(current, assembled, 'Outside bytes or addition positions changed');
  assert.equal(currentText.split(child).length, 2);
  assert.equal(currentText.split(registration).length, 2);
  assert.equal(child.split('\n').length - 1, 5);
  assert.equal(registration.split('\n').length - 1, 14);
});

test('reconstruction returns exact historical Buffer bytes and leaves input untouched', () => {
  const before = Buffer.from(current);
  const output = reconstructPreVerifiedImageMain(current);
  assert.ok(Buffer.isBuffer(output), 'API must return bytes, not lossy text');
  assert.deepEqual(output, baseline);
  assert.equal(digest(output), originalRawSHA256);
  assert.deepEqual(current, before);
  assert.notEqual(output, current, 'Reconstruction cannot reuse/mutate caller buffer');
});

test('independently assembled exact input is also accepted without relying on filesystem identity', () => {
  assert.deepEqual(reconstructPreVerifiedImageMain(Buffer.from(assembled)), baseline);
});

test('old NoCLT frozen main hash remains the same after its existing two exemptions', () => {
  const pinned = '// CHECK-ADDED PAT-2708: additive focused entry point; previous assertions unchanged.\nif Array(CommandLine.arguments.dropFirst()) == ["--pat-2708-pinned-signature"] {\n    runPinnedSignatureChecks()\n}\n\n';
  const unstapled = '// CHECK-ADDED PAT-2707: additive focused entry point; existing assertions unchanged.\nif Array(CommandLine.arguments.dropFirst()) == ["--pat-2707-unstapled"] {\n    runUnstapledEvidenceChecks()\n}\n\n';
  assert.equal(baselineText.split(pinned).length, 2);
  assert.equal(baselineText.split(unstapled).length, 2);
  assert.equal(digest(Buffer.from(baselineText.replace(pinned, '').replace(unstapled, ''))), originalNoCLTSHA256);
  const guard = readFileSync(new URL('../../../scripts/checks/NoCLTTrustSourceGuard.mjs', import.meta.url), 'utf8');
  assert.ok(guard.includes(`"${mainPath}": "${originalNoCLTSHA256}"`), 'Do not move the original frozen acceptance hash');
});

for (const [name, block] of [['child dispatch', child], ['focused/default registration', registration]]) {
  const without = currentText.replace(block, '');
  rejected(`missing ${name} refuses`, Buffer.from(without));
  rejected(`duplicate ${name} at original position refuses`, Buffer.from(currentText.replace(block, block + block)));
  rejected(`duplicate ${name} appended refuses`, Buffer.from(currentText + block));
  rejected(`modified ${name} comment refuses`, Buffer.from(currentText.replace(block, block.replace('PAT-2710', 'PAT-2711'))));
  rejected(`modified ${name} indentation refuses`, Buffer.from(currentText.replace(block, block.replace('    ', '   '))));
  rejected(`moved ${name} to end refuses despite byte-identical old assertions`, Buffer.from(without + block));
  rejected(`moved ${name} before imports refuses`, Buffer.from(block + without));
  rejected(`modified ${name} final blank separator refuses`, Buffer.from(currentText.replace(block, block.slice(0, -1))));
}
rejected('unextended historical main refuses rather than taking a compatibility bypass', baseline);
rejected('both additions absent refuse', Buffer.from(currentText.replace(child, '').replace(registration, '')));
rejected('child dispatch callback changed refuses', Buffer.from(currentText.replace('runVerifiedImageChild(Array(CommandLine.arguments.dropFirst()))', 'runVerifiedImageChild([])')));
rejected('focused branch condition changed refuses', Buffer.from(currentText.replace('["--verified-image"]', '["--verified-image-weakened"]')));
rejected('default registration call deleted refuses', Buffer.from(currentText.replace('}\naddVerifiedImageChecks()\n\nfor pin', '}\n\nfor pin')));
rejected('focused failure exit weakened refuses', Buffer.from(currentText.replace('exit(failures == 0 ? 0 : 1)\n}\naddVerifiedImageChecks()', 'exit(0)\n}\naddVerifiedImageChecks()')));
rejected('old existing assertion deletion refuses', Buffer.from(currentText.replace('        try expect(found == pin, "Target must match every reviewed pin")\n', '')));
rejected('old existing assertion edited refuses', Buffer.from(currentText.replace('Target must match every reviewed pin', 'Target may differ')));
rejected('outside import edit refuses', Buffer.from(currentText.replace('import Darwin\n', 'import Darwin // changed\n')));
rejected('trailing comment refuses', Buffer.concat([current, Buffer.from('// not an approved exemption\n')]));
rejected('leading comment refuses', Buffer.concat([Buffer.from('// extra prefix\n'), current]));
rejected('final newline removed refuses', current.subarray(0, current.length - 1));
rejected('truncated main refuses', current.subarray(0, Math.floor(current.length / 2)));
rejected('empty Buffer refuses', Buffer.alloc(0));
rejected('CRLF translation refuses without newline normalisation', Buffer.from(currentText.replaceAll('\n', '\r\n')));
rejected('embedded carriage return refuses', Buffer.concat([current.subarray(0, 10), Buffer.from([13]), current.subarray(10)]));
rejected('UTF8 BOM refuses', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), current]));
rejected('embedded NUL refuses', Buffer.concat([current.subarray(0, 10), Buffer.from([0]), current.subarray(10)]));
rejected('invalid UTF8 leading byte refuses', Buffer.concat([current, Buffer.from([0xff])]));
rejected('invalid UTF8 continuation sequence refuses', Buffer.concat([current.subarray(0, 10), Buffer.from([0xc3, 0x28]), current.subarray(10)]));
rejected('UTF16 bytes refuse', Buffer.from(currentText, 'utf16le'));
rejected('oversize Buffer refuses before any unbounded scanning', Buffer.alloc(1_048_577, 65));
for (const [label, value] of [
  ['string', currentText], ['Uint8Array', new Uint8Array(current)], ['array', [...current]],
  ['null', null], ['undefined', undefined], ['object', {}], ['number', 1],
  ['Buffer-like object', { type: 'Buffer', data: [...current] }]
]) rejected(`non-Buffer ${label} refuses`, value);

// Second, separately pinned exemption: the two integration lines in NoCLT's
// source guard. Its previous assertions, hashes and normalization stay exact.
const guardOriginalSHA256 = '700bcd989abbcbe18a77817cb11051d5d19331a7841ff98ab0d7f2ad7dc19075';
const guardBaseline = readFileSync(new URL('./fixtures/pre-verified-image-guard.mjs.txt', import.meta.url));
const guardCurrent = readFileSync(new URL('../../../scripts/checks/NoCLTTrustSourceGuard.mjs', import.meta.url));
const guardBaselineText = guardBaseline.toString('utf8');
const guardCurrentText = guardCurrent.toString('utf8');
const guardImport = "import { reconstructPreVerifiedImageMain } from './VerifiedImageRegistration.mjs';\n";
const guardCall = '    bytes = reconstructPreVerifiedImageMain(bytes);\n';
const guardImportAnchor = "import { fileURLToPath } from 'node:url';\n";
const guardCallAnchor = "  if (path.endsWith('/main.swift')) {\n";
const guardAssembled = Buffer.from(guardBaselineText
  .replace(guardImportAnchor, guardImportAnchor + guardImport)
  .replace(guardCallAnchor, guardCallAnchor + guardCall));
function guardRejected(name, value) {
  test(`NoCLT reconstruction: ${name}`, () => {
    const before = Buffer.isBuffer(value) ? Buffer.from(value) : null;
    assert.throws(() => reconstructPreVerifiedImageGuard(value), undefined, 'Only the exact two reviewed integration lines may be stripped');
    if (before) assert.deepEqual(value, before, 'Guard refusal mutated input');
  });
}

test('NoCLT historical fixture authenticates exact original guard bytes', () => {
  assert.equal(digest(guardBaseline), guardOriginalSHA256);
  assert.equal(guardBaselineText.split(guardImportAnchor).length, 2);
  assert.equal(guardBaselineText.split(guardCallAnchor).length, 2);
  assert.ok(!guardBaselineText.includes('reconstructPreVerifiedImageMain'));
});
test('NoCLT current source is exactly original plus the two approved positioned lines', () => {
  assert.deepEqual(guardCurrent, guardAssembled);
  assert.equal(guardCurrentText.split(guardImport).length, 2);
  assert.equal(guardCurrentText.split(guardCall).length, 2);
});
test('NoCLT reconstruction returns exact authenticated historical Buffer without mutation', () => {
  const before = Buffer.from(guardCurrent);
  const output = reconstructPreVerifiedImageGuard(guardCurrent);
  assert.ok(Buffer.isBuffer(output));
  assert.deepEqual(output, guardBaseline);
  assert.equal(digest(output), guardOriginalSHA256);
  assert.deepEqual(guardCurrent, before);
  assert.notEqual(output, guardCurrent);
  assert.deepEqual(reconstructPreVerifiedImageGuard(Buffer.from(guardAssembled)), guardBaseline);
});
for (const [name, line] of [['import', guardImport], ['scoped call', guardCall]]) {
  const without = guardCurrentText.replace(line, '');
  guardRejected(`missing ${name}`, Buffer.from(without));
  guardRejected(`duplicate ${name} adjacent`, Buffer.from(guardCurrentText.replace(line, line + line)));
  guardRejected(`duplicate ${name} appended`, Buffer.from(guardCurrentText + line));
  guardRejected(`modified ${name} identifier`, Buffer.from(guardCurrentText.replace(line, line.replace('reconstructPreVerifiedImageMain', 'reconstructChangedMain'))));
  guardRejected(`modified ${name} spacing`, Buffer.from(guardCurrentText.replace(line, line.replace(' = ', '  = ').replace('import {', 'import  {'))));
  guardRejected(`moved ${name} to end`, Buffer.from(without + line));
  guardRejected(`moved ${name} to start`, Buffer.from(line + without));
}
guardRejected('historical unextended guard is not a compatibility bypass', guardBaseline);
guardRejected('both integration lines absent', Buffer.from(guardCurrentText.replace(guardImport, '').replace(guardCall, '')));
guardRejected('call outside main-only condition', Buffer.from(guardCurrentText.replace(guardCall, '').replace(guardCallAnchor, guardCall + guardCallAnchor)));
guardRejected('historical frozen main checksum edited', Buffer.from(guardCurrentText.replace(originalNoCLTSHA256, '0'.repeat(64))));
guardRejected('historical assertion removed', Buffer.from(guardCurrentText.replace("assert.deepEqual(failures, [], 'No productive CLT command references outside exact historical data tables');\n", '')));
guardRejected('historical assertion weakened', Buffer.from(guardCurrentText.replace('assert.equal(digest(bytes), expected,', 'assert.equal(expected, expected,')));
guardRejected('outside import modified', Buffer.from(guardCurrentText.replace("import assert from 'node:assert/strict';", "import assert from 'node:assert';")));
guardRejected('extra trailing comment', Buffer.concat([guardCurrent, Buffer.from('// extra exemption\n')]));
guardRejected('truncated source', guardCurrent.subarray(0, Math.floor(guardCurrent.length / 2)));
guardRejected('final newline removed', guardCurrent.subarray(0, guardCurrent.length - 1));
guardRejected('empty buffer', Buffer.alloc(0));
guardRejected('CRLF source', Buffer.from(guardCurrentText.replaceAll('\n', '\r\n')));
guardRejected('embedded carriage return', Buffer.concat([guardCurrent.subarray(0, 10), Buffer.from([13]), guardCurrent.subarray(10)]));
guardRejected('UTF8 BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), guardCurrent]));
guardRejected('embedded NUL', Buffer.concat([guardCurrent.subarray(0, 10), Buffer.from([0]), guardCurrent.subarray(10)]));
guardRejected('invalid UTF8', Buffer.concat([guardCurrent, Buffer.from([0xff])]));
guardRejected('invalid UTF8 continuation', Buffer.concat([guardCurrent.subarray(0, 10), Buffer.from([0xc3, 0x28]), guardCurrent.subarray(10)]));
guardRejected('UTF16 source', Buffer.from(guardCurrentText, 'utf16le'));
guardRejected('oversize source', Buffer.alloc(1_048_577, 65));
for (const [name, value] of [
  ['string', guardCurrentText], ['Uint8Array', new Uint8Array(guardCurrent)],
  ['array', [...guardCurrent]], ['null', null], ['undefined', undefined],
  ['object', {}], ['number', 1], ['Buffer-like object', { type: 'Buffer', data: [...guardCurrent] }]
]) guardRejected(`non-Buffer ${name}`, value);
