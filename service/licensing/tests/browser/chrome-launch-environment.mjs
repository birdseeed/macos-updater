// Test-launch environment only. Allocation and cleanup remain factory-owned.
import assert from 'node:assert/strict';
export function createChromeLaunchEnvironment({platform, run, temporaryDirectory, inherited = process.env}) {
  const env = Object.fromEntries(['PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'LANG', '__CF_USER_TEXT_ENCODING']
    .flatMap(key => inherited[key] === undefined ? [] : [[key, inherited[key]]]));
  env.TMPDIR = temporaryDirectory?.path ?? run;
  if (platform === 'darwin') {
    assert.ok(typeof temporaryDirectory?.path === 'string' && temporaryDirectory.path.length > 0,
      'owned Chrome temporary directory required for Mac child environment');
    // The native caller passes its real factory allocation; public metadata is
    // not an authentication seam. Only the factory owns cleanup authority.
    env.HOME = temporaryDirectory.path;
    env.CFFIXED_USER_HOME = temporaryDirectory.path;
    env.TMPDIR = temporaryDirectory.path;
  }
  return env;
}
