// Pure unsigned caller observations. Typed values and matching bytes do not
// authenticate a worker, verify output contents or establish native OS truth.
import { createHash } from 'node:crypto';
import { types } from 'node:util';
import { URL } from 'node:url';
import { isIP } from 'node:net';
import { parseStrictJSON } from './strict-json.mjs';
import { decodeJobV2 } from './job-v2.mjs';

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

const EMPTY_SHA256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const CHECK_IDS = ['codesign-integrity', 'codesign-identity', 'gatekeeper', 'notarisation', 'container-integrity', 'cleanup'];
const REPORT_FIELDS = [
  'schema', 'kind', 'jobID', 'jobDescriptorSHA256', 'routeID', 'routeDigest',
  'policyVersion', 'policyDigest', 'checkerVersion', 'checkerSourceSHA', 'architecture',
  'artifact', 'finalSourceURL', 'osVersion', 'osBuild', 'startedAt', 'finishedAt', 'observations',
];
function output(value) {
  const fields = record(value, ['sha256', 'length']);
  require(digest(fields.sha256) && integer(fields.length, 0, 1048576));
  require(fields.length !== 0 || fields.sha256 === EMPTY_SHA256);
  return { sha256: fields.sha256, length: fields.length };
}
function observation(value, expectedCheckID) {
  const fields = record(value, ['checkID', 'outcome', 'exitCode', 'signal', 'stdout', 'stderr']);
  require(fields.checkID === expectedCheckID);
  require(fields.outcome === 'completed' || fields.outcome === 'unavailable');
  require(fields.exitCode === null || integer(fields.exitCode, 0, 255));
  require(fields.signal === null || integer(fields.signal, 1, 64));
  const stdout = output(fields.stdout);
  const stderr = output(fields.stderr);
  if (fields.outcome === 'completed') {
    require((fields.exitCode === null) !== (fields.signal === null));
  } else {
    require(fields.exitCode === null && fields.signal === null && stdout.length === 0 && stderr.length === 0);
  }
  return {
    checkID: fields.checkID, outcome: fields.outcome,
    exitCode: fields.exitCode, signal: fields.signal, stdout, stderr,
  };
}
function observations(value) {
  require(!types.isProxy(value) && Array.isArray(value) && Object.getPrototypeOf(value) === Array.prototype);
  // Inspect length before keys or traversal, including huge sparse arrays.
  const length = Object.getOwnPropertyDescriptor(value, 'length');
  require(length !== undefined && Object.hasOwn(length, 'value') && length.value === 6);
  require(Reflect.ownKeys(value).length === 7);
  const copy = [];
  for (let i = 0; i < 6; i++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(i));
    require(descriptor !== undefined && descriptor.enumerable && Object.hasOwn(descriptor, 'value'));
    copy.push(observation(descriptor.value, CHECK_IDS[i]));
  }
  return copy;
}
function validateEvidence(value) {
  const fields = record(value, REPORT_FIELDS);
  require(fields.schema === 2 && fields.kind === 'inspection-observations');
  identity(fields);
  require(digest(fields.jobDescriptorSHA256) && httpsURL(fields.finalSourceURL)
    && identifier(fields.osVersion) && identifier(fields.osBuild));
  require(integer(fields.startedAt) && integer(fields.finishedAt)
    && fields.finishedAt >= fields.startedAt && fields.finishedAt - fields.startedAt <= 86400);
  return {
    schema: 2, kind: 'inspection-observations', jobID: fields.jobID,
    jobDescriptorSHA256: fields.jobDescriptorSHA256,
    routeID: fields.routeID, routeDigest: fields.routeDigest,
    policyVersion: fields.policyVersion, policyDigest: fields.policyDigest,
    checkerVersion: fields.checkerVersion, checkerSourceSHA: fields.checkerSourceSHA,
    architecture: fields.architecture, artifact: artifact(fields.artifact),
    finalSourceURL: fields.finalSourceURL, osVersion: fields.osVersion, osBuild: fields.osBuild,
    startedAt: fields.startedAt, finishedAt: fields.finishedAt,
    observations: observations(fields.observations),
  };
}

export function decodeEvidenceV2(inputBytes) {
  try {
    const bytes = copyBytes(inputBytes);
    const report = validateEvidence(parseStrictJSON(bytes, { maximumBytes: MAX_BYTES, maximumDepth: 16 }));
    return { status: 'valid', report, byteDigest: sha256(bytes), ...flags() };
  } catch { return { status: 'invalid', reason: 'invalid-evidence', ...flags() }; }
}
export function encodeEvidenceV2(inputRecord) {
  try {
    const report = validateEvidence(inputRecord);
    const bytes = new TextEncoder().encode(JSON.stringify(report));
    require(bytes.byteLength <= MAX_BYTES);
    return { status: 'encoded', bytes, byteDigest: sha256(bytes), ...flags() };
  } catch { return { status: 'refused', reason: 'invalid-evidence', ...flags() }; }
}
export function compareEvidenceBinding(jobBytes, reportBytes) {
  try {
    const decodedJob = decodeJobV2(jobBytes);
    const decodedReport = decodeEvidenceV2(reportBytes);
    require(decodedJob.status === 'valid' && decodedReport.status === 'valid');
    const job = decodedJob.job;
    const report = decodedReport.report;
    require(decodedJob.byteDigest === report.jobDescriptorSHA256);
    for (const field of ['jobID', 'routeID', 'routeDigest', 'policyVersion', 'policyDigest', 'checkerVersion', 'checkerSourceSHA', 'architecture']) {
      require(job[field] === report[field]);
    }
    require(job.artifact.sha256 === report.artifact.sha256 && job.artifact.length === report.artifact.length);
    // URLs, OS claims, times and raw outcomes remain untrusted and unapproved.
    return { status: 'matched', ...flags() };
  } catch { return { status: 'refused', reason: 'binding-mismatch', ...flags() }; }
}
