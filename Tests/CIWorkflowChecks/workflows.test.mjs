// PAT-2696/PAT-2702 fixture-only configuration contracts. No YAML dependency or CI execution.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const directory = fileURLToPath(new URL('../../.github/workflows/', import.meta.url));
const hashes = {
  'catalogue-ci-diagnostics.yml': '2bb7bba97306e722c6f86bf27754f3d510533cbc5b033859606a9fd17f42a031',
  'disposable-ci-diagnostics.yml': '1e4af73364c358b962a96416807dc45d3da88ec4be6fcb32a32c1a1a501572d3',
  'licensing-verify.yml': 'f91fe1daf126c3a6d4328178ae7255ada3772d43cc88eb0b2b85a95778628e66',
  'verify.yml': '674339f1b140bf9592112c544d02338cf6c5bcadc79ea94c37a4fb70c59df644',
};
// Exact manual-only runner exception; the four product workflows retain their pause guards.
const smokeName = 'macos-runner-smoke.yml';
const smokeHash = '9575a1bbe9e09d96942001642057846885930428d8e9242381a2584e94d18226';
// CHECK-MODIFIED PAT-2702: retain legacy normalisation solely to authenticate original bytes.
const legacyMacGuard = "    if: ${{ vars.PATCHED_MACOS_ACTIONS_ENABLED == 'true' }}\n";
const linuxGuard = "    if: ${{ github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository }}\n";
const linuxRunner = '    runs-on: [self-hosted, Linux, X64]\n';
// CHECK-MODIFIED PAT-2702: exact additive cutover blocks, never generic YAML stripping.
const macGuard = "    if: ${{ vars.PATCHED_MACOS_ACTIONS_ENABLED == 'true' && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository) }}\n";
const macRunner = '    runs-on: [self-hosted, macOS, ARM64, patched-macos-01]\n';
const nativeOnlyLinuxGuard = "    if: ${{ (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository) && !(github.event_name == 'workflow_dispatch' && inputs.native_only == true) }}\n";
const nativeOnlyDispatch = `  workflow_dispatch:
    inputs:
      native_only:
        description: Run only the native macOS bridge
        type: boolean
        default: false
`;
const macIdentityStep = `      - name: Confirm approved macOS runner
        run: |
          test "$RUNNER_NAME" = patched-macos-01
          test "$RUNNER_OS" = macOS
          test "$RUNNER_ARCH" = ARM64
          test "$(id -u)" -ne 0
          printf 'Runner: %s\\nCommit: %s\\n' "$RUNNER_NAME" "$GITHUB_SHA"
`;
const checkoutStep = `      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262
        with:
          persist-credentials: false
`;
const nodeStep = `      - uses: actions/setup-node@2028fbc5c25fe9cf00d9f06a71cc4710d4507903 # v6.0.0
        with:
          node-version: '24.21.0'
          package-manager-cache: false
`;
// CHECK-MODIFIED PAT-2710: allow only the independently reviewed two-job Swift
// shim, reversing its complete literal step to the original authenticated bytes.
const originalVerifyStep = '      - run: ./scripts/verify.sh\n';
const cappedSwiftVerifyStep = `      - name: Verify with at most two Swift jobs
        shell: bash
        run: |
          set -euo pipefail
          swift_shim="$(mktemp -d "$RUNNER_TEMP/patched-swift-XXXXXX")"
          trap 'rm -f "$swift_shim/swift"; rmdir "$swift_shim"' EXIT
          cat > "$swift_shim/swift" <<'SH'
          #!/bin/bash
          set -eu
          case "\${1:-}" in
            build|run)
              verb="$1"; shift
              for argument in "$@"; do
                case "$argument" in
                  --jobs|--jobs=*|-j|-j[0-9]*) echo 'Swift job overrides are not allowed in CI' >&2; exit 64;;
                esac
              done
              exec /usr/bin/swift "$verb" --jobs 2 "$@";;
            *) exec /usr/bin/swift "$@";;
          esac
          SH
          chmod 700 "$swift_shim/swift"
          PATH="$swift_shim:$PATH" ./scripts/verify.sh
`;

