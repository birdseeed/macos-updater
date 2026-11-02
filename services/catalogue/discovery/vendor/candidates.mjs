import { createHash } from 'node:crypto';
import { vendorBounds, vendorScope } from './contracts.mjs';
import { record, list, need, hex, string, url, artifactURL, bytes, version, order, os, integrity, length,
  comparatorFor, parserFor, identity as hash, canonical, copy, digest, reasonOf, without } from './validation.mjs';

const identityKeys = ['productId','bundleId','developerTeamId','channel','edition','architecture'];
const candidateKeys = ['candidateId','scope','routeId','policyVersion','adapter','parserVersion','identity','version',
  'displayVersion','artifactURL','artifactLength','integrityClaim','sourceDigests','redirects'];
const authority = () => ({scope:vendorScope,verificationAllowed:false,installationAllowed:false,publicationAllowed:false});
const held = reason => ({status:'held',reason,candidate:null,...authority()});
const artifactHeld = reason => ({status:'held',reason,bindingSha256:null,...authority()});
function adapter(value) { need(['sparkle','electron'].includes(value)); }
function identity(value) {
  record(value,identityKeys);
  for (const key of identityKeys) string(value[key]);
  need(/^[A-Z0-9]{10}$/.test(value.developerTeamId));
  need(value.channel === 'stable' && ['arm64','universal'].includes(value.architecture));
}
function optionalString(value) { if (value !== null) string(value); }
function claim(value, kind) {
  record(value,['algorithm','value']); integrity(value,kind === 'sparkle' ? 'ed25519' : 'sha512');
}
function digests(value, kind) {
  record(value,['configSha256','feedSha256']); hex(value.feedSha256);
  if (kind === 'sparkle') need(value.configSha256 === null); else hex(value.configSha256);
}
function redirects(value, start = null, allowed = null) {
  list(value,vendorBounds.redirects);
  let current = start;
  const seen = new Set(start === null ? [] : [start]);
  for (const hop of value) {
    record(hop,['from','to']); url(hop.from); url(hop.to);
    if (current !== null) need(hop.from === current);
    if (allowed !== null) need(allowed.includes(hop.to));
    need(!seen.has(hop.to)); seen.add(hop.from); seen.add(hop.to); current = hop.to;
  }
  return current;
}
function policy(route) {
  record(route,['routeId','policyVersion','identity','comparator','feedURL','allowedRedirectURLs','artifactURLs','minOS','maxOS']);
  string(route.routeId); string(route.policyVersion); identity(route.identity); url(route.feedURL);
  need(['sparkle-dotted-v1','electron-stable-semver-v1'].includes(route.comparator));
  list(route.allowedRedirectURLs, vendorBounds.redirects); list(route.artifactURLs,16);
  need(route.artifactURLs.length > 0);
  for (const value of route.allowedRedirectURLs) url(value);
  for (const value of route.artifactURLs) artifactURL(value);
  need(new Set(route.allowedRedirectURLs).size === route.allowedRedirectURLs.length);
  need(new Set(route.artifactURLs).size === route.artifactURLs.length);
  need(order(os(route.minOS),os(route.maxOS)) <= 0);
}
function validateCandidate(value, route = null) {
  record(value,candidateKeys); hex(value.candidateId); need(value.scope === vendorScope);
  string(value.routeId); string(value.policyVersion); adapter(value.adapter);
  need(value.parserVersion === parserFor(value.adapter)); identity(value.identity);
  version(value.version,comparatorFor(value.adapter)); optionalString(value.displayVersion);
  artifactURL(value.artifactURL); length(value.artifactLength); claim(value.integrityClaim,value.adapter);
  digests(value.sourceDigests,value.adapter); redirects(value.redirects);
  need(value.candidateId === hash(without(value,'candidateId')));
  if (route !== null) {
    need(route.comparator === comparatorFor(value.adapter));
    need(value.routeId === route.routeId && value.policyVersion === route.policyVersion);
    need(canonical(value.identity) === canonical(route.identity) && route.artifactURLs.includes(value.artifactURL));
    redirects(value.redirects,route.feedURL,route.allowedRedirectURLs);
  }
}
function extracted(value, kind) {
  record(value,['status','reason','metadata','sourceDigests']); need(value.status === 'extracted' && value.reason === null);
  const m = value.metadata;
  record(m,['parserVersion','feedURL','version','displayVersion','artifactURL','artifactLength','integrityClaim','channel','architecture','minOS','maxOS']);
  need(m.parserVersion === parserFor(kind)); url(m.feedURL); version(m.version,comparatorFor(kind));
  optionalString(m.displayVersion); artifactURL(m.artifactURL); length(m.artifactLength); claim(m.integrityClaim,kind);
  optionalString(m.channel); optionalString(m.architecture);
  if (m.minOS !== null) os(m.minOS); if (m.maxOS !== null) os(m.maxOS);
  digests(value.sourceDigests,kind); return m;
}

