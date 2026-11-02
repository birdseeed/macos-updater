import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
import { types } from 'node:util';
import { parseStrictJSON } from '../protocol/strict-json.mjs';

// Private fixture receipts describe syntax and an initial byte snapshot only.
// They confer no consent, observation, authentication or action authority.
const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const intrinsicBuffer = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer').get;
const intrinsicOffset = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteOffset').get;
const intrinsicLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength').get;
const uuidV4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const encoder = new TextEncoder();

function receipt(status, value = null, bytes = null) {
  return {
    status, reason: status === 'refused' ? 'invalid-coverage' : null, value, bytes,
    sha256: bytes === null ? null : createHash('sha256').update(bytes).digest('hex'),
    scope: 'fixture-only', requestSent: false, userConsentVerified: false,
    inventoryVerified: false, sourceApproved: false, deletionPerformed: false,
    cataloguePublished: false,
  };
}

function invalid() { throw new TypeError('Invalid coverage fixture'); }

// Detect proxies before any operation that could invoke a trap, even if revoked.
function dataRecord(value, expected) {
  if (value === null || typeof value !== 'object' || types.isProxy(value)) invalid();
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) invalid();
  const keys = Reflect.ownKeys(value);
  if (keys.length !== expected.length) invalid();
  const result = Object.create(null);
  for (const key of keys) {
    if (typeof key !== 'string' || !expected.includes(key)) invalid();
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    result[key] = descriptor.value;
  }
  return result;
}

function appArray(value) {
  if (types.isProxy(value) || !Array.isArray(value)
      || Object.getPrototypeOf(value) !== Array.prototype) invalid();
  const length = Object.getOwnPropertyDescriptor(value, 'length').value;
  if (length < 1 || length > 10) invalid();
  const keys = Reflect.ownKeys(value);
  if (keys.length !== length + 1) invalid();
  const result = [];
  for (let index = 0; index < length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
    if (!descriptor || !descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    result.push(descriptor.value);
  }
  return result;
}

function validUUID(value) {
  return typeof value === 'string' && value.length === 36 && uuidV4.test(value);
}

function boundedText(value) {
  if (typeof value !== 'string' || value.length < 1 || value.length > 256) invalid();
  let scalars = 0;
  for (let index = 0; index < value.length; index++) {
    const unit = value.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(++index);
      if (!(next >= 0xdc00 && next <= 0xdfff)) invalid();
    } else if (unit >= 0xdc00 && unit <= 0xdfff) invalid();
    if (++scalars > 128) invalid();
  }
  if (encoder.encode(value).byteLength > 512) invalid();
  // Conservative syntax screens can false-refuse valid text; they prove no privacy property.
  if (/[\u0000-\u001f\u007f-\u009f/\\]/u.test(value)
      || /\S+@\S+/u.test(value) || /[A-Za-z][A-Za-z0-9+.-]*:/u.test(value)) invalid();
  return value;
}

function reportValue(input) {
  const root = dataRecord(input, ['schema', 'reportID', 'disclosureVersion', 'apps']);
  if (root.schema !== 'coverage-report-v1' || root.disclosureVersion !== 1
      || !validUUID(root.reportID)) invalid();
  const identities = new Set();
  const apps = appArray(root.apps).map(inputApp => {
    const app = dataRecord(inputApp, ['bundleID', 'displayName', 'version']);
    if (typeof app.bundleID !== 'string' || app.bundleID.length < 3 || app.bundleID.length > 255
        || !/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(app.bundleID)
        || identities.has(app.bundleID)) invalid();
    identities.add(app.bundleID);
    return {
      bundleID: app.bundleID, displayName: boundedText(app.displayName),
      version: app.version === null ? null : boundedText(app.version),
    };
  });
  apps.sort((left, right) => left.bundleID < right.bundleID ? -1 : left.bundleID > right.bundleID ? 1 : 0);
  return { apps, disclosureVersion: 1, reportID: root.reportID, schema: 'coverage-report-v1' };
}