// Owner-approved extension applies only to the Linux service-only fixture job.
const originalLinuxTimeout = `    env:
      PAT2646_NATIVE_CHECK_MODE: service-only
    timeout-minutes: 60
`;
const approvedLinuxTimeout = originalLinuxTimeout.replace('timeout-minutes: 60', 'timeout-minutes: 90');
const identityStep = `      - name: Confirm approved Linux runner
        run: |
          test "$RUNNER_NAME" = patched-linux-01
          printf 'Runner: %s\\nCommit: %s\\n' "$RUNNER_NAME" "$GITHUB_SHA"
`;
const contractStep = `      - name: Check Linux routing and macOS pause
        run: node --test Tests/CIWorkflowChecks/workflows.test.mjs
`;
// CHECK-MODIFIED: only these five lines may extend each original event filter.
const addedTriggerPaths = `      - 'Tests/CIWorkflowChecks/**'
      - '.github/workflows/catalogue-ci-diagnostics.yml'
      - '.github/workflows/disposable-ci-diagnostics.yml'
      - '.github/workflows/verify.yml'
      - '.github/workflows/macos-runner-smoke.yml'
`;

function stripAllowedChanges(name, text) {
  if (name === smokeName) return text;
  // CHECK-MODIFIED PAT-2702: reverse only the exact approved new blocks.
  text = text.replaceAll(macGuard, legacyMacGuard)
    .replaceAll(macRunner, '    runs-on: macos-15\n')
    .replaceAll(macIdentityStep, '');
  if (name !== 'licensing-verify.yml') {
    text = text.replace(checkoutStep + nodeStep, checkoutStep);
  }
  if (name === 'verify.yml') {
    text = text.replace('  workflow_dispatch:\n', '')
      .replace(cappedSwiftVerifyStep, originalVerifyStep);
  }
  if (name === 'licensing-verify.yml') {
    text = text.replace(nativeOnlyDispatch, '  workflow_dispatch:\n')
      .replace(nativeOnlyLinuxGuard, linuxGuard);
  }
  text = text.replaceAll(legacyMacGuard, '');
  if (name === 'licensing-verify.yml') {
    text = text.replace(approvedLinuxTimeout, originalLinuxTimeout)
      .replace('  workflow_dispatch:\n', '').replace(linuxGuard, '')
      .replace(linuxRunner, '    runs-on: ubuntu-24.04\n')
      .replace(identityStep, '').replace(contractStep, '');
    for (const line of addedTriggerPaths.match(/[^\n]+\n/g)) text = text.replaceAll(line, '');
  }
  return text;
}

// An inert expected fixture assembled from authenticated preserved workflow bytes.
function expectedCandidate(name, original) {
  if (name === smokeName) return original;
  // CHECK-MODIFIED PAT-2702: exact route and identity placement for each native job.
  let text = original.replace('    runs-on: macos-15\n', macGuard + macRunner);
  if (name in hashes) {
    if (name === 'licensing-verify.yml') {
      text = text.replace('      PAT2646_NATIVE_CHECK_MODE: native-required\n    steps:\n',
        '      PAT2646_NATIVE_CHECK_MODE: native-required\n    steps:\n' + macIdentityStep);
    } else text = text.replace(checkoutStep, macIdentityStep + checkoutStep);
    if (name !== 'licensing-verify.yml') text = text.replace(checkoutStep, checkoutStep + nodeStep);
  }
  if (name === 'verify.yml') {
    text = text.replace('on:\n', 'on:\n  workflow_dispatch:\n')
      .replace(originalVerifyStep, cappedSwiftVerifyStep);
  }
  if (name === 'licensing-verify.yml') {
    text = text.replace(originalLinuxTimeout, approvedLinuxTimeout)
      .replace('on:\n', 'on:\n' + nativeOnlyDispatch)
      .replace('    runs-on: ubuntu-24.04\n', nativeOnlyLinuxGuard + linuxRunner)
      .replace('    steps:\n', '    steps:\n' + identityStep)
      .replace('      - name: Diagnose owned Linux Chrome startup\n', contractStep + '      - name: Diagnose owned Linux Chrome startup\n')
      .replaceAll("      - '.github/workflows/licensing-verify.yml'\n", "      - '.github/workflows/licensing-verify.yml'\n" + addedTriggerPaths);
  }
  return text;
}

