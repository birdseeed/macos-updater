import { createHash } from 'node:crypto';
import { parseStrictJSON } from '../../protocol/strict-json.mjs';
import { HOMEBREW_LIMITS, HOMEBREW_PROJECTION_VERSION, flags, refusingHomebrewResult, need, exact, time, digest, text, artifactURL, ownTree } from './contracts.mjs';

const required = ['token', 'full_token', 'tap', 'url', 'url_specs', 'version', 'artifacts', 'depends_on', 'auto_updates', 'deprecated', 'disabled', 'tap_git_head', 'ruby_source_path', 'ruby_source_checksum', 'variations'];
export function validateMetadata(m) {
  exact(m, required, ['sha256', 'name', 'desc', 'homepage', 'caveats', 'conflicts_with']);
  need(text(m.token) && /^[a-z0-9][a-z0-9-]*$/.test(m.token) && m.full_token === m.token && m.tap === 'homebrew/cask');
  need(artifactURL(m.url) && text(m.version) && typeof m.auto_updates === 'boolean' && m.deprecated === false && m.disabled === false);
  need(typeof m.tap_git_head === 'string' && /^[a-f0-9]{40}$/.test(m.tap_git_head));
  need(m.ruby_source_path === `Casks/${m.token[0]}/${m.token}.rb`);
  exact(m.ruby_source_checksum, ['sha256']); need(digest(m.ruby_source_checksum.sha256));
  exact(m.url_specs, []); exact(m.depends_on, []);
  need(m.conflicts_with === undefined || m.conflicts_with === null);
  for (const k of ['desc', 'homepage', 'caveats']) need(m[k] === undefined || m[k] === null || typeof m[k] === 'string');
  if (m.name !== undefined) need(Array.isArray(m.name) && m.name.every(n => typeof n === 'string'));
  need(Array.isArray(m.artifacts) && m.artifacts.length === 1);
  exact(m.artifacts[0], ['app']);
  const app = m.artifacts[0].app;
  need(Array.isArray(app) && app.length === 1 && text(app[0]) && /^[^/\\\x00-\x1f]+\.app$/u.test(app[0]) && app[0] !== '..app' && !app[0].startsWith('.'));
  const checksum = v => need(v === undefined || v === null || v === 'no_check' || digest(v));
  checksum(m.sha256); exact(m.variations, [], Object.keys(m.variations ?? {}));
  need(Object.keys(m.variations).length + m.artifacts.length <= HOMEBREW_LIMITS.maximumRecords);
  for (const [key, variant] of Object.entries(m.variations)) {
    need(/^(arm64|x86_64)_(sequoia|sonoma|ventura|tahoe)$/.test(key));
    exact(variant, [], ['url', 'sha256']); need(Object.keys(variant).length > 0);
    if (Object.hasOwn(variant, 'url')) need(artifactURL(variant.url));
    checksum(variant.sha256);
  }
  return m;
}
export function parseHomebrewMetadata(input) {
  try {
    const i = ownTree(input, true); exact(i, ['bytes', 'receipt']);
    // The byte position is the only typed-array position accepted by ownTree.
    need(i.bytes instanceof Uint8Array);
    const r = i.receipt;
    exact(r, ['locator', 'startedAt', 'finishedAt', 'statusCode', 'etag', 'lastModified', 'generationTime']);
    need(time(r.startedAt) && time(r.finishedAt) && r.startedAt <= r.finishedAt && r.statusCode === 200);
    need(r.generationTime === null || (time(r.generationTime) && r.generationTime <= r.finishedAt));
    for (const k of ['etag', 'lastModified']) need(r[k] === null || text(r[k], 2048));
    const m = validateMetadata(parseStrictJSON(i.bytes, { maximumBytes: HOMEBREW_LIMITS.maximumBytes, maximumDepth: 16 }));
    need(r.locator === `https://formulae.brew.sh/api/cask/${m.token}.json`);
    return { status: 'parsed', projectionVersion: HOMEBREW_PROJECTION_VERSION, ...flags(), record: m,
      source: { rawBytes: Array.from(i.bytes), sha256: createHash('sha256').update(i.bytes).digest('hex'), byteLength: i.bytes.length,
        locator: r.locator, retrievalStartedAt: r.startedAt, retrievalFinishedAt: r.finishedAt,
        etag: r.etag, lastModified: r.lastModified, generationTime: r.generationTime,
        tap: m.tap, tapGitHead: m.tap_git_head, rubySourcePath: m.ruby_source_path, rubySourceChecksum: m.ruby_source_checksum.sha256 } };
  } catch { return refusingHomebrewResult(); }
}
