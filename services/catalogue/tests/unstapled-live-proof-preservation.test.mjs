import {preservedPinnedSignatureLiveProofBytes} from '../../../scripts/lib/pinned-signature-live-proof-preservation.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {preservedUnstapledLiveProofSHA256} from '../../../scripts/lib/unstapled-live-proof-preservation.mjs';

// Independent literal pin and expected edit. Do not import helper policy or exports.
const path = "Tests/PatchedOperatorTests/LiveCatalogueProof.swift";
const historicalSHA256 = "3938ef5692b4cb540a3c2b55ecb7668e83a359edb8a348848863035efd4c6ed4";
const before = "    for key in [\"containerSignature\", \"containerGatekeeper\", \"containerTicket\"] {\n        guard let result = observed[key] as? [String: Any], let code = unsigned(result[\"exitCode\"]) else {\n            throw CheckFailure(description: \"Inspection record omits the \\(key) result\")\n        }\n        try expect(code != 0, \"Inspection record does not keep the failing \\(key) result\")\n    }\n";
const after = "    try expect(observed[\"ticket\"] == nil && observed[\"containerTicket\"] == nil &&\n               flag(assessment[\"containerTicketPassed\"]) == false,\n               \"Live inspection retained ticket observations or claimed current ticket validation\")\n    try expect(ran.allSatisfy { value in\n        guard let command = value as? [String: Any], let executable = command[\"executable\"] as? String,\n              let arguments = command[\"arguments\"] as? [String] else { return false }\n        return executable != \"/usr/bin/xcrun\" && !arguments.contains(\"stapler\")\n    }, \"Live inspection ran a stapling command or has malformed command records\")\n    for key in [\"containerSignature\", \"containerGatekeeper\"] {\n        guard let result = observed[key] as? [String: Any], let code = unsigned(result[\"exitCode\"]) else {\n            throw CheckFailure(description: \"Inspection record omits the \\(key) result\")\n        }\n        try expect(code != 0, \"Inspection record does not keep the failing \\(key) result\")\n    }\n";
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const original = readFileSync(new URL('../protocol/fixtures/unstapled-live-proof-preservation/LiveCatalogueProof.original.swift', import.meta.url));
const current = preservedPinnedSignatureLiveProofBytes(path, readFileSync(new URL('../../../Tests/PatchedOperatorTests/LiveCatalogueProof.swift', import.meta.url)));
function replaceOnce(bytes, needleText, replacementText) {
  const needle = Buffer.from(needleText), replacement = Buffer.from(replacementText);
  const index = bytes.indexOf(needle);
  assert.ok(index >= 0, 'independent mutation anchor exists');
  assert.equal(bytes.indexOf(needle, index + 1), -1, 'independent mutation anchor is unique');
  return Buffer.concat([bytes.subarray(0, index), replacement, bytes.subarray(index + needle.length)]);
}
const expectedCurrent = replaceOnce(original, before, after);
function refuses(candidatePath, bytes) {
  const snapshot = Buffer.isBuffer(bytes) ? Buffer.from(bytes) : undefined;
  assert.throws(() => preservedUnstapledLiveProofSHA256(candidatePath, bytes), TypeError);
  if (snapshot) assert.deepEqual(bytes, snapshot, 'refusal leaves input exact');
}
test('independently pinned original matches immutable frozen-v1 entry', () => {
  const manifest = JSON.parse(readFileSync(new URL('../protocol/fixtures/catalogue-v2/frozen-v1-sha256.json', import.meta.url)));
  assert.equal(manifest[path], historicalSHA256);
  assert.equal(sha256(original), historicalSHA256);
});
test('current live proof has exactly the new observation assertions and two preserved container failures', () => {
  assert.ok(current.equals(expectedCurrent), 'prospective RED until the exact proof change is adopted');
  assert.deepEqual(replaceOnce(current, after, before), original, 'all other historical bytes are exact');
});
for (const [name, bytes] of [['historical', original], ['reviewed current', expectedCurrent]]) {
  test(`accepts only exact ${name} reconstruction without modifying input`, () => {
    const snapshot = Buffer.from(bytes);
    assert.equal(preservedUnstapledLiveProofSHA256(path, bytes), historicalSHA256);
    assert.equal(preservedUnstapledLiveProofSHA256(path, bytes), historicalSHA256);
    assert.deepEqual(bytes, snapshot);
  });
  for (const [label, mutated] of [
    ['trailing comment', Buffer.concat([bytes, Buffer.from('// unrelated\n')])],
    ['truncation', bytes.subarray(0, bytes.length - 1)],
    ['invalid UTF8', Buffer.concat([bytes, Buffer.from([0xff])])],
    ['BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), bytes])],
    ['NUL', Buffer.concat([bytes, Buffer.from([0])])],
    ['CRLF', Buffer.from(bytes.toString('utf8').replaceAll('\n', '\r\n'))],
    ['outside edit import', replaceOnce(bytes, 'import Foundation\n', 'import Foundation\n// unrelated\n')],
  ]) test(`refuses ${name} ${label}`, () => refuses(path, mutated));
}
for (const [label, mutated] of [
  ['missing entire replacement', replaceOnce(expectedCurrent, after, '')],
  ['duplicate replacement', replaceOnce(expectedCurrent, after, after + after)],
  ['modified replacement', replaceOnce(expectedCurrent, after, after + ' ')],
  ['old and new anchors together', replaceOnce(expectedCurrent, after, after + before)],
  ['missing ticket absence check', replaceOnce(expectedCurrent, 'observed["ticket"] == nil && ', '')],
  ['missing container ticket absence check', replaceOnce(expectedCurrent, 'observed["containerTicket"] == nil &&', 'true &&')],
  ['missing recorded command check', replaceOnce(expectedCurrent, 'return executable != "/usr/bin/xcrun" && !arguments.contains("stapler")', 'return true')],
  ['malformed command records accepted', replaceOnce(expectedCurrent, 'let arguments = command["arguments"] as? [String] else { return false }', 'let arguments = command["arguments"] as? [String] else { return true }')],
  ['signature refusal removed', replaceOnce(expectedCurrent, 'for key in ["containerSignature", "containerGatekeeper"] {', 'for key in ["containerGatekeeper"] {')],
  ['Gatekeeper refusal removed', replaceOnce(expectedCurrent, 'for key in ["containerSignature", "containerGatekeeper"] {', 'for key in ["containerSignature"] {')],
  ['ticket failure still mandatory', replaceOnce(expectedCurrent, 'for key in ["containerSignature", "containerGatekeeper"] {', 'for key in ["containerSignature", "containerGatekeeper", "containerTicket"] {')],
  ['raw negative exit accepted', replaceOnce(expectedCurrent, 'try expect(code != 0, "Inspection record does not keep the failing', 'try expect(code == 0, "Inspection record does not keep the failing')],
  ['ticket validated flag fabricated', replaceOnce(expectedCurrent, 'flag(assessment["containerTicketPassed"]) == false,\n               "Live inspection', 'flag(assessment["containerTicketPassed"]) == true,\n               "Live inspection')],
]) test(`refuses current ${label}`, () => refuses(path, mutated));
// Old assertion text outside the edited loop is independently retained.
for (const [label, anchor] of [
  ['receipt authority refusal', '    try expect(!receipt.installationAuthorized, "Live receipt grants installation authority")\n'],
  ['live origin requirement', '    try expect(assessment["origin"] as? String == "live" && flag(assessment["appChecksPassed"]) == true &&\n'],
  ['signature and Gatekeeper failure summary', '    try expect(flag(assessment["containerSignaturePassed"]) == false && flag(assessment["containerGatekeeperPassed"]) == false &&\n'],
]) test(`refuses deletion of original ${label}`, () => refuses(path, replaceOnce(expectedCurrent, anchor, '')));
for (const value of [undefined, null, '', {}, new Uint8Array(expectedCurrent), Buffer.alloc(0), Buffer.alloc(131073)]) {
  test(`refuses nonbuffer or unbounded input ${String(value?.constructor?.name)}`, () => refuses(path, value));
}
for (const wrongPath of ['', 'Package.swift', '../' + path, '/' + path, path + '/', path.toLowerCase(), path.replaceAll('/', '\\'), '__proto__', null, {}, new String(path)]) {
  test(`refuses nonexact path ${String(wrongPath)}`, () => refuses(wrongPath, expectedCurrent));
}