function validate(candidate) {
  assert.deepEqual(Object.keys(candidate).sort(), [...Object.keys(hashes), smokeName].sort(), 'workflow inventory');
  for (const [name, text] of Object.entries(candidate)) {
    if (name === smokeName) {
      assert.equal(createHash('sha256').update(text).digest('hex'), smokeHash, `${name}: exact manual smoke bytes`);
      continue;
    }
    const original = stripAllowedChanges(name, text);
    assert.equal(createHash('sha256').update(original).digest('hex'), hashes[name], `${name}: preserved bytes`);
    // Exact reconstruction rejects alternate syntax, duplicate keys and moved guards.
    assert.equal(text, expectedCandidate(name, original), `${name}: required changes`);
  }
}

const actual = Object.fromEntries(readdirSync(directory).filter(name => /\.ya?ml$/.test(name))
  .map(name => [name, readFileSync(directory + name, 'utf8')]));
const positive = Object.fromEntries(Object.entries(actual)
  .map(([name, text]) => [name, expectedCandidate(name, stripAllowedChanges(name, text))]));

test('checked-in workflows meet Linux routing and fail-closed macOS contract', () => validate(actual));
test('missing manual smoke workflow refuses', () => {
  const { [smokeName]: omitted, ...missingSmoke } = positive;
  assert.ok(omitted);
  assert.throws(() => validate(missingSmoke), /workflow inventory/);
});
test('modified manual smoke workflow refuses', () => {
  assert.throws(() => validate({ ...positive, [smokeName]: positive[smokeName] + '# changed\n' }), /exact manual smoke bytes/);
});
test('inert positive fixture preserves all four macOS jobs', () => {
  validate(positive);
  assert.equal(Object.values(positive).join('').split(macGuard).length - 1, 4);
});

// PAT-2710: mutation controls keep the cap, override refusal, verification and
// cleanup mandatory. Only the one exact complete step is an allowed amendment.
test('Verify references contains exactly one literal two-job Swift shim', () => {
  assert.equal(actual['verify.yml'].split(cappedSwiftVerifyStep).length - 1, 1);
  assert.ok(!actual['verify.yml'].includes(originalVerifyStep));
  validate({ ...positive, 'verify.yml': actual['verify.yml'] });
});
for (const [label, oldText, replacement] of [
  ['shim removed', cappedSwiftVerifyStep, originalVerifyStep],
  ['job cap removed', '--jobs 2 ', ''],
  ['job cap raised', '--jobs 2 ', '--jobs 3 '],
  ['job cap made configurable', '--jobs 2 ', '--jobs "$SWIFT_JOBS" '],
  ['override refusal bypassed', 'exit 64;;', 'true;;'],
  ['long job override allowed', '--jobs|--jobs=*|-j|-j[0-9]*)', '--jobs=*|-j|-j[0-9]*)'],
  ['long equals job override allowed', '--jobs|--jobs=*|-j|-j[0-9]*)', '--jobs|-j|-j[0-9]*)'],
  ['short job override allowed', '--jobs|--jobs=*|-j|-j[0-9]*)', '--jobs|--jobs=*|-j[0-9]*)'],
  ['short attached job override allowed', '--jobs|--jobs=*|-j|-j[0-9]*)', '--jobs|--jobs=*|-j)'],
  ['verification replaced', 'PATH="$swift_shim:$PATH" ./scripts/verify.sh', 'PATH="$swift_shim:$PATH" true'],
  ['verification bypasses shim', 'PATH="$swift_shim:$PATH" ./scripts/verify.sh', './scripts/verify.sh'],
  ['cleanup removed', '          trap \'rm -f "$swift_shim/swift"; rmdir "$swift_shim"\' EXIT\n', ''],
  ['duplicate shim', cappedSwiftVerifyStep, cappedSwiftVerifyStep + cappedSwiftVerifyStep],
  ['additional step', cappedSwiftVerifyStep, cappedSwiftVerifyStep + '      - run: true\n'],
]) {
  test(`Verify references Swift ${label} refuses`, () => {
    const name = 'verify.yml';
    assert.ok(positive[name].includes(oldText));
    const changed = positive[name].replace(oldText, replacement);
    assert.notEqual(changed, positive[name]);
    assert.throws(() => validate({ ...positive, [name]: changed }));
  });
}

