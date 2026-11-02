// Inert byte controls only. Never evaluates Swift or executes the check target.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, lstatSync} from 'node:fs';
import {projectScheduleSessionRegistration} from './schedule-session-registration-projection.mjs';
// CHECK-MODIFIED PAT-2668: only the two actual reads project the new session call.
// Projection must strictly validate before removing that exact call; historical virtual
// vectors, assertions, pinned bytes, identity and mode contracts remain unchanged.

const ORIGINAL_HEAD = '79deb652581d2b8110d21d67c36076688ccc76ff';
const ORIGINAL_SHA256 = 'be36b102eff738f71f005d6bd4d8acc6fb7345f6ae0fc6c7ed0acf0f426a44a6';
const LINE = '    scheduleRecordChecks(checks)\n';
const ANCHOR = '    print("SETUP ';
const INVENTORY_LINE = '    inventoryProjectionChecks(checks)\n';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const fixtureURL = new URL('../../../Fixtures/SchedulePreferences/main.original.swift', import.meta.url);
const candidateURL = new URL('../../../Tests/PatchedUpdatePreferencesChecks/main.swift', import.meta.url);
const original = readFileSync(fixtureURL);
const oldText = original.toString('utf8');
// Byte acceptance is independently pinned. Removing a moved or duplicate call never suffices.
function preservedMain(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length > 65536) throw new TypeError('bounded Buffer required');
  const text = bytes.toString('utf8');
  if (!Buffer.from(text).equals(bytes) || text.split(LINE).length !== 2 ||
      text.split(LINE + ANCHOR).length !== 2) throw new TypeError('exact single registration required');
  const restored = Buffer.from(text.replace(LINE + ANCHOR, ANCHOR));
  if (digest(restored) !== ORIGINAL_SHA256) throw new TypeError('original main bytes changed');
  return restored;
}
// Only the current exact inventory insertion may precede the preserved schedule gate.
function preservedInventoryMain(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length > 65536) throw new TypeError('bounded Buffer required');
  const text = bytes.toString('utf8');
  const block = LINE + INVENTORY_LINE + ANCHOR;
  if (!Buffer.from(text).equals(bytes) || text.split(INVENTORY_LINE).length !== 2 ||
      text.split(block).length !== 2) throw new TypeError('exact single inventory registration required');
  return preservedMain(Buffer.from(text.replace(block, LINE + ANCHOR)));
}
// CHECK-MODIFIED PAT-2662: admit only exact native additions before the unchanged pinned guards.
function preservedNativeStoreMain(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length > 65536) throw new TypeError('bounded Buffer required');
  const text = bytes.toString('utf8');
  const runAnchor = '@MainActor func runAll() {\n';
  const defaultLine = '    nativeStoreChecks(checks)\n';
  const dispatchBlock = String.raw`    if nativeStoreChildDispatch() { return }
    if Array(CommandLine.arguments.dropFirst()) == ["--pat-2662-native-store"] {
        let checks = Checks()
        nativeStoreChecks(checks)
        print("SETUP \(checks.setupCount) failures \(checks.setupFailures); BEHAVIOR \(checks.behaviorCount) failures \(checks.behaviorFailures)")
        if checks.setupFailures + checks.behaviorFailures > 0 { exit(1) }
        return
    }
`;
  const dispatch = runAnchor + dispatchBlock;
  const block = LINE + INVENTORY_LINE + defaultLine + ANCHOR;
  if (!Buffer.from(text).equals(bytes) || text.split(runAnchor).length !== 2 ||
      text.split(dispatchBlock).length !== 2 || text.split(dispatch).length !== 2 ||
      text.split('\n' + defaultLine).length !== 2 || text.split(block).length !== 2) {
    throw new TypeError('exact single native store registrations required');
  }
  const withoutDispatch = text.replace(dispatch, runAnchor);
  return preservedInventoryMain(Buffer.from(withoutDispatch.replace(block, LINE + INVENTORY_LINE + ANCHOR)));
}
function mutate(before, after) {
  const text = approved.toString('utf8');
  assert.equal(text.split(before).length, 2, 'mutation anchor unique');
  assert.notEqual(before, after);
  return Buffer.from(text.replace(before, after));
}
const approved = Buffer.from(oldText.replace(ANCHOR, LINE + ANCHOR));
test('original main is an inert exact Git HEAD copy with pinned digest', () => {
  assert.match(ORIGINAL_HEAD, /^[a-f0-9]{40}$/);
  assert.equal(digest(original), ORIGINAL_SHA256);
  assert.equal(oldText.split(ANCHOR).length, 2);
  assert.equal(oldText.includes('scheduleRecordChecks('), false);
  assert.equal(lstatSync(fixtureURL).isFile(), true);
  assert.equal(lstatSync(fixtureURL).isSymbolicLink(), false);
  assert.equal(lstatSync(fixtureURL).mode & 0o777, 0o644);
});
test('actual main has exactly the one insertion and every original byte/mode', () => {
  const bytes = projectScheduleSessionRegistration(readFileSync(candidateURL)); const snapshot = Buffer.from(bytes);
  assert.deepEqual(preservedNativeStoreMain(bytes), original);
  assert.deepEqual(bytes, snapshot);
  assert.equal(lstatSync(candidateURL).mode & 0o777, 0o644);
});
test('approved virtual addition reconstructs the pinned original', () => {
  assert.deepEqual(preservedMain(approved), original);
  assert.deepEqual(preservedMain(approved), original);
});
const mutations = [
  ['changed old assertion', mutate('if try !value()', 'if try value()')],
  ['changed old helper', mutate('let storeScope = "synthetic-store"', 'let storeScope = "other-store"')],
  ['changed old registration order', mutate('recordChecks(checks); persistenceChecks(checks); raceChecks(checks); projectionChecks(checks)',
    'persistenceChecks(checks); recordChecks(checks); raceChecks(checks); projectionChecks(checks)')],
  ['changed failure exit', mutate('exit(1)', 'exit(0)')],
  ['duplicate new registration', mutate(LINE, LINE + LINE)],
  ['removed new registration', mutate(LINE, '')],
  ['moved registration before old calls', Buffer.from(approved.toString('utf8').replace(LINE, '').replace('    recordChecks(checks);', LINE + '    recordChecks(checks);'))],
  ['moved registration after summary', Buffer.from(approved.toString('utf8').replace(LINE, '').replace('    if checks.setupFailures', LINE + '    if checks.setupFailures'))],
  ['registration argument changed', mutate(LINE, '    scheduleRecordChecks(Checks())\n')],
  ['registration whitespace changed', mutate(LINE, '   scheduleRecordChecks(checks)\n')],
  ['registration commented out', mutate(LINE, '    // scheduleRecordChecks(checks)\n')],
  ['original helper body changed', mutate('return String(decoding: canonical(object), as: UTF8.self)', 'return "invented"')],
  ['extra trailing byte', Buffer.concat([approved, Buffer.from('\n')])],
  ['CRLF', Buffer.from(approved.toString('utf8').replaceAll('\n', '\r\n'))],
  ['BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), approved])],
];
for (const [name, bytes] of mutations) {
  test(`refuse virtual ${name}`, () => {
    assert.notDeepEqual(bytes, approved, 'negative changes actual approved bytes');
    const snapshot = Buffer.from(bytes);
    assert.throws(() => preservedMain(bytes), TypeError);
    assert.deepEqual(bytes, snapshot);
  });
}
for (const [name, value] of [['string', approved.toString()], ['undefined', undefined], ['null', null],
  ['typed array', new Uint8Array(approved)], ['oversized', Buffer.alloc(65537)], ['invalid UTF8', Buffer.from([0xff])]]) {
  test(`refuse ${name}`, () => assert.throws(() => preservedMain(value), TypeError));
}

// Construct the combined positive solely from the original independently pinned fixture.
assert.equal(approved.toString('utf8').split(LINE + ANCHOR).length, 2, 'future construction anchor unique');
const approvedFuture = Buffer.from(approved.toString('utf8').replace(LINE + ANCHOR, LINE + INVENTORY_LINE + ANCHOR));
function mutateFuture(before, after) {
  const text = approvedFuture.toString('utf8');
  assert.equal(text.split(before).length, 2, 'future mutation anchor unique');
  assert.notEqual(before, after);
  return Buffer.from(text.replace(before, after));
}
test('approved combined inventory addition reconstructs the pinned original without mutation', () => {
  const snapshot = Buffer.from(approvedFuture);
  assert.deepEqual(preservedInventoryMain(approvedFuture), original);
  assert.deepEqual(preservedInventoryMain(approvedFuture), original);
  assert.deepEqual(approvedFuture, snapshot);
});
const futureText = approvedFuture.toString('utf8');
const futureMutations = [
  ['inventory duplicated adjacently', mutateFuture(INVENTORY_LINE, INVENTORY_LINE + INVENTORY_LINE)],
  ['inventory duplicated nonadjacently', mutateFuture('    recordChecks(checks);', INVENTORY_LINE + '    recordChecks(checks);')],
  ['inventory removed', mutateFuture(INVENTORY_LINE, '')],
  ['inventory moved before old checks', Buffer.from(futureText.replace(INVENTORY_LINE, '').replace('    recordChecks(checks);', INVENTORY_LINE + '    recordChecks(checks);'))],
  ['inventory moved before schedule', mutateFuture(LINE + INVENTORY_LINE, INVENTORY_LINE + '\n' + LINE)],
  ['inventory moved after summary', Buffer.from(futureText.replace(INVENTORY_LINE, '').replace('    if checks.setupFailures', INVENTORY_LINE + '    if checks.setupFailures'))],
  ['schedule inventory order reversed', mutateFuture(LINE + INVENTORY_LINE, INVENTORY_LINE + LINE)],
  ['inventory argument changed', mutateFuture(INVENTORY_LINE, '    inventoryProjectionChecks(Checks())\n')],
  ['inventory argument whitespace changed', mutateFuture(INVENTORY_LINE, '    inventoryProjectionChecks( checks)\n')],
  ['inventory indentation changed', mutateFuture(INVENTORY_LINE, '   inventoryProjectionChecks(checks)\n')],
  ['inventory commented out', mutateFuture(INVENTORY_LINE, '    // inventoryProjectionChecks(checks)\n')],
  ['newline before inventory', mutateFuture(LINE + INVENTORY_LINE, LINE + '\n' + INVENTORY_LINE)],
  ['newline after inventory', mutateFuture(INVENTORY_LINE + ANCHOR, INVENTORY_LINE + '\n' + ANCHOR)],
  ['schedule duplicated', mutateFuture(LINE, LINE + LINE)],
  ['schedule removed', mutateFuture(LINE, '')],
  ['old assertion changed', mutateFuture('if try !value()', 'if try value()')],
  ['old helper changed', mutateFuture('let storeScope = "synthetic-store"', 'let storeScope = "other-store"')],
  ['old registration order changed', mutateFuture('recordChecks(checks); persistenceChecks(checks); raceChecks(checks); projectionChecks(checks)',
    'persistenceChecks(checks); recordChecks(checks); raceChecks(checks); projectionChecks(checks)')],
  ['old failure exit changed', mutateFuture('exit(1)', 'exit(0)')],
  ['extra trailing byte', Buffer.concat([approvedFuture, Buffer.from('\n')])],
  ['CRLF', Buffer.from(futureText.replaceAll('\n', '\r\n'))],
  ['BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), approvedFuture])],
];
for (const [name, bytes] of futureMutations) {
  test(`inventory wrapper refuses future ${name}`, () => {
    assert.notDeepEqual(bytes, approvedFuture, 'negative changes actual combined approved bytes');
    const snapshot = Buffer.from(bytes);
    assert.throws(() => preservedInventoryMain(bytes), TypeError);
    assert.deepEqual(bytes, snapshot);
  });
}
for (const [name, value] of [['string', approvedFuture.toString()], ['undefined', undefined], ['null', null],
  ['typed array', new Uint8Array(approvedFuture)], ['oversized', Buffer.alloc(65537)], ['invalid UTF8', Buffer.from([0xff])]]) {
  test(`inventory wrapper refuses ${name}`, () => {
    const snapshot = Buffer.isBuffer(value) || value instanceof Uint8Array ? Buffer.from(value) : value;
    assert.throws(() => preservedInventoryMain(value), TypeError);
    if (Buffer.isBuffer(value) || value instanceof Uint8Array) assert.deepEqual(Buffer.from(value), snapshot);
    else assert.equal(value, snapshot);
  });
}

// Independent native registration acceptance controls. Swift bytes are inert data only.
// These literals are specified from the admitted registration contract, never the candidate.
const NATIVE_RUN_ANCHOR = '@MainActor func runAll() {\n';
const NATIVE_DEFAULT_LINE = '    nativeStoreChecks(checks)\n';
const NATIVE_DISPATCH_BLOCK = String.raw`    if nativeStoreChildDispatch() { return }
    if Array(CommandLine.arguments.dropFirst()) == ["--pat-2662-native-store"] {
        let checks = Checks()
        nativeStoreChecks(checks)
        print("SETUP \(checks.setupCount) failures \(checks.setupFailures); BEHAVIOR \(checks.behaviorCount) failures \(checks.behaviorFailures)")
        if checks.setupFailures + checks.behaviorFailures > 0 { exit(1) }
        return
    }
`;
const nativeInventoryAnchor = LINE + INVENTORY_LINE + ANCHOR;
assert.equal(oldText.split(NATIVE_RUN_ANCHOR).length, 2, 'independent run anchor unique');
assert.equal(oldText.split(ANCHOR).length, 2, 'independent summary anchor unique');
// Rebuild all additions directly from the independently digest-pinned original.
const nativeVirtualText = oldText
  .replace(ANCHOR, LINE + INVENTORY_LINE + NATIVE_DEFAULT_LINE + ANCHOR)
  .replace(NATIVE_RUN_ANCHOR, NATIVE_RUN_ANCHOR + NATIVE_DISPATCH_BLOCK);
const nativeVirtual = Buffer.from(nativeVirtualText);
// Indented anchors must start a physical line: four spaces cannot match inside eight.
function nativeReplaceExact(text, before, after) {
  const positions = [];
  for (let at = text.indexOf(before); at !== -1; at = text.indexOf(before, at + 1)) {
    if (!before.startsWith(' ') || at === 0 || text[at - 1] === '\n') positions.push(at);
  }
  assert.equal(positions.length, 1, 'native mutation exact anchor unique');
  assert.notEqual(before, after);
  const at = positions[0];
  return text.slice(0, at) + after + text.slice(at + before.length);
}
function nativeMutation(before, after) {
  return Buffer.from(nativeReplaceExact(nativeVirtualText, before, after));
}
function nativeMove(block, anchor) {
  const without = nativeReplaceExact(nativeVirtualText, block, '');
  const moved = Buffer.from(nativeReplaceExact(without, anchor, block + anchor));
  assert.notDeepEqual(moved, nativeVirtual);
  return moved;
}
// An independent inverse controls the test construction, without calling the new wrapper.
test('native reconstruction matches complete actual source and independently restores pinned original', () => {
  assert.equal(digest(original), ORIGINAL_SHA256);
  assert.deepEqual(nativeVirtual, projectScheduleSessionRegistration(readFileSync(candidateURL)));
  assert.equal(nativeVirtualText.split(NATIVE_RUN_ANCHOR + NATIVE_DISPATCH_BLOCK).length, 2);
  const withoutDispatch = nativeVirtualText.replace(NATIVE_RUN_ANCHOR + NATIVE_DISPATCH_BLOCK, NATIVE_RUN_ANCHOR);
  assert.equal(withoutDispatch.split(LINE + INVENTORY_LINE + NATIVE_DEFAULT_LINE + ANCHOR).length, 2);
  const inventoryOnly = Buffer.from(withoutDispatch.replace(
    LINE + INVENTORY_LINE + NATIVE_DEFAULT_LINE + ANCHOR, nativeInventoryAnchor));
  assert.deepEqual(inventoryOnly, approvedFuture);
  assert.deepEqual(preservedInventoryMain(inventoryOnly), original);
  assert.equal(digest(preservedInventoryMain(inventoryOnly)), ORIGINAL_SHA256);
});
test('native wrapper accepts independent complete reconstruction repeatedly without mutation', () => {
  const snapshot = Buffer.from(nativeVirtual);
  assert.deepEqual(preservedNativeStoreMain(nativeVirtual), original);
  assert.deepEqual(preservedNativeStoreMain(nativeVirtual), original);
  assert.deepEqual(nativeVirtual, snapshot);
});
const nativeMutations = [
  ['child dispatch missing', nativeMutation('    if nativeStoreChildDispatch() { return }\n', '')],
  ['child dispatch duplicate', nativeMutation('    if nativeStoreChildDispatch() { return }\n', '    if nativeStoreChildDispatch() { return }\n'.repeat(2))],
  ['child dispatch moved', nativeMove('    if nativeStoreChildDispatch() { return }\n', '    recordChecks(checks);')],
  ['child dispatch commented', nativeMutation('    if nativeStoreChildDispatch() { return }', '    // if nativeStoreChildDispatch() { return }')],
  ['child dispatch changed', nativeMutation('nativeStoreChildDispatch()', 'otherChildDispatch()')],
  ['child return changed', nativeMutation('if nativeStoreChildDispatch() { return }', 'if nativeStoreChildDispatch() { exit(0) }')],
  ['focused block missing', nativeMutation(NATIVE_DISPATCH_BLOCK, '')],
  ['focused block duplicated', nativeMutation(NATIVE_DISPATCH_BLOCK, NATIVE_DISPATCH_BLOCK.repeat(2))],
  ['focused block moved', nativeMove(NATIVE_DISPATCH_BLOCK, '    recordChecks(checks);')],
  ['focused block commented', nativeMutation(NATIVE_DISPATCH_BLOCK, NATIVE_DISPATCH_BLOCK.split('\n').map(x => x ? '// ' + x : x).join('\n'))],
  ['focused flag changed', nativeMutation('--pat-2662-native-store', '--pat-2662-native-store-other')],
  ['focused arguments changed', nativeMutation('Array(CommandLine.arguments.dropFirst())', 'Array(CommandLine.arguments)')],
  ['focused condition broadened', nativeMutation('== ["--pat-2662-native-store"]', '.contains("--pat-2662-native-store")')],
  ['focused checks changed', nativeMutation('        let checks = Checks()', '        let checks = OtherChecks()')],
  ['focused registration changed', nativeMutation('        nativeStoreChecks(checks)', '        nativeStoreChecks(Checks())')],
  ['focused summary changed', nativeMutation('        print("SETUP', '        print("OTHER')],
  ['focused exit changed', nativeMutation('        if checks.setupFailures + checks.behaviorFailures > 0 { exit(1) }', '        if checks.setupFailures + checks.behaviorFailures > 0 { exit(0) }')],
  ['focused return removed', nativeMutation('        return\n', '')],
  ['focused return changed', nativeMutation('        return\n', '        exit(0)\n')],
  ['focused whitespace changed', nativeMutation('    if Array(', '   if Array(')],
  ['default registration missing', nativeMutation(NATIVE_DEFAULT_LINE, '')],
  ['default registration duplicated', nativeMutation(NATIVE_DEFAULT_LINE, NATIVE_DEFAULT_LINE.repeat(2))],
  ['default registration moved before old checks', nativeMove(NATIVE_DEFAULT_LINE, '    recordChecks(checks);')],
  ['default registration moved before schedule', nativeMove(NATIVE_DEFAULT_LINE, LINE)],
  ['default registration moved before inventory', nativeMove(NATIVE_DEFAULT_LINE, INVENTORY_LINE)],
  ['default registration moved after summary', nativeMove(NATIVE_DEFAULT_LINE, '    if checks.setupFailures')],
  ['default registration commented', nativeMutation(NATIVE_DEFAULT_LINE, '    // nativeStoreChecks(checks)\n')],
  ['default registration arguments changed', nativeMutation(NATIVE_DEFAULT_LINE, '    nativeStoreChecks(Checks())\n')],
  ['default registration whitespace changed', nativeMutation(NATIVE_DEFAULT_LINE, '   nativeStoreChecks(checks)\n')],
  ['default summary changed', nativeMutation('    print("SETUP', '    print("OTHER')],
  ['default exit changed', nativeMutation('    if checks.setupFailures + checks.behaviorFailures > 0 { exit(1) }', '    if checks.setupFailures + checks.behaviorFailures > 0 { exit(0) }')],
  ['old assertion changed', nativeMutation('if try !value()', 'if try value()')],
  ['old helper changed', nativeMutation('let storeScope = "synthetic-store"', 'let storeScope = "other-store"')],
  ['old helper body changed', nativeMutation('return String(decoding: canonical(object), as: UTF8.self)', 'return "invented"')],
  ['old registration order changed', nativeMutation('recordChecks(checks); persistenceChecks(checks); raceChecks(checks); projectionChecks(checks)', 'persistenceChecks(checks); recordChecks(checks); raceChecks(checks); projectionChecks(checks)')],
  ['old run invocation changed', nativeMutation('MainActor.assumeIsolated { runAll() }', 'MainActor.assumeIsolated { }')],
  ['schedule removed', nativeMutation(LINE, '')],
  ['schedule duplicated', nativeMutation(LINE, LINE.repeat(2))],
  ['inventory removed', nativeMutation(INVENTORY_LINE, '')],
  ['inventory duplicated', nativeMutation(INVENTORY_LINE, INVENTORY_LINE.repeat(2))],
  ['schedule inventory reversed', nativeMutation(LINE + INVENTORY_LINE, INVENTORY_LINE + LINE)],
  ['newline before default', nativeMutation(INVENTORY_LINE + NATIVE_DEFAULT_LINE, INVENTORY_LINE + '\n' + NATIVE_DEFAULT_LINE)],
  ['newline after default', nativeMutation(NATIVE_DEFAULT_LINE + ANCHOR, NATIVE_DEFAULT_LINE + '\n' + ANCHOR)],
  ['trailing newline', Buffer.concat([nativeVirtual, Buffer.from('\n')])],
  ['trailing NUL', Buffer.concat([nativeVirtual, Buffer.from([0])])],
  ['CRLF', Buffer.from(nativeVirtualText.replaceAll('\n', '\r\n'))],
  ['BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), nativeVirtual])],
  ['invalid UTF8 prefix', Buffer.concat([Buffer.from([0xff]), nativeVirtual])],
  ['invalid UTF8 replacing old byte', Buffer.concat([nativeVirtual.subarray(0, 1), Buffer.from([0xff]), nativeVirtual.subarray(2)])],
];
for (const [name, bytes] of nativeMutations) {
  test(`native wrapper refuses ${name} after accepting its valid control`, () => {
    // A permanently refusing stub or an unrelated early refusal cannot pass any negative.
    const positiveSnapshot = Buffer.from(nativeVirtual);
    assert.deepEqual(preservedNativeStoreMain(nativeVirtual), original, 'paired valid control must succeed');
    assert.deepEqual(nativeVirtual, positiveSnapshot);
    assert.notDeepEqual(bytes, nativeVirtual, 'negative changes independently constructed bytes');
    const snapshot = Buffer.from(bytes);
    assert.throws(() => preservedNativeStoreMain(bytes), TypeError);
    assert.deepEqual(bytes, snapshot);
  });
}
for (const [name, value] of [
  ['string', nativeVirtualText], ['undefined', undefined], ['null', null],
  ['number', 1], ['object', {}], ['typed array', new Uint8Array(nativeVirtual)],
  ['oversized', Buffer.concat([nativeVirtual, Buffer.alloc(65537 - nativeVirtual.length)])],
  ['invalid UTF8', Buffer.from([0xff])],
]) {
  test(`native wrapper refuses ${name} after accepting its valid control`, () => {
    const positiveSnapshot = Buffer.from(nativeVirtual);
    assert.deepEqual(preservedNativeStoreMain(nativeVirtual), original, 'paired valid control must succeed');
    assert.deepEqual(nativeVirtual, positiveSnapshot);
    const snapshot = Buffer.isBuffer(value) || value instanceof Uint8Array ? Buffer.from(value) : value;
    assert.throws(() => preservedNativeStoreMain(value), TypeError);
    if (Buffer.isBuffer(value) || value instanceof Uint8Array) assert.deepEqual(Buffer.from(value), snapshot);
    else assert.equal(value, snapshot);
  });
}

// PAT-2668 independent session-registration controls; no Swift evaluation.
// Construction depends solely on the prior independently pinned native virtual source.
const SESSION_LINE = '    scheduleSessionChecks(checks)\n';
const sessionConstructionAnchor = LINE + INVENTORY_LINE;
assert.equal(nativeVirtualText.split(sessionConstructionAnchor).length, 2,
  'independent session construction anchor unique');
const currentVirtualText = nativeVirtualText.replace(sessionConstructionAnchor,
  LINE + SESSION_LINE + INVENTORY_LINE);
const currentVirtual = Buffer.from(currentVirtualText);
function sessionMutation(before, after) {
  return Buffer.from(nativeReplaceExact(currentVirtualText, before, after));
}
function sessionMove(anchor) {
  const without = nativeReplaceExact(currentVirtualText, SESSION_LINE, '');
  return Buffer.from(nativeReplaceExact(without, anchor, SESSION_LINE + anchor));
}
function restoredSessionMain(bytes) {
  return preservedNativeStoreMain(projectScheduleSessionRegistration(bytes));
}
function sessionValidControl() {
  const snapshot = Buffer.from(currentVirtual);
  assert.deepEqual(restoredSessionMain(currentVirtual), original,
    'paired valid session control must restore original pinned bytes');
  assert.equal(digest(original), ORIGINAL_SHA256);
  assert.deepEqual(currentVirtual, snapshot);
}
test('session independent reconstruction equals complete raw actual source', () => {
  assert.equal(digest(original), ORIGINAL_SHA256);
  assert.deepEqual(readFileSync(candidateURL), currentVirtual);
  assert.equal(currentVirtualText.includes('\r'), false, 'canonical positive is LF');
});
test('session canonical projection and composed restoration repeat byte exactly without mutation', () => {
  const snapshot = Buffer.from(currentVirtual);
  assert.deepEqual(projectScheduleSessionRegistration(currentVirtual), nativeVirtual);
  assert.deepEqual(projectScheduleSessionRegistration(currentVirtual), nativeVirtual);
  assert.deepEqual(restoredSessionMain(currentVirtual), original);
  assert.deepEqual(restoredSessionMain(currentVirtual), original);
  assert.equal(digest(restoredSessionMain(currentVirtual)), ORIGINAL_SHA256);
  assert.deepEqual(currentVirtual, snapshot);
});
const sessionMutations = [
  ['registration missing', sessionMutation(SESSION_LINE, '')],
  ['registration duplicated adjacently', sessionMutation(SESSION_LINE, SESSION_LINE.repeat(2))],
  ['registration duplicated nonadjacently', sessionMutation('    recordChecks(checks);', SESSION_LINE + '    recordChecks(checks);')],
  ['registration moved before old checks', sessionMove('    recordChecks(checks);')],
  ['registration moved before schedule', sessionMove(LINE)],
  ['registration moved after inventory', sessionMove(NATIVE_DEFAULT_LINE)],
  ['registration moved after native default', sessionMove('    print("SETUP')],
  ['registration moved after summary', sessionMove('    if checks.setupFailures')],
  ['registration commented', sessionMutation(SESSION_LINE, '    // scheduleSessionChecks(checks)\n')],
  ['registration argument changed', sessionMutation(SESSION_LINE, '    scheduleSessionChecks(Checks())\n')],
  ['registration argument whitespace changed', sessionMutation(SESSION_LINE, '    scheduleSessionChecks( checks)\n')],
  ['registration indentation changed', sessionMutation(SESSION_LINE, '   scheduleSessionChecks(checks)\n')],
  ['registration nested indentation', sessionMutation(SESSION_LINE, '        scheduleSessionChecks(checks)\n')],
  ['extra blank line before session', sessionMutation(LINE + SESSION_LINE, LINE + '\n' + SESSION_LINE)],
  ['extra blank line after session', sessionMutation(SESSION_LINE + INVENTORY_LINE, SESSION_LINE + '\n' + INVENTORY_LINE)],
  ['old assertion changed', sessionMutation('if try !value()', 'if try value()')],
  ['old helper body changed', sessionMutation('return String(decoding: canonical(object), as: UTF8.self)', 'return "invented"')],
  ['native dispatch changed', sessionMutation('    if nativeStoreChildDispatch() { return }', '    if nativeStoreChildDispatch() { exit(0) }')],
  ['native focused registration changed', sessionMutation('        nativeStoreChecks(checks)', '        nativeStoreChecks(Checks())')],
  ['native default registration changed', sessionMutation(NATIVE_DEFAULT_LINE, '    nativeStoreChecks(Checks())\n')],
  ['old registration order changed', sessionMutation('recordChecks(checks); persistenceChecks(checks); raceChecks(checks); projectionChecks(checks)', 'persistenceChecks(checks); recordChecks(checks); raceChecks(checks); projectionChecks(checks)')],
  ['schedule registration changed', sessionMutation(LINE, '    scheduleRecordChecks(Checks())\n')],
  ['inventory registration changed', sessionMutation(INVENTORY_LINE, '    inventoryProjectionChecks(Checks())\n')],
  ['extra trailing LF', Buffer.concat([currentVirtual, Buffer.from('\n')])],
  ['CRLF', Buffer.from(currentVirtualText.replaceAll('\n', '\r\n'))],
  ['BOM', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), currentVirtual])],
  ['NUL', Buffer.concat([currentVirtual, Buffer.from([0])])],
  ['invalid UTF8 prefix', Buffer.concat([Buffer.from([0xff]), currentVirtual])],
  ['invalid UTF8 replacing old byte', Buffer.concat([currentVirtual.subarray(0, 1), Buffer.from([0xff]), currentVirtual.subarray(2)])],
];
for (const [name, bytes] of sessionMutations) {
  test(`session composed guard refuses ${name} after accepting its valid control`, () => {
    sessionValidControl();
    assert.notDeepEqual(bytes, currentVirtual, 'negative changes independently constructed bytes');
    const snapshot = Buffer.from(bytes);
    assert.throws(() => restoredSessionMain(bytes), TypeError);
    assert.deepEqual(bytes, snapshot);
  });
}
for (const [name, value] of [
  ['string', currentVirtualText], ['undefined', undefined], ['null', null],
  ['number', 1], ['object', {}], ['typed array', new Uint8Array(currentVirtual)],
  ['oversized', Buffer.concat([currentVirtual, Buffer.alloc(65537 - currentVirtual.length)])],
  ['invalid UTF8', Buffer.from([0xff])],
]) {
  test(`session composed guard refuses ${name} after accepting its valid control`, () => {
    sessionValidControl();
    const snapshot = Buffer.isBuffer(value) || value instanceof Uint8Array ? Buffer.from(value) : value;
    assert.throws(() => restoredSessionMain(value), TypeError);
    if (Buffer.isBuffer(value) || value instanceof Uint8Array) assert.deepEqual(Buffer.from(value), snapshot);
    else assert.equal(value, snapshot);
  });
}
