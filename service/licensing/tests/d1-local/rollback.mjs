// Actual Wrangler/workerd D1 binding; only the test client talks to loopback.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';

const service = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const root = realpathSync(resolve(service, '../..'));
const build = resolve(root, '.build');
mkdirSync(build, { recursive: true });
assert.equal(realpathSync(build), build, 'refuse symlinked .build');
const run = mkdtempSync(resolve(build, 'licensing-d1-'));
const source = JSON.parse(readFileSync(resolve(service, 'wrangler.jsonc'), 'utf8'));
assert.deepEqual(Object.keys(source).sort(), ['$schema', 'compatibility_date', 'd1_databases', 'main', 'name', 'preview_urls', 'vars', 'workers_dev'].sort(), 'fixture config must contain only the frozen local allowlist');
assert.equal(source.main, 'src/index.ts');
assert.equal(source.compatibility_date, '2026-10-11');
assert.deepEqual(source.vars, { ENVIRONMENT: 'local-fixture', FIXTURE_MARKER: 'PAT-2639-local-only', PROVIDER_MODE: 'fake' });
assert.deepEqual(source.d1_databases, [{ binding: 'FIXTURE_DB', database_name: 'licensing-local-fixture', database_id: '00000000-0000-0000-0000-000000000000', remote: false }]);
assert.equal(source.name, 'patched-licensing-local-fixture');
assert.equal(source.workers_dev, false);
assert.equal(source.preview_urls, false);
assert.equal(source.account_id, undefined);
assert.equal(source.routes, undefined);
assert.equal(source.env, undefined);
const config = resolve(run, 'wrangler.json');
writeFileSync(config, JSON.stringify({ ...source, main: resolve(service, 'src/index.ts') }));
const cli = resolve(service, 'node_modules/wrangler/bin/wrangler.js');
const env = { PATH: process.env.PATH, TMPDIR: run, XDG_CONFIG_HOME: resolve(run, 'config'), WRANGLER_SEND_METRICS: 'false', CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV: 'false', CI: 'true', NO_COLOR: '1' };
const common = ['--config', config, '--persist-to', resolve(run, 'state')];
function d1(args) {
  const result = spawnSync(process.execPath, [cli, 'd1', 'execute', 'FIXTURE_DB', '--local', ...common, ...args], { cwd: run, env, encoding: 'utf8', timeout: 30_000 });
  assert.equal(result.status, 0, `local D1 command failed: ${result.stderr}\n${result.stdout}`);
  return result.stdout;
}
function snapshot() {
  const result = JSON.parse(d1(['--command', 'SELECT * FROM t0_guard ORDER BY id; SELECT * FROM t0_events ORDER BY id;', '--json']));
  return result.map(item => item.results);
}
d1(['--file', resolve(service, 'tests/d1-local/fixture.sql')]);
const baseline = [[{ id: 1, revision: 0 }], [{ id: 'seed', detail: 'unchanged baseline' }]];
assert.deepEqual(snapshot(), baseline);
let output = '';
const child = spawn(process.execPath, [cli, 'dev', '--local', ...common, '--ip', '127.0.0.1', '--port', '0', '--inspector-port', '0', '--show-interactive-dev-session=false'], { cwd: run, env, stdio: ['ignore', 'pipe', 'pipe'] });
child.stdout.on('data', b => { output += b; }); child.stderr.on('data', b => { output += b; });
try {
  const deadline = Date.now() + 30_000;
  let origin;
  while (Date.now() < deadline) {
    origin = output.match(/Ready on (http:\/\/127\.0\.0\.1:\d+)/)?.[1];
    if (origin) break;
    assert.equal(child.exitCode, null, `local worker exited: ${output}`);
    await new Promise(r => setTimeout(r, 100));
  }
  assert.ok(origin, `local worker did not become ready: ${output}`);
  const post = path => fetch(origin + path, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(5000) });
  // A deliberate dependent-write failure must leave guard and event writes absent.
  const failed = await post('/__fixture/rollback');
  assert.equal(failed.status, 409, 'failed D1 batch must report fixture rollback');
  assert.deepEqual(await failed.json(), { fixture: 'PAT-2639-local-only', outcome: 'rolled-back' });
  assert.deepEqual(snapshot(), baseline, 'failed batch must roll back every preceding write');
  // Positive control proves that the test reaches a real mutable D1 binding.
  const committed = await post('/__fixture/commit');
  assert.equal(committed.status, 200);
  assert.deepEqual(await committed.json(), { fixture: 'PAT-2639-local-only', outcome: 'committed' });
  const after = [[{ id: 1, revision: 1 }], [{ id: 'committed', detail: 'positive control' }, { id: 'seed', detail: 'unchanged baseline' }]];
  assert.deepEqual(snapshot(), after, 'successful batch must durably write both tables');
  const failedAgain = await post('/__fixture/rollback');
  assert.equal(failedAgain.status, 409);
  assert.deepEqual(snapshot(), after, 'later rollback must preserve a previous commit');
  console.log(`PASS actual local D1 rollback, positive control and preserved commit; disposable state: ${run}`);
} finally {
  child.kill('SIGTERM');
  await Promise.race([once(child, 'exit'), new Promise(r => setTimeout(r, 3000))]);
  if (child.exitCode === null) child.kill('SIGKILL');
  writeFileSync(resolve(run, 'wrangler.log'), output);
}
