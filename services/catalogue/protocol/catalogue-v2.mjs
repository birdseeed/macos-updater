// Fixture-only protocol mechanics. No signing, I/O, network or execution authority.
import { createHash, createPublicKey, verify } from 'node:crypto';
import { parseStrictJSON } from './strict-json.mjs';

const MAX_PAYLOAD = 1048576;
const MAX_ENVELOPE = 2097152;
const DOMAIN = 'im.patched.catalogue.v2';
const ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const DIGEST = /^[a-f0-9]{64}$/;
const INPUT_FIELDS = ['envelopeBytes', 'trust', 'context', 'previous', 'bootstrap'];
const PAYLOAD_FIELDS = ['schema', 'domain', 'catalogueID', 'keyID', 'sequence', 'issuedAt', 'expiresAt', 'minimumClientProtocol', 'minimumClientBuild', 'policyDigest', 'entries', 'withdrawals'];
const ENVELOPE_FIELDS = ['schema', 'algorithm', 'keyID', 'payload', 'signature'];
const TRUST_FIELDS = ['catalogueID', 'keyID', 'publicKeyBase64', 'firstSequence', 'lastSequence', 'retired'];
const CHECKPOINT_FIELDS = ['catalogueID', 'sequence', 'payloadSHA256'];
const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const typedGet = Object.fromEntries(['byteLength', 'byteOffset', 'buffer'].map(
  name => [name, Object.getOwnPropertyDescriptor(typedArrayPrototype, name).get],
));

class Refusal extends Error {
  constructor(reason) { super(reason); this.reason = reason; }
}
function require(condition, reason) {
  if (!condition) throw new Refusal(reason);
}
function result(status, reason = null, catalogue = null, payloadSHA256 = null) {
  return {
    status, reason, scope: 'fixture-only', installationAuthorized: false,
    publicationAuthority: false, freshOSValidation: false, payloadSHA256,
    sequence: catalogue === null ? null : catalogue.sequence, catalogue,
    checkpoint: catalogue === null ? null : {
      catalogueID: catalogue.catalogueID, sequence: catalogue.sequence, payloadSHA256,
    },
  };
}

// Read descriptors before values. No getters, toJSON, symbols, hidden fields or
// custom prototypes are accepted as caller-provided protocol records.
function record(value, fields, reason) {
  require(value !== null && typeof value === 'object' && !Array.isArray(value), reason);
  const prototype = Object.getPrototypeOf(value);
  require(prototype === Object.prototype || prototype === null, reason);
  const keys = Reflect.ownKeys(value);
  require(keys.length === fields.length, reason);
  for (const key of keys) {
    require(typeof key === 'string' && fields.includes(key), reason);
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    require(descriptor !== undefined && descriptor.enumerable && Object.hasOwn(descriptor, 'value'), reason);
  }
  return value;
}
function array(value, maximum, reason, minimum = 0) {
  require(Array.isArray(value) && Object.getPrototypeOf(value) === Array.prototype, reason);
  const length = Object.getOwnPropertyDescriptor(value, 'length').value;
  require(length >= minimum && length <= maximum, reason);
  const keys = Reflect.ownKeys(value);
  require(keys.length === length + 1, reason);
  for (let index = 0; index < length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
    require(descriptor !== undefined && descriptor.enumerable && Object.hasOwn(descriptor, 'value'), reason);
  }
  return value;
}
const integer = (value, minimum = 0, maximum = Number.MAX_SAFE_INTEGER) =>
  Number.isSafeInteger(value) && !Object.is(value, -0) && value >= minimum && value <= maximum;
const matches = (value, expression, maxLength) =>
  typeof value === 'string' && value.length <= maxLength && expression.test(value);
const id = value => matches(value, ID, 64);
const digest = value => matches(value, DIGEST, 64);

function versionParts(value) {
  if (typeof value !== 'string' || value.length > 87
      || !/^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,7}$/.test(value)) return null;
  const parts = value.split('.').map(Number);
  return parts.every(part => Number.isSafeInteger(part) && part <= 4294967295) ? parts : null;
}
function orderVersions(left, right) {
  for (let index = 0; index < Math.max(left.length, right.length); index++) {
    const a = left[index] ?? 0;
    const b = right[index] ?? 0;
    if (a < b) return -1;
    if (a > b) return 1;
  }
  return 0;
}
export function compareVersions(left, right) {
  const a = versionParts(left);
  const b = versionParts(right);
  return a === null || b === null
    ? { status: 'refused', reason: 'invalid-version' }
    : { status: 'compared', order: orderVersions(a, b) };
}

