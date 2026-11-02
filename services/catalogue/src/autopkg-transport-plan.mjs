// Offline declarations only. Nothing here opens files or executes a transport.
const ROOT = '/Users/runner/patched-pat2693-comparison/20261024-A1';
const URL = 'https://archive.mozilla.org/pub/firefox/releases/157.0.1/mac/en-US/Firefox%20157.0.1.dmg';
const INPUT = Object.freeze([
  ROOT + '/curl-wrapper', '--silent', '--show-error', '--no-buffer',
  '--dump-header', '-', '--speed-time', '30', '--location', '--url', URL,
  '--fail', '--output', ROOT + '/download.tmp',
]);

function refusal() {
  return {
    status: 'refused', reason: 'unsupported-invocation',
    executionAllowed: false, transportObserved: false,
    autoPkgParityProven: false, installationAllowed: false,
  };
}

function matchesInvocation(argv) {
  // Inspect only the bounded own data slots. Do not call caller iterators,
  // getters, coercions or array methods, or accept inherited/sparse tokens.
  try {
    if (!Array.isArray(argv)) return false;
    const length = Object.getOwnPropertyDescriptor(argv, 'length');
    if (!length || length.value !== INPUT.length) return false;
    for (let i = 0; i < INPUT.length; i++) {
      const token = Object.getOwnPropertyDescriptor(argv, String(i));
      if (!token || !Object.hasOwn(token, 'value') ||
          typeof token.value !== 'string' || token.value !== INPUT[i]) return false;
    }
    return true;
  } catch {
    // A revoked or throwing proxy cannot turn a malformed invocation into a plan.
    return false;
  }
}

export function planAutoPkgFirefoxComparison(argv) {
  if (!matchesInvocation(argv)) return refusal();
  // Every returned container is newly allocated, including passFds. These are
  // required future controls and captures, never evidence that they occurred.
  return {
    status: 'planned', declarationOnly: true,
    executionAllowed: false, transportObserved: false,
    autoPkgParityProven: false, installationAllowed: false,
    argv: [
      '/usr/bin/curl', '-q', '--no-location', '--proto', '=https', '--proto-redir',
      '=https', '--ipv4', '--resolve', 'archive.mozilla.org:443:151.101.3.19',
      '--noproxy', '*', '--proxy', '', '--connect-timeout', '30', '--max-time', '180',
      '--max-filesize', '161550118', '--header', 'Accept-Encoding: identity',
      '--silent', '--show-error', '--output', '/dev/fd/3', '--dump-header', '/dev/fd/4',
      '--write-out', '%{json}\n', '--url', URL,
    ],
    environment: {
      PATH: '/usr/bin:/bin:/usr/sbin:/sbin', LANG: 'C', LC_ALL: 'C',
      HOME: ROOT + '/curl-home', CURL_HOME: ROOT + '/curl-home',
    },
    descriptorRoles: {
      bodyFd: 3, bodyPath: ROOT + '/download.tmp', headersFd: 4,
      headersPath: ROOT + '/headers.raw', stdoutFd: 5,
      stdoutPath: ROOT + '/curl-metadata.raw', stderrFd: 6,
      stderrPath: ROOT + '/curl-stderr.raw', stdin: '/dev/null', passFds: [3, 4],
    },
    outerWatchdogSeconds: 195, noRetry: true, noFallback: true,
    sourceBindings: {
      autoPkgRevision: 'c36e58f8d3d8ddb70b6c2d848d2ceca7f767ce5c',
      recipesRevision: '0f7b61ab061c77710be4140c404910a11f89fc7b',
      urlDownloaderSha256: '163d5898dfac4e8af128afb85a24eaf062b12c4563c88c2201e7ef4bbb758349',
      urlGetterSha256: 'a640da18d0d7458239fc6e2347e5898f7cc704d2b4e924bd98e662c25466f2b1',
      autoPkgInitSha256: 'd42b6cb929a0d69be85275348197c75c7e68cc340e46275c28720cf1858f1fcc',
      firefoxRecipeSha256: '6d17ddeb226c88af7b4bdef7f981634f2da18403e0ebb86afeb5cfbdf4dc5237',
      mozillaProviderSha256: 'c4ce035b1a629c4925a80003899fcf39480e5224b3015613440f07ab96211f17',
    },
    requiredPostconditions: {
      curlExit: 0, httpStatus: 200, redirects: 0, tlsVerify: 0, effectiveURL: URL,
      remoteIP: '151.101.3.19', remotePort: 443, length: 161550118,
      sha256: '40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982',
      contentEncodingAbsentOrIdentity: true, oneHeaderBlock: true, cleanupVerified: true,
    },
    requiredPreflight: [
      'current-guest-uuid-uid-os-architecture', 'runtime-origins-and-hashes',
      'six-cfprefs-actual-values-and-precedence', 'recipe-override-parent-trust',
      'curl-physical-hash-config-environment', 'fd-path-identities-private-ownership',
      'free-space-and-storage-caps', 'controller-ownership', 'budget-availability',
      'serial-runtime-idle', 'no-retry', 'new-vendor-allowance', 'independent-review',
      'reviewed-wrapper-and-autopkg-binding', 'cleanup-and-native-validation',
      'current-route-revalidation-and-policy-regeneration',
    ],
  };
}
