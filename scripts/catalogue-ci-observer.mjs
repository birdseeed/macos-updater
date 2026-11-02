import { spawn } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { isAbsolute, resolve } from 'node:path';
import { StringDecoder } from 'node:string_decoder';
import { release, version } from 'node:os';

const cwd = fileURLToPath(new URL('../', import.meta.url));
const defaults = Object.freeze({
  deadlineMs: 60000, outputLimitBytes: 65536, sampleTimeoutMs: 5000, killGraceMs: 250,
});
const limits = { deadlineMs: [100, 60000], outputLimitBytes: [64, 65536],
  sampleTimeoutMs: [25, 5000], killGraceMs: [10, 1000] };

function invalid() {
  throw Object.assign(new Error('Invalid observer options'), { code: 'INVALID_OPTIONS' });
}

function record(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
      || ![Object.prototype, null].includes(Object.getPrototypeOf(value))) invalid();
  for (const key of Reflect.ownKeys(value)) {
    if (!keys.includes(key) || !('value' in Object.getOwnPropertyDescriptor(value, key))) invalid();
  }
}

function optionsFor(options) {
  record(options, ['testing']);
  if (!Object.hasOwn(options, 'testing')) return { ...defaults, mode: 'production' };
  const t = options.testing;
  record(t, ['fixturePath', 'sample', ...Object.keys(limits)]);
  if (typeof t.fixturePath !== 'string' || !isAbsolute(t.fixturePath)
      || !t.fixturePath.endsWith('.mjs') || t.fixturePath.includes('\0')
      || typeof t.sample !== 'function') invalid();
  for (const [key, [min, max]] of Object.entries(limits)) {
    if (!Number.isInteger(t[key]) || t[key] < min || t[key] > max) invalid();
  }
  return { ...t, mode: 'test-only' };
}

// Two fixed buffers, one shared retained-byte budget; counting/draining never stops.
// Decode only at the end. Invalid UTF-8 replacement and partial characters must
// not expand the returned strings beyond the advertised UTF-8 byte ceiling.
function capture(limit) {
  const buffers = { stdout: Buffer.alloc(limit), stderr: Buffer.alloc(limit) };
  const lengths = { stdout: 0, stderr: 0 };
  const counts = { stdout: 0, stderr: 0 };
  let retained = 0;
  function add(stream, chunk) {
    const bytes = typeof chunk === 'string' ? Buffer.byteLength(chunk) : chunk.length;
    counts[stream] = Math.min(Number.MAX_SAFE_INTEGER, counts[stream] + bytes);
    const available = limit - retained;
    const data = typeof chunk === 'string' ? Buffer.from(chunk.slice(0, available)) : chunk;
    const size = Math.min(available, data.length);
    data.copy(buffers[stream], lengths[stream], 0, size);
    lengths[stream] += size;
    retained += size;
  }
  function result() {
    let remaining = limit;
    let truncated = counts.stdout + counts.stderr > limit;
    const output = {};
    for (const stream of ['stdout', 'stderr']) {
      const repaired = Buffer.from(buffers[stream].subarray(0, lengths[stream]).toString('utf8'));
      output[stream] = new StringDecoder('utf8').write(repaired.subarray(0, remaining));
      if (Buffer.byteLength(output[stream]) < repaired.length) truncated = true;
      remaining -= Buffer.byteLength(output[stream]);
    }
    return { ...output, stdoutBytes: counts.stdout, stderrBytes: counts.stderr,
      truncated };
  }
  return { add, result };
}

function timer(ms, value) {
  let id;
  return { promise: new Promise(resolve => { id = setTimeout(resolve, Math.max(0, ms), value); }),
    cancel: () => clearTimeout(id) };
}

