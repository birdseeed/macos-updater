import {vendorBounds, vendorScope} from './contracts.mjs';
import {record, need, string, url, bytes, digest, hex, version, reasonOf, metadataText} from './validation.mjs';
import {parseSparkle} from './sparkle.mjs';
import {parseElectron} from './electron.mjs';
import {discoverVendorCandidate} from './candidates.mjs';
import {parseStrictJSON} from '../../protocol/strict-json.mjs';

const result = (status, reason) => ({status,reason,candidate:null,scope:vendorScope,
  verificationAllowed:false,installationAllowed:false,publicationAllowed:false});
const disposition = value => need(['observed','unavailable','malformed','refused'].includes(value));
const nullableString = (value, maximum) => { if (value !== null) string(value,maximum); };

function rawBytes(value) {
  const data = bytes(value,vendorBounds.metadataBytes);
  // Ordinary byte indices only: refuse symbols, custom properties and accessors
  // without evaluating them. The shared helper already refuses shadowed byte
  // intrinsics, shared backing stores and custom prototypes before reading.
  const keys = Reflect.ownKeys(value);
  need(keys.length === data.length);
  for (const key of keys) {
    need(typeof key === 'string' && /^(0|[1-9][0-9]*)$/.test(key) && Number(key) < data.length);
    const descriptor = Object.getOwnPropertyDescriptor(value,key);
    need(descriptor && descriptor.enumerable && Object.hasOwn(descriptor,'value'));
  }
  return data;
}

// Inert caller-built projection only; no native decoding, path reading or I/O.
export function discoverInstalledVendorCandidate(input) {
  try {
    record(input,['schemaVersion','adapter','observation','source','context','route','redirects','previous']);
    need(input.schemaVersion === 'installed-vendor-fixture-v1');
    need(['sparkle','electron'].includes(input.adapter));
    record(input.observation,['metadataDisposition','claimedBundleIdentifier','claimedShortVersion','claimedBuild','vendorMetadata']);
    const observed = input.observation, vendor = observed.vendorMetadata;
    record(vendor,['sparkleFeedURL','electronConfigBytes','sparkleDisposition','electronDisposition']);
    record(input.source,['feedURL','feedBytes','configSha256']);
    record(input.context,['productId','bundleId','developerTeamId','channel','edition','architecture','osVersion','baselineVersion']);
    record(input.route,['routeId','policyVersion','identity','comparator','feedURL','allowedRedirectURLs','artifactURLs','minOS','maxOS']);
    disposition(observed.metadataDisposition);
    disposition(vendor.sparkleDisposition); disposition(vendor.electronDisposition);
    nullableString(observed.claimedBundleIdentifier,vendorBounds.identityBytes);
    nullableString(observed.claimedShortVersion,vendorBounds.versionBytes);
    nullableString(observed.claimedBuild,vendorBounds.versionBytes);
    if (vendor.sparkleFeedURL !== null) url(vendor.sparkleFeedURL);
    const config = vendor.electronConfigBytes === null ? null : rawBytes(vendor.electronConfigBytes);
    if (observed.metadataDisposition === 'unavailable') return result('unknown','metadata-unavailable');
    need(observed.metadataDisposition === 'observed');
    const selected = vendor[input.adapter + 'Disposition'];
    if (selected === 'unavailable') return result('unknown','metadata-unavailable');
    need(selected === 'observed');
    need(observed.claimedBundleIdentifier !== null && observed.claimedBundleIdentifier === input.context.bundleId);
    const baseline = input.adapter === 'sparkle' ? observed.claimedBuild : observed.claimedShortVersion;
    version(baseline,input.adapter === 'sparkle' ? 'sparkle-dotted-v1' : 'electron-stable-semver-v1');
    need(baseline === input.context.baselineVersion);
    url(input.source.feedURL); url(input.route.feedURL);
    const feed = rawBytes(input.source.feedBytes);
    let parsed;
    if (input.adapter === 'sparkle') {
      need(input.source.configSha256 === null);
      need(vendor.sparkleFeedURL !== null && vendor.sparkleFeedURL === input.route.feedURL);
      parsed = parseSparkle({feedURL:input.source.feedURL,bytes:feed,parserVersion:'sparkle-subset-v1'});
    } else {
      need(config !== null); hex(input.source.configSha256);
      need(digest(config) === input.source.configSha256);
      parsed = parseElectron({configBytes:config,feedBytes:feed,parserVersion:'electron-subset-v1'});
      need(parsed.status === 'extracted');
      // Preserve the independent config-derived start binding before replacing
      // only this detached parser result's location. Existing candidate policy
      // then validates the complete approved chain to the final fixture URL.
      need(parsed.metadata.feedURL === input.route.feedURL);
      parsed = {...parsed,metadata:{...parsed.metadata,feedURL:input.source.feedURL}};
    }
    return discoverVendorCandidate({adapter:input.adapter,metadata:parsed,context:input.context,
      route:input.route,redirects:input.redirects,previous:input.previous});
  } catch (error) { return result('held',reasonOf(error)); }
}


