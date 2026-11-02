// Independent E-only controls; parent reconciled exact actual combined Package after Preferences main acceptance before integration.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {preservedPackageSHA256} from '../../../scripts/lib/package-registration-preservation.mjs';

// Independent literals: never import expected values from the candidate guard.
const ORIGINAL = '8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699';
const SHELL = '6f69e14efb17c845fc194149d8248500ca6efb49416ebeba9a28030362bff447';
const PREFERENCES = '16c464dab3fa2cc783ef174a68dfaa2969a713c2c2403e484114880e1991b2a2';
const COMBINED = '9efb689b91704ce21ee5aef32fc1e3501994df49b37e874ebdf714bab56525e4';
const PRODUCT_HEADER = '    products: [\n';
const TARGET_HEADER = '    targets: [\n';
const NEW_PRODUCTS =
  '        .library(name: "PatchedActivity", targets: ["PatchedActivity"]),\n' +
  '        .executable(name: "patched-activity-checks", targets: ["PatchedActivityChecks"]),\n';
const NEW_TARGETS =
  '        .target(name: "PatchedActivity"),\n' +
  '        .executableTarget(name: "PatchedActivityChecks", dependencies: ["PatchedActivity"], path: "Tests/PatchedActivityChecks"),\n';
const PREFERENCES_PRODUCTS =
  '        .library(name: "PatchedUpdatePreferences", targets: ["PatchedUpdatePreferences"]),\n' +
  '        .executable(name: "patched-update-preferences-checks", targets: ["PatchedUpdatePreferencesChecks"]),\n';
const PREFERENCES_TARGETS =
  '        .target(name: "PatchedUpdatePreferences", dependencies: ["PatchedScheduling"]),\n' +
  '        .executableTarget(name: "PatchedUpdatePreferencesChecks", dependencies: ["PatchedUpdatePreferences", "PatchedScheduling"], path: "Tests/PatchedUpdatePreferencesChecks"),\n';
const OLD_PRODUCTS =
  '        .library(name: "PatchedShell", targets: ["PatchedShell"]),\n' +
  '        .executable(name: "patched-shell-checks", targets: ["PatchedShellChecks"]),\n';
const OLD_TARGETS =
  '        .target(name: "PatchedShell"),\n' +
  '        .executableTarget(name: "PatchedShellChecks", dependencies: ["PatchedShell", "PatchedCore", "PatchedUI"], path: "Tests/PatchedShellChecks"),\n';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
// Only parent-owned inert data copies are read; no worktree/source discovery.
const original = readFileSync(new URL('../protocol/fixtures/package-registration/Package.original.swift', import.meta.url));
const shell = readFileSync(new URL('../protocol/fixtures/package-registration/Package.shell.swift', import.meta.url));
const preferences = readFileSync(new URL('../protocol/fixtures/package-registration/Package.preferences.swift', import.meta.url));
const combined = readFileSync(new URL('../protocol/fixtures/package-registration/Package.activity.swift', import.meta.url));
const text = combined.toString('utf8');
const replace = (source, before, after) => {
  assert.notEqual(before, after, 'mutation must change its literal');
  assert.equal(source.split(before).length, 2, 'mutation anchor must occur exactly once');
  return source.replace(before, after);
};
const strip = (source, header, block) => replace(source, header + block, header);
const mutate = (before, after) => Buffer.from(replace(text, before, after));

