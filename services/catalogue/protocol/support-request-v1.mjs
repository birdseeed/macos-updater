// Pure fixture-only wire validation. No I/O, request submission or trust source.
import { createHash } from 'node:crypto';
import { types } from 'node:util';
import { parseStrictJSON } from './strict-json.mjs';

const MAX_BYTES = 8192;
const ROOT_FIELDS = ['schema', 'clientRequestID', 'submittedAt', 'app', 'notes', 'consent'];
const APP_FIELDS = ['displayName', 'bundleID', 'version', 'vendorURL'];
const OBSERVATION_FIELDS = ['value', 'provenance'];
const CONSENT_FIELDS = ['schema', 'purpose', 'destination', 'presentedAt', 'acceptedAt'];
const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const typedGet = Object.fromEntries(['byteLength', 'byteOffset', 'buffer'].map(
  key => [key, Object.getOwnPropertyDescriptor(typedArrayPrototype, key).get],
));

function require(condition) {
  if (!condition) throw new TypeError('Invalid fixture support request');
}
function result(operation, value = null, digest = null) {
  return {
    status: value === null ? 'refused' : operation === 'decode' ? 'validated' : 'encoded',
    reason: value === null ? 'invalid-request' : null,
    scope: 'fixture-only', requestSent: false, ownershipVerified: false,
    userConsentVerified: false, sourceApproved: false, requestSHA256: digest,
    [operation === 'decode' ? 'request' : 'requestBytes']: value,
  };
}
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

// Reject Proxies before reflection, including revoked Proxies. Copy only the
// intrinsic view, without reading caller getters, iterators or conversion hooks.
function copyBytes(value) {
  require(!types.isProxy(value) && types.isUint8Array(value));
  const length = typedGet.byteLength.call(value);
  require(length > 0 && length <= MAX_BYTES);
  const backing = typedGet.buffer.call(value);
  require(!types.isSharedArrayBuffer(backing));
  const offset = typedGet.byteOffset.call(value);
  const view = new Uint8Array(backing, offset, length);
  const copied = new Uint8Array(length);
  copied.set(view);
  return copied;
}

// Fixed schema traversal only: at most seven records and three levels. Reading
// descriptor.value never invokes the object's getter or inherited properties.
function record(value, fields) {
  require(value !== null && typeof value === 'object' && !types.isProxy(value));
  const prototype = Object.getPrototypeOf(value);
  require(prototype === Object.prototype || prototype === null);
  const keys = Reflect.ownKeys(value);
  require(keys.length === fields.length);
  const copied = Object.create(null);
  for (const key of keys) {
    require(typeof key === 'string' && fields.includes(key));
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    require(descriptor !== undefined && descriptor.enumerable && Object.hasOwn(descriptor, 'value'));
    copied[key] = descriptor.value;
  }
  return copied;
}
function integer(value) {
  return Number.isSafeInteger(value) && !Object.is(value, -0) && value >= 0;
}
function text(value, maximumScalars, maximumBytes, allowEmpty = false, allowLayout = false) {
  // Code-unit preflight bounds the byte/scalar scans even for oversized input.
  if (typeof value !== 'string' || value.length > maximumScalars * 2
      || (!allowEmpty && value.length === 0)
      || !String.prototype.isWellFormed.call(value)
      || Buffer.byteLength(value, 'utf8') > maximumBytes) return false;
  const controls = allowLayout
    ? /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/u
    : /[\u0000-\u001f\u007f-\u009f]/u;
  if (controls.test(value)) return false;
  let scalars = 0;
  for (const unused of value) {
    void unused;
    if (++scalars > maximumScalars) return false;
  }
  return true;
}
function bundleID(value) {
  return typeof value === 'string' && value.length >= 3 && value.length <= 255
    && !/[^A-Za-z0-9.-]/u.test(value)
    && value.includes('.') && value.split('.').every(component => component.length > 0);
}
function vendorURL(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 2048
      || !String.prototype.isWellFormed.call(value)
      || Buffer.byteLength(value, 'utf8') > 2048
      || !value.startsWith('https://')
      || /[\s\u0000-\u001f\u007f-\u009f\\?#]/u.test(value)) return false;
  const pathStart = value.indexOf('/', 8);
  const authority = value.slice(8, pathStart === -1 ? undefined : pathStart);
  const colon = authority.indexOf(':');
  const host = colon === -1 ? authority : authority.slice(0, colon);
  if (host.length < 1 || host.length > 253
      || !host.split('.').every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) return false;
  if (colon !== -1) {
    const port = authority.slice(colon + 1);
    if (!/^[1-9][0-9]{0,4}$/.test(port) || Number(port) > 65535) return false;
  }
  // WHATWG would remove these literal or percent-dot path segments. Refuse
  // them explicitly while retaining ordinary Unicode/percent path text raw.
  if (pathStart !== -1) {
    for (const segment of value.slice(pathStart).split('/')) {
      const dots = segment.replace(/%2e/gi, '.');
      if (dots === '.' || dots === '..') return false;
    }
  }
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' && parsed.hostname === host
      && !/^[0-9]+(?:\.[0-9]+)*$/.test(host)
      && parsed.username === '' && parsed.password === ''
      && parsed.search === '' && parsed.hash === '';
  } catch { return false; }
}
function observation(value, validate, userSuppliedOnly = false) {
  const fields = record(value, OBSERVATION_FIELDS);
  require(fields.provenance === 'userSupplied'
    || (!userSuppliedOnly && fields.provenance === 'locallyObserved'));
  require(validate(fields.value));
  return { value: fields.value, provenance: fields.provenance };
}

