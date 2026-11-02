import {createHash} from 'node:crypto';

// CHECK-ADDED PAT-2708: bounded inert exact-byte reversal to independently pinned PAT-2707.
// No I/O, source execution, decoding, regular-expression rewrite or caller edit policy.
const approvedPath = "Tests/PatchedOperatorTests/LiveCatalogueProof.swift";
const acceptedSHA256 = "2bc9ff01fe103b557523eef48ee3c591b23a0e82a0f46896d767ba0bb0b4e96b";
const addition = Buffer.from("    // CHECK-ADDED PAT-2708: structured pinned-signature evidence from native Security validation.\n    guard let inspectedApp = evidence[\"appPath\"] as? String,\n          let signature = evidence[\"signatureObservation\"] as? [String: Any],\n          let signatureApp = signature[\"appPath\"] as? String,\n          let signatureStarted = signature[\"startedAt\"] as? String,\n          let signatureFinished = signature[\"finishedAt\"] as? String else {\n        throw CheckFailure(description: \"Live inspection lacks structured signature paths or mandatory timestamps\")\n    }\n    try expect(unsigned(evidence[\"schemaVersion\"]) == 3 &&\n               Set(signature.keys) == [\"appPath\", \"requirement\", \"validationFlags\", \"validationStatus\", \"signingInformationStatus\",\n                                       \"teamID\", \"identifier\", \"startedAt\", \"finishedAt\"],\n               \"Live inspection does not use the exact schema3 signature observation\")\n    let expectedSignatureRequirement = \"anchor apple generic and certificate leaf[subject.OU] = \\\"\\(pin.teamID)\\\" and identifier \\\"\\(pin.bundleID)\\\"\"\n    try expect(signatureApp == inspectedApp && signature[\"requirement\"] as? String == expectedSignatureRequirement &&\n               unsigned(signature[\"validationFlags\"]) == 25 && unsigned(signature[\"validationStatus\"]) == 0 &&\n               unsigned(signature[\"signingInformationStatus\"]) == 0 && signature[\"teamID\"] as? String == pin.teamID &&\n               signature[\"identifier\"] as? String == pin.bundleID && !signatureStarted.isEmpty && !signatureFinished.isEmpty,\n               \"Live inspection signature differs from its inspected path, exact requirement, flags, status, pin or timestamps\")\n    try expect(observed[\"signature\"] == nil && observed[\"identity\"] == nil && ran.allSatisfy { value in\n        guard let command = value as? [String: Any], let executable = command[\"executable\"] as? String,\n              let arguments = command[\"arguments\"] as? [String] else { return false }\n        return executable != \"/usr/bin/codesign\" || !arguments.contains(inspectedApp)\n    }, \"Live inspection retained CLI app signature/identity observations, ran app codesign or has malformed command records\")\n");
const followingAnchor = Buffer.from("    try expect(observed[\"ticket\"] == nil && observed[\"containerTicket\"] == nil &&\n");
const maximumBytes = 128 * 1024;
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

export function preservedPinnedSignatureLiveProofBytes(path, candidateBytes) {
  if (path !== approvedPath || !Buffer.isBuffer(candidateBytes) ||
      candidateBytes.length === 0 || candidateBytes.length > maximumBytes) {
    throw new TypeError('Pinned signature preservation requires the exact path and bounded Buffer');
  }
  const bytes = Buffer.from(candidateBytes);
  if (digest(bytes) === acceptedSHA256) return bytes;
  const index = bytes.indexOf(addition);
  if (index < 0 || bytes.indexOf(addition, index + 1) !== -1 ||
      !bytes.subarray(index + addition.length, index + addition.length + followingAnchor.length).equals(followingAnchor)) {
    throw new TypeError('Pinned signature preservation requires one unique exact addition');
  }
  const reconstructed = Buffer.concat([bytes.subarray(0, index), bytes.subarray(index + addition.length)]);
  if (digest(reconstructed) !== acceptedSHA256) {
    throw new TypeError('Pinned signature addition does not reconstruct accepted PAT-2707 bytes');
  }
  return reconstructed;
}