function hostname(value) {
  if (typeof value !== 'string' || value.length < 1 || value.length > 253) return false;
  const labels = value.split('.');
  if (!labels.every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) return false;
  // WHATWG numeric-host parsing also recognises shortened/octal/hex IPv4 forms.
  // Require exact hostname preservation, then exclude the resulting IP form.
  try {
    const parsed = new URL(`https://${value}/`);
    return parsed.hostname === value && !/^[0-9]+(?:\.[0-9]+)*$/.test(value);
  } catch { return false; }
}
function sourceURL(value) {
  if (typeof value !== 'string' || !String.prototype.isWellFormed.call(value) || value.length > 2048
      || Buffer.byteLength(value, 'utf8') > 2048
      || !value.startsWith('https://') || /[\s\u0000-\u0020\u007f\\#]/u.test(value)) return false;
  const authority = value.slice(8).split(/[/?]/, 1)[0];
  if (authority.includes('@')) return false;
  const colon = authority.indexOf(':');
  const host = colon === -1 ? authority : authority.slice(0, colon);
  if (!hostname(host)) return false;
  if (colon !== -1) {
    const port = authority.slice(colon + 1);
    if (!/^[1-9][0-9]{0,4}$/.test(port) || Number(port) > 65535) return false;
  }
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' && parsed.hostname === host
      && parsed.username === '' && parsed.password === '' && parsed.hash === '';
  } catch { return false; }
}
function sortedStrings(values, maximum, validate, minimum = 0) {
  array(values, maximum, 'invalid-payload', minimum);
  let previous = null;
  for (const value of values) {
    require(validate(value) && (previous === null || previous < value), 'invalid-payload');
    previous = value;
  }
}

function validateEntry(entry, payload) {
  const reason = 'invalid-payload';
  record(entry, ['identity', 'release', 'compatibility', 'source', 'artifact', 'evidence', 'installer'], reason);
  const identity = record(entry.identity, ['productID', 'releaseID', 'bundleID', 'teamID', 'edition', 'generation', 'channel'], reason);
  for (const field of ['productID', 'releaseID', 'edition', 'generation']) require(id(identity[field]), reason);
  require(matches(identity.bundleID, /^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/, 255), reason);
  require(matches(identity.teamID, /^[A-Z0-9]{10}$/, 10) && identity.channel === 'stable', reason);
  const release = record(entry.release, ['version', 'comparator'], reason);
  require(versionParts(release.version) !== null && release.comparator === 'numeric-dotted-u32-v1', reason);
  const compatibility = record(entry.compatibility, ['platform', 'minimumOS', 'maximumOS', 'architectures'], reason);
  require(compatibility.platform === 'macOS', reason);
  const minimum = versionParts(compatibility.minimumOS);
  const maximum = compatibility.maximumOS === null ? null : versionParts(compatibility.maximumOS);
  require(minimum !== null && (compatibility.maximumOS === null
    || (maximum !== null && orderVersions(minimum, maximum) <= 0)), reason);
  sortedStrings(compatibility.architectures, 2, value => value === 'arm64' || value === 'x86_64', 1);
  const source = record(entry.source, ['routeID', 'routeVersion', 'url', 'redirectHosts', 'observedAt'], reason);
  require(id(source.routeID) && id(source.routeVersion) && sourceURL(source.url) && integer(source.observedAt), reason);
  sortedStrings(source.redirectHosts, 16, hostname);
  const artifact = record(entry.artifact, ['sha256', 'byteLength'], reason);
  require(digest(artifact.sha256) && integer(artifact.byteLength, 1, 8589934592), reason);
  const evidence = record(entry.evidence, ['sha256', 'byteLength', 'policyVersion', 'checkerVersion', 'environmentVersion', 'verifiedAt', 'validUntil'], reason);
  require(digest(evidence.sha256) && integer(evidence.byteLength, 1, 4194304), reason);
  for (const field of ['policyVersion', 'checkerVersion', 'environmentVersion']) require(id(evidence[field]), reason);
  require(integer(evidence.verifiedAt) && integer(evidence.validUntil), reason);
  const installer = record(entry.installer, ['method', 'version', 'interaction', 'restart', 'coordination'], reason);
  require(['dmg-app', 'pkg', 'zip-app'].includes(installer.method) && id(installer.version)
    && ['ask', 'defer'].includes(installer.interaction) && ['none', 'ask'].includes(installer.restart)
    && installer.coordination === 'exclusive-app', reason);
  require(source.observedAt <= payload.issuedAt && payload.issuedAt - source.observedAt <= 86400
    && evidence.verifiedAt <= payload.issuedAt && evidence.validUntil > payload.issuedAt
    && evidence.validUntil - evidence.verifiedAt <= 259200
    && payload.expiresAt <= evidence.validUntil, 'invalid-time');
}
function validatePayload(payload) {
  const reason = 'invalid-payload';
  record(payload, PAYLOAD_FIELDS, reason);
  require(payload.schema === 'fixture-catalogue-v2' && payload.domain === DOMAIN, reason);
  require(id(payload.catalogueID) && id(payload.keyID) && integer(payload.sequence, 1), reason);
  require(integer(payload.issuedAt) && integer(payload.expiresAt)
    && integer(payload.minimumClientProtocol, 1) && integer(payload.minimumClientBuild, 1)
    && digest(payload.policyDigest), reason);
  require(payload.minimumClientProtocol === 2, 'unsupported-client');
  require(payload.expiresAt > payload.issuedAt && payload.expiresAt - payload.issuedAt <= 172800, 'invalid-time');
  array(payload.entries, 1000, reason);
  array(payload.withdrawals, 1000, reason);
  const releases = new Set();
  let previous = null;
  for (const entry of payload.entries) {
    validateEntry(entry, payload);
    const release = entry.identity.releaseID;
    require(previous === null || previous < release, reason);
    previous = release;
    releases.add(release);
  }
  previous = null;
  for (const withdrawal of payload.withdrawals) {
    record(withdrawal, ['productID', 'releaseID', 'artifactSHA256', 'reason', 'effectiveAt'], reason);
    require(id(withdrawal.productID) && id(withdrawal.releaseID) && id(withdrawal.reason)
      && digest(withdrawal.artifactSHA256) && integer(withdrawal.effectiveAt), reason);
    require(withdrawal.effectiveAt <= payload.issuedAt, 'invalid-time');
    require((previous === null || previous < withdrawal.releaseID) && !releases.has(withdrawal.releaseID), reason);
    previous = withdrawal.releaseID;
  }
  return payload;
}

function base64(value, maximumBytes, exactBytes, reason) {
  require(typeof value === 'string' && value.length > 0
    && value.length <= Math.ceil(maximumBytes / 3) * 4
    && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value), reason);
  const decoded = Buffer.from(value, 'base64');
  require(decoded.length <= maximumBytes && (exactBytes === null || decoded.length === exactBytes)
    && decoded.toString('base64') === value, reason);
  return decoded;
}
function envelopeCopy(bytes) {
  require(bytes instanceof Uint8Array, 'invalid-input');
  const length = typedGet.byteLength.call(bytes);
  require(length <= MAX_ENVELOPE, 'invalid-envelope');
  const buffer = typedGet.buffer.call(bytes);
  const offset = typedGet.byteOffset.call(bytes);
  // Intrinsic typed-array operations avoid caller getters/iterators. Copy before
  // parsing so every subsequent check binds one immutable local byte snapshot.
  const copy = new Uint8Array(length);
  Uint8Array.prototype.set.call(copy, new Uint8Array(buffer, offset, length));
  return copy;
}
function parse(bytes, maximumBytes, reason) {
  try { return parseStrictJSON(bytes, { maximumBytes, maximumDepth: 16 }); }
  catch { throw new Refusal(reason); }
}
function validateTrust(trust) {
  record(trust, TRUST_FIELDS, 'invalid-trust');
  require(id(trust.catalogueID) && id(trust.keyID)
    && integer(trust.firstSequence, 1) && integer(trust.lastSequence, 1)
    && trust.lastSequence >= trust.firstSequence && typeof trust.retired === 'boolean', 'invalid-trust');
  return base64(trust.publicKeyBase64, 32, 32, 'invalid-trust');
}
function validateContext(context) {
  record(context, ['now', 'clientProtocol', 'clientBuild'], 'invalid-context');
  require(integer(context.now) && integer(context.clientProtocol, 1)
    && integer(context.clientBuild, 1), 'invalid-context');
  require(context.clientProtocol === 2, 'unsupported-client');
}
function validateHistory(previous, bootstrap, catalogueID) {
  if (previous === null) {
    require(bootstrap, 'bootstrap-required');
    return;
  }
  require(!bootstrap, 'bootstrap-conflict');
  record(previous, CHECKPOINT_FIELDS, 'invalid-history');
  require(id(previous.catalogueID) && previous.catalogueID === catalogueID
    && integer(previous.sequence, 1) && digest(previous.payloadSHA256), 'invalid-history');
}