// Return a new exact wire record. No caller object survives validation and no
// untrusted deep traversal/JSON serialisation is used to obtain this copy.
function validateRequest(value) {
  const root = record(value, ROOT_FIELDS);
  require(root.schema === 'fixture-support-request-v1');
  require(typeof root.clientRequestID === 'string' && root.clientRequestID.length === 36
    && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(root.clientRequestID));
  require(integer(root.submittedAt));
  const app = record(root.app, APP_FIELDS);
  const nameOrVersion = value => text(value, 128, 512);
  const copiedApp = {
    displayName: observation(app.displayName, nameOrVersion),
    bundleID: app.bundleID === null ? null : observation(app.bundleID, bundleID),
    version: app.version === null ? null : observation(app.version, nameOrVersion),
    vendorURL: app.vendorURL === null ? null : observation(app.vendorURL, vendorURL, true),
  };
  require(root.notes === null || text(root.notes, 1000, 2048, true, true));
  const consent = record(root.consent, CONSENT_FIELDS);
  require(consent.schema === 'fixture-support-consent-v1'
    && consent.purpose === 'coverage-research'
    && consent.destination === 'patched-catalogue-support');
  require(integer(consent.presentedAt) && integer(consent.acceptedAt)
    && consent.presentedAt <= consent.acceptedAt && consent.acceptedAt <= root.submittedAt);
  return {
    schema: root.schema, clientRequestID: root.clientRequestID, submittedAt: root.submittedAt,
    app: copiedApp, notes: root.notes,
    consent: {
      schema: consent.schema, purpose: consent.purpose, destination: consent.destination,
      presentedAt: consent.presentedAt, acceptedAt: consent.acceptedAt,
    },
  };
}

// Only internally constructed, validated records reach this function. JSON is
// used on primitive strings/numbers, never caller objects or toJSON callbacks.
function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  return `{${Object.keys(value).sort().map(
    key => `${JSON.stringify(key)}:${canonical(value[key])}`,
  ).join(',')}}`;
}

export function decodeSupportRequest(requestBytes) {
  try {
    const bytes = copyBytes(requestBytes);
    const parsed = parseStrictJSON(bytes, { maximumBytes: MAX_BYTES, maximumDepth: 16 });
    const request = validateRequest(parsed);
    return result('decode', request, sha256(bytes));
  } catch { return result('decode'); }
}

export function encodeSupportRequest(validatedRequest) {
  try {
    const request = validateRequest(validatedRequest);
    const bytes = new TextEncoder().encode(canonical(request));
    require(bytes.byteLength <= MAX_BYTES);
    return result('encode', bytes, sha256(bytes));
  } catch { return result('encode'); }
}
