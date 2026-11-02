import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {preservedPackageSHA256} from '../../../scripts/lib/package-registration-preservation.mjs';

// Independent literals: never import expected values from the candidate guard.
const ORIGINAL = '8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699';
const SHELL = '6f69e14efb17c845fc194149d8248500ca6efb49416ebeba9a28030362bff447';
const PREFERENCES = '16c464dab3fa2cc783ef174a68dfaa2969a713c2c2403e484114880e1991b2a2';
const PRODUCT_HEADER = '    products: [\n';
const TARGET_HEADER = '    targets: [\n';
const NEW_PRODUCTS =
  '        .library(name: "PatchedUpdatePreferences", targets: ["PatchedUpdatePreferences"]),\n' +
  '        .executable(name: "patched-update-preferences-checks", targets: ["PatchedUpdatePreferencesChecks"]),\n';
const NEW_TARGETS =
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
const text = preferences.toString('utf8');
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
]) {
  test(`fixture ${name} has independently pinned bytes`, () => assert.equal(digest(bytes), expected));
}
test('only the four approved Preferences lines reconstruct exact Shell bytes', () => {
  const reconstructed = Buffer.from(strip(strip(text, PRODUCT_HEADER, NEW_PRODUCTS), TARGET_HEADER, NEW_TARGETS));
  assert.equal(digest(reconstructed), SHELL);
  assert.deepEqual(reconstructed, shell);
  assert.equal(preservedPackageSHA256(reconstructed), ORIGINAL);
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
  ['array of approved bytes', [...preferences]],
  ['Uint8Array containing approved bytes', new Uint8Array(preferences)],
  ['ArrayBuffer containing approved bytes', Uint8Array.from(preferences).buffer],
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
    toString() { calls++; return text; }, valueOf() { calls++; return preferences; }};
  assert.throws(() => preservedPackageSHA256(value), TypeError);
  assert.equal(calls, 0);
});
test('code-shaped unknown input stays inert and refused without input mutation', () => {
  const marker = Symbol.for('PAT-2662-package-guard-inert');
  const before = globalThis[marker];
  const bytes = Buffer.from(text + '\nglobalThis[Symbol.for("PAT-2662-package-guard-inert")] = true;\n');
  const snapshot = Buffer.from(bytes);
  assert.throws(() => preservedPackageSHA256(bytes), TypeError);
  assert.equal(globalThis[marker], before);
  assert.deepEqual(bytes, snapshot);
});