for (const name of Object.keys(hashes)) {
  for (const [label, replacement] of [
    ['removed', ''], ['always bypass', '    if: ${{ always() }}\n'],
    ['default enabled', macGuard.replace("== 'true'", "!= 'false'")],
  ]) {
    test(`${name}: macOS guard ${label} refuses`, () => {
      assert.ok(positive[name].includes(macGuard));
      assert.throws(() => validate({ ...positive, [name]: positive[name].replace(macGuard, replacement) }));
    });
  }
}

const mutations = [
  ['wrong runner label', linuxRunner, linuxRunner.replace('Linux', 'ubuntu-24.04')],
  ['name treated as label', linuxRunner, linuxRunner.replace('X64', 'patched-linux-01')],
  // CHECK-MODIFIED PAT-2702: existing Linux guard controls target its input-scoped extension.
  ['fork guard removed', nativeOnlyLinuxGuard, ''],
  ['fork guard bypassed', nativeOnlyLinuxGuard, '    if: ${{ always() }}\n'],
  ['fork allowed', 'head.repo.full_name == github.repository', 'head.repo.full_name != github.repository'],
  ['identity removed', identityStep, ''],
  ['wrong identity', 'test "$RUNNER_NAME" = patched-linux-01', 'test "$RUNNER_NAME" = another-runner'],
  ['identity after checkout', identityStep, ''],
  ['timeout raised', 'timeout-minutes: 90', 'timeout-minutes: 120'],
  ['writable permissions', 'contents: read', 'contents: write'],
  ['persisted credentials', 'persist-credentials: false', 'persist-credentials: true'],
  ['checkout unpinned', 'actions/checkout@11d5960a326750d5838078e36cf38b85af677262', 'actions/checkout@main'],
  ['node unpinned', 'actions/setup-node@2028fbc5c25fe9cf00d9f06a71cc4710d4507903', 'actions/setup-node@main'],
  ['unsafe PR event', '  pull_request:\n', '  pull_request_target:\n'],
  ['dispatch removed', '  workflow_dispatch:\n', ''],
  ['verification weakened', 'run: ./scripts/verify-service.sh', 'run: true'],
  ['duplicate job key', linuxRunner, linuxRunner + '    if: true\n'],
  ['contract check removed', contractStep, ''],
];
for (const [label, oldText, replacement] of mutations) {
  test(`Linux ${label} refuses`, () => {
    const name = 'licensing-verify.yml';
    assert.ok(positive[name].includes(oldText));
    let changed = positive[name].replace(oldText, replacement);
    if (label === 'identity after checkout') changed += identityStep;
    assert.throws(() => validate({ ...positive, [name]: changed }));
  });
}
for (const timeout of [60, 91]) {
  test(`Linux timeout ${timeout} instead of approved 90 refuses`, () => {
    const name = 'licensing-verify.yml';
    const expected = '      PAT2646_NATIVE_CHECK_MODE: service-only\n    timeout-minutes: 90\n';
    assert.ok(positive[name].includes(expected));
    const changed = positive[name].replace(expected, expected.replace('timeout-minutes: 90', `timeout-minutes: ${timeout}`));
    assert.notEqual(changed, positive[name]);
    assert.throws(() => validate({ ...positive, [name]: changed }));
  });
}
test('native bridge timeout raised from preserved 60 refuses', () => {
  const name = 'licensing-verify.yml';
  // CHECK-MODIFIED PAT-2702: preserve the native timeout assertion on the approved route.
  const expected = macRunner + '    timeout-minutes: 60\n';
  assert.ok(positive[name].includes(expected));
  const changed = positive[name].replace(expected, expected.replace('timeout-minutes: 60', 'timeout-minutes: 90'));
  assert.notEqual(changed, positive[name]);
  assert.throws(() => validate({ ...positive, [name]: changed }), /licensing-verify\.yml: preserved bytes/);
});
test('extra workflow refuses', () => assert.throws(() => validate({ ...positive, 'extra.yml': 'jobs: {}\n' })));
for (const name of Object.keys(hashes)) {
  test(`${name}: unrelated step or byte change refuses`, () => {
    assert.throws(() => validate({ ...positive, [name]: positive[name] + '# unrelated change\n' }));
  });
}

