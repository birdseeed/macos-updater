import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {preservedPackageSHA256} from '../../../scripts/lib/package-registration-preservation.mjs';

// Independent literal expectations. Never derive authority from guard output.
const originalSHA = '8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699';
const shellSHA = '6f69e14efb17c845fc194149d8248500ca6efb49416ebeba9a28030362bff447';
const fixture = name => readFileSync(new URL(`../protocol/fixtures/package-registration/${name}`, import.meta.url));
const original = fixture('Package.original.swift');
const shell = fixture('Package.shell.swift');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const productHeader = '    products: [\n';
const targetHeader = '    targets: [\n';
const productLines = '        .library(name: "PatchedShell", targets: ["PatchedShell"]),\n' +
  '        .executable(name: "patched-shell-checks", targets: ["PatchedShellChecks"]),\n';
const targetLines = '        .target(name: "PatchedShell"),\n' +
  '        .executableTarget(name: "PatchedShellChecks", dependencies: ["PatchedShell", "PatchedCore", "PatchedUI"], path: "Tests/PatchedShellChecks"),\n';
const count = (text, literal) => text.split(literal).length - 1;

function replaceOnce(bytes, before, after) {
  const text = bytes.toString('utf8');
  assert.equal(count(text, before), 1, `mutation anchor must occur exactly once: ${before}`);
  const result = Buffer.from(text.replace(before, after), 'utf8');
  assert.notDeepEqual(result, bytes, 'mutation must change bytes');
  return result;
}

function refuses(bytes) {
  const snapshot = Buffer.isBuffer(bytes) ? Buffer.from(bytes) : null;
  assert.throws(() => preservedPackageSHA256(bytes));
  if (snapshot) assert.deepEqual(bytes, snapshot, 'refusal must not mutate input');
}

test('literal package fixtures have independently pinned digests', () => {
  assert.equal(digest(original), originalSHA);
  assert.equal(digest(shell), shellSHA);
  assert.notDeepEqual(original, shell);
});

test('removing only the exact four approved registration lines reconstructs historical bytes', () => {
  const originalText = original.toString('utf8');
  const shellText = shell.toString('utf8');
  assert.deepEqual(Buffer.from(originalText, 'utf8'), original, 'original is exact UTF-8');
  assert.deepEqual(Buffer.from(shellText, 'utf8'), shell, 'registered fixture is exact UTF-8');
  for (const [header, lines] of [[productHeader, productLines], [targetHeader, targetLines]]) {
    assert.equal(count(originalText, header), 1);
    assert.equal(count(shellText, header), 1);
    assert.equal(count(originalText, lines), 0);
    assert.equal(count(shellText, lines), 1);
    assert.equal(count(shellText, header + lines), 1, 'registration is directly after its header');
    for (const line of lines.trimEnd().split('\n')) {
      assert.equal(count(shellText, line + '\n'), 1, 'each approved line occurs once');
      assert.equal(count(originalText, line + '\n'), 0, 'no pre-existing registration');
    }
  }
  const reconstructed = Buffer.from(shellText
    .replace(productHeader + productLines, productHeader)
    .replace(targetHeader + targetLines, targetHeader), 'utf8');
  assert.deepEqual(reconstructed, original, 'every other historical byte remains exact');
  assert.equal(digest(reconstructed), originalSHA);
  const rebuilt = Buffer.from(originalText
    .replace(productHeader, productHeader + productLines)
    .replace(targetHeader, targetHeader + targetLines), 'utf8');
  assert.deepEqual(rebuilt, shell, 'nothing was added elsewhere');
});

// These are the two prospective meaningful Phase A failures, not setup checks.
for (const [name, bytes] of [['historical original', original], ['exact shell registration', shell]]) {
  test(`${name} returns the historical original digest without mutating bytes`, () => {
    const input = Buffer.from(bytes);
    const before = Buffer.from(input);
    assert.equal(preservedPackageSHA256(input), originalSHA);
    assert.deepEqual(input, before);
    assert.equal(preservedPackageSHA256(Buffer.from(bytes)), originalSHA, 'repeat is deterministic');
  });
}

