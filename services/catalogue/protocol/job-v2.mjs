// Pure standalone fixture descriptor. No worker, lease, artifact or route authority.
import { createHash } from 'node:crypto';
import { types } from 'node:util';
import { URL } from 'node:url';
import { isIP } from 'node:net';
import { parseStrictJSON } from './strict-json.mjs';

const MAX_BYTES = 65536;
const MAX_ARTIFACT = 1099511627776;
const typedPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const byteGet = Object.fromEntries(['buffer', 'byteOffset', 'byteLength'].map(
  key => [key, Object.getOwnPropertyDescriptor(typedPrototype, key).get],
));
const flags = () => ({
  scope: 'fixture-only', authenticated: false, policyAccepted: false,
  freshOSValidation: false, publicationAllowed: false, installationAllowed: false,
});
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
function require(condition) {
  if (!condition) throw new TypeError('Invalid inert inspection record');
}

// Copy the intrinsic view into fresh, unshared storage. Never call user byte
// getters, species, iterators or conversion hooks, even for a Uint8Array subclass.
function copyBytes(value) {
  require(!types.isProxy(value) && types.isUint8Array(value));
  const length = byteGet.byteLength.call(value);
  require(length > 0 && length <= MAX_BYTES);
  const backing = byteGet.buffer.call(value);
  require(!types.isSharedArrayBuffer(backing));
  const offset = byteGet.byteOffset.call(value);
  const view = new Uint8Array(backing, offset, length);
  const copy = new Uint8Array(length);
  copy.set(view);
  return copy;
}

// Fixed schema traversal reads only own enumerable data descriptors. Shape
// rejection terminates cycles without recursively walking arbitrary caller data.
function record(value, fields) {
  require(value !== null && typeof value === 'object' && !types.isProxy(value));
  const prototype = Object.getPrototypeOf(value);
  require(prototype === Object.prototype || prototype === null);
  const keys = Reflect.ownKeys(value);
  require(keys.length === fields.length);
  const copy = Object.create(null);
  for (const key of keys) {
    require(typeof key === 'string' && fields.includes(key));
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    require(descriptor !== undefined && descriptor.enumerable && Object.hasOwn(descriptor, 'value'));
    copy[key] = descriptor.value;
  }
  return copy;
}
const integer = (value, minimum = 0, maximum = Number.MAX_SAFE_INTEGER) =>
  Number.isSafeInteger(value) && !Object.is(value, -0) && value >= minimum && value <= maximum;
const identifier = value => typeof value === 'string' && value.length >= 1 && value.length <= 64
  && /^[A-Za-z0-9]/.test(value) && !/[^A-Za-z0-9._-]/.test(value);
const digest = value => typeof value === 'string' && value.length === 64 && !/[^0-9a-f]/.test(value);
const sourceSHA = value => typeof value === 'string' && value.length === 40 && !/[^0-9a-f]/.test(value);
const uuid = value => typeof value === 'string' && value.length === 36
  && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);

function httpsURL(value) {
  // ASCII character count equals UTF8 byte count. Preflight before regex/URL work.
  if (typeof value !== 'string' || value.length < 9 || value.length > 2048
      || !value.startsWith('https://') || /[^\x21-\x7e]|[\\?#]/.test(value)) return false;
  const pathStart = value.indexOf('/', 8);
  const authority = value.slice(8, pathStart === -1 ? undefined : pathStart);
  const colon = authority.indexOf(':');
  const host = colon === -1 ? authority : authority.slice(0, colon);
  if (colon !== -1 && authority.slice(colon) !== ':443') return false;
  if (host.length < 1 || host.length > 253
      || !host.split('.').every(label => /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(label))) return false;
  // This probe detects alternate numeric IP spellings only. Its serialisation
  // is never returned, and a DNS-shaped name is not approved for network use.
  try { if (isIP(new URL(`https://${host}/`).hostname) !== 0) return false; }
  catch { /* DNS syntax was checked above; no global URL-normalisation rule. */ }
  if (pathStart !== -1) {
    const path = value.slice(pathStart);
    if (/%(?![0-9a-fA-F]{2})/.test(path)) return false;
    for (const segment of path.split('/')) {
      const dots = segment.replace(/%2e/gi, '.');
      if (dots === '.' || dots === '..') return false;
    }
  }
  return true;
}
function artifact(value) {
  const fields = record(value, ['sha256', 'length']);
  require(digest(fields.sha256) && integer(fields.length, 1, MAX_ARTIFACT));
  return { sha256: fields.sha256, length: fields.length };
}
function identity(fields) {
  require(uuid(fields.jobID) && identifier(fields.routeID) && digest(fields.routeDigest)
    && identifier(fields.policyVersion) && digest(fields.policyDigest)
    && identifier(fields.checkerVersion) && sourceSHA(fields.checkerSourceSHA)
    && (fields.architecture === 'arm64' || fields.architecture === 'x86_64'));
}

const JOB_FIELDS = [
  'schema', 'kind', 'jobID', 'routeID', 'routeDigest', 'policyVersion', 'policyDigest',
  'checkerVersion', 'checkerSourceSHA', 'architecture', 'sourceURL', 'artifact',
];
function validateJob(value) {
  const fields = record(value, JOB_FIELDS);
  require(fields.schema === 2 && fields.kind === 'inspection-job');
  identity(fields);
  require(httpsURL(fields.sourceURL));
  // Explicit construction fixes encoder field order and severs caller aliases.
  return {
    schema: 2, kind: 'inspection-job', jobID: fields.jobID,
    routeID: fields.routeID, routeDigest: fields.routeDigest,
    policyVersion: fields.policyVersion, policyDigest: fields.policyDigest,
    checkerVersion: fields.checkerVersion, checkerSourceSHA: fields.checkerSourceSHA,
    architecture: fields.architecture, sourceURL: fields.sourceURL,
    artifact: artifact(fields.artifact),
  };
}

export function decodeJobV2(inputBytes) {
  try {
    const bytes = copyBytes(inputBytes);
    const job = validateJob(parseStrictJSON(bytes, { maximumBytes: MAX_BYTES, maximumDepth: 16 }));
    return { status: 'valid', job, byteDigest: sha256(bytes), ...flags() };
  } catch { return { status: 'invalid', reason: 'invalid-job', ...flags() }; }
}
export function encodeJobV2(inputRecord) {
  try {
    // Only fresh validated records containing bounded primitive fields reach JSON.
    const job = validateJob(inputRecord);
    const bytes = new TextEncoder().encode(JSON.stringify(job));
    require(bytes.byteLength <= MAX_BYTES);
    return { status: 'encoded', bytes, byteDigest: sha256(bytes), ...flags() };
  } catch { return { status: 'refused', reason: 'invalid-job', ...flags() }; }
}
