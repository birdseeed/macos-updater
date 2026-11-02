import { parseHomebrewMetadata } from './metadata.mjs';
import { HOMEBREW_PROJECTION_VERSION, flags, refusingHomebrewResult, need, exact, time, digest, text, artifactURL, ownTree, equal } from './contracts.mjs';

const identityKeys = ['productId', 'bundleId', 'developerTeamId', 'channel', 'edition', 'generation'];
function identity(i) {
  exact(i, identityKeys); need(identityKeys.every(k => text(i[k])) && i.channel === 'stable');
}
function version(v) {
  need(typeof v === 'string' && /^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,3}$/.test(v));
  const parts = v.split('.').map(Number); need(parts.every(time)); return parts;
}
function compare(a, b) {
  const av = version(a), bv = version(b);
  for (let n = 0; n < 4; n++) { const d = (av[n] ?? 0) - (bv[n] ?? 0); if (d) return d < 0 ? -1 : 1; }
  return 0;
}
function parsedFromSource(s) {
  exact(s, ['rawBytes', 'sha256', 'byteLength', 'locator', 'retrievalStartedAt', 'retrievalFinishedAt', 'etag', 'lastModified', 'generationTime', 'tap', 'tapGitHead', 'rubySourcePath', 'rubySourceChecksum']);
  need(Array.isArray(s.rawBytes) && s.rawBytes.length > 0 && s.rawBytes.length <= 262144 && s.rawBytes.every(n => Number.isInteger(n) && n >= 0 && n <= 255));
  const p = parseHomebrewMetadata({ bytes: new Uint8Array(s.rawBytes), receipt: {
    locator: s.locator, startedAt: s.retrievalStartedAt, finishedAt: s.retrievalFinishedAt, statusCode: 200,
    etag: s.etag, lastModified: s.lastModified, generationTime: s.generationTime,
  } });
  need(p.status === 'parsed' && equal(p.source, s)); return p;
}
function validateParsed(p) {
  const rebuilt = parsedFromSource(p.source); need(equal(p, rebuilt)); return rebuilt;
}
function policy(p) {
  exact(p, ['token', 'tap', 'sourceLocator', 'policySha256', 'routeSha256', 'identity', 'comparator', 'allowedArtifactURLs', 'allowedRedirectURLs', 'architectures', 'minOS', 'maxOS', 'installer', 'appArtifact']);
  identity(p.identity);
  need(text(p.token) && /^[a-z0-9][a-z0-9-]*$/.test(p.token) && p.tap === 'homebrew/cask'
    && p.sourceLocator === `https://formulae.brew.sh/api/cask/${p.token}.json`
    && digest(p.policySha256) && digest(p.routeSha256) && p.comparator === 'numeric-dotted-v1'
    && p.installer === 'single-app-dmg-or-zip' && text(p.appArtifact));
  need(Array.isArray(p.allowedArtifactURLs) && p.allowedArtifactURLs.length > 0 && p.allowedArtifactURLs.length <= 64 && p.allowedArtifactURLs.every(artifactURL));
  need(new Set(p.allowedArtifactURLs).size === p.allowedArtifactURLs.length);
  need(Array.isArray(p.allowedRedirectURLs) && p.allowedRedirectURLs.length === 0);
  need(Array.isArray(p.architectures) && p.architectures.length > 0 && p.architectures.length <= 2
    && p.architectures.every(a => a === 'arm64' || a === 'x86_64') && new Set(p.architectures).size === p.architectures.length);
  need(compare(p.minOS, p.maxOS) <= 0);
}
function project(parsed, p, v) {
  const m = parsed.record;
  exact(v, ['key', 'architecture', 'osVersion', 'identity', 'comparator']); identity(v.identity);
  need(equal(v.identity, p.identity) && v.comparator === p.comparator && p.architectures.includes(v.architecture));
  need(compare(v.osVersion, p.minOS) >= 0 && compare(v.osVersion, p.maxOS) <= 0);
  need(m.token === p.token && m.tap === p.tap && parsed.source.locator === p.sourceLocator && m.artifacts[0].app[0] === p.appArtifact);
  version(m.version);
  let selected = m;
  if (Object.keys(m.variations).length === 0) need(v.key === 'base');
  else {
    need(typeof v.key === 'string' && Object.hasOwn(m.variations, v.key));
    const major = version(v.osVersion)[0];
    const family = { 13: 'ventura', 14: 'sonoma', 15: 'sequoia', 26: 'tahoe' }[major];
    need(family !== undefined && v.key === `${v.architecture}_${family}`);
    selected = { ...m, ...m.variations[v.key] };
  }
  need(p.allowedArtifactURLs.includes(selected.url));
  // Only explicit DMG/ZIP vendor routes belong to this fixture installer subset.
  need(/\.(dmg|zip)$/.test(new URL(selected.url).pathname));
  const checksum = selected.sha256 === 'no_check' ? { state: 'no-check', value: null }
    : selected.sha256 == null ? { state: 'absent', value: null } : { state: 'digest', value: selected.sha256 };
  return { status: 'discovery', projectionVersion: HOMEBREW_PROJECTION_VERSION, ...flags(),
    source: parsed.source, identity: p.identity, release: { version: m.version, comparator: p.comparator },
    selection: v, checksum, artifact: { url: selected.url, sha256: null, byteLength: null },
    continuity: { firstObservedAt: parsed.source.retrievalStartedAt, previousSourceSHA256: null },
    policyBinding: { policySha256: p.policySha256, routeSha256: p.routeSha256 },
    requiresIndependentArtifactValidation: true, artifactConsistency: 'unchecked' };
}
function previousCandidate(previous, p, now) {
  // Rebuild every field against retained raw bytes and independently supplied policy.
  const parsed = parsedFromSource(previous.source);
  const expected = project(parsed, p, previous.selection);
  exact(previous.continuity, ['firstObservedAt', 'previousSourceSHA256']);
  const c = previous.continuity;
  need(time(c.firstObservedAt) && c.firstObservedAt <= parsed.source.retrievalStartedAt
    && parsed.source.retrievalFinishedAt <= now
    && (c.previousSourceSHA256 === null || digest(c.previousSourceSHA256)));
  need(c.previousSourceSHA256 !== null || c.firstObservedAt === parsed.source.retrievalStartedAt);
  need(previous.artifactConsistency === 'unchecked' || (previous.artifactConsistency === 'injected-claim-consistent' && expected.checksum.state === 'digest'));
  expected.continuity = c; expected.artifactConsistency = previous.artifactConsistency;
  need(equal(previous, expected)); return expected;
}
export function deriveHomebrewCandidate(input) {
  try {
    const i = ownTree(input); exact(i, ['parsed', 'policy', 'variant', 'clock', 'history', 'artifactObservation']);
    const parsed = validateParsed(i.parsed); policy(i.policy);
    exact(i.clock, ['now']); need(time(i.clock.now));
    exact(i.history, ['previous']);
    const now = i.clock.now, source = parsed.source;
    need(source.retrievalFinishedAt <= now && now - source.retrievalStartedAt <= 86400);
    const result = project(parsed, i.policy, i.variant);
    if (i.artifactObservation !== null) {
      exact(i.artifactObservation, ['sha256', 'byteLength']);
      need(digest(i.artifactObservation.sha256) && time(i.artifactObservation.byteLength) && i.artifactObservation.byteLength > 0);
      if (result.checksum.state === 'digest') {
        if (i.artifactObservation.sha256 !== result.checksum.value) return refusingHomebrewResult('artifact-digest-mismatch');
        result.artifactConsistency = 'injected-claim-consistent';
      }
    }
    if (i.history.previous !== null) {
      const previous = previousCandidate(i.history.previous, i.policy, now);
      const ordering = compare(result.release.version, previous.release.version); need(ordering >= 0);
      if (ordering === 0) {
        // Equal comparator values with different literal releases are ambiguous.
        need(result.release.version === previous.release.version && source.sha256 === previous.source.sha256
          && equal(result.selection, previous.selection) && equal(result.policyBinding, previous.policyBinding)
          && source.generationTime === previous.source.generationTime
          && equal(result.checksum, previous.checksum) && equal(result.artifact, previous.artifact)
          && source.retrievalStartedAt >= previous.source.retrievalStartedAt
          && source.retrievalFinishedAt >= previous.source.retrievalFinishedAt);
        need(now - previous.continuity.firstObservedAt <= 86400);
        result.continuity.firstObservedAt = previous.continuity.firstObservedAt;
      }
      result.continuity.previousSourceSHA256 = previous.source.sha256;
    }
    // Detach all output objects from each other and from caller-owned input.
    return ownTree(result);
  } catch { return refusingHomebrewResult(); }
}