// Independent literal event expectations do not derive from addedTriggerPaths
// or expectedCandidate. Preserve every original filter and require both events.
const expectedPullRequestPaths = `  pull_request:
    paths:
      - 'service/licensing/**'
      - 'scripts/verify-service.sh'
      - 'scripts/verify-billing.sh'
      - 'Fixtures/Billing/**'
      - '.github/workflows/licensing-verify.yml'
      - 'Tests/CIWorkflowChecks/**'
      - '.github/workflows/catalogue-ci-diagnostics.yml'
      - '.github/workflows/disposable-ci-diagnostics.yml'
      - '.github/workflows/verify.yml'
      - '.github/workflows/macos-runner-smoke.yml'
      - 'docs/licensing-implementation-plan.md'
      - 'AGENTS.md'
`;
const expectedPushPaths = `  push:
    branches: [main]
    paths:
      - 'service/licensing/**'
      - 'scripts/verify-service.sh'
      - 'scripts/verify-billing.sh'
      - 'Fixtures/Billing/**'
      - '.github/workflows/licensing-verify.yml'
      - 'Tests/CIWorkflowChecks/**'
      - '.github/workflows/catalogue-ci-diagnostics.yml'
      - '.github/workflows/disposable-ci-diagnostics.yml'
      - '.github/workflows/verify.yml'
      - '.github/workflows/macos-runner-smoke.yml'
      - 'docs/licensing-implementation-plan.md'
      - 'AGENTS.md'
`;
test('inert fixture explicitly covers checker and all protected workflows in both events', () => {
  assert.ok(positive['licensing-verify.yml'].includes(expectedPullRequestPaths));
  assert.ok(positive['licensing-verify.yml'].includes(expectedPushPaths));
});

