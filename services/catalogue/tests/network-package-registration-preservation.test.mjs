import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {preservedPackageSHA256} from '../../../scripts/lib/package-registration-preservation.mjs';

// Independent author literals. Never import hashes or registration blocks from candidate code.
const ORIGINAL = '8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699';
const SHELL = '6f69e14efb17c845fc194149d8248500ca6efb49416ebeba9a28030362bff447';
const PREFERENCES = '16c464dab3fa2cc783ef174a68dfaa2969a713c2c2403e484114880e1991b2a2';
const CURRENT = '9efb689b91704ce21ee5aef32fc1e3501994df49b37e874ebdf714bab56525e4';
const NETWORK = '07a0e74dc59364b3132ed91cb9eb2adf3bdee8a0b3a4f4a4ca536552a9732cb0';
const PRODUCT_HEADER = '    products: [\n';
const TARGET_HEADER = '    targets: [\n';
const PRODUCTS = '        .library(name: "PatchedNetworking", targets: ["PatchedNetworking"]),\n' +
  '        .executable(name: "patched-network-checks", targets: ["PatchedNetworkChecks"]),\n';
const TARGETS = '        .target(name: "PatchedNetworking"),\n' +
  '        .executableTarget(name: "PatchedNetworkChecks", dependencies: ["PatchedNetworking"], path: "Tests/PatchedNetworkChecks"),\n';
const original = readFileSync(new URL('../../../Fixtures/Network/package-registration/Package.original.swift', import.meta.url));
const current = readFileSync(new URL('../../../Fixtures/Network/package-registration/Package.current.swift', import.meta.url));
const network = readFileSync(new URL('../../../Fixtures/Network/package-registration/Package.network.swift', import.meta.url));
const shell = readFileSync(new URL('../protocol/fixtures/package-registration/Package.shell.swift', import.meta.url));
const preferences = readFileSync(new URL('../protocol/fixtures/package-registration/Package.preferences.swift', import.meta.url));
const historicalActivity = readFileSync(new URL('../protocol/fixtures/package-registration/Package.activity.swift', import.meta.url));
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const text = network.toString('utf8');
const replace = (source, before, after) => {
  assert.notEqual(before, after, 'mutation must alter its anchor');
  assert.equal(source.split(before).length, 2, 'mutation anchor must occur once');
  return source.replace(before, after);
};
const mutate = (before, after) => Buffer.from(replace(text, before, after));
const strip = source => replace(replace(source, PRODUCT_HEADER + PRODUCTS, PRODUCT_HEADER), TARGET_HEADER + TARGETS, TARGET_HEADER);
const pinned = [['original', original, ORIGINAL], ['shell', shell, SHELL], ['preferences', preferences, PREFERENCES],
  ['current', current, CURRENT], ['network', network, NETWORK]];
