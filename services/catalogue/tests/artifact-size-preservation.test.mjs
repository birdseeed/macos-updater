import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {preservedArtifactSizeSHA256} from '../../../scripts/lib/artifact-size-preservation.mjs';

// Independent literal pins and edit expectations, not obtained from the helper.
const expectations = {
  "Sources/PatchedCore/CatalogueVerifier.swift": {
    "sha256": "86a195b79421f4e0e0ad92aea535044790b6384b768da71324f690cfbd0bfe5f",
    "edits": [
      [
        "import CryptoKit\n\n",
        "import CryptoKit\nimport ArtifactInspection\n\n"
      ],
      [
        "              let length = fields[\"byteLength\"]?.unsigned, length > 0, length <= 170_000_000 else { throw CoreFailure.invalidPayload }\n",
        "              let length = fields[\"byteLength\"]?.unsigned, length > 0, length <= UInt64(ArtifactSizePolicy.absoluteMaximumBytes) else { throw CoreFailure.invalidPayload }\n"
      ]
    ]
  },
  "Sources/PatchedOperator/CatalogueSigning.swift": {
    "sha256": "3db34f1a2d2e6ac5fd321ee90aa44cf9d4a831f7111e1aaea90d4428556702d1",
    "edits": [
      [
        "    static let maximumArtifactBytes: Int64 = 170_000_000\n",
        "    static let maximumArtifactBytes: Int64 = ArtifactSizePolicy.absoluteMaximumBytes\n"
      ]
    ]
  },
  "Tests/PatchedCoreChecks/CatalogueChecks.swift": {
    "sha256": "82799522307be5025c6225668fbf5e68197bdb2d053aa9a1a13018ad561c2faa",
    "edits": [
      [
        "    for value: Any in [0, -1, 170_000_001, 3.5, true, \"3\", NSNull()] {\n",
        "    for value: Any in [0, -1, 2_147_483_649, 3.5, true, \"3\", NSNull()] {\n"
      ]
    ]
  },
  "Tests/PatchedCoreChecks/main.swift": {
    "sha256": "4d86b914a4d1c89b677f1d224397901069c34b74a41b8252610d15a34f06ee5f",
    "edits": [
      [
        "@MainActor func check(_ name: String, _ action: @escaping () throws -> Void) { cases.append((name, action)) }\nregisterCatalogueChecks()\n",
        "@MainActor func check(_ name: String, _ action: @escaping () throws -> Void) { cases.append((name, action)) }\nif arguments == [\"--size-policy\"] {\n    registerSizePolicyCatalogueChecks()\n    var failures = 0\n    for (name, action) in cases {\n        do { try action(); print(\"PASS fixture: \\(name)\") }\n        catch { failures += 1; print(\"FAIL fixture: \\(name): \\(error)\") }\n    }\n    print(\"PAT-2709 catalogue: \\(cases.count) cases, \\(failures) failures\")\n    exit(failures == 0 ? 0 : 1)\n}\nregisterSizePolicyCatalogueChecks()\nregisterCatalogueChecks()\n"
      ]
    ]
  }
};
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const current = path => readFileSync(new URL('../../../' + path, import.meta.url));
const fixtureNames = ['CoreCatalogueVerifier.original.swift', 'OperatorCatalogueSigning.original.swift', 'CoreCatalogueChecks.original.swift', 'CoreMain.original.swift'];
const fixture = index => readFileSync(new URL('../protocol/fixtures/artifact-size-preservation/' + fixtureNames[index], import.meta.url));
function replaceOnce(bytes, before, after) {
  const needle = Buffer.from(before), replacement = Buffer.from(after);
  const index = bytes.indexOf(needle);
  assert.ok(index >= 0, 'independent mutation anchor exists');
  assert.equal(bytes.indexOf(needle, index + 1), -1, 'independent mutation anchor unique');
  return Buffer.concat([bytes.subarray(0, index), replacement, bytes.subarray(index + needle.length)]);
}
function refuses(path, bytes) {
  const snapshot = Buffer.isBuffer(bytes) ? Buffer.from(bytes) : undefined;
  assert.throws(() => preservedArtifactSizeSHA256(path, bytes), TypeError);
  if (snapshot) assert.deepEqual(bytes, snapshot, 'refusal leaves input exact');
}
for (const [index, [path, spec]] of Object.entries(expectations).entries()) {
  const original = fixture(index), candidate = current(path);
  test(`historical and current exact reconstruction: ${path}`, () => {
    assert.equal(sha(original), spec.sha256, 'independently pinned original fixture');
    let reconstructed = Buffer.from(candidate);
    for (const [before, after] of spec.edits) reconstructed = replaceOnce(reconstructed, after, before);
    assert.deepEqual(reconstructed, original, 'only reviewed edits differ');
    for (const bytes of [original, candidate]) {
      const snapshot = Buffer.from(bytes);
      assert.equal(preservedArtifactSizeSHA256(path, bytes), spec.sha256);
      assert.equal(preservedArtifactSizeSHA256(path, bytes), spec.sha256, 'deterministic repeat');
      assert.deepEqual(bytes, snapshot, 'acceptance leaves input exact');
    }
  });
  for (const [editIndex, [before, after]] of spec.edits.entries()) {
    test(`missing approved edit ${editIndex}: ${path}`, () => refuses(path, replaceOnce(candidate, after, '')));
    test(`duplicate approved edit ${editIndex}: ${path}`, () => refuses(path, replaceOnce(candidate, after, after + after)));
    test(`modified approved edit ${editIndex}: ${path}`, () => refuses(path, replaceOnce(candidate, after, after + ' ')));
    test(`old and new anchor both present ${editIndex}: ${path}`, () => refuses(path, replaceOnce(candidate, after, after + before)));
  }
  for (const [label, bytes] of [['historical', original], ['current', candidate]]) {
    for (const [name, mutated] of [
      ['trailing comment', Buffer.concat([bytes, Buffer.from('// unapproved\n')])],
      ['truncation', bytes.subarray(0, bytes.length - 1)],
      ['invalid UTF8', Buffer.concat([bytes, Buffer.from([0xff])])],
      ['CRLF', Buffer.from(bytes.toString('utf8').replaceAll('\n', '\r\n'))],
      ['outside edit import', replaceOnce(bytes, 'import Foundation\n', 'import Foundation\n// unrelated\n')],
    ]) test(`refuses ${label} ${name}: ${path}`, () => refuses(path, mutated));
  }
  for (const value of [undefined, null, '', new Uint8Array(candidate), {}, Buffer.alloc(0), Buffer.alloc(131073)]) {
    test(`bounded buffer input ${String(value?.constructor?.name)}: ${path}`, () => refuses(path, value));
  }
}
test('wrong shared ceiling reference refuses', () => {
  const path = 'Sources/PatchedCore/CatalogueVerifier.swift';
  refuses(path, replaceOnce(current(path), 'UInt64(ArtifactSizePolicy.absoluteMaximumBytes)', 'UInt64(4_294_967_296)'));
});
test('operator wrong ceiling refuses', () => {
  const path = 'Sources/PatchedOperator/CatalogueSigning.swift';
  refuses(path, replaceOnce(current(path), 'ArtifactSizePolicy.absoluteMaximumBytes', '4_294_967_296'));
});
test('original negative assertion deletion refuses', () => {
  const path = 'Tests/PatchedCoreChecks/CatalogueChecks.swift';
  const line = '        check("invalid bounded artifact length \\(value)") { try verifyRefusal(mutateArtifact { $0["byteLength"] = value }, .invalidPayload) }\n';
  refuses(path, replaceOnce(current(path), line, ''));
});
for (const path of ['', '../Sources/PatchedCore/CatalogueVerifier.swift', 'Package.swift', '__proto__', null, {}]) {
  test(`unapproved preservation path ${String(path)}`, () => refuses(path, current('Sources/PatchedCore/CatalogueVerifier.swift')));
}
