// Independent infrastructure controls. No child process, browser or filesystem.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {EventEmitter} from 'node:events';
import {PassThrough} from 'node:stream';
import {observeChromeStartup} from './chrome-startup-diagnostics.mjs';

const paths = {run:'/owned/run', profile:'/owned/run/chrome-profile'};
const turn = () => new Promise(resolve => setImmediate(resolve));
function fakeChild(t, state = {}) {
  const child = new EventEmitter();
  child.stderr = new PassThrough({highWaterMark:1024});
  child.exitCode = null;
  child.signalCode = null;
  Object.assign(child, state);
  child.kill = () => assert.fail('observer has no kill authority');
  t.after(() => child.stderr.destroy());
  return child;
}
function read(observer) {
  const value = observer.snapshot();
  assert.ok(value !== null && typeof value === 'object', 'startup snapshot must contain observed diagnostics');
  return value;
}
function exactEvent(event, kind) {
  assert.equal(event.kind, kind);
  assert.match(event.at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  assert.equal(new Date(event.at).toISOString(), event.at);
  assert.ok(Object.keys(event).every(key => ['kind','at','code','signal','errorCode'].includes(key)));
}

test('initial live snapshot has exact detached diagnostic shape and no process authority', t => {
  const child = fakeChild(t);
  const observer = observeChromeStartup(child, paths);
  const value = read(observer);
  assert.deepEqual(Object.keys(value).sort(), ['events','paths','process','stderr','stderrBytes','stderrTruncated']);
  assert.deepEqual(value.process, {exitCode:null, signalCode:null, terminated:false});
  assert.deepEqual(value.paths, {runBytes:10, profileBytes:25});
  assert.equal(value.stderr, '');
  assert.equal(value.stderrBytes, 0);
  assert.equal(value.stderrTruncated, false);
  assert.deepEqual(value.events, []);
});

test('separately emitted stderr chunks preserve order and original byte counts', async t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  child.stderr.write(Buffer.from('first\n'));
  child.stderr.write(Buffer.from('second\n'));
  await turn();
  const value = read(observer);
  assert.equal(value.stderr, 'first\nsecond\n');
  assert.equal(value.stderrBytes, 13);
  assert.equal(value.stderrTruncated, false);
  assert.equal(child.stderr.readableLength, 0);
});

test('UTF8 split inside multibyte characters decodes without replacement or byte loss', async t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  const bytes = Buffer.from('Aé😀Z');
  for (const byte of bytes) child.stderr.write(Buffer.from([byte]));
  child.stderr.end();
  await turn();
  const value = read(observer);
  assert.equal(value.stderr, 'Aé😀Z');
  assert.equal(value.stderrBytes, 8);
  assert.equal(value.stderrTruncated, false);
});

test('exact ASCII capture limit is retained without premature truncation', async t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  child.stderr.write(Buffer.alloc(65536, 0x61));
  await turn();
  const value = read(observer);
  assert.equal(value.stderr, 'a'.repeat(65536));
  assert.equal(value.stderrBytes, 65536);
  assert.equal(value.stderrTruncated, false);
});

test('over-limit stderr keeps its bounded prefix and drains every subsequent byte', async t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  child.stderr.write(Buffer.alloc(65536, 0x61));
  await turn();
  let count = 65536;
  for (let i=0; i<128; i++) {
    const accepted = child.stderr.write(Buffer.alloc(8192, 0x62));
    count += 8192;
    await turn();
    assert.equal(accepted, true, 'draining prevents accumulated writable backpressure');
    const value = read(observer);
    assert.equal(value.stderrBytes, count, 'drained original byte counter remains monotone after cap');
    assert.equal(value.stderr, 'a'.repeat(65536));
    assert.equal(value.stderrTruncated, true);
    assert.equal(child.stderr.readableLength, 0);
    assert.equal(child.stderr.writableLength, 0);
    assert.ok(JSON.stringify(value).length < 70000, 'retained snapshot cannot grow with discarded chunks');
  }
});

