import { isIP } from 'node:net';
import { vendorBounds as bounds } from './contracts.mjs';
export { record, list, need, hex, canonical, copy, identity, digest, reasonOf, without } from '../upstream/contracts.mjs';
import { need, text, byteView, decode64 } from '../upstream/contracts.mjs';

export function string(value, maximum = bounds.identityBytes) {
  text(value, maximum);
  need(!/[\u0000-\u001f\u007f]/u.test(value));
  return value;
}
export function url(value) {
  string(value, bounds.urlBytes);
  // Require literal DNS authority. URL normalisation must not repair an input.
  need(/^https:\/\/[a-z0-9.-]+(?::443)?(?:\/|$)/.test(value));
  const parsed = new URL(value);
  need(parsed.protocol === 'https:' && !parsed.username && !parsed.password && !parsed.hash);
  need(!/[\\\s]/u.test(value) && !value.includes('#'));
  const host = parsed.hostname;
  need(!isIP(host) && host.length <= 253 && !host.endsWith('.'));
  const labels = host.split('.');
  need(labels.length >= 2 && labels.every(s => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(s)));
  need(!labels.every(s => /^[0-9]+$/.test(s)));
  need(!['localhost','local','internal','lan','home','invalid'].includes(labels.at(-1)));
  need(!labels.some(s => s === 'localhost'));
  return parsed;
}
export function artifactURL(value) {
  const parsed = url(value);
  need(/\.(zip|dmg)$/.test(parsed.pathname));
  return value;
}
export function bytes(value, maximum) {
  need(value instanceof Uint8Array);
  need([Uint8Array.prototype, Buffer.prototype].includes(Object.getPrototypeOf(value)));
  // byteView reads these intrinsic properties. Refuse shadowing before that
  // shared validator runs, so a caller's accessor cannot execute here.
  for (const key of ['buffer','byteLength','byteOffset']) need(!Object.hasOwn(value,key));
  return Buffer.from(byteView(value, maximum));
}
export function metadataText(value) {
  const data = bytes(value, bounds.metadataBytes);
  need(data.length > 0 && !(data[0] === 239 && data[1] === 187 && data[2] === 191));
  const decoded = new TextDecoder('utf-8', {fatal:true}).decode(data);
  need(!/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(decoded));
  need(!/\r(?!\n)/.test(decoded) && decoded.split('\n').length <= bounds.lines);
  return {data, decoded};
}
export function version(value, comparator) {
  string(value, bounds.versionBytes);
  need(['sparkle-dotted-v1','electron-stable-semver-v1'].includes(comparator));
  const parts = value.split('.');
  need(comparator === 'sparkle-dotted-v1' ? parts.length >= 1 && parts.length <= 4 : parts.length === 3);
  need(parts.every(p => /^(0|[1-9][0-9]*)$/.test(p) && p.length <= 10 && Number(p) <= 2147483647));
  return parts.map(Number);
}
export function order(left, right) {
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const a = left[i] ?? 0, b = right[i] ?? 0;
    if (a !== b) return a < b ? -1 : 1;
  }
  return 0;
}
export const os = value => version(value, 'electron-stable-semver-v1');
export function integrity(value, algorithm) {
  need(value.algorithm === algorithm);
  need(decode64(value.value, 64).length === 64);
}
export function length(value) {
  need(Number.isSafeInteger(value) && value > 0 && value <= bounds.artifactBytes);
  return value;
}
export function decimal(value) {
  need(typeof value === 'string' && /^(0|[1-9][0-9]*)$/.test(value) && value.length <= 10);
  return length(Number(value));
}
export const comparatorFor = adapter => adapter === 'sparkle' ? 'sparkle-dotted-v1' : 'electron-stable-semver-v1';
export const parserFor = adapter => adapter + '-subset-v1';
export const parserHeld = error => ({status:'held',reason: error instanceof Error && error.reason ? error.reason : 'invalid-input',metadata:null,sourceDigests:null});
