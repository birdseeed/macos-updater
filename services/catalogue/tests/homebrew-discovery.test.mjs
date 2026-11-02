import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { syncBuiltinESMExports } from 'node:module';
import * as childProcess from 'node:child_process';
import * as http from 'node:http';
import * as https from 'node:https';
import * as net from 'node:net';
import { parseHomebrewMetadata } from '../discovery/homebrew/metadata.mjs';
import { deriveHomebrewCandidate } from '../discovery/homebrew/candidates.mjs';
import { HOMEBREW_LIMITS, HOMEBREW_PROJECTION_VERSION } from '../discovery/homebrew/contracts.mjs';

const root = new URL('../../../', import.meta.url);
const fixture = name => JSON.parse(readFileSync(new URL(`Fixtures/HomebrewDiscovery/${name}`, root), 'utf8'));
const copy = value => structuredClone(value);
const cask = () => fixture('simple-cask.json');
const context = () => fixture('context.json');
const bytes = text => new TextEncoder().encode(text);
const encode = object => bytes(JSON.stringify(object));
const sha = value => createHash('sha256').update(value).digest('hex');
const flags = {
  scope: 'synthetic-fixture-only', sourceAuthenticated: false,
  artifactAcquired: false, independentlyVerified: false,
  publicationAllowed: false, installationAllowed: false, ownershipEstablished: false,
};
function noAuthority(result) {
  for (const [key, value] of Object.entries(flags)) assert.equal(result[key], value, key);
}
function held(result) {
  assert.equal(result.status, 'held');
  assert.equal(typeof result.reason, 'string');
  assert.ok(result.reason.length > 0);
  for (const key of ['candidate', 'job', 'catalogue', 'installation']) assert.equal(result[key], undefined);
  noAuthority(result);
}
function parseInput(metadata = cask()) { return { bytes: encode(metadata), receipt: context().receipt }; }
// Independently specified expected projection, never obtained from production API.
function expectedParsed(metadata = cask(), receipt = context().receipt, raw = encode(metadata)) {
  return {
    status: 'parsed', projectionVersion: 'homebrew-single-cask-fixture-v1', ...flags,
    source: {
      rawBytes: Array.from(raw), sha256: sha(raw), byteLength: raw.length,
      locator: receipt.locator, retrievalStartedAt: receipt.startedAt,
      retrievalFinishedAt: receipt.finishedAt, etag: receipt.etag,
      lastModified: receipt.lastModified, generationTime: receipt.generationTime,
      tap: metadata.tap, tapGitHead: metadata.tap_git_head,
      rubySourcePath: metadata.ruby_source_path,
      rubySourceChecksum: metadata.ruby_source_checksum.sha256,
    },
    record: copy(metadata),
  };
}
function input(metadata = cask()) {
  const i = context(); delete i.receipt;
  return { parsed: expectedParsed(metadata), ...i };
}
function expectedCandidate(i = input()) {
  const m = i.parsed.record;
  const selected = i.variant.key === 'base' ? m : { ...m, ...m.variations[i.variant.key] };
  const checksum = selected.sha256 === 'no_check' ? { state: 'no-check', value: null }
    : selected.sha256 == null ? { state: 'absent', value: null }
      : { state: 'digest', value: selected.sha256 };
  return {
    status: 'discovery', projectionVersion: 'homebrew-single-cask-fixture-v1', ...flags,
    source: copy(i.parsed.source), identity: copy(i.policy.identity),
    release: { version: m.version, comparator: i.policy.comparator },
    selection: copy(i.variant), checksum,
    artifact: { url: selected.url, sha256: null, byteLength: null },
    continuity: { firstObservedAt: i.parsed.source.retrievalStartedAt, previousSourceSHA256: null },
    policyBinding: { policySha256: i.policy.policySha256, routeSha256: i.policy.routeSha256 },
    requiresIndependentArtifactValidation: true, artifactConsistency: 'unchecked',
  };
}