for (const [event, eventBlock] of [
  ['pull_request', expectedPullRequestPaths], ['push', expectedPushPaths],
]) {
  for (const pathLine of [
    "      - 'Tests/CIWorkflowChecks/**'\n",
    "      - '.github/workflows/catalogue-ci-diagnostics.yml'\n",
    "      - '.github/workflows/disposable-ci-diagnostics.yml'\n",
    "      - '.github/workflows/verify.yml'\n",
    "      - '.github/workflows/macos-runner-smoke.yml'\n",
  ]) {
    test(`${event}: missing trigger ${pathLine.trim()} refuses`, () => {
      const name = 'licensing-verify.yml';
      assert.ok(positive[name].includes(eventBlock));
      assert.ok(eventBlock.includes(pathLine));
      const changed = positive[name].replace(eventBlock, eventBlock.replace(pathLine, ''));
      assert.notEqual(changed, positive[name]);
      assert.throws(() => validate({ ...positive, [name]: changed }), /licensing-verify\.yml: required changes/);
    });
  }
  test(`${event}: added coverage in the other event only refuses`, () => {
    const name = 'licensing-verify.yml';
    assert.ok(positive[name].includes(eventBlock));
    const originalOnly = eventBlock
      .replace("      - 'Tests/CIWorkflowChecks/**'\n", '')
      .replace("      - '.github/workflows/catalogue-ci-diagnostics.yml'\n", '')
      .replace("      - '.github/workflows/disposable-ci-diagnostics.yml'\n", '')
      .replace("      - '.github/workflows/verify.yml'\n", '')
      .replace("      - '.github/workflows/macos-runner-smoke.yml'\n", '');
    const changed = positive[name].replace(eventBlock, originalOnly);
    assert.notEqual(changed, positive[name]);
    assert.throws(() => validate({ ...positive, [name]: changed }), /licensing-verify\.yml: required changes/);
  });
}

// PAT-2702 additive controls use exact inert text only, never evaluate workflow expressions.
for (const [name, timeout] of [
  ['verify.yml', 15], ['catalogue-ci-diagnostics.yml', 3],
  ['disposable-ci-diagnostics.yml', 3], ['licensing-verify.yml', 60],
]) {
  test(`${name}: checked-in native cutover is present`, () => {
    validate({ ...positive, [name]: actual[name] });
  });
  test(`${name}: inert native route, timeout and pre-checkout identity are explicit`, () => {
    const native = positive[name].slice(positive[name].indexOf(macGuard));
    assert.ok(native.startsWith(macGuard + macRunner + `    timeout-minutes: ${timeout}\n`));
    assert.ok(native.includes('    steps:\n' + macIdentityStep + checkoutStep + nodeStep));
    assert.equal(native.split(macIdentityStep).length - 1, 1);
  });
  const nativeMutations = [
    ['hosted runner restored', macRunner, '    runs-on: macos-15\n'],
    ['private runner name omitted', macRunner, macRunner.replace(', patched-macos-01', '')],
    ['wrong private runner name', macRunner, macRunner.replace('patched-macos-01', 'other-macos')],
    ['wrong runner OS', macRunner, macRunner.replace('macOS', 'Linux')],
    ['wrong runner architecture', macRunner, macRunner.replace('ARM64', 'X64')],
    ['identity removed', macIdentityStep, ''],
    ['identity runner mismatch', 'test "$RUNNER_NAME" = patched-macos-01', 'test "$RUNNER_NAME" = other-macos'],
    ['identity OS mismatch', 'test "$RUNNER_OS" = macOS', 'test "$RUNNER_OS" = Linux'],
    ['identity architecture mismatch', 'test "$RUNNER_ARCH" = ARM64', 'test "$RUNNER_ARCH" = X64'],
    ['nonroot check removed', '          test "$(id -u)" -ne 0\n', ''],
    ['root required', 'test "$(id -u)" -ne 0', 'test "$(id -u)" -eq 0'],
    ['identity moved after checkout', macIdentityStep + checkoutStep, checkoutStep + macIdentityStep],
    ['pause guard removed', macGuard, linuxGuard],
    ['fork guard removed', macGuard, legacyMacGuard],
    ['fork pause OR bypass', macGuard, macGuard.replace("== 'true' &&", "== 'true' ||")],
    ['fork comparison inverted', macGuard, macGuard.replace('head.repo.full_name ==', 'head.repo.full_name !=')],
    ['guard moved after runner', macGuard + macRunner, macRunner + macGuard],
    ['Node setup removed', nodeStep, ''],
    ['Node action unpinned', 'actions/setup-node@2028fbc5c25fe9cf00d9f06a71cc4710d4507903', 'actions/setup-node@main'],
    ['Node version drift', "node-version: '24.21.0'", "node-version: '24'"],
    ['Node cache enabled', 'package-manager-cache: false', 'package-manager-cache: true'],
    ['native timeout drift', `timeout-minutes: ${timeout}`, `timeout-minutes: ${timeout + 1}`],
  ];
  for (const [label, oldText, replacement] of nativeMutations) {
    test(`${name}: native ${label} refuses`, () => {
      const offset = positive[name].indexOf(macGuard);
      assert.ok(offset >= 0);
      const native = positive[name].slice(offset);
      assert.ok(native.includes(oldText), 'mutation must target the native job');
      const changed = positive[name].slice(0, offset) + native.replace(oldText, replacement);
      assert.notEqual(changed, positive[name]);
      assert.throws(() => validate({ ...positive, [name]: changed }));
    });
  }
}

