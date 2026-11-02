import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {preservedPackageSHA256} from '../../../scripts/lib/package-registration-preservation.mjs';
const original = '8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699';
const network = readFileSync(new URL('../../../Fixtures/Network/package-registration/Package.network.swift', import.meta.url));
const networkSHA = '07a0e74dc59364b3132ed91cb9eb2adf3bdee8a0b3a4f4a4ca536552a9732cb0';
// Independent literals; no candidate constants/fixtures are imported.
const oldClient = '        .target(name: "PatchedClient", dependencies: ["ArtifactInspection"]),\n';
const newClient = '        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI"]),\n';
const oldChecks = '        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection"],\n';
const newChecks = '        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection", "PatchedShell"],\n';
function replace(text, before, after) {
  assert.equal(text.split(before).length, 2, 'independent anchor occurs once');
  assert.notEqual(before, after);
  return text.replace(before, after);
}
const candidate = replace(replace(network.toString('utf8'), oldClient, newClient), oldChecks, newChecks);
test('independent predecessor remains exact Network hash', () => {
  assert.equal(createHash('sha256').update(network).digest('hex'), networkSHA);
});
// CHECK-MODIFIED PAT-2667: independently derive the exact two-line first-run
// dependency amendment; preserve all older candidates, hashes and controls below.
const settingsClient = '        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI", "PatchedNetworking"]),\n';
const settingsCandidate = replace(candidate, newClient, settingsClient);
const firstRunClient = '        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI", "PatchedNetworking", "PatchedUpdatePreferences"]),\n';
const firstRunChecks = '        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection", "PatchedShell", "PatchedUpdatePreferences", "PatchedScheduling"],\n';
const firstRunCandidate = replace(replace(settingsCandidate, settingsClient, firstRunClient), newChecks, firstRunChecks);
const settingsSHA = 'a59ebf6cc9c5ec8140a9f5a1ffdf03c917808cfb9c2bfd39b8a2608ebd43bb68';
const firstRunSHA = '1bdfbe0bc438e7383bb92f432bcd43a1825bb2001228ad9babe15dfc818f4558';
test('exact live first-run dependencies invert through Network settings and native composition', () => {
  // CHECK-MODIFIED PAT-2673: authenticate the complete approved live bytes,
  // then invert only the unique owned-process registration before older oracles.
  const rawLive = readFileSync(new URL('../../../Package.swift', import.meta.url));
  const rawLiveBefore = Buffer.from(rawLive);
  assert.equal(createHash('sha256').update(rawLive).digest('hex'), 'ce5dae62dfa109f3823dc2b38175ca92155beec89f0667ea0b72f0e3ae54a7c5');
  const live = Buffer.from(replace(rawLive.toString('utf8'),
    '    targets: [\n' +
    '        .testTarget(name: "PatchedOwnedProcessTests", dependencies: ["PatchedDisposableProof"],\n' +
    '                    path: "Tests/PatchedOwnedProcessTests"),\n',
    '    targets: [\n'));
  assert.equal(createHash('sha256').update(live).digest('hex'), '1bdfbe0bc438e7383bb92f432bcd43a1825bb2001228ad9babe15dfc818f4558');
  assert.equal(preservedPackageSHA256(rawLive), original);
  assert.deepEqual(rawLive, rawLiveBefore);
  assert.deepEqual(live, Buffer.from(firstRunCandidate));
  assert.equal(createHash('sha256').update(live).digest('hex'), firstRunSHA);
  const networkSettings = replace(replace(live.toString('utf8'), firstRunClient, settingsClient), firstRunChecks, newChecks);
  assert.equal(createHash('sha256').update(networkSettings).digest('hex'), settingsSHA);
  assert.equal(networkSettings, settingsCandidate);
  const previous = replace(networkSettings, settingsClient, newClient);
  assert.equal(createHash('sha256').update(previous).digest('hex'), '335c3ea6c99d38ab9e8f9e6d047cb7b72eb09c4bd7501b9d55938e38fe80d3aa');
  const reverse = replace(replace(previous, newClient, oldClient), newChecks, oldChecks);
  assert.deepEqual(Buffer.from(reverse), network);
  assert.equal(preservedPackageSHA256(live), original);
});
test('accepting exact amendments preserves input bytes', () => {
  const input = Buffer.from(candidate), before = Buffer.from(input);
  assert.equal(preservedPackageSHA256(input), original);
  assert.deepEqual(input, before);
});
const mutations = [
  ['only client amended', replace(candidate, newChecks, oldChecks)],
  ['only checks amended', replace(candidate, newClient, oldClient)],
  ['removed client', replace(candidate, newClient, '')],
  ['removed checks', replace(candidate, newChecks, '')],
  ['duplicate client', replace(candidate, newClient, newClient + newClient)],
  ['duplicate checks', replace(candidate, newChecks, newChecks + newChecks)],
  ['extra dependency', replace(candidate, newClient, newClient.replace('"PatchedUI"', '"PatchedUI", "PatchedCore"'))],
  ['removed dependency', replace(candidate, newClient, newClient.replace(', "PatchedActivity"', ''))],
  ['changed dependency', replace(candidate, newChecks, newChecks.replace('"PatchedShell"', '"PatchedUI"'))],
  ['reordered dependencies', replace(candidate, newClient, newClient.replace('"PatchedShell", "PatchedActivity"', '"PatchedActivity", "PatchedShell"'))],
  ['duplicate dependency', replace(candidate, newChecks, newChecks.replace('"PatchedShell"', '"PatchedShell", "PatchedShell"'))],
  ['moved client', replace(candidate, newClient, '') + newClient],
  ['moved checks', replace(candidate, newChecks, '') + newChecks],
  ['other byte', candidate + '\n'],
  ['changed product', replace(candidate, 'name: "PatchedClient", targets:', 'name: "OtherClient", targets:')],
  ['changed indent', replace(candidate, newClient, newClient.slice(1))],
  ['CRLF', candidate.replaceAll('\n', '\r\n')],
];
for (const [name, text] of mutations) test(`refuse native amendment mutation: ${name}`, () => {
  const input = Buffer.from(text), before = Buffer.from(input);
  assert.throws(() => preservedPackageSHA256(input), TypeError);
  assert.deepEqual(input, before);
});