export function verifyCatalogue(input) {
  try {
    record(input, INPUT_FIELDS, 'invalid-input');
    require(typeof input.bootstrap === 'boolean', 'invalid-input');
    const envelopeBytes = envelopeCopy(input.envelopeBytes);
    const envelope = record(parse(envelopeBytes, MAX_ENVELOPE, 'invalid-envelope'), ENVELOPE_FIELDS, 'invalid-envelope');
    require(envelope.schema === 'fixture-catalogue-envelope-v2' && envelope.algorithm === 'Ed25519'
      && id(envelope.keyID), 'invalid-envelope');
    const payloadBytes = base64(envelope.payload, MAX_PAYLOAD, null, 'invalid-envelope');
    const signature = base64(envelope.signature, 64, 64, 'invalid-envelope');
    const publicKeyBytes = validateTrust(input.trust);
    validateContext(input.context);
    const payload = validatePayload(parse(payloadBytes, MAX_PAYLOAD, 'invalid-payload'));
    const trust = input.trust;
    require(payload.catalogueID === trust.catalogueID && payload.keyID === trust.keyID
      && envelope.keyID === payload.keyID, 'untrusted-key');
    require(!trust.retired, 'retired-key');
    require(payload.sequence >= trust.firstSequence && payload.sequence <= trust.lastSequence, 'sequence-out-of-range');
    require(input.context.clientBuild >= payload.minimumClientBuild, 'unsupported-client');
    require(payload.issuedAt - input.context.now <= 300 && payload.expiresAt > input.context.now, 'invalid-time');
    validateHistory(input.previous, input.bootstrap, payload.catalogueID);
    const message = Buffer.concat([Buffer.from(`${DOMAIN}\0`, 'utf8'), payloadBytes]);
    let validSignature = false;
    try {
      const publicKey = createPublicKey({
        key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), publicKeyBytes]),
        format: 'der', type: 'spki',
      });
      validSignature = verify(null, message, publicKey, signature);
    } catch { /* Unsupported/malformed public material never grants authority. */ }
    require(validSignature, 'invalid-signature');
    const payloadSHA256 = createHash('sha256').update(payloadBytes).digest('hex');
    let status = 'verified';
    if (input.previous !== null) {
      require(payload.sequence >= input.previous.sequence, 'rollback');
      if (payload.sequence === input.previous.sequence) {
        require(payloadSHA256 === input.previous.payloadSHA256, 'equivocation');
        status = 'duplicate';
      }
    }
    // The parser created this complete payload graph from copied bytes. Neither
    // the result nor its checkpoint aliases any caller-owned mutable object.
    return result(status, null, payload, payloadSHA256);
  } catch (error) {
    return result('refused', error instanceof Refusal ? error.reason : 'invalid-input');
  }
}

function sortedCopy(value) {
  if (Array.isArray(value)) return value.map(sortedCopy);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, sortedCopy(value[key])]));
  }
  return value;
}
export function encodePayload(payload) {
  try {
    // Validate bounded closed records before copying or JSON.stringify, so no
    // accessor/toJSON hook runs and no unbounded caller graph is traversed.
    validatePayload(payload);
    const bytes = Buffer.from(JSON.stringify(sortedCopy(payload)), 'utf8');
    require(bytes.length <= MAX_PAYLOAD, 'invalid-payload');
    return bytes;
  } catch { throw new TypeError('Invalid fixture catalogue payload'); }
}
