// TEST ONLY: fixed public test seed from fixture directory. Never use for real signing.
import { readFileSync } from 'node:fs';
import { createHash, createPrivateKey, sign } from 'node:crypto';
export const fixtureRoot = new URL('../protocol/fixtures/catalogue-v2/', import.meta.url);
export const readFixture = name => readFileSync(new URL(name, fixtureRoot));
export const key = JSON.parse(readFixture('TEST-ONLY-key.json'));
const privateKey = createPrivateKey({
  key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), Buffer.from(key.seedHex, 'hex')]),
  format: 'der', type: 'pkcs8',
});
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export const clone = value => structuredClone(value);
export const stable = value => Array.isArray(value) ? value.map(stable)
  : value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(k => [k, stable(value[k])])) : value;
export const bytesOf = value => Buffer.from(JSON.stringify(stable(value)));
export const message = bytes => Buffer.concat([Buffer.from('im.patched.catalogue.v2\0'), bytes]);
export const signBytes = bytes => sign(null, message(bytes), privateKey);
// Test-only malformed-message signing for domain-separation refusal cases.
export const signRawFixtureMessage = bytes => sign(null, bytes, privateKey);
export function envelopeFor(bytes) {
  return { schema: 'fixture-catalogue-envelope-v2', algorithm: 'Ed25519', keyID: 'test-key-1',
    payload: Buffer.from(bytes).toString('base64'), signature: signBytes(bytes).toString('base64') };
}
export const wrap = bytes => bytesOf(envelopeFor(bytes));
export const payload = () => JSON.parse(readFixture('one-entry.payload.json'));
export const emptyPayload = () => JSON.parse(readFixture('empty.payload.json'));
export const withdrawalPayload = () => JSON.parse(readFixture('withdrawal.payload.json'));
export const trust = () => ({catalogueID: 'test-catalogue', keyID: 'test-key-1',
  publicKeyBase64: key.publicKeyBase64, firstSequence: 1, lastSequence: Number.MAX_SAFE_INTEGER, retired: false});
export const context = () => ({now: 1800000000, clientProtocol: 2, clientBuild: 100});
export function input(p = payload()) {
  return {envelopeBytes: wrap(bytesOf(p)), trust: trust(), context: context(), previous: null, bootstrap: true};
}
export const checkpoint = p => ({catalogueID: p.catalogueID, sequence: p.sequence, payloadSHA256: sha256(bytesOf(p))});
export function change(p, path, value) {
  const parts = path.split('.');
  let target = p;
  for (const part of parts.slice(0, -1)) target = target[part];
  target[parts.at(-1)] = value;
  return p;
}
