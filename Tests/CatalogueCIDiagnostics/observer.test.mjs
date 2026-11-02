import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { performance } from 'node:perf_hooks';
import { observeCatalogue } from '../../scripts/catalogue-ci-observer.mjs';

// Public local fixtures only. No suite, guest, OS sampler, credentials or network.
// Retain the generated fixtures below .build for parent inspection.
const root = fileURLToPath(new URL('../../.build/catalogue-ci-diagnostics/', import.meta.url));
mkdirSync(root, { recursive: true });
const directory = mkdtempSync(join(root, 'phase-a-'));
const bodies = {
  pass: "process.stdout.write('PUBLIC-PASS\\n'); process.stderr.write('PUBLIC-STDERR\\n');",
  fail: "process.stderr.write('PUBLIC-FAIL\\n'); process.exitCode = 7;",
  signal: "process.kill(process.pid, 'SIGTERM');",
  hang: "process.on('SIGTERM', () => {}); setInterval(() => {}, 25);",
  lateSuccess: "process.on('SIGTERM', () => process.exit(0)); setInterval(() => {}, 25);",
  noisyHang: "process.on('SIGTERM', () => {}); setInterval(() => { process.stdout.write('PUBLIC-TICK\\n'); }, 5);",
  // > pipe capacity on both streams; respect backpressure so completion proves
  // draining continues even after the observer's retained output has filled.
  flood: `import { once } from 'node:events';
    for (let i = 0; i < 256; i++) {
      if (!process.stdout.write('x'.repeat(4096))) await once(process.stdout, 'drain');
      if (!process.stderr.write('y'.repeat(4096))) await once(process.stderr, 'drain');
    }
    process.stdout.write('PUBLIC-FLOOD-END\\n');`,
};

function fixture(name) {
  const path = join(directory, `${name}-${sequence++}.mjs`);
  const pidPath = `${path}.pid`;
  writeFileSync(path, `import { writeFileSync } from 'node:fs';
    writeFileSync(${JSON.stringify(pidPath)}, String(process.pid));
    process.stdout.write(JSON.stringify({node:process.version,pid:process.pid})+'\\n');
    // Harness safety fuse is much later than tested observer deadlines.
    setTimeout(() => process.exit(91), 6000).unref();
    ${bodies[name]}\n`, { flag: 'wx' });
  return { path, pidPath };
}
let sequence = 0;
const alive = pid => {
  try { process.kill(pid, 0); return true; }
  catch (error) { if (error.code === 'ESRCH') return false; throw error; }
};
function stopped(pid) {
  assert.equal(alive(pid), false, `owned child ${pid} must already be reaped`);
}

async function run(t, name, overrides = {}) {
  const f = fixture(name);
  // Cleanup only the fixture PID this particular test created, if a broken
  // future observer leaves it alive; the fixture also has its own safety fuse.
  t.after(() => {
    if (existsSync(f.pidPath)) {
      const pid = Number(readFileSync(f.pidPath, 'utf8'));
      if (Number.isSafeInteger(pid) && pid > 0 && alive(pid)) process.kill(pid, 'SIGKILL');
    }
  });
  const calls = [];
  const sample = async ({ pid, signal }) => {
    calls.push(pid);
    assert.equal(pid, Number(readFileSync(f.pidPath, 'utf8')));
    assert.equal(alive(pid), true, 'sample targets the still-live owned child');
    assert.ok(signal instanceof AbortSignal);
    return { stdout: 'PUBLIC-INJECTED-SAMPLE', stderr: '' };
  };
  const before = performance.now();
  let report;
  try {
    report = await observeCatalogue({ testing: {
      fixturePath: f.path, deadlineMs: 600, outputLimitBytes: 4096,
      sampleTimeoutMs: 100, killGraceMs: 50, sample, ...overrides,
    } });
  } catch (error) {
    assert.fail(`${name}: expected an observed child report; got ${error.message}`);
  }
  return { report, f, calls, before, after: performance.now() };
}