test('contract limits are the armed bounded projection', () => {
  assert.equal(HOMEBREW_PROJECTION_VERSION, 'homebrew-single-cask-fixture-v1');
  assert.deepEqual(HOMEBREW_LIMITS, {
    maximumBytes: 262144, maximumDepth: 16, maximumCasks: 1, maximumRecords: 64,
    maximumURLBytes: 2048, maximumIdentityBytes: 128, maximumObservationAge: 86400,
  });
});

test('positive parser retains exact bytes, source claims and honestly unknown generation', () => {
  const i = parseInput();
  assert.deepEqual(parseHomebrewMetadata(i), expectedParsed(cask(), i.receipt, i.bytes));
});
test('positive parser hashes formatting bytes rather than canonical JSON', () => {
  const i = parseInput(); i.bytes = bytes(` \n${JSON.stringify(cask(), null, 2)}\n`);
  const r = parseHomebrewMetadata(i);
  assert.deepEqual(r, expectedParsed(cask(), i.receipt, i.bytes));
  assert.notEqual(r.source.sha256, sha(encode(cask())));
});
test('declared generation is preserved as a claim, never validator-derived', () => {
  const i = parseInput(); i.receipt.generationTime = i.receipt.startedAt - 100;
  const r = parseHomebrewMetadata(i); assert.equal(r.status, 'parsed');
  assert.equal(r.source.generationTime, i.receipt.generationTime); noAuthority(r);
});
test('code-looking descriptions remain exact inert source data', () => {
  const m = cask(); m.caveats = 'system("curl evil"); `brew install`; ${process.exit(7)}';
  const r = parseHomebrewMetadata(parseInput(m));
  assert.equal(r.status, 'parsed'); assert.equal(r.record.caveats, m.caveats); noAuthority(r);
});

const invalidJSON = {
  'duplicate token': '{"token":"one","token":"two"}',
  'nested duplicate': '{"x":{"a":1,"a":2}}',
  'escaped duplicate': '{"token":1,"tok\\u0065n":2}',
  'fraction': '{"x":1.1}', 'exponent': '{"x":1e2}', 'negative': '{"x":-1}',
  'leading zero': '{"x":01}', 'unsafe integer': '{"x":9007199254740993}',
  'lone surrogate': '{"x":"\\ud800"}', 'trailing JSON': '{}{}',
  'BOM': '\ufeff{}', 'trailing comma': '{"x":1,}', 'NaN': '{"x":NaN}',
};
for (const [label, text] of Object.entries(invalidJSON)) test(`parse refuses ${label}`, () => {
  const i = parseInput(); i.bytes = bytes(text); held(parseHomebrewMetadata(i));
});
for (const [label, raw] of [
  ['invalid UTF8', new Uint8Array([0x7b, 0xc0, 0xaf, 0x7d])],
  ['oversized response', bytes(' '.repeat(262145))],
  ['depth17', bytes('['.repeat(17) + '0' + ']'.repeat(17))],
]) test(`parse refuses ${label} before projection`, () => {
  held(parseHomebrewMetadata({ ...parseInput(), bytes: raw }));
});