for (const [name, fixture, pin] of pinned) {
  test(`independent exact ${name} fixture hash`, () => assert.equal(sha256(fixture), pin));
  test(`accept exact ${name} fixture preserving bytes and return historical hash`, () => {
    const bytes = Buffer.from(fixture);
    const before = Buffer.from(bytes);
    assert.equal(preservedPackageSHA256(bytes), ORIGINAL);
    assert.deepEqual(bytes, before);
    assert.equal(preservedPackageSHA256(bytes), ORIGINAL);
    assert.deepEqual(bytes, before);
  });
}
test('current fixture equals exact historical Activity baseline', () => assert.deepEqual(current, historicalActivity));
test('candidate removes exactly four additions to reconstruct every predecessor byte', () => {
  const reconstructed = Buffer.from(strip(text));
  assert.deepEqual(reconstructed, current);
  assert.equal(sha256(reconstructed), CURRENT);
  assert.equal(preservedPackageSHA256(reconstructed), ORIGINAL);
});
// CHECK-MODIFIED PAT-2660: only two exact dependency-line amendments. All
// historical fixture/hash/mutation controls below remain unchanged.
// CHECK-MODIFIED PAT-2666: the live inverse includes exactly one additional
// PatchedNetworking dependency; no historical accepted fixture changes.
// CHECK-MODIFIED PAT-2667: pin exactly the two first-run dependency amendments:
// PatchedClient adds PatchedUpdatePreferences; PatchedClientChecks adds
// PatchedUpdatePreferences and PatchedScheduling. This is no general whitelist;
// prove the exact native predecessor in both directions before older inverses.
test('live Package equals independently pinned candidate fixture plus exact native composition dependencies', () => {
  const amendments = [
    ['        .target(name: "PatchedClient", dependencies: ["ArtifactInspection"]),\n',
     '        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI", "PatchedNetworking"]),\n'],
    ['        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection"],\n',
     '        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection", "PatchedShell"],\n'],
  ];
  let expected = network.toString('utf8');
  for (const [before, after] of amendments) expected = replace(expected, before, after);
  const nativePredecessor = Buffer.from(expected);
  const nativePredecessorSHA256 = 'a59ebf6cc9c5ec8140a9f5a1ffdf03c917808cfb9c2bfd39b8a2608ebd43bb68';
  assert.equal(sha256(nativePredecessor), nativePredecessorSHA256);
  const firstRunAmendments = [
    ['        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI", "PatchedNetworking"]),\n',
     '        .target(name: "PatchedClient", dependencies: ["ArtifactInspection", "PatchedShell", "PatchedActivity", "PatchedUI", "PatchedNetworking", "PatchedUpdatePreferences"]),\n'],
    ['        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection", "PatchedShell"],\n',
     '        .executableTarget(name: "PatchedClientChecks", dependencies: ["PatchedClient", "ArtifactInspection", "PatchedShell", "PatchedUpdatePreferences", "PatchedScheduling"],\n'],
  ];
  for (const [before, after] of firstRunAmendments) expected = replace(expected, before, after);
  assert.equal(sha256(Buffer.from(expected)), '1bdfbe0bc438e7383bb92f432bcd43a1825bb2001228ad9babe15dfc818f4558');
  // CHECK-MODIFIED PAT-2673: authenticate the complete approved live bytes,
  // then invert only the unique owned-process registration before older oracles.
  const rawLive = readFileSync(new URL('../../../Package.swift', import.meta.url));
  const rawLiveBefore = Buffer.from(rawLive);
  assert.equal(createHash('sha256').update(rawLive).digest('hex'), 'ce5dae62dfa109f3823dc2b38175ca92155beec89f0667ea0b72f0e3ae54a7c5');
  const live = Buffer.from(replace(rawLive.toString('utf8'),
    '    targets: [\n' +
    '        .testTarget(name: "PatchedOwnedProcessTests", dependencies: ["PatchedDisposableProof"],\n' +
    '                    path: "Tests/PatchedOwnedProcessTests"),\n',
    '    targets: [\n'));
  assert.equal(createHash('sha256').update(live).digest('hex'), '1bdfbe0bc438e7383bb92f432bcd43a1825bb2001228ad9babe15dfc818f4558');
  assert.equal(preservedPackageSHA256(rawLive), ORIGINAL);
  assert.deepEqual(rawLive, rawLiveBefore);
  assert.deepEqual(live, Buffer.from(expected));
  const liveBefore = Buffer.from(live);
  assert.equal(preservedPackageSHA256(live), ORIGINAL);
  assert.deepEqual(live, liveBefore);
  let reversed = live.toString('utf8');
  for (const [before, after] of firstRunAmendments) reversed = replace(reversed, after, before);
  assert.deepEqual(Buffer.from(reversed), nativePredecessor);
  assert.equal(sha256(Buffer.from(reversed)), nativePredecessorSHA256);
  for (const [before, after] of amendments) reversed = replace(reversed, after, before);
  assert.deepEqual(Buffer.from(reversed), network);
});
test('new focused gate and full gate are registered exactly once', () => {
  const full = readFileSync(new URL('../../../scripts/verify.sh', import.meta.url), 'utf8');
  assert.equal(full.split('\n').filter(line => line === 'bash scripts/verify-network.sh').length, 1);
  const focused = readFileSync(new URL('../../../scripts/verify-network.sh', import.meta.url), 'utf8');
  for (const literal of ['swift build --product patched-network-checks', 'swift run --skip-build patched-network-checks',
    'node --test services/catalogue/tests/network-package-registration-preservation.test.mjs']) {
    assert.equal(focused.split(literal).length, 2, `focused gate includes once: ${literal}`);
  }
});
test('pure source has no direct platform effects or effectful imports', () => {
  for (const name of ['NetworkPolicy', 'NetworkConfiguration', 'NetworkAdapters', 'NetworkState']) {
    const source = readFileSync(new URL(`../../../Sources/PatchedNetworking/${name}.swift`, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /^\s*import\s/m, 'pure model needs no imports');
    assert.doesNotMatch(source, /\b(?:URLSession|URLRequest|URLComponents|Process|ProcessInfo|FileManager|UserDefaults|SecItemCopyMatching|SecItemAdd|SecItemUpdate|getaddrinfo|CFNetworkCopySystemProxySettings|Date|Task|Timer)\s*[.(]/);
  }
});
for (const [name, input] of [
  ['undefined', undefined], ['null', null], ['false', false], ['number', 7], ['bigint', 7n],
  ['symbol', Symbol('inert')], ['string', text], ['plain object', {}], ['array', [...network]],
  ['Uint8Array', new Uint8Array(network)], ['ArrayBuffer', Uint8Array.from(network).buffer],
  ['empty', Buffer.alloc(0)], ['oversized', Buffer.alloc(65537, 32)], ['unknown bounded', Buffer.alloc(65536, 32)],
]) {
  test(`refuse invalid preservation input ${name}`, () => assert.throws(() => preservedPackageSHA256(input), TypeError));
}
test('unknown object getters and coercion stay inert', () => {
  let calls = 0;
  const object = {[Symbol.toPrimitive]() { calls++; return text; }, toString() { calls++; return text; }, valueOf() { calls++; return network; }};
  for (const key of ['length', 'byteLength', 'buffer', 'constructor']) {
    Object.defineProperty(object, key, {get() { calls++; throw new Error('getter called'); }});
  }
  assert.throws(() => preservedPackageSHA256(object), TypeError);
  assert.equal(calls, 0);
});
const mutations = [
  ['new products missing', mutate(PRODUCTS, '')], ['new targets missing', mutate(TARGETS, '')],
  ['new library product missing', mutate(PRODUCTS, PRODUCTS.split('\n')[1] + '\n')],
  ['new executable product missing', mutate(PRODUCTS, PRODUCTS.split('\n')[0] + '\n')],
  ['new library target missing', mutate(TARGETS, TARGETS.split('\n')[1] + '\n')],
  ['new executable target missing', mutate(TARGETS, TARGETS.split('\n')[0] + '\n')],
  ['products duplicated', mutate(PRODUCTS, PRODUCTS + PRODUCTS)], ['targets duplicated', mutate(TARGETS, TARGETS + TARGETS)],
  ['both duplicated', Buffer.from(text.replace(PRODUCTS, PRODUCTS + PRODUCTS).replace(TARGETS, TARGETS + TARGETS))],
  ['product order reversed', mutate(PRODUCTS, PRODUCTS.split('\n').slice(0, 2).reverse().join('\n') + '\n')],
  ['target order reversed', mutate(TARGETS, TARGETS.split('\n').slice(0, 2).reverse().join('\n') + '\n')],
  ['products moved after Activity', mutate(PRODUCTS + '        .library(name: "PatchedActivity", targets: ["PatchedActivity"]),\n', '        .library(name: "PatchedActivity", targets: ["PatchedActivity"]),\n' + PRODUCTS)],
  ['targets moved after Activity', mutate(TARGETS + '        .target(name: "PatchedActivity"),\n', '        .target(name: "PatchedActivity"),\n' + TARGETS)],
  ['blocks swapped', Buffer.from(text.replace(PRODUCTS, TARGETS).replace(TARGET_HEADER + TARGETS, TARGET_HEADER + PRODUCTS))],
  ['new target extra dependency', mutate('.target(name: "PatchedNetworking")', '.target(name: "PatchedNetworking", dependencies: ["PatchedCore"])')],
  ['new checks changed dependency', mutate('dependencies: ["PatchedNetworking"]', 'dependencies: ["PatchedCore"]')],
  ['new checks extra dependency', mutate('dependencies: ["PatchedNetworking"]', 'dependencies: ["PatchedNetworking", "PatchedCore"]')],
  ['new checks path changed', mutate('path: "Tests/PatchedNetworkChecks"', 'path: "../Tests/PatchedNetworkChecks"')],
  ['new product target changed', mutate('targets: ["PatchedNetworking"]', 'targets: ["PatchedCore"]')],
  ['new executable name changed', mutate('name: "patched-network-checks"', 'name: "other-checks"')],
  ['inherited name changed', mutate('    name: "PatchedProof",\n', '    name: "ChangedProof",\n')],
  ['inherited platform changed', mutate('platforms: [.macOS(.v13)]', 'platforms: [.macOS(.v14)]')],
  ['inherited dependency changed', mutate('dependencies: ["PatchedShell", "PatchedCore", "PatchedUI"]', 'dependencies: ["PatchedShell", "PatchedCore"]')],
  ['inherited path changed', mutate('path: "Tests/PatchedShellChecks"', 'path: "Tests/OtherShellChecks"')],
  ['inherited target changed', mutate('.target(name: "PatchedScheduling")', '.target(name: "OtherScheduling")')],
  ['extra product', mutate(PRODUCT_HEADER, PRODUCT_HEADER + '        .library(name: "Unexpected", targets: ["Unexpected"]),\n')],
  ['extra target', mutate(TARGET_HEADER, TARGET_HEADER + '        .target(name: "Unexpected"),\n')],
  ['unknown registration', Buffer.from(text.replaceAll('PatchedNetworking', 'UnknownNetworking'))],
  ['product header changed', mutate(PRODUCT_HEADER, '   products: [\n')], ['target header changed', mutate(TARGET_HEADER, '   targets: [\n')],
  ['product indentation', mutate(PRODUCTS, PRODUCTS.replaceAll('        .', '       .'))],
  ['target indentation', mutate(TARGETS, TARGETS.replaceAll('        .', '\t.'))],
  ['product blank line', mutate(PRODUCTS, PRODUCTS.replace('\n', '\n\n'))],
  ['target blank line', mutate(TARGETS, TARGETS.replace('\n', '\n\n'))],
  ['product trailing whitespace', mutate(PRODUCTS, PRODUCTS.replace('\n', ' \n'))],
  ['target trailing whitespace', mutate(TARGETS, TARGETS.replace('\n', ' \n'))],
  ['CRLF', Buffer.from(text.replaceAll('\n', '\r\n'))],
  ['products CRLF', mutate(PRODUCTS, PRODUCTS.replaceAll('\n', '\r\n'))],
  ['targets CRLF', mutate(TARGETS, TARGETS.replaceAll('\n', '\r\n'))],
  ['missing final newline', Buffer.from(text.slice(0, -1))], ['extra final newline', Buffer.from(text + '\n')],
  ['leading BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), network])],
  ['trailing NUL', Buffer.concat([network, Buffer.from([0])])], ['unknown comment', Buffer.from(text + '// unknown\n')],
  ['inherited changed without additions', Buffer.from(strip(text).replace('PatchedProof', 'ChangedProof'))],
  ['network additions to original skipping predecessors', Buffer.from(original.toString('utf8').replace(PRODUCT_HEADER, PRODUCT_HEADER + PRODUCTS).replace(TARGET_HEADER, TARGET_HEADER + TARGETS))],
  ['network additions to shell skipping predecessors', Buffer.from(shell.toString('utf8').replace(PRODUCT_HEADER, PRODUCT_HEADER + PRODUCTS).replace(TARGET_HEADER, TARGET_HEADER + TARGETS))],
  ['network additions to preferences skipping activity', Buffer.from(preferences.toString('utf8').replace(PRODUCT_HEADER, PRODUCT_HEADER + PRODUCTS).replace(TARGET_HEADER, TARGET_HEADER + TARGETS))],
];
for (const [name, bytes] of mutations) {
  test(`refuse exact-byte mutation: ${name}`, () => {
    const before = Buffer.from(bytes);
    assert.ok(!pinned.some(([, , pin]) => sha256(bytes) === pin), 'negative differs from every accepted fixture');
    assert.throws(() => preservedPackageSHA256(bytes), TypeError);
    assert.deepEqual(bytes, before);
  });
}
test('code-shaped appended bytes remain inert and refused', () => {
  const marker = Symbol.for('PAT-2666-network-inert');
  const before = globalThis[marker];
  const input = Buffer.from(text + '\nglobalThis[Symbol.for("PAT-2666-network-inert")] = true;\n');
  const snapshot = Buffer.from(input);
  assert.throws(() => preservedPackageSHA256(input), TypeError);
  assert.equal(globalThis[marker], before);
  assert.deepEqual(input, snapshot);
});
