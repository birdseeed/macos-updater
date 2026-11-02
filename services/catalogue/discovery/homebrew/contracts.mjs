import { types } from 'node:util';

export const HOMEBREW_PROJECTION_VERSION = 'homebrew-single-cask-fixture-v1';
export const HOMEBREW_LIMITS = Object.freeze({
  maximumBytes: 262144, maximumDepth: 16, maximumCasks: 1,
  maximumRecords: 64, maximumURLBytes: 2048, maximumIdentityBytes: 128,
  maximumObservationAge: 86400,
});
export function flags() {
  return { scope: 'synthetic-fixture-only', sourceAuthenticated: false,
    artifactAcquired: false, independentlyVerified: false, publicationAllowed: false,
    installationAllowed: false, ownershipEstablished: false };
}
export function refusingHomebrewResult(reason = 'unsupported-homebrew-input') {
  return { status: 'held', reason, ...flags() };
}
export function need(condition) { if (!condition) throw new Error('unsupported-homebrew-input'); }
export function exact(value, required, optional = []) {
  need(value !== null && typeof value === 'object' && !Array.isArray(value));
  const keys = Object.keys(value);
  need(required.every(k => Object.hasOwn(value, k)) && keys.every(k => required.includes(k) || optional.includes(k)));
}
export const time = value => Number.isSafeInteger(value) && value >= 0;
export const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
export function text(value, maximum = 128) {
  if (typeof value !== 'string' || value.length === 0 || value.length > maximum) return false;
  // Buffer-free UTF8 sizing; lone surrogates are never accepted as identities.
  let length = 0;
  for (let n = 0; n < value.length; n++) {
    const c = value.charCodeAt(n);
    if (c >= 0xd800 && c <= 0xdbff) {
      const next = value.charCodeAt(++n);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
      length += 4;
    } else if (c >= 0xdc00 && c <= 0xdfff) return false;
    else length += c < 128 ? 1 : c < 2048 ? 2 : 3;
  }
  return length <= maximum;
}
export function artifactURL(value) {
  if (!text(value, 2048) || /[\s\\?#]/u.test(value)) return false;
  try {
    const u = new URL(value);
    return u.protocol === 'https:' && u.hostname !== '' && u.username === '' && u.password === ''
      && u.port === '' && u.href === value && !u.hash && !u.search;
  } catch { return false; }
}
export function equal(a, b) {
  if (a === b) return true;
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object' || Array.isArray(a) !== Array.isArray(b)) return false;
  const ak = Object.keys(a), bk = Object.keys(b);
  return ak.length === bk.length && ak.every(k => Object.hasOwn(b, k) && equal(a[k], b[k]));
}
const typed = Object.getPrototypeOf(Uint8Array.prototype);
const getters = Object.fromEntries(['buffer', 'byteOffset', 'byteLength', 'length'].map(k => [k, Object.getOwnPropertyDescriptor(typed, k).get]));
const bufferLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
const typedSet = Uint8Array.prototype.set;

// Descriptor-first copying makes all later schema access operate on owned data.
// The set is intentionally never unwound: shared references are rejected too.
export function ownTree(input, allowBytes = false) {
  const seen = new Set(); let nodes = 0;
  function visit(v, depth, bytePosition = false) {
    need(++nodes <= 1100000 && depth <= 32);
    if (v === null || typeof v === 'string' || typeof v === 'boolean' || (typeof v === 'number' && Number.isFinite(v))) return v;
    need(typeof v === 'object' && !types.isProxy(v) && !seen.has(v)); seen.add(v);
    if (bytePosition) {
      need(Object.getPrototypeOf(v) === Uint8Array.prototype && types.isUint8Array(v));
      const length = getters.length.call(v), byteLength = getters.byteLength.call(v);
      const buffer = getters.buffer.call(v);
      need(length > 0 && length <= HOMEBREW_LIMITS.maximumBytes && byteLength === length
        && getters.byteOffset.call(v) === 0 && !types.isSharedArrayBuffer(buffer)
        && bufferLength.call(buffer) === length);
      need(!seen.has(buffer)); seen.add(buffer);
      const keys = Reflect.ownKeys(v); need(keys.length === length);
      for (let n = 0; n < length; n++) {
        need(keys[n] === String(n));
        const d = Object.getOwnPropertyDescriptor(v, keys[n]);
        need(d.enumerable && Object.hasOwn(d, 'value'));
      }
      const result = new Uint8Array(length); typedSet.call(result, v); return result;
    }
    const array = Array.isArray(v), proto = Object.getPrototypeOf(v);
    need(array ? proto === Array.prototype : proto === Object.prototype || proto === null);
    const keys = Reflect.ownKeys(v), out = array ? [] : {};
    let arrayLength;
    if (array) {
      const d = Object.getOwnPropertyDescriptor(v, 'length');
      need(d && Object.hasOwn(d, 'value')); arrayLength = d.value;
      need(arrayLength <= 262144 && keys.length === arrayLength + 1);
    }
    for (const k of keys) {
      need(typeof k === 'string'); if (array && k === 'length') continue;
      const d = Object.getOwnPropertyDescriptor(v, k);
      need(d.enumerable && Object.hasOwn(d, 'value'));
      if (array) need(/^(0|[1-9][0-9]*)$/.test(k) && Number(k) < arrayLength);
      Object.defineProperty(out, k, { value: visit(d.value, depth + 1, allowBytes && depth === 0 && k === 'bytes'), enumerable: true, configurable: true, writable: true });
    }
    return out;
  }
  return visit(input, 0);
}
