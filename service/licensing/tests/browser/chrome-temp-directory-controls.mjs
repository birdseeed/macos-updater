// Independent filesystem controls. No browser, child process, server or D1.
// Independent fixtures live only in this worktree's exclusive .build root.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdir, mkdtemp, realpath, lstat, writeFile, readFile, symlink,
  readlink, chmod, rename, rm} from 'node:fs/promises';
import {dirname, resolve, join, basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createChromeTemporaryDirectory} from './chrome-temporary-directory.mjs';
import {createChromeLaunchEnvironment} from './chrome-launch-environment.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
const ended = Object.freeze({exitCode: 0, signalCode: null});
const killed = Object.freeze({exitCode: null, signalCode: 'SIGKILL'});
const live = Object.freeze({exitCode: null, signalCode: null});
const absent = async path => assert.rejects(lstat(path), {code: 'ENOENT'});
const marker = async path => assert.equal(await readFile(path, 'utf8'), 'retain me');

async function fixture(t) {
  const build = join(root, '.build');
  await mkdir(build, {recursive: true});
  const base = await mkdtemp(join(build, 'chrome-temp-controls-'));
  // Deliberately longer than the observed 79-byte Linux run, without changing it.
  const run = join(base, 'retained-long-run-' + 'x'.repeat(96));
  const profile = join(run, 'chrome-profile');
  const sibling = join(base, 'unrelated-owned-sibling');
  await mkdir(profile, {recursive: true});
  await mkdir(sibling);
  for (const path of [join(run, 'run-marker'), join(profile, 'profile-marker'), join(sibling, 'sibling-marker')]) {
    await writeFile(path, 'retain me');
  }
  t.after(async () => { await rm(base, {recursive: true, force: true}); });
  return {base, run: await realpath(run), profile, sibling};
}

async function allocated(t, run) {
  const owner = await createChromeTemporaryDirectory(run);
  // This assertion is the intended Phase A geometry red, before any mutation.
  assert.ok(Buffer.byteLength(owner.path, 'utf8') <= 48, 'Chrome temporary directory must be <=48 UTF8 bytes even with a long retained run');
  assert.notEqual(owner.path, run, 'run is never cleanup authority');
  assert.equal(dirname(owner.path), await realpath('/tmp'));
  assert.match(basename(owner.path), /^pat2657-[A-Za-z0-9]+$/);
  assert.equal(await realpath(owner.path), owner.path);
  const stat = await lstat(owner.path);
  assert.ok(stat.isDirectory() && !stat.isSymbolicLink());
  assert.equal(stat.uid, process.getuid());
  assert.equal(stat.mode & 0o7777, 0o700);
  assert.deepEqual(owner.ownership, {
    canonical: owner.path, device: stat.dev, inode: stat.ino, uid: stat.uid,
    mode: 0o700, pathBytes: Buffer.byteLength(owner.path, 'utf8'), allocated: true,
  });
  assert.ok(Object.isFrozen(owner) && Object.isFrozen(owner.ownership), 'public snapshots cannot rewrite the private cleanup identity');
  t.after(async () => { await owner.dispose(ended); });
  return owner;
}

async function retained(f) {
  await marker(join(f.run, 'run-marker'));
  await marker(join(f.profile, 'profile-marker'));
  await marker(join(f.sibling, 'sibling-marker'));
}

test('long run and profile geometry stay canonical and retained', async t => {
  const f = await fixture(t), before = await lstat(f.run), profile = await lstat(f.profile);
  assert.ok(Buffer.byteLength(f.run) > 94);
  const owner = await allocated(t, f.run);
  assert.deepEqual(await owner.dispose(ended), {removed: true, reason: 'removed'});
  await absent(owner.path);
  assert.equal((await lstat(f.run)).ino, before.ino);
  assert.equal((await lstat(f.profile)).ino, profile.ino);
  await retained(f);
});

