import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const fixtureRoot = new URL('../../../Fixtures/InstallomatorDiscovery/', import.meta.url);
// Static controlled paths only. No input-derived filename is ever opened.
const staticBytes = new Map([
  ['literal-valid.sh', readFileSync(new URL('labels/literal-valid.sh', fixtureRoot))],
  ['dynamic-held.sh', readFileSync(new URL('labels/dynamic-held.sh', fixtureRoot))],
  ['malformed-held.sh', readFileSync(new URL('labels/malformed-held.sh', fixtureRoot))],
]);
const manifestBytes = readFileSync(new URL('snapshot-manifest.json', fixtureRoot));
const policyBytes = readFileSync(new URL('approved-route-policy.json', fixtureRoot));
export const expectedEvents = JSON.parse(readFileSync(new URL('expected-events.json', fixtureRoot)));
export const scenario = JSON.parse(readFileSync(new URL('attempt-history.json', fixtureRoot)));
const license = readFileSync(new URL('../../../ThirdParty/Installomator/LICENSE', import.meta.url));
export const path = 'fragments/labels/literal-valid.sh';
export const versions = { parserVersion: 'literal-v1', policyVersion: 'policy-v1' };
export const copy = value => structuredClone(value);
export const sha = bytes => createHash('sha256').update(bytes).digest('hex');
export function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value !== null && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  }
  return JSON.stringify(value);
}
export function contentId(value, key) {
  const fields = copy(value); delete fields[key];
  return sha(Buffer.from(canonical(fields)));
}
export const labelBytes = () => Buffer.from(staticBytes.get('literal-valid.sh'));
export const policy = () => JSON.parse(policyBytes);
export function snapshot() {
  const manifest = JSON.parse(manifestBytes);
  return { manifest, payloads: [...staticBytes].map(([name, bytes]) => ({ path: 'fragments/labels/' + name, bytes: Buffer.from(bytes) })),
    licenseBytes: Buffer.from(license), noticePayloads: [] };
}
export function bootstrapOptions(overrides = {}) {
  return { previous: null, expectedCheckpointId: null, bootstrap: true, ...versions, repair: null, ...overrides };
}
export function nextOptions(previous, overrides = {}) {
  return { previous, expectedCheckpointId: previous.checkpointId, bootstrap: false, ...versions, repair: null, ...overrides };
}
export function revise(input, previous, changes = {}) {
  input.manifest.commit = '3'.repeat(40); input.manifest.tree = '4'.repeat(40);
  input.manifest.parentCommit = previous.commit; input.manifest.priorCheckpointId = previous.checkpointId;
  input.manifest.observedAt = previous.observedAt + 1;
  Object.assign(input.manifest, changes); return input;
}
export function replaceLabel(input, bytes, labelPath = path) {
  input.payloads.find(p => p.path === labelPath).bytes = Buffer.from(bytes);
  Object.assign(input.manifest.inventory.find(p => p.path === labelPath), { sha256: sha(bytes), byteLength: bytes.length });
  return input;
}
export function addLabel(input, name) {
  const p = 'fragments/labels/' + name + '.sh';
  const bytes = Buffer.from(labelBytes().toString().replace('literal-valid)', name + ')'));
  const desc = copy(input.manifest.inventory.find(x => x.path === path));
  Object.assign(desc, { path: p, sha256: sha(bytes), byteLength: bytes.length });
  input.manifest.inventory.push(desc); input.payloads.push({ path: p, bytes }); return p;
}
export function complete(result) {
  assert.equal(result.status, 'complete', 'valid complete fixture snapshot must advance');
  assert.ok(result.checkpoint); return result.checkpoint;
}
export function refused(result, previous = null) {
  assert.equal(result.status, 'refused'); assert.deepEqual(result.checkpoint, previous);
  assert.match(result.reason, /\S/); assert.match(result.nextAction, /\S/);
}
export function noAuthority(result) {
  assert.equal(result.publicationAuthority, false);
  assert.equal(Object.hasOwn(result, 'nativeEvidence'), false);
}
export function candidateFixture(overrides = {}) {
  const bytes = labelBytes();
  return { schema: 'fixture-candidate-v1', scope: 'fixture-only',
    candidateId: sha(Buffer.from('Installomator/Installomator\n' + path)),
    repository: 'Installomator/Installomator', checkpointId: 'a'.repeat(64),
    commit: '1'.repeat(40), tree: '2'.repeat(40), labelPath: path,
    labelSha256: sha(bytes), labelByteLength: bytes.length, labelBytesBase64: bytes.toString('base64'),
    parserVersion: 'literal-v1', policyVersion: 'policy-v1', route: copy(policy().routes[0]),
    publicationAuthority: false, ...overrides };
}
export function observation(overrides = {}) {
  return { schema: 'fixture-observation-v1', checkerVersion: scenario.checkerVersion,
    environmentVersion: scenario.environmentVersion, capabilityVersion: scenario.capabilityVersion,
    availability: 'available', artifactBytes: Buffer.from(scenario.artifactBase64, 'base64'),
    observedPublisher: 'AAAAAAAAAA', checks: { signature: 'passed', notarisation: 'passed', container: 'passed', compatibility: 'passed' },
    evidenceRefs: [{ ref: 'fixture:evidence-v1', sha256: sha(Buffer.from('fixture evidence v1')) }], ...overrides };
}
export function attemptInput(overrides = {}) {
  return { state: null, expectedStateId: null, bootstrap: true, batchId: 'batch-1', attemptId: 'attempt-1',
    candidate: candidateFixture(), observation: observation(), observedAt: 1000,
    activeMilliseconds: 10, retry: null, ...overrides };
}
export function continueInput(state, overrides = {}) {
  return attemptInput({ state: copy(state), expectedStateId: state.stateId, bootstrap: false,
    attemptId: 'attempt-' + (state.history.length + 1), observedAt: state.history.at(-1).observedAt + 1, ...overrides });
}
export function recorded(result) {
  assert.equal(result.status, 'recorded', 'a valid fixture attempt must append immutable history');
  assert.ok(result.attempt); assert.ok(result.state); return result;
}
export function heldAttempt(result, state, reason) {
  assert.equal(result.status, 'held'); assert.deepEqual(result.state, state);
  assert.equal(result.attempt, null); assert.equal(result.reason, reason); assert.match(result.nextAction, /\S/);
}
export function candidateForName(name) {
  const c = candidateFixture(), labelPath = 'fragments/labels/' + name + '.sh';
  const bytes = Buffer.from(labelBytes().toString().replace('literal-valid)', name + ')'));
  return { ...c, candidateId: sha(Buffer.from(c.repository+'\n'+labelPath)), labelPath,
    labelSha256: sha(bytes), labelByteLength: bytes.length, labelBytesBase64: bytes.toString('base64'),
    route: { ...c.route, routeId: name, labelPath } };
}