export function compareVendorVersions(input) {
  try {
    record(input,['comparator','left','right']);
    return {status:'compared',order:order(version(input.left,input.comparator),version(input.right,input.comparator)),reason:null};
  } catch (error) { return {status:'held',order:null,reason:reasonOf(error)}; }
}

export function discoverVendorCandidate(input) {
  try {
    record(input,['adapter','metadata','context','route','redirects','previous']);
    if (input.adapter === 'squirrel') return {status:'vendor-updater',reason:'app-specific-vendor-route-required',candidate:null,...authority()};
    adapter(input.adapter);
    if (input.metadata === null) return {status:'unknown',reason:'metadata-absent',candidate:null,...authority()};
    policy(input.route);
    const route = input.route, context = input.context;
    record(context,[...identityKeys,'osVersion','baselineVersion']);
    const contextIdentity = Object.fromEntries(identityKeys.map(key => [key,context[key]]));
    identity(contextIdentity); need(canonical(contextIdentity) === canonical(route.identity));
    need(route.comparator === comparatorFor(input.adapter));
    const currentOS = os(context.osVersion);
    need(order(currentOS,os(route.minOS)) >= 0 && order(currentOS,os(route.maxOS)) <= 0);
    const m = extracted(input.metadata,input.adapter);
    need(m.channel === null || m.channel === context.channel);
    need(m.architecture === null || m.architecture === context.architecture);
    if (m.minOS !== null) need(order(os(m.minOS),os(route.minOS)) >= 0 && order(currentOS,os(m.minOS)) >= 0);
    if (m.maxOS !== null) need(order(os(m.maxOS),os(route.maxOS)) <= 0 && order(currentOS,os(m.maxOS)) <= 0);
    if (m.minOS !== null && m.maxOS !== null) need(order(os(m.minOS),os(m.maxOS)) <= 0);
    need(redirects(input.redirects,route.feedURL,route.allowedRedirectURLs) === m.feedURL);
    need(route.artifactURLs.includes(m.artifactURL));
    need(order(version(m.version,route.comparator),version(context.baselineVersion,route.comparator)) > 0);
    const body = {scope:vendorScope,routeId:route.routeId,policyVersion:route.policyVersion,adapter:input.adapter,
      parserVersion:m.parserVersion,identity:copy(route.identity),version:m.version,displayVersion:m.displayVersion,
      artifactURL:m.artifactURL,artifactLength:m.artifactLength,integrityClaim:copy(m.integrityClaim),
      sourceDigests:copy(input.metadata.sourceDigests),redirects:copy(input.redirects)};
    const candidate = {candidateId:hash(body),...body};
    if (input.previous !== null) {
      validateCandidate(input.previous,route); need(input.previous.adapter === input.adapter);
      const comparison = order(version(m.version,route.comparator),version(input.previous.version,route.comparator));
      need(comparison >= 0);
      if (comparison === 0) {
        need(candidate.candidateId === input.previous.candidateId);
        return {status:'unchanged',reason:null,candidate:copy(input.previous),...authority()};
      }
    }
    return {status:'candidate',reason:null,candidate,...authority()};
  } catch (error) { return held(reasonOf(error)); }
}

export function checkVendorArtifact(input) {
  try {
    record(input,['candidate','artifactBytes','observation']);
    validateCandidate(input.candidate);
    const candidate = input.candidate, observed = input.observation;
    record(observed,['identity','version','signature','notarisation','container','compatibility']);
    identity(observed.identity); version(observed.version,comparatorFor(candidate.adapter));
    need(canonical(observed.identity) === canonical(candidate.identity) && observed.version === candidate.version);
    for (const key of ['signature','notarisation','container','compatibility']) need(observed[key] === 'passed');
    const data = bytes(input.artifactBytes,vendorBounds.artifactBytes); need(data.length === candidate.artifactLength);
    if (candidate.adapter === 'electron') need(createHash('sha512').update(data).digest('base64') === candidate.integrityClaim.value);
    // Sparkle's signature remains a syntactic claim. Injected verdicts are not native trust.
    const bindingSha256 = hash({candidateId:candidate.candidateId,artifactSha256:digest(data),artifactLength:data.length,observation:copy(observed)});
    return {status:'fixture-consistent',reason:null,bindingSha256,...authority()};
  } catch (error) { return artifactHeld(reasonOf(error)); }
}
