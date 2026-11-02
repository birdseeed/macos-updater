import { reconstructPreVerifiedImageGuard } from '../../../scripts/checks/VerifiedImageRegistration.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {preservedPinnedSignatureLiveProofBytes} from '../../../scripts/lib/pinned-signature-live-proof-preservation.mjs';

// Independent accepted-source pin, exact addition and proposed bytes. Never import helper policy.
const path = "Tests/PatchedOperatorTests/LiveCatalogueProof.swift";
const acceptedSHA256 = "2bc9ff01fe103b557523eef48ee3c591b23a0e82a0f46896d767ba0bb0b4e96b";
const addition = "    // CHECK-ADDED PAT-2708: structured pinned-signature evidence from native Security validation.\n    guard let inspectedApp = evidence[\"appPath\"] as? String,\n          let signature = evidence[\"signatureObservation\"] as? [String: Any],\n          let signatureApp = signature[\"appPath\"] as? String,\n          let signatureStarted = signature[\"startedAt\"] as? String,\n          let signatureFinished = signature[\"finishedAt\"] as? String else {\n        throw CheckFailure(description: \"Live inspection lacks structured signature paths or mandatory timestamps\")\n    }\n    try expect(unsigned(evidence[\"schemaVersion\"]) == 3 &&\n               Set(signature.keys) == [\"appPath\", \"requirement\", \"validationFlags\", \"validationStatus\", \"signingInformationStatus\",\n                                       \"teamID\", \"identifier\", \"startedAt\", \"finishedAt\"],\n               \"Live inspection does not use the exact schema3 signature observation\")\n    let expectedSignatureRequirement = \"anchor apple generic and certificate leaf[subject.OU] = \\\"\\(pin.teamID)\\\" and identifier \\\"\\(pin.bundleID)\\\"\"\n    try expect(signatureApp == inspectedApp && signature[\"requirement\"] as? String == expectedSignatureRequirement &&\n               unsigned(signature[\"validationFlags\"]) == 25 && unsigned(signature[\"validationStatus\"]) == 0 &&\n               unsigned(signature[\"signingInformationStatus\"]) == 0 && signature[\"teamID\"] as? String == pin.teamID &&\n               signature[\"identifier\"] as? String == pin.bundleID && !signatureStarted.isEmpty && !signatureFinished.isEmpty,\n               \"Live inspection signature differs from its inspected path, exact requirement, flags, status, pin or timestamps\")\n    try expect(observed[\"signature\"] == nil && observed[\"identity\"] == nil && ran.allSatisfy { value in\n        guard let command = value as? [String: Any], let executable = command[\"executable\"] as? String,\n              let arguments = command[\"arguments\"] as? [String] else { return false }\n        return executable != \"/usr/bin/codesign\" || !arguments.contains(inspectedApp)\n    }, \"Live inspection retained CLI app signature/identity observations, ran app codesign or has malformed command records\")\n";
const anchor = "    try expect(observed[\"ticket\"] == nil && observed[\"containerTicket\"] == nil &&\n";
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const original = readFileSync(new URL('../protocol/fixtures/pinned-signature-live-proof-preservation/LiveCatalogueProof.original.swift', import.meta.url));
const current = readFileSync(new URL('../../../Tests/PatchedOperatorTests/LiveCatalogueProof.swift', import.meta.url));
function replaceOnce(bytes, oldText, newText) {
  const old = Buffer.from(oldText), next = Buffer.from(newText), index = bytes.indexOf(old);
  assert.ok(index >= 0 && bytes.indexOf(old, index + 1) === -1, 'independent unique mutation anchor');
  return Buffer.concat([bytes.subarray(0, index), next, bytes.subarray(index + old.length)]);
}
const expectedCurrent = replaceOnce(original, anchor, addition + anchor);
function refuses(candidatePath, bytes) {
  const snapshot = Buffer.isBuffer(bytes) ? Buffer.from(bytes) : undefined;
  assert.throws(() => preservedPinnedSignatureLiveProofBytes(candidatePath, bytes), TypeError);
  if (snapshot) assert.ok(bytes.equals(snapshot), 'refusal leaves bytes exact');
}
test('inert original is independently pinned accepted PAT-2707', () => {
  assert.equal(digest(original), acceptedSHA256);
});
test('actual current proof is exactly the new independently constructed proposal', () => {
  assert.ok(current.equals(expectedCurrent), 'prospective RED until the exact additive proof is adopted');
});
for (const [name, bytes] of [['accepted PAT-2707', original], ['reviewed PAT-2708 proposal', expectedCurrent]]) {
  test(`accepts exact ${name} and returns an independent bounded copy`, () => {
    const snapshot = Buffer.from(bytes), result = preservedPinnedSignatureLiveProofBytes(path, bytes);
    assert.ok(result.equals(original)); assert.notEqual(result, bytes);
    result[0] ^= 1;
    assert.ok(bytes.equals(snapshot));
    assert.ok(preservedPinnedSignatureLiveProofBytes(path, bytes).equals(original));
  });
  for (const [label, changed] of [
    ['trailing bytes', Buffer.concat([bytes, Buffer.from('// unrelated\n')])],
    ['truncation', bytes.subarray(0, bytes.length - 1)],
    ['invalid UTF8', Buffer.concat([bytes, Buffer.from([255])])],
    ['BOM', Buffer.concat([Buffer.from([239,187,191]), bytes])],
    ['NUL', Buffer.concat([bytes, Buffer.from([0])])],
    ['CRLF', Buffer.from(bytes.toString().replaceAll('\n', '\r\n'))],
    ['unrelated import', replaceOnce(bytes, 'import Foundation\n', 'import Foundation\n// unrelated\n')],
  ]) test(`refuses ${name} ${label}`, () => refuses(path, changed));
}
for (const [label, changed] of [
  ['missing block with unrelated bytes', replaceOnce(expectedCurrent, addition, '// removed block\n')],
  ['duplicate block', replaceOnce(expectedCurrent, addition, addition + addition)],
  ['modified block', replaceOnce(expectedCurrent, addition, addition + ' ')],
  ['relocated exact block', Buffer.concat([Buffer.from(addition), replaceOnce(expectedCurrent, addition, '')])],
  ["receipt authority", replaceOnce(expectedCurrent, "    try expect(!receipt.installationAuthorized, \"Live receipt grants installation authority\")\n", "")],
  ["live assessment", replaceOnce(expectedCurrent, "assessment[\"origin\"] as? String == \"live\"", "assessment[\"origin\"] as? String == \"fixture\"")],
  ["fresh OS", replaceOnce(expectedCurrent, "flag(assessment[\"freshOSValidation\"]) == true", "flag(assessment[\"freshOSValidation\"]) == false")],
  ["assessment authority", replaceOnce(expectedCurrent, "flag(assessment[\"installationAuthorized\"]) == false", "flag(assessment[\"installationAuthorized\"]) == true")],
  ["container signature summary", replaceOnce(expectedCurrent, "flag(assessment[\"containerSignaturePassed\"]) == false", "flag(assessment[\"containerSignaturePassed\"]) == true")],
  ["container Gatekeeper summary", replaceOnce(expectedCurrent, "flag(assessment[\"containerGatekeeperPassed\"]) == false", "flag(assessment[\"containerGatekeeperPassed\"]) == true")],
  ["ticket absence", replaceOnce(expectedCurrent, "observed[\"ticket\"] == nil && ", "true && ")],
  ["container ticket absence", replaceOnce(expectedCurrent, "observed[\"containerTicket\"] == nil &&", "true &&")],
  ["stapler command refusal", replaceOnce(expectedCurrent, "return executable != \"/usr/bin/xcrun\" && !arguments.contains(\"stapler\")", "return true")],
  ["container signature failure", replaceOnce(expectedCurrent, "for key in [\"containerSignature\", \"containerGatekeeper\"] {", "for key in [\"containerGatekeeper\"] {")],
  ["container Gatekeeper failure", replaceOnce(expectedCurrent, "for key in [\"containerSignature\", \"containerGatekeeper\"] {", "for key in [\"containerSignature\"] {")],
  ["container raw failure", replaceOnce(expectedCurrent, "try expect(code != 0, \"Inspection record does not keep the failing", "try expect(code == 0, \"Inspection record does not keep the failing")],
  ["command nonvacuity", replaceOnce(expectedCurrent, "!ran.isEmpty && osVersion.range", "true && osVersion.range")],
  ["ticket mandatory", replaceOnce(expectedCurrent, "for key in [\"containerSignature\", \"containerGatekeeper\"] {", "for key in [\"containerSignature\", \"containerGatekeeper\", \"containerTicket\"] {")],
  ["ticket status fabricated", replaceOnce(expectedCurrent, "flag(assessment[\"containerTicketPassed\"]) == false,\n               \"Live inspection", "flag(assessment[\"containerTicketPassed\"]) == true,\n               \"Live inspection")],
 ]) test(`refuses proof mutation ${label}`, () => refuses(path, changed));