for (const [name, bytes, expected] of [
  ['original', original, ORIGINAL],
  ['shell', shell, SHELL],
  ['preferences', preferences, PREFERENCES],
  ['provisional combined', combined, COMBINED],
]) {
  test(`fixture ${name} has independently pinned bytes`, () => assert.equal(digest(bytes), expected));
}
test('only the four literal Activity lines reconstruct exact Preferences bytes', () => {
  const reconstructed = Buffer.from(strip(strip(text, PRODUCT_HEADER, NEW_PRODUCTS), TARGET_HEADER, NEW_TARGETS));
  assert.equal(digest(reconstructed), PREFERENCES);
  assert.deepEqual(reconstructed, preferences);
  assert.equal(preservedPackageSHA256(reconstructed), ORIGINAL);
});
test('only the four literal Preferences lines reconstruct exact Shell bytes', () => {
  const reconstructed = Buffer.from(strip(strip(preferences.toString('utf8'), PRODUCT_HEADER, PREFERENCES_PRODUCTS), TARGET_HEADER, PREFERENCES_TARGETS));
  assert.equal(digest(reconstructed), SHELL);
  assert.deepEqual(reconstructed, shell);
  assert.equal(preservedPackageSHA256(reconstructed), ORIGINAL);
});
test('combined literal removals preserve every predecessor byte through original', () => {
  const withoutActivity = strip(strip(text, PRODUCT_HEADER, NEW_PRODUCTS), TARGET_HEADER, NEW_TARGETS);
  assert.deepEqual(Buffer.from(withoutActivity), preferences);
  const withoutPreferences = strip(strip(withoutActivity, PRODUCT_HEADER, PREFERENCES_PRODUCTS), TARGET_HEADER, PREFERENCES_TARGETS);
  assert.deepEqual(Buffer.from(withoutPreferences), shell);
  const withoutShell = strip(strip(withoutPreferences, PRODUCT_HEADER, OLD_PRODUCTS), TARGET_HEADER, OLD_TARGETS);
  assert.deepEqual(Buffer.from(withoutShell), original);
  assert.equal(digest(Buffer.from(withoutShell)), ORIGINAL);
});
test('only the four historical Shell lines reconstruct exact original bytes', () => {
  const reconstructed = Buffer.from(strip(strip(shell.toString('utf8'), PRODUCT_HEADER, OLD_PRODUCTS), TARGET_HEADER, OLD_TARGETS));
  assert.equal(digest(reconstructed), ORIGINAL);
  assert.deepEqual(reconstructed, original);
});
for (const [name, fixture] of [
  ['original', original],
  ['shell', shell],
  ['preferences', preferences],
  ['provisional combined', combined],
]) {
  test(`accept exact ${name}, return original hash, preserve input and repeat`, () => {
    const bytes = Buffer.from(fixture);
    const before = Buffer.from(bytes);
    assert.equal(preservedPackageSHA256(bytes), ORIGINAL);
    assert.deepEqual(bytes, before);
    assert.equal(preservedPackageSHA256(bytes), ORIGINAL);
    assert.deepEqual(bytes, before);
  });
}
const invalidInputs = [
  ['undefined', undefined],
  ['null', null],
  ['false', false],
  ['number', 0],
  ['bigint', 1n],
  ['symbol', Symbol('inert')],
  ['string containing approved bytes', text],
  ['plain object', {}],
  ['array of approved bytes', [...combined]],
  ['Uint8Array containing approved bytes', new Uint8Array(combined)],
  ['ArrayBuffer containing approved bytes', Uint8Array.from(combined).buffer],
  ['arbitrary small Buffer', Buffer.from('unknown')],
  ['empty Buffer', Buffer.alloc(0)],
  ['oversized Buffer', Buffer.alloc(65537, 32)],
  ['exact maximum but unknown bytes', Buffer.alloc(65536, 32)],
];
for (const [name, value] of invalidInputs) {
  test(`refuse ${name}`, () => assert.throws(() => preservedPackageSHA256(value), TypeError));
}
test('non-Buffer property getters are never read', () => {
  let reads = 0;
  const value = Object.create(null);
  for (const key of ['length', 'byteLength', 'buffer', 'constructor', 'toString', 'valueOf']) {
    Object.defineProperty(value, key, {get() { reads++; throw new Error('getter invoked'); }});
  }
  assert.throws(() => preservedPackageSHA256(value), TypeError);
  assert.equal(reads, 0);
});
test('non-Buffer coercion hooks are never invoked', () => {
  let calls = 0;
  const value = {[Symbol.toPrimitive]() { calls++; return text; },
    toString() { calls++; return text; }, valueOf() { calls++; return combined; }};
  assert.throws(() => preservedPackageSHA256(value), TypeError);
  assert.equal(calls, 0);
});
test('code-shaped unknown input stays inert and refused without input mutation', () => {
  const marker = Symbol.for('PAT-2663-package-guard-inert');
  const before = globalThis[marker];
  const bytes = Buffer.from(text + '\nglobalThis[Symbol.for("PAT-2663-package-guard-inert")] = true;\n');
  const snapshot = Buffer.from(bytes);
  assert.throws(() => preservedPackageSHA256(bytes), TypeError);
  assert.equal(globalThis[marker], before);
  assert.deepEqual(bytes, snapshot);
});