const sourceResult = (status, reason, sourceClaim = null) => ({
  ...result(status,reason),sourceClaim,
});

// The shared strict parser rejects duplicate decoded keys at every depth, lone
// surrogates and non-integer numeric syntax. Its returned values are fresh data.
// Reject escaped controls too, including in unrelated keys/values, after decode.
function productData(value) {
  if (typeof value === 'string') need(!/[\u0000-\u001f\u007f-\u009f]/u.test(value),'control-data');
  else if (Array.isArray(value)) { for (const child of value) productData(child); }
  else if (value !== null && typeof value === 'object') {
    for (const key of Object.keys(value)) { productData(key); productData(value[key]); }
  }
}

// Separate source-only fixture seam. No native serialisation, path I/O, updater,
// feed acquisition or release candidate is supplied by installed product claims.
export function discoverInstalledVSCodeSource(input) {
  try {
    record(input,['schemaVersion','observation','context','sourcePolicy']);
    need(input.schemaVersion === 'installed-vscode-source-fixture-v1');
    const observed = input.observation, context = input.context, policy = input.sourcePolicy;
    record(observed,['metadataDisposition','claimedBundleIdentifier','productDisposition','productBytes']);
    record(context,['productId','bundleId','channel','architecture']);
    record(policy,['productId','bundleId','applicationName','updateUrl','channel','architecture']);
    disposition(observed.metadataDisposition); disposition(observed.productDisposition);
    nullableString(observed.claimedBundleIdentifier,vendorBounds.identityBytes);
    // Independent policy is caller-injected fixture context, never derived from
    // the product bytes. This deliberately admits one literal native subset.
    need(context.productId === 'microsoft-vscode' && policy.productId === context.productId,
      'unsupported-product');
    need(context.bundleId === 'com.microsoft.VSCode' && policy.bundleId === context.bundleId,
      'unsupported-bundle');
    need(context.channel === 'stable' && policy.channel === context.channel,'unsupported-channel');
    need(context.architecture === 'arm64' && policy.architecture === context.architecture,
      'unsupported-architecture');
    need(policy.applicationName === 'code','unsupported-application');
    url(policy.updateUrl);
    need(policy.updateUrl === 'https://update.code.visualstudio.com','unsupported-endpoint');
    const raw = observed.productBytes === null ? null : rawBytes(observed.productBytes);
    if (observed.metadataDisposition === 'unavailable' || observed.productDisposition === 'unavailable')
      return sourceResult('unknown','metadata-unavailable');
    need(observed.metadataDisposition === 'observed' && observed.productDisposition === 'observed',
      'metadata-not-observed');
    need(observed.claimedBundleIdentifier === context.bundleId,'installed-bundle-mismatch');
    need(raw !== null,'metadata-unavailable');
    const text = metadataText(raw);
    const product = parseStrictJSON(text.data,{maximumBytes:vendorBounds.metadataBytes,maximumDepth:16});
    need(product !== null && typeof product === 'object' && !Array.isArray(product),'unsupported-product-shape');
    record(product,Reflect.ownKeys(product));
    productData(product);
    // Official Darwin routing may use this override. Refuse its presence even
    // when null rather than silently treating it as an unrelated inert field.
    need(!Object.hasOwn(product,'darwinUniversalAssetId'),'unsupported-routing');
    for (const key of ['applicationName','darwinBundleIdentifier','updateUrl','quality'])
      need(Object.hasOwn(product,key),'missing-routing-field');
    need(product.applicationName === policy.applicationName,'application-mismatch');
    need(product.darwinBundleIdentifier === policy.bundleId,'bundle-mismatch');
    need(product.quality === policy.channel,'unsupported-channel');
    need(!Object.hasOwn(product,'channel') || product.channel === policy.channel,'unsupported-channel');
    url(product.updateUrl);
    need(product.updateUrl === policy.updateUrl,'endpoint-mismatch');
    return sourceResult('source-claim',null,{
      format:'vscode-product-subset-v1',updateUrl:product.updateUrl,
      applicationName:product.applicationName,claimedBundleIdentifier:product.darwinBundleIdentifier,
      channel:policy.channel,architecture:context.architecture,metadataSha256:digest(text.data),
    });
  } catch (error) { return sourceResult('unsupported',reasonOf(error)); }
}