const mutationCases = [
  ['existing target name', '.executableTarget(name: "PatchedApp"', '.executableTarget(name: "ChangedApp"'],
  ['existing dependency', 'dependencies: ["PatchedClient"]', 'dependencies: ["PatchedCore"]'],
  ['new target path', 'path: "Tests/PatchedShellChecks"', 'path: "Tests/OtherChecks"'],
  ['new target dependency', 'dependencies: ["PatchedShell", "PatchedCore", "PatchedUI"]', 'dependencies: ["PatchedShell", "PatchedCore", "PatchedUI", "PatchedClient"]'],
  ['new dependency order', 'dependencies: ["PatchedShell", "PatchedCore", "PatchedUI"]', 'dependencies: ["PatchedCore", "PatchedShell", "PatchedUI"]'],
  ['product order', productLines, productLines.split('\n').slice(0, 2).reverse().join('\n') + '\n'],
  ['target order', targetLines, targetLines.split('\n').slice(0, 2).reverse().join('\n') + '\n'],
  ['product whitespace', productLines, ' ' + productLines],
  ['target whitespace', targetLines, targetLines.replace('        .target', '       .target')],
  ['remove products registration', productLines, ''],
  ['remove targets registration', targetLines, ''],
  ['duplicate products registration', productLines, productLines + productLines],
  ['duplicate targets registration', targetLines, targetLines + targetLines],
  ['extra product', productHeader, productHeader + '        .library(name: "Other", targets: ["Other"]),\n'],
  ['extra target', targetHeader, targetHeader + '        .target(name: "Other"),\n'],
  ['move product registration away from header', productHeader + productLines, productHeader + '\n' + productLines],
  ['move target registration away from header', targetHeader + targetLines, targetHeader + '\n' + targetLines],
];
for (const [name, before, after] of mutationCases) {
  test(`refuses registered package mutation: ${name}`, () => refuses(replaceOnce(shell, before, after)));
}
for (const [group, lines] of [['product', productLines], ['target', targetLines]]) {
  for (const [index, line] of lines.trimEnd().split('\n').entries()) {
    test(`refuses missing individual ${group} registration line ${index + 1}`, () => {
      refuses(replaceOnce(shell, line + '\n', ''));
    });
  }
}
for (const [name, bytes] of [['original', original], ['registered', shell]]) {
  for (const [mutation, changed] of [
    ['trailing newline', Buffer.concat([bytes, Buffer.from('\n')])],
    ['trailing text', Buffer.concat([bytes, Buffer.from('// added\n')])],
    ['trailing NUL', Buffer.concat([bytes, Buffer.from([0])])],
    ['invalid UTF-8', Buffer.concat([bytes, Buffer.from([0xc3, 0x28])])],
    ['UTF-8 BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), bytes])],
    ['CRLF conversion', Buffer.from(bytes.toString('utf8').replaceAll('\n', '\r\n'))],
    ['missing last byte', bytes.subarray(0, bytes.length - 1)],
    ['existing package name', replaceOnce(bytes, '    name: "PatchedProof",\n', '    name: "ChangedProof",\n')],
  ]) {
    test(`refuses ${name} package mutation: ${mutation}`, () => refuses(changed));
  }
}
for (const [name, value] of [
  ['undefined', undefined], ['null', null], ['string', original.toString('utf8')],
  ['array', [...original]], ['Uint8Array', new Uint8Array(original)],
  ['ArrayBuffer', new Uint8Array(original).buffer], ['object', {bytes: original}],
  ['number', 1], ['boolean', true], ['bigint', 1n], ['symbol', Symbol('package')],
  ['function', () => original], ['empty Buffer', Buffer.alloc(0)],
]) {
  test(`refuses invalid package input: ${name}`, () => refuses(value));
}