test('refuses malformed-command acceptance in both native and prior ticket guards', () => {
  const refusing = 'let arguments = command["arguments"] as? [String] else { return false }';
  const accepting = 'let arguments = command["arguments"] as? [String] else { return true }';
  const blockChanged = addition.replace(refusing, accepting);
  refuses(path, replaceOnce(expectedCurrent, addition, blockChanged));
  const priorStart = '    try expect(ran.allSatisfy { value in';
  const oldGuardStart = expectedCurrent.indexOf(priorStart);
  assert.ok(oldGuardStart > 0);
  const oldTail = expectedCurrent.subarray(oldGuardStart);
  const changedTail = replaceOnce(oldTail, refusing, accepting);
  refuses(path, Buffer.concat([expectedCurrent.subarray(0, oldGuardStart), changedTail]));
});
test('refuses every signature block guard weakening', () => {
  for (const [before, after] of [["unsigned(evidence[\"schemaVersion\"]) == 3", "unsigned(evidence[\"schemaVersion\"]) == 2"], ["let inspectedApp = evidence[\"appPath\"] as? String", "let inspectedApp = evidence[\"appPath\"] as? String?"], ["let signatureStarted = signature[\"startedAt\"] as? String,", "let signatureStarted = signature[\"startedAt\"] as? String?, "], ["let signatureFinished = signature[\"finishedAt\"] as? String else {", "let signatureFinished = signature[\"finishedAt\"] as? String? else {"], ["Set(signature.keys) ==", "Set(signature.keys).isSubset(of:"], ["signatureApp == inspectedApp", "signatureApp == signatureApp"], ["signature[\"requirement\"] as? String == expectedSignatureRequirement", "true"], ["unsigned(signature[\"validationFlags\"]) == 25", "unsigned(signature[\"validationFlags\"]) == 0"], ["unsigned(signature[\"validationStatus\"]) == 0", "true"], ["unsigned(signature[\"signingInformationStatus\"]) == 0", "true"], ["signature[\"teamID\"] as? String == pin.teamID", "true"], ["signature[\"identifier\"] as? String == pin.bundleID", "true"], ["observed[\"signature\"] == nil", "true"], ["observed[\"identity\"] == nil", "true"], ["return executable != \"/usr/bin/codesign\" || !arguments.contains(inspectedApp)", "return true"]]) refuses(path, replaceOnce(expectedCurrent, before, after));
});
for (const value of [undefined, null, '', {}, new Uint8Array(expectedCurrent), Buffer.alloc(0), Buffer.alloc(131072), Buffer.alloc(131073)]) {
  test(`refuses nonbuffer or out-of-bound ${String(value?.constructor?.name)}`, () => refuses(path, value));
}
for (const wrongPath of ['', 'Package.swift', '../' + path, '/' + path, path + '/', path.toLowerCase(), path.replaceAll('/', '\\'), '__proto__', null, {}, new String(path)]) {
  test(`refuses nonexact path ${String(wrongPath)}`, () => refuses(wrongPath, expectedCurrent));
}
const integrations = [
  {
    "path": "services/catalogue/tests/catalogue-protocol.test.mjs",
    "beforeSHA256": "fc86aed86ca0e57dbffa86326d1ac06f32e03f0425867192e9777b538703f735",
    "afterSHA256": "cd360d2ed632d353ac4160b01c025a930817720c964656b962f66b50b3cc9cf6",
    "reverseSHA256": "fc86aed86ca0e57dbffa86326d1ac06f32e03f0425867192e9777b538703f735",
    "reverseExact": true,
    "pairs": [
      {
        "before": "",
        "after": "import {preservedPinnedSignatureLiveProofBytes} from '../../../scripts/lib/pinned-signature-live-proof-preservation.mjs';\n",
        "position": "prefix"
      },
      {
        "before": "preservedUnstapledLiveProofSHA256(path,readFileSync(url))",
        "after": "preservedUnstapledLiveProofSHA256(path,preservedPinnedSignatureLiveProofBytes(path,readFileSync(url)))"
      }
    ]
  },
  {
    "path": "services/catalogue/tests/unstapled-live-proof-preservation.test.mjs",
    "beforeSHA256": "211fe7ad989780ca4dcb52f8b50c716a4c1d071687cd534bb636c4e7b93cb79c",
    "afterSHA256": "113dc177da4ddd8f6664645b819875cad3d162cafaad708a156f5b708e993730",
    "reverseSHA256": "211fe7ad989780ca4dcb52f8b50c716a4c1d071687cd534bb636c4e7b93cb79c",
    "reverseExact": true,
    "pairs": [
      {
        "before": "",
        "after": "import {preservedPinnedSignatureLiveProofBytes} from '../../../scripts/lib/pinned-signature-live-proof-preservation.mjs';\n",
        "position": "prefix"
      },
      {
        "before": "const current = readFileSync(new URL('../../../Tests/PatchedOperatorTests/LiveCatalogueProof.swift', import.meta.url));",
        "after": "const current = preservedPinnedSignatureLiveProofBytes(path, readFileSync(new URL('../../../Tests/PatchedOperatorTests/LiveCatalogueProof.swift', import.meta.url)));"
      }
    ]
  },
  {
    "path": "scripts/checks/NoCLTTrustSourceGuard.mjs",
    "beforeSHA256": "cbffbe51d024f1eea3bce72d9f7d7af5dcc51fbda4e06e7f17536bcb39883d99",
    "afterSHA256": "700bcd989abbcbe18a77817cb11051d5d19331a7841ff98ab0d7f2ad7dc19075",
    "reverseSHA256": "cbffbe51d024f1eea3bce72d9f7d7af5dcc51fbda4e06e7f17536bcb39883d99",
    "reverseExact": true,
    "pairs": [
      {
        "before": "    const text = bytes.toString('utf8');\n",
        "after": "    let text = bytes.toString('utf8');\n    const pinnedEntry = \"// CHECK-ADDED PAT-2708: additive focused entry point; previous assertions unchanged.\\nif Array(CommandLine.arguments.dropFirst()) == [\\\"--pat-2708-pinned-signature\\\"] {\\n    runPinnedSignatureChecks()\\n}\\n\\n\";\n    assert.equal(text.split(pinnedEntry).length, 2, 'Add exactly the unique PAT-2708 focused entry point');\n    assert.ok(text.indexOf(pinnedEntry) < text.indexOf(entry), 'PAT-2708 entry must precede the unchanged PAT-2707 entry');\n    text = text.replace(pinnedEntry, '');\n"
      }
    ]
  }
];
for (const integration of integrations) {
  function reverse(bytes) {
    if (integration.path === 'scripts/checks/NoCLTTrustSourceGuard.mjs') bytes = reconstructPreVerifiedImageGuard(bytes);
    let result = Buffer.from(bytes);
    for (const pair of [...integration.pairs].reverse()) {
      if (pair.position === 'prefix') {
        assert.ok(result.subarray(0, Buffer.byteLength(pair.after)).equals(Buffer.from(pair.after)));
        result = result.subarray(Buffer.byteLength(pair.after));
      } else result = replaceOnce(result, pair.after, pair.before);
    }
    assert.equal(digest(result), integration.beforeSHA256, 'all prior integration bytes exact');
    return result;
  }
  test(`integration preserves exact accepted bytes: ${integration.path}`, () => {
    const bytes = readFileSync(new URL('../../../' + integration.path, import.meta.url));
    reverse(bytes);
    assert.throws(() => reverse(Buffer.concat([bytes, Buffer.from('// unrelated\n')])));
    for (const pair of integration.pairs) {
      assert.throws(() => reverse(replaceOnce(bytes, pair.after, pair.after + '// changed\n')));
    }
  });
}