function deletionValue(input) {
  const root = dataRecord(input, ['reportID', 'deletionSecret']);
  if (!validUUID(root.reportID) || typeof root.deletionSecret !== 'string'
      || root.deletionSecret.length !== 64 || !/^[0-9a-f]{64}$/.test(root.deletionSecret)) invalid();
  return { deletionSecret: root.deletionSecret, reportID: root.reportID };
}

// Emit the closed schema in recursively sorted key order. Only primitive strings
// reach JSON.stringify, so no caller-owned toJSON or other callback can run.
function reportWire(value) {
  const apps = value.apps.map(app => '{"bundleID":' + JSON.stringify(app.bundleID)
    + ',"displayName":' + JSON.stringify(app.displayName)
    + ',"version":' + (app.version === null ? 'null' : JSON.stringify(app.version)) + '}');
  return '{"apps":[' + apps.join(',') + '],"disclosureVersion":1,"reportID":'
    + JSON.stringify(value.reportID) + ',"schema":"coverage-report-v1"}';
}

function deletionWire(value) {
  return '{"deletionSecret":' + JSON.stringify(value.deletionSecret)
    + ',"reportID":' + JSON.stringify(value.reportID) + '}';
}

function byteSnapshot(input, maximumBytes) {
  if (types.isProxy(input) || !types.isUint8Array(input)) invalid();
  const prototype = Object.getPrototypeOf(input);
  if (prototype !== Uint8Array.prototype && prototype !== Buffer.prototype) invalid();
  const length = intrinsicLength.call(input);
  if (length < 1 || length > maximumBytes) invalid();
  const buffer = intrinsicBuffer.call(input);
  const offset = intrinsicOffset.call(input);
  if (!types.isArrayBuffer(buffer)) invalid(); // Includes refusal of SharedArrayBuffer.
  const keys = Reflect.ownKeys(input);
  if (keys.length !== length) invalid();
  for (let index = 0; index < length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(input, String(index));
    if (!descriptor || !descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
  }
  // Construction uses intrinsic buffer/offset/length, never input iterators or species.
  const view = new Uint8Array(buffer, offset, length);
  const snapshot = new Uint8Array(length);
  for (let index = 0; index < length; index++) snapshot[index] = view[index];
  return snapshot;
}

function boundedDepth(bytes) {
  let depth = 0;
  let quoted = false;
  let escaped = false;
  for (let index = 0; index < bytes.length; index++) {
    const byte = bytes[index];
    if (quoted) {
      if (escaped) escaped = false;
      else if (byte === 92) escaped = true;
      else if (byte === 34) quoted = false;
    } else if (byte === 34) quoted = true;
    else if (byte === 123 || byte === 91) {
      if (++depth > 4) invalid();
    } else if (byte === 125 || byte === 93) depth--;
  }
  // Grammar, delimiter matching and full consumption belong to the unchanged parser.
}

function encode(input, validate, wire, maximumBytes) {
  try {
    const value = validate(input);
    const bytes = encoder.encode(wire(value));
    if (bytes.byteLength > maximumBytes) invalid();
    return receipt('encoded', value, bytes);
  } catch { return receipt('refused'); }
}

function decode(input, validate, wire, maximumBytes) {
  try {
    const bytes = byteSnapshot(input, maximumBytes);
    boundedDepth(bytes);
    const parsed = parseStrictJSON(bytes, { maximumBytes, maximumDepth: 16 });
    const value = validate(parsed);
    const canonical = encoder.encode(wire(value));
    if (canonical.byteLength !== bytes.byteLength) invalid();
    for (let index = 0; index < bytes.byteLength; index++) {
      if (canonical[index] !== bytes[index]) invalid();
    }
    return receipt('validated', value, bytes);
  } catch { return receipt('refused'); }
}

export function encodeCoverageReport(value) { return encode(value, reportValue, reportWire, 16384); }
export function decodeCoverageReport(bytes) { return decode(bytes, reportValue, reportWire, 16384); }
export function encodeCoverageDeletion(value) { return encode(value, deletionValue, deletionWire, 512); }
export function decodeCoverageDeletion(bytes) { return decode(bytes, deletionValue, deletionWire, 512); }