test('capture cap crossing UTF8 retains a valid original prefix within 65536 encoded bytes', async t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  const original = 'a'.repeat(65535) + '😀suffix';
  const bytes = Buffer.from(original);
  child.stderr.write(bytes.subarray(0,65536));
  child.stderr.write(bytes.subarray(65536));
  child.stderr.end();
  await turn();
  const value = read(observer);
  assert.ok(original.startsWith(value.stderr));
  assert.ok(value.stderr.startsWith('a'.repeat(65535)), 'complete pre-cap characters are retained');
  assert.ok(Buffer.byteLength(value.stderr, 'utf8') <= 65536);
  assert.ok(!value.stderr.includes('\uFFFD'));
  assert.equal(value.stderrBytes, 65545);
  assert.equal(value.stderrTruncated, true);
});

test('spawn, error, exit and close retain emitted order and ISO UTC times', t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  const before = Date.now();
  child.emit('spawn');
  assert.doesNotThrow(() => child.emit('error', Object.assign(new Error('private host detail'), {code:'ENOENT'})));
  child.exitCode = 1;
  child.emit('exit', 1, null);
  child.emit('close', 1, null);
  const after = Date.now(), value = read(observer);
  assert.deepEqual(value.events.map(event => event.kind), ['spawn','error','exit','close']);
  for (const event of value.events) {
    exactEvent(event, event.kind);
    assert.ok(Date.parse(event.at) >= before && Date.parse(event.at) <= after);
  }
  assert.equal(value.events[1].errorCode, 'ENOENT');
  assert.equal(value.events[2].code, 1);
  assert.equal(value.events[2].signal, null);
  assert.equal(value.events[3].code, 1);
  assert.deepEqual(value.process, {exitCode:1, signalCode:null, terminated:true});
  assert.ok(!JSON.stringify(value).includes('private host detail'));
});

for (const code of [0,1]) test(`exit ${code} is terminated, including clean exit zero`, t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  child.exitCode = code;
  child.emit('exit', code, null);
  assert.deepEqual(read(observer).process, {exitCode:code, signalCode:null, terminated:true});
});

test('signal death with null exitCode is never classified as live', t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  child.signalCode = 'SIGKILL';
  child.emit('exit', null, 'SIGKILL');
  const value = read(observer);
  assert.deepEqual(value.process, {exitCode:null, signalCode:'SIGKILL', terminated:true});
  exactEvent(value.events[0], 'exit');
  assert.equal(value.events[0].code, null);
  assert.equal(value.events[0].signal, 'SIGKILL');
});

test('close alone with unchanged null status is terminal evidence', t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  child.emit('close', null, null);
  const value = read(observer);
  assert.equal(value.process.terminated, true);
  exactEvent(value.events[0], 'close');
});

test('exit event alone with unchanged null status is terminal evidence', t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  child.emit('exit', null, null);
  assert.equal(read(observer).process.terminated, true);
});

test('spawn failure listener is attached synchronously and ENOENT is safe', t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  const error = Object.assign(new Error('private executable and environment'), {code:'ENOENT', path:'/private/executable', env:{PRIVATE:'private'}});
  assert.doesNotThrow(() => child.emit('error', error), 'child error must not escape as unhandled EventEmitter error');
  const value = read(observer);
  assert.deepEqual(value.process, {exitCode:null, signalCode:null, terminated:true});
  assert.equal(value.events.length, 1);
  exactEvent(value.events[0], 'error');
  assert.equal(value.events[0].errorCode, 'ENOENT');
  assert.ok(!JSON.stringify(value).includes('private'));
});