const badMetadata = [
  ['bulk array', () => [cask()]], ['bulk wrapper', () => ({ casks: [cask()] })],
  ['foreign tap', m => { m.tap = 'attacker/cask'; }],
  ['wrong full token', m => { m.full_token = 'other'; }],
  ['token overflow UTF8', m => { m.token = 'é'.repeat(65); m.full_token = m.token; }],
  ['URL overflow UTF8', m => { m.url = 'https://downloads.example.test/' + 'é'.repeat(1024); }],
  ['HTTP artifact route', m => { m.url = 'http://downloads.example.test/editor.dmg'; }],
  ['userinfo artifact route', m => { m.url = 'https://user@downloads.example.test/editor.dmg'; }],
  ['fragment artifact route', m => { m.url += '#fragment'; }],
  ['query artifact route requiring shared-contract mapping', m => { m.url += '?download=1'; }],
  ['nondefault artifact port', m => { m.url = 'https://downloads.example.test:444/editor.dmg'; }],
  ['missing head', m => { delete m.tap_git_head; }],
  ['bad head', m => { m.tap_git_head = 'HEAD'; }],
  ['wrong source path', m => { m.ruby_source_path = 'Casks/../evil.rb'; }],
  ['missing source checksum', m => { delete m.ruby_source_checksum; }],
  ['malformed source checksum', m => { m.ruby_source_checksum.sha256 = 'not-a-digest'; }],
  ['malformed artifact digest', m => { m.sha256 = 'A'.repeat(64); }],
  ['url specs', m => { m.url_specs = { user_agent: ':fake' }; }],
  ['unknown install semantics', m => { m.postflight = 'system("bad")'; }],
  ['language conditional', m => { m.languages = ['en']; }],
  ['dependency', m => { m.depends_on = { formula: ['tool'] }; }],
  ['macOS recipe dependency', m => { m.depends_on = { macos: { '>=': ['13'] } }; }],
  ['package', m => { m.artifacts = [{ pkg: ['installer.pkg'] }]; }],
  ['hook beside app', m => { m.artifacts.push({ preflight: ['system("bad")'] }); }],
  ['suite', m => { m.artifacts.push({ app: ['Other.app'] }); }],
  ['move options', m => { m.artifacts[0].app.push({ target: '/Applications/Other.app' }); }],
  ['traversal app', m => { m.artifacts[0].app[0] = '../Other.app'; }],
  ['missing app inventory', m => { delete m.artifacts; }],
  ['record bound', m => { m.artifacts = Array.from({ length: 65 }, () => ({ app: ['Fixture Editor.app'] })); }],
  ['disabled', m => { m.disabled = true; }], ['deprecated', m => { m.deprecated = true; }],
  ['unknown variant key', m => { m.variations = { mysterious: { url: m.url } }; }],
  ['variant executable override', m => { m.variations = { arm64_sequoia: { artifacts: [{ pkg: ['a.pkg'] }] } }; }],
];
for (const [label, mutate] of badMetadata) test(`parse holds ${label}`, () => {
  const m = cask(); const replacement = mutate(m);
  held(parseHomebrewMetadata(parseInput(replacement ?? m)));
});
for (const [key, value] of [
  ['locator', 'https://attacker.example.test/fixture-editor.json'],
  ['locator', 'https://formulae.brew.sh/api/cask/other.json'],
  ['locator', 'https://formulae.brew.sh/api/cask/fixture-editor.json?q=x'],
  ['locator', 'https://formulae.brew.sh:444/api/cask/fixture-editor.json'],
  ['locator', 'https://user@formulae.brew.sh/api/cask/fixture-editor.json'],
  ['statusCode', 304], ['startedAt', 1800000002], ['finishedAt', -1],
  ['generationTime', 1800000002], ['etag', { authenticated: true }],
]) test(`parse refuses receipt ${key}=${JSON.stringify(value)}`, () => {
  const i = parseInput(); i.receipt[key] = value; held(parseHomebrewMetadata(i));
});