// Every entry changes actual independently pinned fixture bytes. No Swift is evaluated.
const mutations = [
  ['unknown four-line insertion', Buffer.from(strip(strip(text, PRODUCT_HEADER, NEW_PRODUCTS), TARGET_HEADER, NEW_TARGETS)
    .replace(PRODUCT_HEADER, PRODUCT_HEADER + NEW_PRODUCTS.replaceAll('PatchedUpdatePreferences', 'UnknownPreferences'))
    .replace(TARGET_HEADER, TARGET_HEADER + NEW_TARGETS.replaceAll('PatchedUpdatePreferences', 'UnknownPreferences')))],
  ['missing new products', mutate(PRODUCT_HEADER + NEW_PRODUCTS, PRODUCT_HEADER)],
  ['missing new targets', mutate(TARGET_HEADER + NEW_TARGETS, TARGET_HEADER)],
  ['missing all new registrations but altered inherited bytes', Buffer.from(strip(strip(text, PRODUCT_HEADER, NEW_PRODUCTS), TARGET_HEADER, NEW_TARGETS).replace('PatchedProof', 'OtherProof'))],
  ['missing new library product', mutate(NEW_PRODUCTS, NEW_PRODUCTS.split('\n').slice(1).join('\n'))],
  ['missing new executable product', mutate(NEW_PRODUCTS, NEW_PRODUCTS.split('\n')[0] + '\n')],
  ['missing new library target', mutate(NEW_TARGETS, NEW_TARGETS.split('\n').slice(1).join('\n'))],
  ['missing new executable target', mutate(NEW_TARGETS, NEW_TARGETS.split('\n')[0] + '\n')],
  ['duplicate new products', mutate(NEW_PRODUCTS, NEW_PRODUCTS + NEW_PRODUCTS)],
  ['duplicate new targets', mutate(NEW_TARGETS, NEW_TARGETS + NEW_TARGETS)],
  ['duplicate all new registrations', Buffer.from(text.replace(NEW_PRODUCTS, NEW_PRODUCTS + NEW_PRODUCTS).replace(NEW_TARGETS, NEW_TARGETS + NEW_TARGETS))],
  ['products moved after Shell', mutate(NEW_PRODUCTS + OLD_PRODUCTS, OLD_PRODUCTS + NEW_PRODUCTS)],
  ['targets moved after Shell', mutate(NEW_TARGETS + OLD_TARGETS, OLD_TARGETS + NEW_TARGETS)],
  ['product lines reversed', mutate(NEW_PRODUCTS, NEW_PRODUCTS.split('\n').slice(0, 2).reverse().join('\n') + '\n')],
  ['target lines reversed', mutate(NEW_TARGETS, NEW_TARGETS.split('\n').slice(0, 2).reverse().join('\n') + '\n')],
  ['product and target blocks exchanged', Buffer.from(text.replace(NEW_PRODUCTS, NEW_TARGETS).replace(TARGET_HEADER + NEW_TARGETS, TARGET_HEADER + NEW_PRODUCTS))],
  ['extra target', mutate(TARGET_HEADER, TARGET_HEADER + '        .target(name: "Unexpected"),\n')],
  ['extra product', mutate(PRODUCT_HEADER, PRODUCT_HEADER + '        .library(name: "Unexpected", targets: ["Unexpected"]),\n')],
  ['new library dependency changed', mutate('.target(name: "PatchedUpdatePreferences", dependencies: ["PatchedScheduling"])', '.target(name: "PatchedUpdatePreferences", dependencies: ["PatchedCore"])')],
  ['new library dependency removed', mutate('.target(name: "PatchedUpdatePreferences", dependencies: ["PatchedScheduling"])', '.target(name: "PatchedUpdatePreferences")')],
  ['new library extra dependency', mutate('.target(name: "PatchedUpdatePreferences", dependencies: ["PatchedScheduling"])', '.target(name: "PatchedUpdatePreferences", dependencies: ["PatchedScheduling", "PatchedCore"])')],
  ['new checks dependency changed', mutate('dependencies: ["PatchedUpdatePreferences", "PatchedScheduling"]', 'dependencies: ["PatchedUpdatePreferences", "PatchedCore"]')],
  ['new checks dependencies reordered', mutate('dependencies: ["PatchedUpdatePreferences", "PatchedScheduling"]', 'dependencies: ["PatchedScheduling", "PatchedUpdatePreferences"]')],
  ['new checks path changed', mutate('path: "Tests/PatchedUpdatePreferencesChecks"', 'path: "Tests/OtherChecks"')],
  ['new checks path traversal', mutate('path: "Tests/PatchedUpdatePreferencesChecks"', 'path: "../Tests/PatchedUpdatePreferencesChecks"')],
  ['new product target changed', mutate('.library(name: "PatchedUpdatePreferences", targets: ["PatchedUpdatePreferences"])', '.library(name: "PatchedUpdatePreferences", targets: ["PatchedShell"])')],
  ['new executable name changed', mutate('name: "patched-update-preferences-checks"', 'name: "unknown-checks"')],
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
  ['leading BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), preferences])],
  ['trailing NUL', Buffer.concat([preferences, Buffer.from([0])])],
  ['comment appended', Buffer.from(text + '// unknown\n')],
  ['new products only on original baseline', Buffer.from(original.toString('utf8').replace(PRODUCT_HEADER, PRODUCT_HEADER + NEW_PRODUCTS))],
  ['all new registrations on original baseline without Shell', Buffer.from(original.toString('utf8').replace(PRODUCT_HEADER, PRODUCT_HEADER + NEW_PRODUCTS).replace(TARGET_HEADER, TARGET_HEADER + NEW_TARGETS))],
  ['original mutated inherited name', Buffer.from(original.toString('utf8').replace('PatchedProof', 'UnknownProof'))],
  ['Shell mutated inherited name', Buffer.from(shell.toString('utf8').replace('PatchedProof', 'UnknownProof'))],
];
for (const [name, bytes] of mutations) {
  test(`refuse mutation: ${name}`, () => {
    const before = Buffer.from(bytes);
    assert.ok(![ORIGINAL, SHELL, PREFERENCES].includes(digest(bytes)), 'negative input must differ from all accepted fixtures');
    assert.throws(() => preservedPackageSHA256(bytes), TypeError);
    assert.deepEqual(bytes, before);
  });
}
