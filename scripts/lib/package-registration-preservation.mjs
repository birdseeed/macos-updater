import {createHash} from 'node:crypto';

// Historical provenance is unchanged. Each exact four-line additive
// registration must reconstruct its approved predecessor's Package bytes.
const originalSHA256 = '8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699';
const shellSHA256 = '6f69e14efb17c845fc194149d8248500ca6efb49416ebeba9a28030362bff447';
const preferencesSHA256 = '16c464dab3fa2cc783ef174a68dfaa2969a713c2c2403e484114880e1991b2a2';
const combinedSHA256 = '9efb689b91704ce21ee5aef32fc1e3501994df49b37e874ebdf714bab56525e4';
const networkSHA256 = '07a0e74dc59364b3132ed91cb9eb2adf3bdee8a0b3a4f4a4ca536552a9732cb0';
const nativeCompositionSHA256 = '335c3ea6c99d38ab9e8f9e6d047cb7b72eb09c4bd7501b9d55938e38fe80d3aa';
// CHECK-MODIFIED PAT-2666: exact one-line dependency inverse only.
const nativeNetworkSettingsSHA256 = 'a59ebf6cc9c5ec8140a9f5a1ffdf03c917808cfb9c2bfd39b8a2608ebd43bb68';
// CHECK-MODIFIED PAT-2667: exact two-line dependency inverse only.
const nativeFirstRunSHA256 = '1bdfbe0bc438e7383bb92f432bcd43a1825bb2001228ad9babe15dfc818f4558';
// CHECK-MODIFIED PAT-2673: exact two-line test-target inverse only.
const ownedProcessSHA256 = 'ce5dae62dfa109f3823dc2b38175ca92155beec89f0667ea0b72f0e3ae54a7c5';
const maxPackageBytes = 64 * 1024;
const productHeader = Buffer.from('    products: [\n');
const targetHeader = Buffer.from('    targets: [\n');
const productRegistration = Buffer.from(
  '        .library(name: "PatchedShell", targets: ["PatchedShell"]),\n' +
  '        .executable(name: "patched-shell-checks", targets: ["PatchedShellChecks"]),\n');
const targetRegistration = Buffer.from(
  '        .target(name: "PatchedShell"),\n' +
  '        .executableTarget(name: "PatchedShellChecks", dependencies: ["PatchedShell", "PatchedCore", "PatchedUI"], path: "Tests/PatchedShellChecks"),\n');
const preferencesProductRegistration = Buffer.from(
  '        .library(name: "PatchedUpdatePreferences", targets: ["PatchedUpdatePreferences"]),\n' +
  '        .executable(name: "patched-update-preferences-checks", targets: ["PatchedUpdatePreferencesChecks"]),\n');
const preferencesTargetRegistration = Buffer.from(
  '        .target(name: "PatchedUpdatePreferences", dependencies: ["PatchedScheduling"]),\n' +
  '        .executableTarget(name: "PatchedUpdatePreferencesChecks", dependencies: ["PatchedUpdatePreferences", "PatchedScheduling"], path: "Tests/PatchedUpdatePreferencesChecks"),\n');
const activityProductRegistration = Buffer.from(
  '        .library(name: "PatchedActivity", targets: ["PatchedActivity"]),\n' +
  '        .executable(name: "patched-activity-checks", targets: ["PatchedActivityChecks"]),\n');
const activityTargetRegistration = Buffer.from(
  '        .target(name: "PatchedActivity"),\n' +
  '        .executableTarget(name: "PatchedActivityChecks", dependencies: ["PatchedActivity"], path: "Tests/PatchedActivityChecks"),\n');
const networkProductRegistration = Buffer.from(
  '        .library(name: "PatchedNetworking", targets: ["PatchedNetworking"]),\n' +
  '        .executable(name: "patched-network-checks", targets: ["PatchedNetworkChecks"]),\n');
const networkTargetRegistration = Buffer.from(
  '        .target(name: "PatchedNetworking"),\n' +
  '        .executableTarget(name: "PatchedNetworkChecks", dependencies: ["PatchedNetworking"], path: "Tests/PatchedNetworkChecks"),\n');
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

function removeExactRegistration(bytes, header, registration) {
  const block = Buffer.concat([header, registration]);
  const start = bytes.indexOf(block);
  // Both the whole anchored block and its inserted bytes must occur once.
  if (start < 0 || bytes.indexOf(block, start + 1) !== -1 ||
      bytes.indexOf(registration) !== start + header.length ||
      bytes.indexOf(registration, start + header.length + 1) !== -1) {
    throw new TypeError('Package registration does not match the approved exact insertion');
  }
  return Buffer.concat([
    bytes.subarray(0, start + header.length),
    bytes.subarray(start + block.length),
  ]);
}