// Never signal a numeric PID: retain the spawned handle and consult its exit
// state immediately before every signal. There are no process-group operations.
function own(executable, args, output, onOutput = () => {}) {
  const child = spawn(executable, args, {
    cwd, env: {}, shell: false, stdio: ['ignore', 'pipe', 'pipe'],
  });
  const state = { child, spawned: false, exited: false, closed: false,
    error: false, pipesComplete: true, requested: false, escalated: false };
  state.done = new Promise(resolveDone => {
    child.once('close', () => { state.closed = true; resolveDone(); });
  });
  state.exit = new Promise(resolveExit => {
    child.once('exit', () => { state.exited = true; resolveExit(); });
    child.on('error', () => {
      state.error = true;
      if (!state.spawned) { state.exited = true; resolveExit(); }
    });
  });
  child.once('spawn', () => { state.spawned = true; state.spawnMs = performance.now(); });
  for (const stream of ['stdout', 'stderr']) {
    child[stream].on('data', chunk => { onOutput(); output.add(stream, chunk); });
    child[stream].on('error', () => { state.error = true; state.pipesComplete = false; });
  }
  state.live = () => !state.exited && !state.closed && Number.isInteger(child.pid)
    && child.exitCode === null && child.signalCode === null;
  state.signal = signal => {
    if (!state.live()) return;
    state.requested = true;
    if (signal === 'SIGKILL') state.escalated = true;
    try { child.kill(signal); } catch { state.error = true; }
  };
  return state;
}

async function stop(state, graceMs) {
  if (state.closed) return;
  if (state.live()) {
    state.signal('SIGTERM');
    const grace = timer(graceMs);
    try { await Promise.race([state.exit, grace.promise]); }
    finally { grace.cancel(); }
    state.signal('SIGKILL');
  }
  // Reap our direct child before returning. SIGKILL/OS failure cannot honestly
  // become a successful bounded cleanup; the outer CI timeout remains a backstop.
  await state.exit;
  const drain = timer(graceMs);
  try { await Promise.race([state.done, drain.promise]); }
  finally { drain.cancel(); }
  if (!state.closed) {
    // Descendants can inherit pipes. Close our ends, label evidence incomplete,
    // and claim neither discovery nor termination of that process tree.
    state.pipesComplete = false;
    state.child.stdout.destroy();
    state.child.stderr.destroy();
    await state.done;
  }
}

async function sampleOwned(target, config, cancelled) {
  const provenance = config.mode === 'test-only' ? 'test-injected' : 'os-sample';
  const base = { provenance, pid: target.child.pid, startMs: performance.now() };
  const output = capture(config.outputLimitBytes);
  const controller = new AbortController();
  const bound = timer(config.sampleTimeoutMs, 'timed-out');
  let sampler;
  let status = 'failed';
  try {
    // No await between the live check and invoking the owned-child sampler.
    if (!target.live()) status = 'child-exited';
    else if (config.mode === 'test-only') {
      const injected = Promise.resolve().then(() => {
        if (!target.live()) return 'child-exited';
        return config.sample({ pid: target.child.pid, signal: controller.signal });
      }).then(value => {
        if (value === 'child-exited') return value;
        if (!value || typeof value.stdout !== 'string' || typeof value.stderr !== 'string') return 'failed';
        if (!controller.signal.aborted) {
          output.add('stdout', value.stdout);
          output.add('stderr', value.stderr);
        }
        return 'captured';
      }, () => 'failed');
      status = await Promise.race([injected, bound.promise,
        target.exit.then(() => 'child-exited'), cancelled]);
    } else {
      // -file avoids sample's default unbounded /tmp report; only bounded pipes
      // are retained. No name matching, -wait, shell, sudo or external PID input.
      sampler = own('/usr/bin/sample', [String(target.child.pid), '1', '-mayDie',
        '-file', '/dev/stdout'], output);
      status = await Promise.race([
        sampler.done.then(() => !sampler.error && sampler.child.exitCode === 0
          && sampler.child.signalCode === null ? 'captured' : 'failed'),
        bound.promise, target.exit.then(() => 'child-exited'), cancelled,
      ]);
    }
  } catch {
    status = 'failed';
  } finally {
    bound.cancel();
    controller.abort();
    if (sampler) await stop(sampler, config.killGraceMs);
  }
  const captured = output.result();
  if (status === 'captured' && captured.stdoutBytes === 0 && captured.stderrBytes === 0) status = 'empty';
  return { ...base, status, ...captured, endMs: performance.now(),
    ...(sampler ? { samplerPid: sampler.child.pid ?? null,
      execPath: '/usr/bin/sample', spawnMs: sampler.spawnMs ?? null,
      exitCode: sampler.child.exitCode, signal: sampler.child.signalCode,
      closed: sampler.closed, pipesComplete: sampler.pipesComplete } : {}) };
}