test('Verify references requires a plain manual dispatch without inputs', () => {
  assert.ok(positive['verify.yml'].startsWith('name: Verify references\non:\n  workflow_dispatch:\n  pull_request:\n'));
  const changed = positive['verify.yml'].replace('  workflow_dispatch:\n', '');
  assert.throws(() => validate({ ...positive, 'verify.yml': changed }));
});
test('licensing manual native-only input is a single boolean defaulting false', () => {
  assert.ok(positive['licensing-verify.yml'].includes(nativeOnlyDispatch + '  pull_request:\n'));
  assert.equal(positive['licensing-verify.yml'].split('      native_only:\n').length - 1, 1);
  assert.ok(positive['licensing-verify.yml'].includes(nativeOnlyLinuxGuard + linuxRunner));
  assert.ok(positive['licensing-verify.yml'].includes(macGuard + macRunner));
});
for (const [label, oldText, replacement] of [
  ['default true', '        default: false\n', '        default: true\n'],
  ['input type string', '        type: boolean\n', '        type: string\n'],
  ['default omitted', '        default: false\n', ''],
  ['extra input', nativeOnlyDispatch, nativeOnlyDispatch + '      runner:\n        type: string\n'],
  ['input removed', nativeOnlyDispatch, '  workflow_dispatch:\n'],
  ['PR input bypass', nativeOnlyLinuxGuard, nativeOnlyLinuxGuard.replace("github.event_name == 'workflow_dispatch' && ", '')],
  ['push input bypass', nativeOnlyLinuxGuard, nativeOnlyLinuxGuard.replace("github.event_name == 'workflow_dispatch'", "github.event_name != 'pull_request'")],
  ['dispatch check inverted', nativeOnlyLinuxGuard, nativeOnlyLinuxGuard.replace("github.event_name == 'workflow_dispatch'", "github.event_name != 'workflow_dispatch'")],
  ['Linux skips ordinary manual dispatch', nativeOnlyLinuxGuard, nativeOnlyLinuxGuard.replace(' && inputs.native_only == true', '')],
  ['Linux required for native-only dispatch', nativeOnlyLinuxGuard, linuxGuard],
  ['Linux fork bypass from input', nativeOnlyLinuxGuard, nativeOnlyLinuxGuard.replace(' && !(', ' || !(')],
  ['native-only pause bypass', macGuard, "    if: ${{ inputs.native_only == true || vars.PATCHED_MACOS_ACTIONS_ENABLED == 'true' }}\n"],
  ['native-only fork bypass', macGuard, macGuard.replace("vars.PATCHED_MACOS_ACTIONS_ENABLED == 'true' &&", "vars.PATCHED_MACOS_ACTIONS_ENABLED == 'true' && inputs.native_only == true ||")],
]) {
  test(`licensing native-only ${label} refuses`, () => {
    const name = 'licensing-verify.yml';
    assert.ok(positive[name].includes(oldText));
    const changed = positive[name].replace(oldText, replacement);
    assert.notEqual(changed, positive[name]);
    assert.throws(() => validate({ ...positive, [name]: changed }));
  });
}