test('positive candidate selects independently admitted simple route without any authority', () => {
  const i = input(); assert.deepEqual(deriveHomebrewCandidate(i), expectedCandidate(i));
});
test('positive explicit variant selects exact URL/digest and retains base source bytes', () => {
  const m = cask(); m.variations = { x86_64_sequoia: { url: 'https://downloads.example.test/editor-2.0.0-x64.zip', sha256: 'b'.repeat(64) } };
  const i = input(m); i.variant.key = 'x86_64_sequoia'; i.variant.architecture = 'x86_64'; i.policy.architectures = ['x86_64'];
  assert.deepEqual(deriveHomebrewCandidate(i), expectedCandidate(i));
});
for (const state of ['absent', 'null', 'no_check']) test(`positive ${state} checksum permits discovery only`, () => {
  const m = cask(); if (state === 'absent') delete m.sha256; else m.sha256 = state === 'null' ? null : state;
  const i = input(m); const r = deriveHomebrewCandidate(i);
  assert.deepEqual(r, expectedCandidate(i)); noAuthority(r);
  assert.equal(r.requiresIndependentArtifactValidation, true);
});
test('matching injected digest is only claim consistency with artifact bytes/length unknown', () => {
  const i = input(); i.artifactObservation = { sha256: 'a'.repeat(64), byteLength: 123 };
  const expected = expectedCandidate(i); expected.artifactConsistency = 'injected-claim-consistent';
  assert.deepEqual(deriveHomebrewCandidate(i), expected);
});
test('mismatched injected digest holds with an explicit reason and preserves inputs', () => {
  const i = input(); i.artifactObservation = { sha256: 'b'.repeat(64), byteLength: 123 };
  const before = copy(i); const r = deriveHomebrewCandidate(i); held(r);
  assert.equal(r.reason, 'artifact-digest-mismatch'); assert.deepEqual(i, before);
});
test('no_check injected digest never claims independent validation', () => {
  const m = cask(); m.sha256 = 'no_check'; const i = input(m);
  i.artifactObservation = { sha256: 'b'.repeat(64), byteLength: 123 };
  assert.deepEqual(deriveHomebrewCandidate(i), expectedCandidate(i));
});
for (const version of ['2.0.0,500', 'latest', '2.0-beta', '02.0.0', '1e3']) test(`raw version ${version} retained but candidate held`, () => {
  const m = cask(); m.version = version; if (version === 'latest') m.sha256 = 'no_check';
  const p = parseHomebrewMetadata(parseInput(m)); assert.equal(p.status, 'parsed');
  assert.equal(p.record.version, version); held(deriveHomebrewCandidate(input(m)));
});
for (const key of ['productId', 'bundleId', 'developerTeamId', 'channel', 'edition', 'generation']) {
  for (const mode of ['wrong', 'missing']) test(`independent ${key} ${mode} holds`, () => {
    const i = input(); if (mode === 'wrong') i.variant.identity[key] = 'foreign'; else delete i.policy.identity[key];
    held(deriveHomebrewCandidate(i));
  });
}
const badCandidate = [
  ['wrong token', i => { i.policy.token = 'other'; }],
  ['foreign tap', i => { i.policy.tap = 'other/cask'; }],
  ['wrong source endpoint', i => { i.policy.sourceLocator += '?x'; }],
  ['unknown comparator', i => { i.policy.comparator = 'coerce-any-version'; i.variant.comparator = i.policy.comparator; }],
  ['comparator mismatch', i => { i.variant.comparator = 'semver'; }],
  ['architecture mismatch', i => { i.variant.architecture = 'x86_64'; }],
  ['universal without slice evidence', i => { i.variant.architecture = 'universal'; i.policy.architectures = ['universal']; }],
  ['too old OS', i => { i.variant.osVersion = '12.9.9'; }],
  ['too new OS', i => { i.variant.osVersion = '17.0.0'; }],
  ['unknown OS', i => { i.variant.osVersion = 'latest'; }],
  ['missing variant', i => { delete i.variant.key; }],
  ['unresolved variant', i => { i.variant.key = 'arm64_sequoia'; }],
  ['route mismatch', i => { i.policy.allowedArtifactURLs = ['https://other.example.test/editor.dmg']; }],
  ['host widening', i => { i.policy.allowedArtifactURLs = ['https://downloads.example.test/']; }],
  ['unapproved redirects', i => { i.policy.allowedRedirectURLs = ['https://else.example.test/file.dmg']; }],
  ['wrong installation method', i => { i.policy.installer = 'pkg'; }],
  ['wrong app artifact', i => { i.policy.appArtifact = 'Other.app'; }],
  ['missing policy digest', i => { delete i.policy.policySha256; }],
  ['bad route digest', i => { i.policy.routeSha256 = 'invalid'; }],
  ['future receipt', i => { i.clock.now = 1799999999; }],
  ['stale observation', i => { i.clock.now = 1800086402; }],
  ['missing clock', i => { delete i.clock; }],
  ['unknown history', i => { delete i.history; }],
  ['invalid observation length', i => { i.artifactObservation = { sha256: 'a'.repeat(64), byteLength: 0 }; }],
  ['fake native observation', i => { i.artifactObservation = { sha256: 'a'.repeat(64), byteLength: 1, notarised: true }; }],
  ['record mutated after parsing', i => { i.parsed.record.url = 'https://evil.example.test/file.dmg'; }],
  ['raw digest mutated', i => { i.parsed.source.sha256 = 'b'.repeat(64); }],
  ['raw bytes mutated', i => { i.parsed.source.rawBytes[0] ^= 1; }],
  ['source path mutated', i => { i.parsed.source.rubySourcePath = 'Casks/o/other.rb'; }],
  ['tap head mutated', i => { i.parsed.source.tapGitHead = 'f'.repeat(40); }],
  ['source checksum mutated', i => { i.parsed.source.rubySourceChecksum = 'e'.repeat(64); }],
  ['generation manufactured', i => { i.parsed.source.generationTime = i.clock.now + 1; }],
  ['authority smuggled', i => { i.parsed.installationAllowed = true; }],
];
for (const [label, mutate] of badCandidate) test(`candidate holds ${label}`, () => {
  const i = input(); mutate(i); held(deriveHomebrewCandidate(i));
});
test('variants cannot silently fall back to base or mismatch OS family', () => {
  const m = cask(); m.variations = { arm64_sonoma: { url: m.url } };
  const i = input(m); held(deriveHomebrewCandidate(i));
  i.variant.key = 'arm64_sonoma'; held(deriveHomebrewCandidate(i));
});
test('freshness exact boundary is admitted without asserting durable freshness', () => {
  const i = input(); i.clock.now = i.parsed.source.retrievalStartedAt + 86400;
  assert.deepEqual(deriveHomebrewCandidate(i), expectedCandidate(i));
});
test('duplicate observation retains original time and unknown generation', () => {
  const i = input(); i.history.previous = expectedCandidate(i);
  i.parsed.source.retrievalStartedAt += 50; i.parsed.source.retrievalFinishedAt += 50;
  const r = deriveHomebrewCandidate(i); assert.equal(r.status, 'discovery');
  assert.equal(r.continuity.firstObservedAt, 1800000000);
  assert.equal(r.source.generationTime, null);
  assert.equal(r.continuity.previousSourceSHA256, i.history.previous.source.sha256); noAuthority(r);
});
test('refetch cannot rejuvenate stale original observation', () => {
  const i = input(); i.history.previous = expectedCandidate(i);
  i.clock.now = 1800086500; i.parsed.source.retrievalStartedAt = i.clock.now - 1;
  i.parsed.source.retrievalFinishedAt = i.clock.now; held(deriveHomebrewCandidate(i));
});
for (const [label, mutate] of [
  ['descriptive bytes', m => { m.desc += ' changed'; }],
  ['URL', m => { m.url = 'https://downloads.example.test/editor-2.0.0-x64.zip'; }],
  ['checksum', m => { m.sha256 = 'b'.repeat(64); }],
  ['tap revision', m => { m.tap_git_head = '5'.repeat(40); }],
  ['source checksum', m => { m.ruby_source_checksum.sha256 = '6'.repeat(64); }],
]) test(`same release changed ${label} holds and leaves both attempts intact`, () => {
  const m = cask(); mutate(m); const i = input(m); i.history.previous = expectedCandidate();
  const before = copy(i); held(deriveHomebrewCandidate(i)); assert.deepEqual(i, before);
});
for (const key of ['routeSha256', 'policySha256']) test(`same release changed ${key} holds`, () => {
  const i = input(); i.history.previous = expectedCandidate(i); i.policy[key] = 'f'.repeat(64);
  held(deriveHomebrewCandidate(i));
});
test('same release changed selection holds despite equal raw bytes', () => {
  const i = input(); i.history.previous = expectedCandidate(i); i.variant.osVersion = '15.1.0';
  held(deriveHomebrewCandidate(i));
});
test('same bytes cannot fabricate a generation from changed receipt', () => {
  const i = input(); i.history.previous = expectedCandidate(i);
  i.parsed.source.generationTime = 1799999990; held(deriveHomebrewCandidate(i));
});
test('greater release links previous source without granting update authority', () => {
  const m = cask(); m.version = '3.0.0'; const i = input(m); i.history.previous = expectedCandidate();
  const r = deriveHomebrewCandidate(i); assert.equal(r.status, 'discovery');
  assert.equal(r.release.version, '3.0.0');
  assert.equal(r.continuity.previousSourceSHA256, i.history.previous.source.sha256); noAuthority(r);
});
for (const corrupt of [
  p => { p.source.sha256 = 'x'; }, p => { p.identity.bundleId = 'foreign'; },
  p => { p.release.version = '9.0.0'; }, p => { p.continuity.firstObservedAt = 1800000200; },
  p => { p.artifact.sha256 = 'a'.repeat(64); }, p => { p.installationAllowed = true; },
]) test(`previous observation revalidation ${corrupt.toString()}`, () => {
  const i = input(); i.history.previous = expectedCandidate(i); corrupt(i.history.previous);
  held(deriveHomebrewCandidate(i));
});

