import test from 'node:test';
import assert from 'node:assert/strict';
import { planAutoPkgFirefoxComparison } from '../src/autopkg-transport-plan.mjs';

// Independent literal oracle from retained URLDownloader.py 200-232 and
// URLGetter.py 60-67. The pinned archive URL requires a future reviewed override;
// it is not MozillaURLProvider's stock default. No upstream code is imported.
const ROOT = '/Users/runner/patched-pat2693-comparison/20261024-A1';
const URL = 'https://archive.mozilla.org/pub/firefox/releases/157.0.1/mac/en-US/Firefox%20157.0.1.dmg';
const SHA = '40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982';
const INPUT = Object.freeze([
  ROOT + '/curl-wrapper', '--silent', '--show-error', '--no-buffer',
  '--dump-header', '-', '--speed-time', '30', '--location', '--url', URL,
  '--fail', '--output', ROOT + '/download.tmp',
]);
// Independent S2 policy oracle: no options are inherited from INPUT.
const CURL = Object.freeze([
  '/usr/bin/curl', '-q', '--no-location', '--proto', '=https', '--proto-redir',
  '=https', '--ipv4', '--resolve', 'archive.mozilla.org:443:151.101.3.19',
  '--noproxy', '*', '--proxy', '', '--connect-timeout', '30', '--max-time', '180',
  '--max-filesize', '161550118', '--header', 'Accept-Encoding: identity',
  '--silent', '--show-error', '--output', '/dev/fd/3', '--dump-header', '/dev/fd/4',
  '--write-out', '%{json}\n', '--url', URL,
]);
const FLAGS = Object.freeze({
  executionAllowed: false, transportObserved: false,
  autoPkgParityProven: false, installationAllowed: false,
});
const REFUSAL = Object.freeze({status: 'refused', reason: 'unsupported-invocation', ...FLAGS});
const BINDINGS = Object.freeze({
  autoPkgRevision: 'c36e58f8d3d8ddb70b6c2d848d2ceca7f767ce5c',
  recipesRevision: '0f7b61ab061c77710be4140c404910a11f89fc7b',
  urlDownloaderSha256: '163d5898dfac4e8af128afb85a24eaf062b12c4563c88c2201e7ef4bbb758349',
  urlGetterSha256: 'a640da18d0d7458239fc6e2347e5898f7cc704d2b4e924bd98e662c25466f2b1',
  autoPkgInitSha256: 'd42b6cb929a0d69be85275348197c75c7e68cc340e46275c28720cf1858f1fcc',
  firefoxRecipeSha256: '6d17ddeb226c88af7b4bdef7f981634f2da18403e0ebb86afeb5cfbdf4dc5237',
  mozillaProviderSha256: 'c4ce035b1a629c4925a80003899fcf39480e5224b3015613440f07ab96211f17',
});
const PREFLIGHT = Object.freeze([
  'current-guest-uuid-uid-os-architecture', 'runtime-origins-and-hashes',
  'six-cfprefs-actual-values-and-precedence', 'recipe-override-parent-trust',
  'curl-physical-hash-config-environment', 'fd-path-identities-private-ownership',
  'free-space-and-storage-caps', 'controller-ownership', 'budget-availability',
  'serial-runtime-idle', 'no-retry', 'new-vendor-allowance', 'independent-review',
  'reviewed-wrapper-and-autopkg-binding', 'cleanup-and-native-validation',
  'current-route-revalidation-and-policy-regeneration',
]);
const POSTCONDITIONS = Object.freeze({
  curlExit: 0, httpStatus: 200, redirects: 0, tlsVerify: 0, effectiveURL: URL,
  remoteIP: '151.101.3.19', remotePort: 443, length: 161550118, sha256: SHA,
  contentEncodingAbsentOrIdentity: true, oneHeaderBlock: true, cleanupVerified: true,
});
function planned() {
  const result = planAutoPkgFirefoxComparison([...INPUT]);
  assert.equal(result.status, 'planned', 'genuine cold URLDownloader shape must produce a data plan');
  return result;
}
function refuse(input) {
  const result = planAutoPkgFirefoxComparison(input);
  assert.equal(Object.getPrototypeOf(result), Object.prototype);
  assert.deepEqual(result, REFUSAL, 'exact refusal must not echo or retain supplied data');
  return result;
}