test('full gate registers native composition preservation exactly once', () => {
  const gate = readFileSync(new URL('../../../scripts/verify.sh', import.meta.url), 'utf8');
  const line = 'node --test services/catalogue/tests/native-composition-package-registration-preservation.test.mjs';
  assert.equal(gate.split('\n').filter(value => value === line).length, 1);
});

// Independent negative controls for the new exact one-line amendment.
test('exact native Network dependency bytes preserve historical hash and input', () => {
  const input = Buffer.from(settingsCandidate), before = Buffer.from(input);
  assert.equal(preservedPackageSHA256(input), original);
  assert.deepEqual(input, before);
});
for (const [name, changed] of [
  ['wrong dependency', replace(settingsCandidate, settingsClient, settingsClient.replace('"PatchedNetworking"', '"PatchedCore"'))],
  ['duplicate dependency', replace(settingsCandidate, settingsClient, settingsClient.replace('"PatchedNetworking"', '"PatchedNetworking", "PatchedNetworking"'))],
  ['unexpected extra dependency', replace(settingsCandidate, settingsClient, settingsClient.replace('"PatchedNetworking"', '"PatchedNetworking", "PatchedCore"'))],
  ['reordered dependency', replace(settingsCandidate, settingsClient, settingsClient.replace('"PatchedUI", "PatchedNetworking"', '"PatchedNetworking", "PatchedUI"'))],
  ['missing inherited dependency', replace(settingsCandidate, settingsClient, settingsClient.replace(', "PatchedActivity"', ''))],
  ['duplicate line', replace(settingsCandidate, settingsClient, settingsClient + settingsClient)],
  ['inherited platform changed', replace(settingsCandidate, 'platforms: [.macOS(.v13)]', 'platforms: [.macOS(.v14)]')],
  ['inherited checks changed', replace(settingsCandidate, newChecks, oldChecks)],
  ['inherited target changed', replace(settingsCandidate, '.target(name: "PatchedScheduling")', '.target(name: "UnexpectedScheduling")')],
  ['unexpected whitespace', settingsCandidate + '\n'],
]) test(`refuse native Network settings amendment mutation: ${name}`, () => {
  const input = Buffer.from(changed), before = Buffer.from(input);
  assert.throws(() => preservedPackageSHA256(input), TypeError);
  assert.deepEqual(input, before);
});
test('missing new dependency is historical only and cannot satisfy live settings contract', () => {
  const missing = replace(settingsCandidate, settingsClient, newClient);
  assert.equal(missing, candidate);
  assert.notDeepEqual(Buffer.from(missing), Buffer.from(settingsCandidate));
  // Historical acceptance is intentionally preserved, rather than erased.
  assert.equal(preservedPackageSHA256(Buffer.from(missing)), original);
});

