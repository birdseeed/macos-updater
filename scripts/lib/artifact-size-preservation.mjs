import {createHash} from 'node:crypto';

// PAT-2709: invert only the four explicitly reviewed size-policy changes.
// Historical manifest pins remain immutable; candidate source is inert bytes.
const approved = {
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
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const maximumBytes = 128 * 1024;

function replaceUnique(bytes, beforeText, afterText) {
  const before = Buffer.from(beforeText);
  const after = Buffer.from(afterText);
  const index = bytes.indexOf(after);
  if (index < 0 || bytes.indexOf(after, index + 1) !== -1 || bytes.indexOf(before) !== -1) {
    throw new TypeError('Artifact size preservation requires each exact approved edit once');
  }
  return Buffer.concat([bytes.subarray(0, index), before, bytes.subarray(index + after.length)]);
}

export function preservedArtifactSizeSHA256(path, candidateBytes) {
  if (typeof path !== 'string' || !Object.hasOwn(approved, path) ||
      !Buffer.isBuffer(candidateBytes) || candidateBytes.length === 0 || candidateBytes.length > maximumBytes) {
    throw new TypeError('Artifact size preservation requires an approved path and bounded Buffer');
  }
  const spec = approved[path];
  let bytes = Buffer.from(candidateBytes);
  if (sha256(bytes) === spec.sha256) return spec.sha256;
  for (const [before, after] of spec.edits) bytes = replaceUnique(bytes, before, after);
  const digest = sha256(bytes);
  if (digest !== spec.sha256) throw new TypeError('Artifact size edits do not reconstruct the historical pin');
  return digest;
}