/**
 * Production: zero options, fixed Node catalogue child and fixed bounds.
 * Explicit test-only API: { testing: { fixturePath, deadlineMs,
 * outputLimitBytes, sampleTimeoutMs, killGraceMs, sample({pid, signal}) } }.
 * Injected observations never represent OS samples or original full CI proof.
 */
export async function observeCatalogue(options = {}) {
  const config = optionsFor(options); // All validation precedes spawn.
  const startMs = performance.now();
  const args = config.mode === 'test-only' ? [config.fixturePath]
    : ['--test', 'services/catalogue/tests/catalogue-protocol.test.mjs'];
  const output = capture(config.outputLimitBytes);
  let lastOutputMs = null;
  let owned;
  let deadlineExceeded = false;
  let interrupted = null;
  let observerError = false;
  let cancel;
  const cancelled = new Promise(resolveCancel => { cancel = resolveCancel; });
  const interrupt = signal => { interrupted ??= signal; cancel('interrupted'); };
  const onTerm = () => interrupt('SIGTERM');
  const onInt = () => interrupt('SIGINT');
  const sampleProvenance = config.mode === 'test-only' ? 'test-injected' : 'os-sample';
  let sample = { status: 'not-needed', provenance: sampleProvenance, pid: null,
    stdout: '', stderr: '', stdoutBytes: 0, stderrBytes: 0, truncated: false };
  const deadline = timer(config.deadlineMs, 'deadline');
  if (config.mode === 'production') {
    process.on('SIGTERM', onTerm);
    process.on('SIGINT', onInt);
  }
  try {
    owned = own(process.execPath, args, output, () => { lastOutputMs = performance.now(); });
    const reason = await Promise.race([owned.done.then(() => 'closed'), deadline.promise, cancelled]);
    deadlineExceeded = reason === 'deadline' || performance.now() - startMs >= config.deadlineMs;
    if (deadlineExceeded && !interrupted) sample = await sampleOwned(owned, config, cancelled);
  } catch {
    observerError = true;
  } finally {
    deadline.cancel();
    try { if (owned) await stop(owned, config.killGraceMs); }
    finally {
      if (config.mode === 'production') {
        process.removeListener('SIGTERM', onTerm);
        process.removeListener('SIGINT', onInt);
      }
    }
  }
  const child = owned?.child;
  const ok = !observerError && !interrupted && !deadlineExceeded && owned?.closed
    && owned.pipesComplete && !owned.error && child.exitCode === 0 && child.signalCode === null;
  const exitCode = deadlineExceeded ? 124 : interrupted === 'SIGINT' ? 130
    : interrupted === 'SIGTERM' ? 143 : ok ? 0 : child?.exitCode > 0 ? child.exitCode : 1;
  return {
    mode: config.mode, ok: Boolean(ok), exitCode, originalFullCIPassed: false,
    deadlineExceeded, interrupted, observerError: observerError || Boolean(owned?.error),
    host: { platform: process.platform, release: release(), version: version() },
    child: { nodeVersion: process.version, execPath: process.execPath, args, cwd,
      pid: child?.pid ?? null, exitCode: child?.exitCode ?? null, signal: child?.signalCode ?? null },
    timing: { startMs, spawnMs: owned?.spawnMs ?? null, lastOutputMs, endMs: performance.now() },
    limits: Object.fromEntries(Object.keys(limits).map(key => [key, config[key]])),
    termination: { requested: owned?.requested ?? false, escalated: owned?.escalated ?? false,
      closed: owned?.closed ?? false, pipesComplete: owned?.pipesComplete ?? false,
      scope: 'direct-child-only', processTreeCleanupClaimed: false },
    output: output.result(), sample,
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 2) {
    console.error(JSON.stringify({ error: 'INVALID_OPTIONS', originalFullCIPassed: false }));
    process.exitCode = 2;
  } else {
    try {
      const report = await observeCatalogue();
      // JSON frames modern commands; hash escaping also neutralises legacy
      // ##[commands] recognised anywhere in a runner log line. Decoding restores text.
      console.log(JSON.stringify(report).replaceAll('#', '\\u0023'));
      process.exitCode = report.exitCode;
    } catch {
      console.error(JSON.stringify({ error: 'OBSERVER_FAILED', originalFullCIPassed: false }));
      process.exitCode = 1;
    }
  }
}