for (const code of ['PRIVATE_HOST_DETAIL', undefined, {private:'host detail'}]) {
  test(`unknown spawn error code type ${typeof code} becomes closed other identifier`, t => {
    const child = fakeChild(t), observer = observeChromeStartup(child, paths);
    assert.doesNotThrow(() => child.emit('error', Object.assign(new Error('PRIVATE_ERROR_MESSAGE'), {code})));
    const value = read(observer);
    assert.equal(value.events[0].errorCode, 'other');
    assert.equal(value.process.terminated, true);
    assert.ok(!JSON.stringify(value).includes('PRIVATE'));
    assert.ok(!JSON.stringify(value).includes('host detail'));
  });
}

for (const state of [{exitCode:0}, {exitCode:1}, {signalCode:'SIGTERM'}]) {
  test(`already terminated child at observer attachment: ${JSON.stringify(state)}`, t => {
    const child = fakeChild(t, state), observer = observeChromeStartup(child, paths);
    assert.deepEqual(read(observer).process, {exitCode:state.exitCode ?? null, signalCode:state.signalCode ?? null, terminated:true});
  });
}

test('UTF8 owned paths report byte lengths only and snapshot does not retain caller paths', t => {
  const child = fakeChild(t), owned = {run:'/é😀', profile:'/é😀/p'};
  const observer = observeChromeStartup(child, owned);
  owned.run = '/changed';
  owned.profile = '/also-changed';
  const value = read(observer);
  assert.deepEqual(value.paths, {runBytes:7, profileBytes:9});
  assert.ok(!JSON.stringify(value).includes('/é'));
  assert.ok(!JSON.stringify(value).includes('/changed'));
});

test('snapshots detach nested events, paths and process from caller mutation and later observations', async t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  child.emit('spawn');
  child.stderr.write(Buffer.from('first'));
  await turn();
  const first = read(observer), preserved = structuredClone(first);
  const mutable = read(observer);
  assert.notStrictEqual(first, mutable);
  assert.notStrictEqual(first.events, mutable.events);
  assert.notStrictEqual(first.events[0], mutable.events[0]);
  assert.notStrictEqual(first.paths, mutable.paths);
  assert.notStrictEqual(first.process, mutable.process);
  // Frozen values may reject writes; mutable values must still be detached.
  try { mutable.events[0].kind = 'private'; } catch {}
  try { mutable.events.push({kind:'private'}); } catch {}
  try { mutable.paths.runBytes = -1; } catch {}
  try { mutable.process.terminated = true; } catch {}
  child.stderr.write(Buffer.from('second'));
  child.exitCode = 0;
  child.emit('exit', 0, null);
  await turn();
  assert.deepEqual(first, preserved, 'later observation cannot mutate a previously returned snapshot');
  const latest = read(observer);
  assert.equal(latest.stderr, 'firstsecond');
  assert.equal(latest.stderrBytes, 11);
  assert.deepEqual(latest.events.map(event => event.kind), ['spawn','exit']);
  assert.deepEqual(latest.paths, {runBytes:10, profileBytes:25});
  assert.deepEqual(latest.process, {exitCode:0, signalCode:null, terminated:true});
});

test('lifecycle retention is bounded to 64 ordered entries while terminal state and draining continue', async t => {
  const child = fakeChild(t), observer = observeChromeStartup(child, paths);
  for (let i=0; i<96; i++) child.emit('exit', i, null);
  child.signalCode = 'SIGTERM';
  child.emit('close', null, 'SIGTERM');
  child.stderr.write(Buffer.from('after lifecycle cap'));
  await turn();
  const value = read(observer);
  assert.equal(value.events.length, 64);
  let previous = -1;
  for (const event of value.events) {
    exactEvent(event, event.kind);
    assert.ok(['exit','close'].includes(event.kind));
    if (event.kind === 'exit') {
      assert.ok(Number.isInteger(event.code) && event.code > previous && event.code < 96);
      previous = event.code;
    } else assert.equal(event.signal, 'SIGTERM');
  }
  assert.equal(value.process.terminated, true);
  assert.equal(value.process.signalCode, 'SIGTERM');
  assert.equal(value.stderr, 'after lifecycle cap');
  assert.equal(value.stderrBytes, 19);
  assert.equal(child.stderr.readableLength, 0);
});