function provenance({ report: r, f, before, after }) {
  assert.equal(r.mode, 'test-only');
  assert.equal(r.originalFullCIPassed, false, 'diagnostic success never proves original CI');
  assert.equal(r.child.nodeVersion, process.version);
  assert.equal(r.child.execPath, process.execPath);
  assert.deepEqual(r.child.args, [f.path]);
  assert.equal(r.child.pid, Number(readFileSync(f.pidPath, 'utf8')));
  assert.notEqual(r.child.pid, process.pid);
  const { startMs, spawnMs, lastOutputMs, endMs } = r.timing;
  for (const n of [startMs, spawnMs, lastOutputMs, endMs]) assert.ok(Number.isFinite(n));
  assert.ok(before <= startMs && startMs <= spawnMs && spawnMs <= lastOutputMs);
  assert.ok(lastOutputMs <= endMs && endMs <= after);
  assert.equal(r.termination.closed, true);
  stopped(r.child.pid);
}

test('fixture controls really spawn public Node pass/fail/hang programs', () => {
  for (const [name, code] of [['pass', 0], ['fail', 7]]) {
    const f = fixture(name);
    const r = spawnSync(process.execPath, [f.path], { encoding: 'utf8', timeout: 1500 });
    assert.equal(r.error, undefined);
    assert.equal(r.status, code);
    const identity = JSON.parse(r.stdout.split('\n')[0]);
    assert.equal(identity.node, process.version);
    assert.equal(identity.pid, r.pid);
    stopped(r.pid);
  }
  const f = fixture('hang');
  const r = spawnSync(process.execPath, [f.path], { timeout: 200, killSignal: 'SIGKILL' });
  assert.equal(r.error?.code, 'ETIMEDOUT');
  assert.equal(r.signal, 'SIGKILL');
  stopped(r.pid);
});

test('success requires real zero exit and captures actual identity/monotonic timing', async t => {
  const x = await run(t, 'pass');
  provenance(x);
  assert.equal(x.report.ok, true);
  assert.equal(x.report.exitCode, 0);
  assert.equal(x.report.child.exitCode, 0);
  assert.equal(x.report.child.signal, null);
  assert.equal(x.report.deadlineExceeded, false);
  assert.equal(x.report.termination.requested, false);
  assert.match(x.report.output.stdout, /PUBLIC-PASS/);
  assert.match(x.report.output.stderr, /PUBLIC-STDERR/);
  assert.equal(x.report.output.truncated, false);
  assert.equal(x.report.sample.status, 'not-needed');
  assert.deepEqual(x.calls, []);
});

test('ordinary child exit 7 remains exit 7, with no sampling or false success', async t => {
  const x = await run(t, 'fail');
  provenance(x);
  assert.equal(x.report.ok, false);
  assert.equal(x.report.exitCode, 7);
  assert.equal(x.report.child.exitCode, 7);
  assert.equal(x.report.deadlineExceeded, false);
  assert.equal(x.report.termination.requested, false);
  assert.match(x.report.output.stderr, /PUBLIC-FAIL/);
  assert.equal(x.report.sample.status, 'not-needed');
  assert.deepEqual(x.calls, []);
});

test('signal death remains non-success, not a null-exit success', async t => {
  const x = await run(t, 'signal');
  provenance(x);
  assert.equal(x.report.ok, false);
  assert.ok(Number.isInteger(x.report.exitCode) && x.report.exitCode > 0);
  assert.equal(x.report.child.exitCode, null);
  assert.equal(x.report.child.signal, 'SIGTERM');
  assert.deepEqual(x.calls, []);
});

test('real deadline samples only owned live child, escalates and leaves sibling alive', async t => {
  const siblingFixture = fixture('hang');
  const sibling = spawn(process.execPath, [siblingFixture.path], { stdio: 'ignore' });
  const siblingClosed = new Promise(resolve => sibling.once('close', resolve));
  try {
    const x = await run(t, 'hang');
    provenance(x);
    assert.equal(x.report.ok, false);
    assert.equal(x.report.exitCode, 124);
    assert.equal(x.report.deadlineExceeded, true);
    assert.ok(x.after - x.before >= 600 && x.after - x.before < 2500);
    assert.equal(x.report.termination.requested, true);
    assert.equal(x.report.child.signal, 'SIGKILL');
    assert.deepEqual(x.calls, [x.report.child.pid]);
    assert.equal(x.report.sample.pid, x.report.child.pid);
    assert.equal(x.report.sample.provenance, 'test-injected');
    assert.equal(x.report.sample.status, 'captured');
    assert.equal(x.report.sample.stdout, 'PUBLIC-INJECTED-SAMPLE');
    assert.equal(alive(sibling.pid), true, 'unrelated test sibling must remain alive');
  } finally {
    sibling.kill('SIGKILL');
    await siblingClosed;
  }
});

