import { createHash } from 'node:crypto';

export const MiB = 1024 * 1024;
export const repository = 'Installomator/Installomator';
export class Refusal extends Error {
  constructor(reason) { super(reason); this.reason = reason; }
}
export function need(condition, reason = 'invalid-input') {
  if (!condition) throw new Refusal(reason);
}
export function reasonOf(error) {
  return error instanceof Refusal ? error.reason : 'invalid-input';
}
export function record(value, keys) {
  need(value !== null && typeof value === 'object');
  const prototype = Object.getPrototypeOf(value);
  need(prototype === Object.prototype || prototype === null);
  const own = Reflect.ownKeys(value);
  need(own.length === keys.length && own.every(k => typeof k === 'string' && keys.includes(k)));
  for (const key of keys) {
    const d = Object.getOwnPropertyDescriptor(value, key);
    need(d && d.enumerable && Object.hasOwn(d, 'value'));
  }
  return value;
}
export function list(value, maximum, reason = 'invalid-input') {
  need(Array.isArray(value) && Object.getPrototypeOf(value) === Array.prototype, reason);
  need(value.length <= maximum, reason);
  need(Reflect.ownKeys(value).length === value.length + 1, reason);
  for (let i = 0; i < value.length; i++) {
    const d = Object.getOwnPropertyDescriptor(value, String(i));
    need(d && d.enumerable && Object.hasOwn(d, 'value'), reason);
  }
  return value;
}
export function text(value, maximum = 1024) {
  need(typeof value === 'string' && value.length > 0 && value.isWellFormed() && Buffer.byteLength(value, 'utf8') <= maximum);
  return value;
}
export function identifier(value) {
  need(typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(value));
  return value;
}
export function integer(value, maximum = Number.MAX_SAFE_INTEGER) {
  need(Number.isSafeInteger(value) && value >= 0 && value <= maximum);
  return value;
}
export function hex(value, length = 64) {
  need(typeof value === 'string' && value.length === length && /^[0-9a-f]+$/.test(value));
  return value;
}
export function labelPath(value) {
  // Length first, before scanning a potentially huge caller-supplied path.
  need(typeof value === 'string');
  need(value.length <= 1024 && Buffer.byteLength(value) <= 1024, 'path-limit');
  need(/^fragments\/labels\/[A-Za-z0-9_-]+\.sh$/.test(value));
  return value;
}
export function byteView(value, maximum) {
  need(value instanceof Uint8Array && !(value.buffer instanceof SharedArrayBuffer));
  need(value.byteLength <= maximum, 'byte-limit');
  return Buffer.from(value.buffer, value.byteOffset, value.byteLength);
}
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export function decode64(value, maximum) {
  need(typeof value === 'string' && value.length <= 4 * Math.ceil(maximum / 3));
  need(value.length % 4 === 0 && /^[A-Za-z0-9+/]*={0,2}$/.test(value));
  const bytes = Buffer.from(value, 'base64');
  need(bytes.length <= maximum && bytes.toString('base64') === value);
  return bytes;
}
export function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value !== null && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  }
  return JSON.stringify(value);
}
export const equal = (left, right) => canonical(left) === canonical(right);
export const identity = value => digest(Buffer.from(canonical(value)));
export const copy = value => JSON.parse(canonical(value));
// Detached JSON-shaped records: callers may serialise or tamper their copies;
// every resumed transition revalidates them against the retained independent head.
export const owned = copy;
export function without(value, key) {
  return Object.fromEntries(Object.entries(value).filter(([k]) => k !== key));
}
export function validateRepair(value, components) {
  if (value === null) return;
  record(value, ['component','fromVersion','toVersion','reviewId','rationale']);
  need(components.includes(value.component));
  identifier(value.fromVersion); identifier(value.toVersion); identifier(value.reviewId); text(value.rationale);
  need(value.fromVersion !== value.toVersion);
}
export function evidenceRefs(value) {
  list(value, 16);
  const seen = new Set();
  for (const ref of value) {
    record(ref, ['ref','sha256']); text(ref.ref); hex(ref.sha256);
    need(!seen.has(ref.ref)); seen.add(ref.ref);
  }
}

// Resource preflight on saved, JSON-shaped data, before cloning or hashing. This
// does not authenticate storage. Never invoke caller getters or custom toJSON.
export function boundedData(value, maximum = 16 * MiB) {
  let bytes = 0, nodes = 0;
  const ancestors = new Set();
  function add(n) { bytes += n; need(bytes <= maximum, 'state-limit'); }
  function stringSize(s) {
    need(typeof s === 'string' && s.isWellFormed(), 'invalid-state');
    const remaining = maximum - bytes;
    // Count encoded bytes without constructing an escaped JSON string. Control
    // characters can expand sixfold, so bounding raw UTF-8 alone is insufficient.
    need(s.length <= remaining - 2, 'state-limit');
    let encoded = Buffer.byteLength(s) + 2;
    need(encoded <= remaining, 'state-limit');
    for (let i = 0; i < s.length; i++) {
      const code = s.charCodeAt(i);
      if (code === 34 || code === 92) encoded++;
      else if (code < 32) encoded += [8,9,10,12,13].includes(code) ? 1 : 5;
      need(encoded <= remaining, 'state-limit');
    }
    add(encoded);
  }
  function visit(item, depth) {
    need(++nodes <= 1000000 && depth <= 32, 'state-limit');
    if (item === null) { add(4); return; }
    if (typeof item === 'string') { stringSize(item); return; }
    if (typeof item === 'number') { integer(item); add(String(item).length); return; }
    if (typeof item === 'boolean') { add(item ? 4 : 5); return; }
    need(typeof item === 'object' && !ancestors.has(item), 'invalid-state');
    ancestors.add(item);
    if (Array.isArray(item)) {
      list(item, 30000, 'state-limit'); add(2 + Math.max(0, item.length - 1));
      for (const child of item) visit(child, depth + 1);
    } else {
      const keys = Reflect.ownKeys(item);
      need(keys.length <= 32 && keys.every(k => typeof k === 'string'), 'invalid-state');
      record(item, keys); add(2 + Math.max(0, keys.length - 1));
      for (const key of keys) { stringSize(key); add(1); visit(item[key], depth + 1); }
    }
    ancestors.delete(item);
  }
  visit(value, 0);
  return bytes;
}