export function preservedPackageSHA256(packageBytes) {
  if (!Buffer.isBuffer(packageBytes) || packageBytes.length === 0 ||
      packageBytes.length > maxPackageBytes) {
    throw new TypeError('Package preservation requires bounded Buffer bytes');
  }
  let bytes = Buffer.from(packageBytes);
  let digest = sha256(bytes);
  if (digest === originalSHA256) return originalSHA256;
  if (digest === ownedProcessSHA256) {
    const registration = Buffer.from(
      '        .testTarget(name: "PatchedOwnedProcessTests", dependencies: ["PatchedDisposableProof"],\n' +
      '                    path: "Tests/PatchedOwnedProcessTests"),\n');
    bytes = removeExactRegistration(bytes, targetHeader, registration);
    digest = sha256(bytes);
    if (digest !== nativeFirstRunSHA256) {
      throw new TypeError('Owned-process registration does not reconstruct the native first-run baseline');
    }
  }
  if (digest === nativeFirstRunSHA256) {
    for (const [candidate, predecessor] of [
      ['        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI", "PatchedNetworking", "PatchedUpdatePreferences"]),\n',
       '        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI", "PatchedNetworking"]),\n'],
      ['        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection", "PatchedShell", "PatchedUpdatePreferences", "PatchedScheduling"],\n',
       '        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection", "PatchedShell"],\n'],
    ]) {
      const line = Buffer.from(candidate), original = Buffer.from(predecessor);
      const start = bytes.indexOf(line);
      if (start < 0 || bytes.indexOf(line, start + 1) !== -1) {
        throw new TypeError('Native first-run dependency amendment is not exact');
      }
      bytes = Buffer.concat([bytes.subarray(0, start), original, bytes.subarray(start + line.length)]);
    }
    digest = sha256(bytes);
    if (digest !== nativeNetworkSettingsSHA256) {
      throw new TypeError('Native first-run does not reconstruct the native Network settings baseline');
    }
  }
  if (digest === nativeNetworkSettingsSHA256) {
    const candidate = Buffer.from('        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI", "PatchedNetworking"]),\n');
    const predecessor = Buffer.from('        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI"]),\n');
    const start = bytes.indexOf(candidate);
    if (start < 0 || bytes.indexOf(candidate, start + 1) !== -1) {
      throw new TypeError('Native Network settings dependency amendment is not exact');
    }
    bytes = Buffer.concat([bytes.subarray(0, start), predecessor, bytes.subarray(start + candidate.length)]);
    digest = sha256(bytes);
    if (digest !== nativeCompositionSHA256) {
      throw new TypeError('Native Network settings does not reconstruct the native composition baseline');
    }
  }
  if (digest === nativeCompositionSHA256) {
    // Only these two complete lines may change. The reconstructed full bytes
    // must equal the unchanged approved Network baseline before older inverses.
    for (const [candidate, predecessor] of [
      ['        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI"]),\n',
       '        .target(name: "PatchedClient", dependencies: ["ArtifactInspection"]),\n'],
      ['        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection", "PatchedShell"],\n',
       '        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection"],\n'],
    ]) {
      const line = Buffer.from(candidate), original = Buffer.from(predecessor);
      const start = bytes.indexOf(line);
      if (start < 0 || bytes.indexOf(line, start + 1) !== -1) {
        throw new TypeError('Native composition dependency amendment is not exact');
      }
      bytes = Buffer.concat([bytes.subarray(0, start), original, bytes.subarray(start + line.length)]);
    }
    digest = sha256(bytes);
    if (digest !== networkSHA256) {
      throw new TypeError('Native composition does not reconstruct the Network baseline');
    }
  }

  if (digest === networkSHA256) {
    const withoutNetworkProducts = removeExactRegistration(bytes, productHeader, networkProductRegistration);
    bytes = removeExactRegistration(withoutNetworkProducts, targetHeader, networkTargetRegistration);
    digest = sha256(bytes);
    if (digest !== combinedSHA256) {
      throw new TypeError('Package registration does not reconstruct the Activity baseline');
    }
  }
  if (digest === combinedSHA256) {
    const withoutActivityProducts = removeExactRegistration(bytes, productHeader, activityProductRegistration);
    bytes = removeExactRegistration(withoutActivityProducts, targetHeader, activityTargetRegistration);
    digest = sha256(bytes);
    if (digest !== preferencesSHA256) {
      throw new TypeError('Package registration does not reconstruct the Preferences baseline');
    }
  }
  if (digest === preferencesSHA256) {
    const withoutPreferencesProducts = removeExactRegistration(bytes, productHeader, preferencesProductRegistration);
    bytes = removeExactRegistration(withoutPreferencesProducts, targetHeader, preferencesTargetRegistration);
    if (sha256(bytes) !== shellSHA256) {
      throw new TypeError('Package registration does not reconstruct the Shell baseline');
    }
  } else if (digest !== shellSHA256) {
    throw new TypeError('Package bytes are outside the four approved preservation baselines');
  }
  const withoutProducts = removeExactRegistration(bytes, productHeader, productRegistration);
  const historicalBytes = removeExactRegistration(withoutProducts, targetHeader, targetRegistration);
  if (sha256(historicalBytes) !== originalSHA256) {
    throw new TypeError('Package registration does not reconstruct the historical baseline');
  }
  return originalSHA256;
}