test('a zero exit after deadline still reports deadline failure', async t => {
  const x = await run(t, 'lateSuccess');
  provenance(x);
  assert.equal(x.report.child.exitCode, 0);
  assert.equal(x.report.deadlineExceeded, true);
  assert.equal(x.report.ok, false);
  assert.equal(x.report.exitCode, 124);
});

test('continuous output cannot renew the absolute deadline', async t => {
  const x = await run(t, 'noisyHang');
  provenance(x);
  assert.equal(x.report.deadlineExceeded, true);
  assert.equal(x.report.exitCode, 124);
  assert.ok(x.after - x.before < 2500);
  assert.match(x.report.output.stdout, /PUBLIC-TICK/);
});

test('both full pipes drain after capture cap without deadlock or output growth', async t => {
  const x = await run(t, 'flood', { deadlineMs: 2000, outputLimitBytes: 1024 });
  provenance(x);
  const o = x.report.output;
  assert.equal(x.report.ok, true);
  assert.equal(x.report.deadlineExceeded, false);
  assert.equal(o.truncated, true);
  assert.ok(Buffer.byteLength(o.stdout) + Buffer.byteLength(o.stderr) <= 1024);
  assert.ok(o.stdoutBytes >= 1048576 && o.stderrBytes >= 1048576);
  assert.deepEqual(x.calls, []);
});

test('sample rejection is explicit and cannot prevent termination or become success', async t => {
  const x = await run(t, 'hang', { sample: async () => { throw new Error('PUBLIC-SAMPLE-FAIL'); } });
  provenance(x);
  assert.equal(x.report.sample.provenance, 'test-injected');
  assert.equal(x.report.sample.status, 'failed');
  assert.equal(x.report.ok, false);
  assert.equal(x.report.exitCode, 124);
});

test('hung injected sampler is aborted at its own deadline and child is reaped', async t => {
  let signal;
  const x = await run(t, 'hang', { sample: async request => {
    signal = request.signal;
    return new Promise(() => {});
  } });
  provenance(x);
  assert.equal(signal.aborted, true);
  assert.equal(x.report.sample.status, 'timed-out');
  assert.equal(x.report.sample.provenance, 'test-injected');
  assert.equal(x.report.exitCode, 124);
  assert.ok(x.after - x.before < 2500);
});

test('injected sample capture has a separate combined UTF-8 byte ceiling', async t => {
  const x = await run(t, 'hang', { outputLimitBytes: 1024, sample: async () => ({
    stdout: '€'.repeat(10000), stderr: 'PUBLIC-SAMPLE-STDERR'.repeat(10000),
  }) });
  provenance(x);
  assert.equal(x.report.sample.provenance, 'test-injected');
  assert.equal(x.report.sample.truncated, true);
  assert.ok(Buffer.byteLength(x.report.sample.stdout) + Buffer.byteLength(x.report.sample.stderr) <= 1024);
  assert.equal(x.report.ok, false);
});

for (const [label, patch] of [
  ['zero deadline', { deadlineMs: 0 }],
  ['infinite deadline', { deadlineMs: Infinity }],
  ['fractional limit', { outputLimitBytes: 100.5 }],
  ['unbounded capture', { outputLimitBytes: 65537 }],
  ['zero sample timeout', { sampleTimeoutMs: 0 }],
  ['unbounded kill grace', { killGraceMs: 1001 }],
  ['arbitrary executable', { executable: '/bin/echo' }],
  ['unrelated PID', { pid: process.pid }],
]) {
  test(`rejects ${label} before creating a child`, async () => {
    const f = fixture('pass');
    await assert.rejects(observeCatalogue({ testing: {
      fixturePath: f.path, deadlineMs: 600, outputLimitBytes: 1024,
      sampleTimeoutMs: 100, killGraceMs: 50, sample: async () => ({}), ...patch,
    } }), error => {
      assert.equal(error.code, 'INVALID_OPTIONS', `expected option refusal, got ${error.message}`);
      return true;
    });
    assert.equal(existsSync(f.pidPath), false);
  });
}
