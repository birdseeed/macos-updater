import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { TextDecoder } from 'node:util';

// CHECK-MODIFIED PAT-2710: remove only the independently frozen registration
// additions, then authenticate every historical byte before prior guards run.
const historicalRawSHA256 = '49391a8effb74e3c348636c561c30318b487d1c2d7ded78e02ab12465dd0d2c0';
const importPrelude = 'import Foundation\nimport Darwin\nimport ArtifactInspection\n\n';
const registrationAnchor = 'addSizePolicyChecks()\n\nfor pin in FirefoxTargets.pins {';
const child = String.raw`// CHECK-ADDED PAT-2710: inert child dispatch precedes ordinary registration.
if CommandLine.arguments.dropFirst().first == "--verified-image-child" {
    runVerifiedImageChild(Array(CommandLine.arguments.dropFirst()))
}

`;
const registration = String.raw`// CHECK-ADDED PAT-2710: same additive checks run focused and in the full gate.
if Array(CommandLine.arguments.dropFirst()) == ["--verified-image"] {
    cases.removeAll()
    addVerifiedImageChecks()
    var failures = 0
    for (name, action) in cases {
        do { try action(); print("PASS fixture: \(name)") }
        catch { failures += 1; print("FAIL fixture: \(name): \(error)") }
    }
    print("PAT-2710 verified image: \(cases.count) cases, \(failures) failures; no hdiutil or mount executed")
    exit(failures == 0 ? 0 : 1)
}
addVerifiedImageChecks()

`;

export function reconstructPreVerifiedImageMain(bytes) {
  assert.ok(Buffer.isBuffer(bytes), 'Frozen main input must be a Buffer');
  assert.ok(bytes.length > 0 && bytes.length <= 1_048_576, 'Frozen main input is empty or exceeds its byte limit');
  assert.ok(!bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])), 'Frozen main must not contain a UTF8 BOM');
  assert.ok(!bytes.includes(0) && !bytes.includes(13), 'Frozen main must contain neither NUL nor carriage return');
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  assert.ok(!text.includes('\ufeff'), 'Frozen main must not contain a BOM');
  assert.deepEqual(Buffer.from(text, 'utf8'), bytes, 'Frozen main must round-trip exact UTF8 bytes');
  assert.equal(text.split(child).length, 2, 'Require exactly the frozen PAT-2710 child dispatch');
  assert.equal(text.split(registration).length, 2, 'Require exactly the frozen PAT-2710 focused/default registration');

  const historicalText = text.replace(child, '').replace(registration, '');
  const historical = Buffer.from(historicalText, 'utf8');
  assert.equal(createHash('sha256').update(historical).digest('hex'), historicalRawSHA256,
    'Historical raw acceptance bytes changed outside the two approved additions');
  assert.ok(historicalText.startsWith(importPrelude), 'Historical import prelude must remain first');
  assert.equal(historicalText.split(importPrelude).length, 2, 'Historical import anchor must be unique');
  assert.equal(historicalText.split(registrationAnchor).length, 2, 'Historical ordinary registration anchor must be unique');

  // Hashing stripped bytes alone would accept a moved block. Reassemble the
  // pinned historical content at its original anchors and compare all bytes.
  const assembled = historicalText
    .replace(importPrelude, importPrelude + child)
    .replace(registrationAnchor, 'addSizePolicyChecks()\n\n' + registration + 'for pin in FirefoxTargets.pins {');
  assert.deepEqual(Buffer.from(assembled, 'utf8'), bytes, 'PAT-2710 additions must occupy their exact original positions');
  return historical;
}

// Preserve the prior NoCLT guard itself, including its independent historical
// acceptance hashes. Only the exact PAT-2710 import and reconstruction call vary.
const historicalGuardSHA256 = '700bcd989abbcbe18a77817cb11051d5d19331a7841ff98ab0d7f2ad7dc19075';
const guardImport = "import { reconstructPreVerifiedImageMain } from './VerifiedImageRegistration.mjs';\n";
const guardCall = '    bytes = reconstructPreVerifiedImageMain(bytes);\n';
const guardImportAnchor = "import { fileURLToPath } from 'node:url';\n";
const guardCallAnchor = "  if (path.endsWith('/main.swift')) {\n";

export function reconstructPreVerifiedImageGuard(bytes) {
  assert.ok(Buffer.isBuffer(bytes), 'Frozen guard input must be a Buffer');
  assert.ok(bytes.length > 0 && bytes.length <= 1_048_576, 'Frozen guard input is empty or exceeds its byte limit');
  assert.ok(!bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])), 'Frozen guard must not contain a UTF8 BOM');
  assert.ok(!bytes.includes(0) && !bytes.includes(13), 'Frozen guard must contain neither NUL nor carriage return');
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  assert.ok(!text.includes('\ufeff'), 'Frozen guard must not contain a BOM');
  assert.deepEqual(Buffer.from(text, 'utf8'), bytes, 'Frozen guard must round-trip exact UTF8 bytes');
  assert.equal(text.split(guardImport).length, 2, 'Require exactly the frozen PAT-2710 guard import');
  assert.equal(text.split(guardCall).length, 2, 'Require exactly the frozen PAT-2710 guard call');
  const historicalText = text.replace(guardImport, '').replace(guardCall, '');
  const historical = Buffer.from(historicalText, 'utf8');
  assert.equal(createHash('sha256').update(historical).digest('hex'), historicalGuardSHA256,
    'Historical raw guard bytes changed outside the two approved additions');
  assert.equal(historicalText.split(guardImportAnchor).length, 2, 'Historical guard import anchor must be unique');
  assert.equal(historicalText.split(guardCallAnchor).length, 2, 'Historical guard main branch anchor must be unique');
  const assembled = historicalText
    .replace(guardImportAnchor, guardImportAnchor + guardImport)
    .replace(guardCallAnchor, guardCallAnchor + guardCall);
  assert.deepEqual(Buffer.from(assembled, 'utf8'), bytes, 'PAT-2710 guard additions must occupy their exact original positions');
  return historical;
}