test('parser makes independent copies and subsequent caller byte mutation is harmless', () => {
  const i = parseInput(); const before = copy(i); const r = parseHomebrewMetadata(i);
  assert.equal(r.status, 'parsed'); assert.deepEqual(i, before);
  const retained = copy(r); i.bytes[0] ^= 1; i.receipt.etag = 'changed';
  assert.deepEqual(r, retained); r.record.name[0] = 'changed'; r.source.rawBytes[0] ^= 1;
  assert.deepEqual(parseHomebrewMetadata(parseInput()), expectedParsed());
});
test('candidate return copies cannot mutate input, history or later results', () => {
  const i = input(); i.history.previous = expectedCandidate(i); const before = copy(i);
  const r = deriveHomebrewCandidate(i); assert.equal(r.status, 'discovery'); assert.deepEqual(i, before);
  r.identity.bundleId = 'changed'; r.source.rawBytes[0] ^= 1; r.selection.identity.edition = 'changed';
  assert.deepEqual(i, before); const again = deriveHomebrewCandidate(input());
  assert.deepEqual(again, expectedCandidate());
});
for (const api of ['parser', 'candidate']) {
  const invoke = api === 'parser' ? parseHomebrewMetadata : deriveHomebrewCandidate;
  const make = api === 'parser' ? parseInput : input;
  test(`${api} refuses accessor without executing getter`, () => {
    const i = make(); const target = api === 'parser' ? i.receipt : i.policy.identity;
    const key = api === 'parser' ? 'etag' : 'bundleId'; let calls = 0;
    Object.defineProperty(target, key, { enumerable: true, get() { calls++; throw Error('getter executed'); } });
    held(invoke(i)); assert.equal(calls, 0);
  });
  test(`${api} refuses Proxy without inspecting attacker traps`, () => {
    let calls = 0; const p = new Proxy(make(), { get() { calls++; throw Error('get'); }, ownKeys() { calls++; throw Error('keys'); }, getPrototypeOf() { calls++; throw Error('proto'); } });
    held(invoke(p)); assert.equal(calls, 0);
  });
  test(`${api} refuses exotic prototype, symbols and hidden values`, () => {
    for (const mutate of [i => Object.setPrototypeOf(i, { trusted: true }), i => { i[Symbol('x')] = 1; }, i => Object.defineProperty(i, 'hidden', { value: 1 })]) {
      const i = make(); mutate(i); held(invoke(i));
    }
  });
  test(`${api} refuses aliased data and cycles`, () => {
    const i = make(); if (api === 'parser') i.receipt.etag = i.receipt; else i.variant.identity = i.policy.identity;
    held(invoke(i));
  });
}
for (const [label, make] of [
  ['subarray', () => new Uint8Array(100).subarray(1)],
  ['shared buffer', () => new Uint8Array(new SharedArrayBuffer(10))],
  ['pooled Buffer', () => Buffer.from('{}')],
  ['typed proxy', () => new Proxy(encode(cask()), {})],
  ['extra property', () => { const b = encode(cask()); b.injected = true; return b; }],
]) test(`parser refuses unsafe byte ownership ${label}`, () => {
  held(parseHomebrewMetadata({ ...parseInput(), bytes: make() }));
});
test('nested Proxy cannot execute descriptor traps', () => {
  let calls = 0; const i = input();
  i.policy.identity = new Proxy(i.policy.identity, { ownKeys() { calls++; throw Error('trap'); } });
  held(deriveHomebrewCandidate(i)); assert.equal(calls, 0);
});
test('byte accessors and top-level accessors are refused before reading', () => {
  for (const targetByte of [true, false]) {
    const i = parseInput(); let calls = 0;
    Object.defineProperty(targetByte ? i.bytes : i, targetByte ? 'byteLength' : 'bytes', {
      enumerable: true, get() { calls++; throw Error('unsafe byte getter'); },
    });
    held(parseHomebrewMetadata(i)); assert.equal(calls, 0);
  }
});
test('input function values are refused rather than called', () => {
  let calls = 0; const i = input(); i.clock.now = () => { calls++; return 1800000100; };
  held(deriveHomebrewCandidate(i)); assert.equal(calls, 0);
});