// Additive PAT-2667 controls: expected bytes come only from the pinned Network
// fixture and independent full-line literals above, never from live Package bytes.
test('exact first-run amendment preserves historical hash and input bytes', () => {
  const input = Buffer.from(firstRunCandidate), before = Buffer.from(input);
  assert.equal(preservedPackageSHA256(input), original);
  assert.deepEqual(input, before);
});
test('independent first-run construction has exact pinned full-byte hash', () => {
  const input = Buffer.from(firstRunCandidate), before = Buffer.from(input);
  assert.equal(createHash('sha256').update(input).digest('hex'), firstRunSHA);
  assert.notDeepEqual(input, Buffer.from(settingsCandidate));
  assert.equal(firstRunCandidate.split(firstRunClient).length, 2);
  assert.equal(firstRunCandidate.split(firstRunChecks).length, 2);
  assert.deepEqual(input, before);
});
test('both exact first-run inverses reconstruct pinned Network settings predecessor', () => {
  const input = Buffer.from(firstRunCandidate), before = Buffer.from(input);
  const predecessor = replace(replace(input.toString('utf8'), firstRunClient, settingsClient), firstRunChecks, newChecks);
  assert.equal(predecessor, settingsCandidate);
  assert.equal(createHash('sha256').update(predecessor).digest('hex'), settingsSHA);
  const composition = replace(predecessor, settingsClient, newClient);
  assert.equal(createHash('sha256').update(composition).digest('hex'), '335c3ea6c99d38ab9e8f9e6d047cb7b72eb09c4bd7501b9d55938e38fe80d3aa');
  const reverse = replace(replace(composition, newClient, oldClient), newChecks, oldChecks);
  assert.deepEqual(Buffer.from(reverse), network);
  assert.equal(createHash('sha256').update(reverse).digest('hex'), networkSHA);
  assert.equal(preservedPackageSHA256(Buffer.from(predecessor)), original);
  assert.deepEqual(input, before);
});
test('both first-run additions absent remains historical and fails exact live contract', () => {
  const missing = replace(replace(firstRunCandidate, firstRunClient, settingsClient), firstRunChecks, newChecks);
  const input = Buffer.from(missing), before = Buffer.from(input);
  assert.equal(missing, settingsCandidate);
  assert.equal(createHash('sha256').update(input).digest('hex'), settingsSHA);
  assert.equal(preservedPackageSHA256(input), original);
  assert.notDeepEqual(input, Buffer.from(firstRunCandidate));
  assert.deepEqual(input, before);
});
for (const [name, changed] of [
  ['only client amended', replace(firstRunCandidate, firstRunChecks, newChecks)],
  ['only checks amended', replace(firstRunCandidate, firstRunClient, settingsClient)],
  ['wrong client dependency', replace(firstRunCandidate, firstRunClient, firstRunClient.replace('"PatchedUpdatePreferences"', '"PatchedCore"'))],
  ['wrong checks dependency', replace(firstRunCandidate, firstRunChecks, firstRunChecks.replace('"PatchedScheduling"', '"PatchedCore"'))],
  ['extra client dependency', replace(firstRunCandidate, firstRunClient, firstRunClient.replace('"PatchedUpdatePreferences"', '"PatchedUpdatePreferences", "PatchedCore"'))],
  ['duplicate checks dependency', replace(firstRunCandidate, firstRunChecks, firstRunChecks.replace('"PatchedScheduling"', '"PatchedScheduling", "PatchedScheduling"'))],
  ['reordered client dependencies', replace(firstRunCandidate, firstRunClient, firstRunClient.replace('"PatchedNetworking", "PatchedUpdatePreferences"', '"PatchedUpdatePreferences", "PatchedNetworking"'))],
  ['reordered checks dependencies', replace(firstRunCandidate, firstRunChecks, firstRunChecks.replace('"PatchedUpdatePreferences", "PatchedScheduling"', '"PatchedScheduling", "PatchedUpdatePreferences"'))],
  ['missing inherited client dependency', replace(firstRunCandidate, firstRunClient, firstRunClient.replace(', "PatchedActivity"', ''))],
  ['missing inherited checks dependency', replace(firstRunCandidate, firstRunChecks, firstRunChecks.replace(', "PatchedShell"', ''))],
  ['duplicate client line', replace(firstRunCandidate, firstRunClient, firstRunClient + firstRunClient)],
  ['duplicate checks line', replace(firstRunCandidate, firstRunChecks, firstRunChecks + firstRunChecks)],
  ['foreign inherited platform', replace(firstRunCandidate, 'platforms: [.macOS(.v13)]', 'platforms: [.macOS(.v14)]')],
  ['foreign inherited product', replace(firstRunCandidate, 'name: "PatchedClient", targets:', 'name: "ForeignClient", targets:')],
  ['foreign inherited target', replace(firstRunCandidate, '.target(name: "PatchedScheduling")', '.target(name: "ForeignScheduling")')],
  ['changed line whitespace', replace(firstRunCandidate, firstRunClient, firstRunClient.slice(1))],
  ['CRLF', firstRunCandidate.replaceAll('\n', '\r\n')],
  ['moved client line', replace(firstRunCandidate, firstRunClient, '') + firstRunClient],
  ['moved checks line', replace(firstRunCandidate, firstRunChecks, '') + firstRunChecks],
  ['unknown full-byte hash', firstRunCandidate + '// unapproved bytes\n'],
  ['missing new checks dependency', replace(firstRunCandidate, firstRunChecks, firstRunChecks.replace(', "PatchedScheduling"', ''))],
]) test(`refuse first-run dependency amendment mutation: ${name}`, () => {
  const input = Buffer.from(changed), before = Buffer.from(input);
  assert.notDeepEqual(input, Buffer.from(firstRunCandidate), 'negative control differs from positive');
  assert.throws(() => preservedPackageSHA256(input), TypeError);
  assert.deepEqual(input, before);
});