test('each allocation is fresh and exclusive even for the same long run', async t => {
  const f = await fixture(t), a = await allocated(t, f.run), b = await allocated(t, f.run);
  assert.notEqual(a.path, b.path);
  assert.notEqual(a.ownership.inode, b.ownership.inode);
  await writeFile(join(b.path, 'keep'), 'retain me');
  assert.deepEqual(await a.dispose(ended), {removed: true, reason: 'removed'});
  await marker(join(b.path, 'keep'));
  await retained(f);
});

for (const [name, state] of [['live', live], ['missing exit fields', {}], ['undefined fields', {exitCode: undefined, signalCode: undefined}]]) {
  test(`cleanup refuses ${name} child without deleting contents`, async t => {
    const f = await fixture(t), owner = await allocated(t, f.run);
    await writeFile(join(owner.path, 'keep'), 'retain me');
    assert.deepEqual(await owner.dispose(state), {removed: false, reason: 'not-terminated'});
    await marker(join(owner.path, 'keep'));
    await retained(f);
  });
}

for (const [name, state] of [['zero exit', ended], ['nonzero exit', {exitCode: 1, signalCode: null}], ['signal termination', killed]]) {
  test(`cleanup accepts established ${name} and is idempotent`, async t => {
    const f = await fixture(t), owner = await allocated(t, f.run);
    await mkdir(join(owner.path, 'nested'));
    await writeFile(join(owner.path, 'nested', 'socket-data'), 'temporary');
    assert.deepEqual(await owner.dispose(state), {removed: true, reason: 'removed'});
    await absent(owner.path);
    assert.deepEqual(await owner.dispose(state), {removed: true, reason: 'already-removed'});
    await retained(f);
  });
}

test('child symlink is removed without following its unrelated target', async t => {
  const f = await fixture(t), owner = await allocated(t, f.run);
  await symlink(f.sibling, join(owner.path, 'outside'));
  assert.equal(await readlink(join(owner.path, 'outside')), f.sibling);
  assert.deepEqual(await owner.dispose(ended), {removed: true, reason: 'removed'});
  await absent(owner.path);
  await retained(f);
});

test('changed directory mode refuses and retains contents until identity restored', async t => {
  const f = await fixture(t), owner = await allocated(t, f.run);
  await writeFile(join(owner.path, 'keep'), 'retain me');
  try {
    await chmod(owner.path, 0o755);
    assert.deepEqual(await owner.dispose(ended), {removed: false, reason: 'identity-changed'});
    await marker(join(owner.path, 'keep'));
    await retained(f);
  } finally { await chmod(owner.path, 0o700); }
  assert.deepEqual(await owner.dispose(ended), {removed: true, reason: 'removed'});
});

// Keep the original inode alive inside a second helper-owned directory, avoiding
// inode reuse and cross-filesystem fixture moves. No arbitrary /tmp sibling.
for (const kind of ['directory', 'symlink']) {
  test(`replacement ${kind} at the owned path refuses without following or removing it`, async t => {
    const f = await fixture(t), owner = await allocated(t, f.run);
    const holder = await allocated(t, f.run);
    const saved = join(holder.path, 'moved-original');
    await rename(owner.path, saved);
    let replacement;
    try {
      if (kind === 'directory') {
        await mkdir(owner.path, {mode: 0o700});
        await writeFile(join(owner.path, 'keep'), 'retain me');
      } else {
        await symlink(f.sibling, owner.path);
      }
      replacement = await lstat(owner.path);
      assert.notEqual(replacement.ino, owner.ownership.inode);
      assert.equal((await lstat(saved)).ino, owner.ownership.inode);
      assert.deepEqual(await owner.dispose(ended), {removed: false, reason: 'identity-changed'});
      if (kind === 'directory') await marker(join(owner.path, 'keep'));
      else assert.equal(await readlink(owner.path), f.sibling);
      assert.equal((await lstat(saved)).ino, owner.ownership.inode);
      await retained(f);
    } finally {
      if (replacement) {
        // Teardown authority is only the exact replacement created by this test.
        const current = await lstat(owner.path);
        assert.equal(current.dev, replacement.dev);
        assert.equal(current.ino, replacement.ino);
        assert.equal(current.uid, replacement.uid);
        assert.equal(current.mode, replacement.mode);
        if (kind === 'directory') assert.equal(await realpath(owner.path), owner.path);
        else assert.equal(await readlink(owner.path), f.sibling);
        await rm(owner.path, {recursive: true, force: false});
      }
      assert.deepEqual(await holder.dispose(ended), {removed: true, reason: 'removed'});
    }
    await absent(owner.path);
    await absent(holder.path);
    await retained(f);
  });
}

