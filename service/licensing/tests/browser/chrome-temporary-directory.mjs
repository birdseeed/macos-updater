// Test-owned Chrome socket storage. The run is context, never path authority.
import assert from 'node:assert/strict';
import {mkdtempSync, realpathSync, lstatSync, chmodSync, rmSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {constants} from 'node:os';

/**
 * @typedef {{exitCode: number|null, signalCode: string|null}} Termination
 * @typedef {{canonical: string, device: number, inode: number, uid: number,
 * mode: number, pathBytes: number, allocated: boolean}} Ownership
 * @typedef {{removed: boolean, reason: 'removed'|'already-removed'|'not-terminated'|'identity-changed'}} Disposal
 * @typedef {{path: string, ownership: Readonly<Ownership>,
 * dispose: (termination: Termination) => Promise<Disposal>}} ChromeTemporaryDirectory
 */

function terminated(state) {
  if (!state || typeof state !== 'object') return false;
  const {exitCode, signalCode} = state;
  const validExit = typeof exitCode === 'number' && Number.isFinite(exitCode);
  const validSignal = typeof signalCode === 'string' &&
    Object.hasOwn(constants.signals, signalCode);
  return (exitCode === null || validExit) &&
    (signalCode === null || validSignal) && (validExit || validSignal);
}

/**
 * @param {string} run Diagnostic context only; never selects a filesystem path.
 * @returns {Promise<ChromeTemporaryDirectory>}
 */
export async function createChromeTemporaryDirectory(run) {
  assert.equal(typeof run, 'string');
  assert.equal(typeof process.getuid, 'function');
  const parent = realpathSync('/tmp');
  // No ambient TMPDIR or caller-selected base. mkdtemp creates exclusively.
  const path = mkdtempSync(join(parent, 'pat2657-'));
  chmodSync(path, 0o700);
  const canonical = realpathSync(path), stat = lstatSync(path);
  const uid = process.getuid(), pathBytes = Buffer.byteLength(path, 'utf8');
  assert.ok(canonical === path && dirname(path) === parent && pathBytes <= 48,
    'Chrome temporary directory must be canonical and short');
  assert.ok(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === uid &&
    (stat.mode & 0o7777) === 0o700, 'Chrome temporary directory must be private');
  const device = stat.dev, inode = stat.ino;
  const ownership = Object.freeze({canonical, device, inode, uid,
    mode: 0o700, pathBytes, allocated: true});
  let removed = false;
  return Object.freeze({path, ownership, async dispose(state) {
    if (removed) return {removed: true, reason: 'already-removed'};
    if (!terminated(state)) return {removed: false, reason: 'not-terminated'};
    // Synchronous validation/removal has no event-loop gap or concurrent dispose.
    // Public ownership metadata cannot change these private captured values.
    try {
      const current = lstatSync(path);
      if (!current.isDirectory() || current.isSymbolicLink() ||
          current.uid !== uid || process.getuid() !== uid || (current.mode & 0o7777) !== 0o700 ||
          current.dev !== device || current.ino !== inode ||
          realpathSync(path) !== canonical) {
        return {removed: false, reason: 'identity-changed'};
      }
    } catch {
      return {removed: false, reason: 'identity-changed'};
    }
    // Node recursive rm unlinks child symlinks without traversing their targets.
    // force:false preserves missing/replaced-root failures instead of success.
    rmSync(path, {recursive: true, force: false});
    removed = true;
    return {removed: true, reason: 'removed'};
  }});
}