test('source import closure is limited to pure local Homebrew/strict-json and crypto/util', () => {
  const sourcePaths = ['contracts', 'metadata', 'candidates'].map(n => new URL(`services/catalogue/discovery/homebrew/${n}.mjs`, root));
  for (const path of sourcePaths) {
    const source = readFileSync(path, 'utf8');
    const imports = [...source.matchAll(/\b(?:from\s*|import\s*)['"]([^'"]+)['"]/g)].map(m => m[1]);
    for (const name of imports) assert.ok(['./contracts.mjs', './metadata.mjs', '../../protocol/strict-json.mjs', 'node:crypto', 'node:util'].includes(name), name);
    assert.doesNotMatch(source, /\b(?:require|eval|Function)\s*\(|\bimport\s*\(|\b(?:fetch|XMLHttpRequest|WebSocket|Date\.now)\s*\(|\bprocess\s*[.[]/);
  }
});
test('runtime process/network spies observe zero calls for positive and refusing input', () => {
  const restores = []; let calls = 0;
  function deny() { calls++; throw Error('forbidden process/network operation'); }
  for (const [module, keys] of [[childProcess.default, ['exec', 'execSync', 'spawn', 'spawnSync', 'execFile', 'execFileSync', 'fork']], [http.default, ['request', 'get']], [https.default, ['request', 'get']], [net.default, ['connect', 'createConnection']]]) {
    for (const key of keys) { const original = module[key]; restores.push(() => { module[key] = original; }); module[key] = deny; }
  }
  const originalFetch = globalThis.fetch; globalThis.fetch = deny; syncBuiltinESMExports();
  try {
    parseHomebrewMetadata(parseInput()); deriveHomebrewCandidate(input());
    parseHomebrewMetadata({}); deriveHomebrewCandidate({}); assert.equal(calls, 0);
  } finally {
    globalThis.fetch = originalFetch; for (const restore of restores) restore(); syncBuiltinESMExports();
  }
});