test('positive: cold stock downloader shape yields only a declared plan', () => {
  const p = planned();
  assert.equal(Object.getPrototypeOf(p), Object.prototype);
  assert.equal(p.declarationOnly, true);
});
test('positive: exact S2 curl controls, order, pins and capture channels', () => {
  assert.deepEqual(planned().argv, CURL);
});
test('positive: exact isolated curl environment including future empty HOME', () => {
  assert.deepEqual(planned().environment, {
    PATH: '/usr/bin:/bin:/usr/sbin:/sbin', LANG: 'C', LC_ALL: 'C',
    HOME: ROOT + '/curl-home', CURL_HOME: ROOT + '/curl-home',
  });
});
test('positive: declared FD roles preserve AutoPkg temporary output and separate captures', () => {
  assert.deepEqual(planned().descriptorRoles, {
    bodyFd: 3, bodyPath: ROOT + '/download.tmp', headersFd: 4,
    headersPath: ROOT + '/headers.raw', stdoutFd: 5,
    stdoutPath: ROOT + '/curl-metadata.raw', stderrFd: 6,
    stderrPath: ROOT + '/curl-stderr.raw', stdin: '/dev/null', passFds: [3, 4],
  });
});
test('positive: complete S2 acceptance requirements are declarations rather than observations', () => {
  assert.deepEqual(planned().requiredPostconditions, POSTCONDITIONS);
});
test('positive: preflight names missing current identities, authority and wrapper/native gates', () => {
  const actual = planned().requiredPreflight;
  assert.ok(Array.isArray(actual));
  assert.equal(new Set(actual).size, actual.length);
  assert.ok(actual.every(x => typeof x === 'string'));
  for (const id of PREFLIGHT) assert.ok(actual.includes(id), 'missing semantic prerequisite: ' + id);
});
test('positive: all five retained source hashes and both revisions remain bound', () => {
  assert.deepEqual(planned().sourceBindings, BINDINGS);
});
test('positive: outer deadline and sealed no-retry/no-fallback intent', () => {
  const p = planned();
  assert.equal(p.outerWatchdogSeconds, 195);
  assert.equal(p.noRetry, true);
  assert.equal(p.noFallback, true);
});
test('positive: caller authority hints cannot make any authority claim true or alter input', () => {
  const input = [...INPUT];
  input.executionAllowed = true;
  input.installationAllowed = true;
  const before = Object.getOwnPropertyDescriptors(input);
  const p = planAutoPkgFirefoxComparison(input);
  assert.equal(p.status, 'planned');
  for (const [key, expected] of Object.entries(FLAGS)) assert.equal(p[key], expected);
  assert.deepEqual(Object.getOwnPropertyDescriptors(input), before);
});
test('positive: every plan owns independent nested data and accepts frozen untouched input', () => {
  const a = planned(), b = planAutoPkgFirefoxComparison(INPUT);
  assert.equal(b.status, 'planned');
  assert.notEqual(a, b);
  for (const key of ['argv', 'environment', 'descriptorRoles', 'requiredPostconditions', 'requiredPreflight', 'sourceBindings']) {
    assert.notEqual(a[key], b[key], key + ' must not share mutable output');
  }
  assert.notEqual(a.descriptorRoles.passFds, b.descriptorRoles.passFds);
  a.argv[0] = 'tampered'; a.environment.HOME = 'tampered';
  a.descriptorRoles.passFds[0] = 99; a.requiredPostconditions.sha256 = 'tampered';
  a.requiredPreflight.push('tampered'); a.sourceBindings.autoPkgRevision = 'tampered';
  const c = planned();
  assert.deepEqual(c.argv, CURL); assert.deepEqual(c.sourceBindings, BINDINGS);
  assert.deepEqual(c.requiredPostconditions, POSTCONDITIONS);
  assert.deepEqual(c.descriptorRoles.passFds, [3, 4]);
  assert.equal(c.environment.HOME, ROOT + '/curl-home');
  assert.ok(!c.requiredPreflight.includes('tampered'));
});

for (let i = 0; i < 14; i++) {
  test('refusal: independently changed stock token ' + i, () => {
    const input = [...INPUT]; input[i] += '-changed'; refuse(input);
  });
}
const EXTRAS = [
  ['request-header', '--header', 'Authorization: secret-do-not-echo'],
  ['curl-options', '--connect-timeout', '1'],
  ['conditional-cache', '--header', 'If-None-Match: retained-etag'],
  ['proxy', '--proxy', 'http://127.0.0.1:9'], ['insecure', '-k'],
  ['next-transfer', '--next'], ['config', '--config', '/tmp/untrusted-curlrc'],
  ['redirect', '--location'], ['retry', '--retry', '1'],
  ['compression', '--compressed'], ['route', '--resolve', 'archive.mozilla.org:443:127.0.0.1'],
  ['second-output', '--output', '/tmp/escape'],
];
for (const [name, ...extra] of EXTRAS) {
  test('refusal: extra ' + name, () => refuse([...INPUT, ...extra]));
}
const WRONG_URLS = [
  ['version', URL.replace('157.0.1/mac', '157.0/mac')],
  ['host', URL.replace('archive.mozilla.org', 'archive.mozilla.org.evil.test')],
  ['scheme', URL.replace('https:', 'http:')],
  ['userinfo', URL.replace('https://', 'https://user:password@')],
  ['fragment', URL + '#ignored'], ['query', URL + '?mirror=1'],
  ['literal-space', URL.replace('%20', ' ')], ['double-encoding', URL.replace('%20', '%2520')],
  ['stock-provider-default', 'https://download.mozilla.org/?product=firefox-157.0.1-ssl&os=osx&lang=en-US'],
];
for (const [name, url] of WRONG_URLS) {
  test('refusal: alternate URL ' + name, () => {
    const input = [...INPUT]; input[10] = url; refuse(input);
  });
}
const WRONG_TYPES = [
  ['undefined', () => undefined], ['null', () => null], ['string', () => INPUT.join(' ')],
  ['object', () => ({...INPUT, length: 14})], ['number', () => 14],
  ['sparse-array', () => { const a = [...INPUT]; delete a[5]; return a; }],
  ['nonstring-token', () => { const a = [...INPUT]; a[7] = 30; return a; }],
  ['bounded-oversized-array', () => Array(1024).fill('--silent')],
];
for (const [name, make] of WRONG_TYPES) test('refusal: malformed input ' + name, () => refuse(make()));
test('refusal: wrapper outside proposed fixed private root', () => {
  const a = [...INPUT]; a[0] = '/usr/bin/curl'; refuse(a);
});
test('refusal: temporary output outside proposed fixed private root', () => {
  const a = [...INPUT]; a[13] = ROOT + '/../download.tmp'; refuse(a);
});
test('refusal: deterministic plain fresh result has no input echo or shared authority', () => {
  const a = refuse(['secret-token']), b = refuse(['another-token']);
  assert.notEqual(a, b); a.executionAllowed = true;
  refuse(['secret-token']);
});
test('refusal: malformed frozen input remains unchanged', () => {
  const input = Object.freeze([...INPUT, '--retry', '1']);
  refuse(input); assert.deepEqual(input, [...INPUT, '--retry', '1']);
});