// Every entry changes actual independently pinned fixture bytes. No Swift is evaluated.
const mutations = [
  ['unknown four-line insertion', Buffer.from(strip(strip(text, PRODUCT_HEADER, NEW_PRODUCTS), TARGET_HEADER, NEW_TARGETS)
    .replace(PRODUCT_HEADER, PRODUCT_HEADER + NEW_PRODUCTS.replaceAll('PatchedActivity', 'UnknownActivity'))
    .replace(TARGET_HEADER, TARGET_HEADER + NEW_TARGETS.replaceAll('PatchedActivity', 'UnknownActivity')))],
  ['missing new products', mutate(PRODUCT_HEADER + NEW_PRODUCTS, PRODUCT_HEADER)],
  ['missing new targets', mutate(TARGET_HEADER + NEW_TARGETS, TARGET_HEADER)],
  ['missing all new registrations but altered inherited bytes', Buffer.from(strip(strip(text, PRODUCT_HEADER, NEW_PRODUCTS), TARGET_HEADER, NEW_TARGETS).replace('    name: "PatchedProof",\n', '    name: "OtherProof",\n'))],
  ['missing new library product', mutate(NEW_PRODUCTS, NEW_PRODUCTS.split('\n').slice(1).join('\n'))],
  ['missing new executable product', mutate(NEW_PRODUCTS, NEW_PRODUCTS.split('\n')[0] + '\n')],
  ['missing new library target', mutate(NEW_TARGETS, NEW_TARGETS.split('\n').slice(1).join('\n'))],
  ['missing new executable target', mutate(NEW_TARGETS, NEW_TARGETS.split('\n')[0] + '\n')],
  ['duplicate new products', mutate(NEW_PRODUCTS, NEW_PRODUCTS + NEW_PRODUCTS)],
  ['duplicate new targets', mutate(NEW_TARGETS, NEW_TARGETS + NEW_TARGETS)],
  ['duplicate all new registrations', Buffer.from(text.replace(NEW_PRODUCTS, NEW_PRODUCTS + NEW_PRODUCTS).replace(NEW_TARGETS, NEW_TARGETS + NEW_TARGETS))],
  ['products moved after Preferences', mutate(NEW_PRODUCTS + PREFERENCES_PRODUCTS, PREFERENCES_PRODUCTS + NEW_PRODUCTS)],
  ['targets moved after Preferences', mutate(NEW_TARGETS + PREFERENCES_TARGETS, PREFERENCES_TARGETS + NEW_TARGETS)],
  ['product lines reversed', mutate(NEW_PRODUCTS, NEW_PRODUCTS.split('\n').slice(0, 2).reverse().join('\n') + '\n')],
  ['target lines reversed', mutate(NEW_TARGETS, NEW_TARGETS.split('\n').slice(0, 2).reverse().join('\n') + '\n')],
  ['product and target blocks exchanged', Buffer.from(text.replace(NEW_PRODUCTS, NEW_TARGETS).replace(TARGET_HEADER + NEW_TARGETS, TARGET_HEADER + NEW_PRODUCTS))],
  ['extra target', mutate(TARGET_HEADER, TARGET_HEADER + '        .target(name: "Unexpected"),\n')],
  ['extra product', mutate(PRODUCT_HEADER, PRODUCT_HEADER + '        .library(name: "Unexpected", targets: ["Unexpected"]),\n')],
  ['new library unexpected dependency', mutate('        .target(name: "PatchedActivity"),\n', '        .target(name: "PatchedActivity", dependencies: ["PatchedCore"]),\n')],
  ['new checks dependency changed', mutate('dependencies: ["PatchedActivity"]', 'dependencies: ["PatchedCore"]')],
  ['new checks dependency removed', mutate('dependencies: ["PatchedActivity"]', 'dependencies: []')],
  ['new checks extra dependency', mutate('dependencies: ["PatchedActivity"]', 'dependencies: ["PatchedActivity", "PatchedCore"]')],
  ['new checks path changed', mutate('path: "Tests/PatchedActivityChecks"', 'path: "Tests/OtherChecks"')],
  ['new checks path traversal', mutate('path: "Tests/PatchedActivityChecks"', 'path: "../Tests/PatchedActivityChecks"')],
  ['new product target changed', mutate('.library(name: "PatchedActivity", targets: ["PatchedActivity"])', '.library(name: "PatchedActivity", targets: ["PatchedShell"])')],
  ['new executable name changed', mutate('name: "patched-activity-checks"', 'name: "unknown-checks"')],
  ['inherited package name changed', mutate('    name: "PatchedProof",\n', '    name: "UnknownProof",\n')],
  ['inherited platform changed', mutate('platforms: [.macOS(.v13)]', 'platforms: [.macOS(.v14)]')],
  ['inherited Shell dependency changed', mutate('dependencies: ["PatchedShell", "PatchedCore", "PatchedUI"]', 'dependencies: ["PatchedShell", "PatchedCore"]')],
  ['inherited Shell path changed', mutate('path: "Tests/PatchedShellChecks"', 'path: "Tests/OtherShellChecks"')],
  ['inherited target changed', mutate('.target(name: "PatchedScheduling")', '.target(name: "OtherScheduling")')],
  ['new products indentation changed', mutate(NEW_PRODUCTS, NEW_PRODUCTS.replaceAll('        .', '       .'))],
  ['new targets indentation changed', mutate(NEW_TARGETS, NEW_TARGETS.replaceAll('        .', '\t.'))],
  ['product header indentation changed', mutate(PRODUCT_HEADER, '   products: [\n')],
  ['target header indentation changed', mutate(TARGET_HEADER, '   targets: [\n')],
  ['blank line inside new products', mutate(NEW_PRODUCTS, NEW_PRODUCTS.replace('\n', '\n\n'))],
  ['blank line inside new targets', mutate(NEW_TARGETS, NEW_TARGETS.replace('\n', '\n\n'))],
  ['trailing whitespace in new products', mutate(NEW_PRODUCTS, NEW_PRODUCTS.replace('\n', ' \n'))],
  ['trailing whitespace in new targets', mutate(NEW_TARGETS, NEW_TARGETS.replace('\n', ' \n'))],
  ['CRLF everywhere', Buffer.from(text.replaceAll('\n', '\r\n'))],
  ['CRLF in new products', mutate(NEW_PRODUCTS, NEW_PRODUCTS.replaceAll('\n', '\r\n'))],
  ['CRLF in new targets', mutate(NEW_TARGETS, NEW_TARGETS.replaceAll('\n', '\r\n'))],
  ['missing final newline', Buffer.from(text.slice(0, -1))],
  ['extra final newline', Buffer.from(text + '\n')],
  ['leading BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), combined])],
  ['trailing NUL', Buffer.concat([combined, Buffer.from([0])])],
  ['comment appended', Buffer.from(text + '// unknown\n')],
  ['new products only on original baseline', Buffer.from(original.toString('utf8').replace(PRODUCT_HEADER, PRODUCT_HEADER + NEW_PRODUCTS))],
  ['all new registrations on original baseline without predecessors', Buffer.from(original.toString('utf8').replace(PRODUCT_HEADER, PRODUCT_HEADER + NEW_PRODUCTS).replace(TARGET_HEADER, TARGET_HEADER + NEW_TARGETS))],
  ['Activity registrations on Shell without Preferences', Buffer.from(shell.toString('utf8').replace(PRODUCT_HEADER, PRODUCT_HEADER + NEW_PRODUCTS).replace(TARGET_HEADER, TARGET_HEADER + NEW_TARGETS))],
  ['inherited Preferences dependency changed', mutate('        .target(name: "PatchedUpdatePreferences", dependencies: ["PatchedScheduling"]),\n', '        .target(name: "PatchedUpdatePreferences", dependencies: ["PatchedCore"]),\n')],
  ['inherited Preferences checks dependencies reordered', mutate('dependencies: ["PatchedUpdatePreferences", "PatchedScheduling"]', 'dependencies: ["PatchedScheduling", "PatchedUpdatePreferences"]')],
  ['inherited Preferences checks path changed', mutate('path: "Tests/PatchedUpdatePreferencesChecks"', 'path: "Tests/OtherPreferencesChecks"')],
  ['inherited Preferences product missing', mutate(PREFERENCES_PRODUCTS, '')],
  ['inherited Preferences target missing', mutate(PREFERENCES_TARGETS, '')],
  ['inherited Shell product missing', mutate(OLD_PRODUCTS, '')],
  ['inherited Shell target missing', mutate(OLD_TARGETS, '')],
  ['original mutated inherited name', Buffer.from(original.toString('utf8').replace('    name: "PatchedProof",\n', '    name: "UnknownProof",\n'))],
  ['Shell mutated inherited name', Buffer.from(shell.toString('utf8').replace('    name: "PatchedProof",\n', '    name: "UnknownProof",\n'))],
];
for (const [name, bytes] of mutations) {
  test(`refuse mutation: ${name}`, () => {
    const before = Buffer.from(bytes);
    assert.ok(![ORIGINAL, SHELL, PREFERENCES, COMBINED].includes(digest(bytes)), 'negative input must differ from all accepted fixtures');
    assert.throws(() => preservedPackageSHA256(bytes), TypeError);
    assert.deepEqual(bytes, before);
  });
}