test('supplied run is context only and cannot redirect allocation or removal', async t => {
  const f = await fixture(t), owner = await allocated(t, f.sibling);
  assert.notEqual(owner.path, f.sibling);
  assert.deepEqual(await owner.dispose(ended), {removed: true, reason: 'removed'});
  await retained(f);
});

test('ambient TMPDIR never chooses the allocation or cleanup base', async t => {
  const f = await fixture(t), previous = process.env.TMPDIR;
  try {
    process.env.TMPDIR = f.sibling;
    const owner = await allocated(t, f.run);
    assert.equal(dirname(owner.path), await realpath('/tmp'));
    assert.deepEqual(await owner.dispose(ended), {removed: true, reason: 'removed'});
    await retained(f);
  } finally {
    if (previous === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = previous;
  }
});

// PAT-2702: inspect inert child environments using real private factory allocations.
// The public ownership snapshot is diagnostic data, not allocation/cleanup authority.
const inheritedEnvironment = Object.freeze({
  PATH: '/usr/local/bin:/usr/bin:/bin', HOME: '/Users/retained-account',
  USER: 'runner', LOGNAME: 'runner', SHELL: '/bin/zsh', LANG: 'en_GB.UTF-8',
  __CF_USER_TEXT_ENCODING: '0x1F5:0:2', CFFIXED_USER_HOME: '/ambient-cf-home',
  TMPDIR: '/ambient-temporary', DYLD_INSERT_LIBRARIES: '/unapproved-library',
  UNRELATED_SECRET: 'must-not-reach-child',
});

for (const key of ['HOME', 'CFFIXED_USER_HOME', 'TMPDIR']) {
  test(`Mac child ${key} selects only the real owned allocation`, async t => {
    const f = await fixture(t), owner = await allocated(t, f.run);
    const env = createChromeLaunchEnvironment({platform: 'darwin', run: f.run,
      temporaryDirectory: owner, inherited: inheritedEnvironment});
    assert.equal(env[key], owner.path);
    assert.notEqual(env[key], f.run);
    assert.notEqual(env[key], inheritedEnvironment[key]);
    assert.equal(await realpath(env[key]), owner.path);
    const stat = await lstat(env[key]);
    assert.equal(stat.mode & 0o7777, 0o700);
    assert.equal(stat.uid, process.getuid());
    await retained(f);
  });
}
for (const [label, temporaryDirectory] of [['absent', undefined], ['null', null]]) {
  test(`Mac environment refuses ${label} allocation before child launch`, async t => {
    const f = await fixture(t);
    assert.throws(() => createChromeLaunchEnvironment({platform: 'darwin', run: f.run,
      temporaryDirectory, inherited: inheritedEnvironment}), /owned Chrome temporary directory/);
    await retained(f);
  });
}
test('ambient Mac home values never escape into the child environment', async t => {
  const f = await fixture(t), owner = await allocated(t, f.run);
  const ambient = Object.freeze({...inheritedEnvironment,
    HOME: f.sibling, CFFIXED_USER_HOME: f.profile, TMPDIR: f.run});
  const env = createChromeLaunchEnvironment({platform: 'darwin', run: f.run,
    temporaryDirectory: owner, inherited: ambient});
  assert.deepEqual([env.HOME, env.CFFIXED_USER_HOME, env.TMPDIR],
    [owner.path, owner.path, owner.path]);
  await retained(f);
});
test('Mac isolation supplies both home fields even when ambient values are absent', async t => {
  const f = await fixture(t), owner = await allocated(t, f.run);
  const env = createChromeLaunchEnvironment({platform: 'darwin', run: f.run,
    temporaryDirectory: owner, inherited: Object.freeze({PATH: '/usr/bin:/bin'})});
  assert.deepEqual(env, {PATH: '/usr/bin:/bin', HOME: owner.path,
    CFFIXED_USER_HOME: owner.path, TMPDIR: owner.path});
});
test('Linux child environment remains the original exact allowlist and owned TMPDIR', async t => {
  const f = await fixture(t), owner = await allocated(t, f.run);
  const env = createChromeLaunchEnvironment({platform: 'linux', run: f.run,
    temporaryDirectory: owner, inherited: inheritedEnvironment});
  assert.deepEqual(env, {
    PATH: inheritedEnvironment.PATH, HOME: inheritedEnvironment.HOME,
    USER: 'runner', LOGNAME: 'runner', SHELL: '/bin/zsh', LANG: 'en_GB.UTF-8',
    __CF_USER_TEXT_ENCODING: '0x1F5:0:2', TMPDIR: owner.path,
  });
  assert.equal(Object.hasOwn(env, 'CFFIXED_USER_HOME'), false);
  assert.equal(Object.hasOwn(env, 'DYLD_INSERT_LIBRARIES'), false);
  assert.equal(Object.hasOwn(env, 'UNRELATED_SECRET'), false);
});
for (const platform of ['darwin', 'linux']) {
  test(`${platform} child environment never mutates its parent or inherits extra fields`, async t => {
    const f = await fixture(t), owner = await allocated(t, f.run);
    const before = {...process.env}, inheritedBefore = {...inheritedEnvironment};
    const env = createChromeLaunchEnvironment({platform, run: f.run,
      temporaryDirectory: owner, inherited: inheritedEnvironment});
    createChromeLaunchEnvironment({platform, run: f.run, temporaryDirectory: owner});
    assert.equal(JSON.stringify({...process.env}) === JSON.stringify(before), true, 'parent environment must remain unchanged');
    assert.deepEqual(inheritedEnvironment, inheritedBefore);
    assert.notEqual(env, inheritedEnvironment);
    env.HOME = '/child-copy-only';
    assert.deepEqual(inheritedEnvironment, inheritedBefore);
    assert.equal(JSON.stringify({...process.env}) === JSON.stringify(before), true, 'parent environment must remain unchanged');
    assert.equal(Object.hasOwn(env, 'DYLD_INSERT_LIBRARIES'), false);
    assert.equal(Object.hasOwn(env, 'UNRELATED_SECRET'), false);
  });
}
test('Mac child environment allocation retains live storage and removes only after termination', async t => {
  const f = await fixture(t), owner = await allocated(t, f.run);
  createChromeLaunchEnvironment({platform: 'darwin', run: f.run,
    temporaryDirectory: owner, inherited: inheritedEnvironment});
  await writeFile(join(owner.path, 'keep'), 'retain me');
  assert.deepEqual(await owner.dispose(live), {removed: false, reason: 'not-terminated'});
  await marker(join(owner.path, 'keep'));
  assert.deepEqual(await owner.dispose(killed), {removed: true, reason: 'removed'});
  await absent(owner.path);
  await retained(f);
});
test('Mac child environment does not broaden cleanup of a changed private identity', async t => {
  const f = await fixture(t), owner = await allocated(t, f.run);
  createChromeLaunchEnvironment({platform: 'darwin', run: f.run,
    temporaryDirectory: owner, inherited: inheritedEnvironment});
  await writeFile(join(owner.path, 'keep'), 'retain me');
  try {
    await chmod(owner.path, 0o755);
    assert.deepEqual(await owner.dispose(ended), {removed: false, reason: 'identity-changed'});
    await marker(join(owner.path, 'keep'));
  } finally { await chmod(owner.path, 0o700); }
  assert.deepEqual(await owner.dispose(ended), {removed: true, reason: 'removed'});
  await absent(owner.path);
  await retained(f);
});
