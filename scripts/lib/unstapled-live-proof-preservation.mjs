import {createHash} from 'node:crypto';

// CHECK-MODIFIED PAT-2707: one literal live-proof projection, inert bytes only.
// No files, execution, decoding, regex rewriting or caller-supplied edit policy.
const approvedPath = "Tests/PatchedOperatorTests/LiveCatalogueProof.swift";
const historicalSHA256 = "3938ef5692b4cb540a3c2b55ecb7668e83a359edb8a348848863035efd4c6ed4";
const before = "    for key in [\"containerSignature\", \"containerGatekeeper\", \"containerTicket\"] {\n        guard let result = observed[key] as? [String: Any], let code = unsigned(result[\"exitCode\"]) else {\n            throw CheckFailure(description: \"Inspection record omits the \\(key) result\")\n        }\n        try expect(code != 0, \"Inspection record does not keep the failing \\(key) result\")\n    }\n";
const after = "    try expect(observed[\"ticket\"] == nil && observed[\"containerTicket\"] == nil &&\n               flag(assessment[\"containerTicketPassed\"]) == false,\n               \"Live inspection retained ticket observations or claimed current ticket validation\")\n    try expect(ran.allSatisfy { value in\n        guard let command = value as? [String: Any], let executable = command[\"executable\"] as? String,\n              let arguments = command[\"arguments\"] as? [String] else { return false }\n        return executable != \"/usr/bin/xcrun\" && !arguments.contains(\"stapler\")\n    }, \"Live inspection ran a stapling command or has malformed command records\")\n    for key in [\"containerSignature\", \"containerGatekeeper\"] {\n        guard let result = observed[key] as? [String: Any], let code = unsigned(result[\"exitCode\"]) else {\n            throw CheckFailure(description: \"Inspection record omits the \\(key) result\")\n        }\n        try expect(code != 0, \"Inspection record does not keep the failing \\(key) result\")\n    }\n";
const maximumBytes = 128 * 1024;
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

export function preservedUnstapledLiveProofSHA256(path, candidateBytes) {
  if (path !== approvedPath || !Buffer.isBuffer(candidateBytes) ||
      candidateBytes.length === 0 || candidateBytes.length > maximumBytes) {
    throw new TypeError('Live proof preservation requires the exact approved path and bounded Buffer');
  }
  const bytes = Buffer.from(candidateBytes);
  if (sha256(bytes) === historicalSHA256) return historicalSHA256;
  const oldBytes = Buffer.from(before), newBytes = Buffer.from(after);
  const index = bytes.indexOf(newBytes);
  if (index < 0 || bytes.indexOf(newBytes, index + 1) !== -1 || bytes.indexOf(oldBytes) !== -1) {
    throw new TypeError('Live proof preservation requires the unique exact approved replacement');
  }
  const reconstructed = Buffer.concat([bytes.subarray(0, index), oldBytes, bytes.subarray(index + newBytes.length)]);
  if (sha256(reconstructed) !== historicalSHA256) {
    throw new TypeError('Live proof edit does not reconstruct the independently pinned historical source');
  }
  return historicalSHA256;
}
