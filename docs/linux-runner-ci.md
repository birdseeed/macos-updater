# Private runner CI routing

On 16 October 2026, Andy authorised PAT-2696 to route the local licensing
fixture workflow to the approved organisation self-hosted Linux runner,
`patched-linux-01`, for the private `Patched-LTD/patched-mac-app` repository.
The runner labels are `self-hosted`, `Linux` and `X64`. The first job step
checks the exact runner name before checkout and records the runner name and
`GITHUB_SHA`. Labels alone do not establish the approved runner identity.

The Linux job accepts pushes, manual dispatches and pull requests whose head
repository is the same repository. Effective fork denial requires the repository
server settings `allow_forking: false` and
`run_workflows_from_fork_pull_requests: false`. The same-repository job guard
provides defence in depth; a fork can alter its proposed workflow, so the guard
alone does not establish server-side fork denial. Checkout keeps its pinned
action and does not persist credentials. The pinned Node setup precedes the
fixture-only workflow contract checks, which run before the existing Chrome
diagnostics and unchanged full service verification gate.

Both the pull-request and main-push path filters cover
`Tests/CIWorkflowChecks/**` and all four protected workflows:
`licensing-verify.yml`, `catalogue-ci-diagnostics.yml`,
`disposable-ci-diagnostics.yml` and `verify.yml` under `.github/workflows/`.
Changes to the checker or any protected workflow therefore trigger the routing
contract checks alongside the existing source and documentation paths.

PAT-2702 routes all four macOS jobs to the approved private runner labels
`self-hosted`, `macOS`, `ARM64` and `patched-macos-01`. Before checkout, each
native job requires the exact `RUNNER_NAME`, `RUNNER_OS` and `RUNNER_ARCH`
values `patched-macos-01`, `macOS` and `ARM64`, and refuses UID zero. It prints
only the runner name and commit SHA. The pinned Node setup selects `24.21.0`
with package-manager caching disabled in every native job. The original native
timeouts remain 15 minutes for references, 3 minutes for each diagnostic and
60 minutes for the licensing bridge; the Linux fixture timeout remains 90.

Each native job requires both the repository variable
`PATCHED_MACOS_ACTIONS_ENABLED == 'true'` and either a non-pull-request event
or a same-repository pull-request head. This job-level guard refuses fork pull
requests before runner assignment. Keep the server-side fork restrictions
above: a proposed workflow can alter its own source. GitHub compares strings
case-insensitively, so `TRUE` and `True` also enable native jobs. A false or
absent variable pauses them, including native-only manual dispatches. The
source cutover does not change that variable or enable the two externally
disabled diagnostic workflows. Keep those diagnostic workflow states disabled
until their separate diagnostic scope is released.

For controlled integrated-main proof after the source is merged and native CI
is explicitly enabled, manually dispatch `verify.yml` at `main` without
inputs. Dispatch `licensing-verify.yml` at `main` with its single boolean input
`native_only` set to `true`. First record the intended main SHA; verify that each actual run
checked out that exact SHA on `patched-macos-01`, and retain its successful job
logs and conclusion. The licensing input defaults to `false`. Linux is skipped
only for an explicit `workflow_dispatch` with `native_only == true`; ordinary
manual runs, pushes and same-repository pull requests retain the Linux check.
This avoids duplicating a completed Linux suite during controlled native proof.
Neither input selection nor manual dispatch bypasses the native pause guard.

To pause native CI again, set `PATCHED_MACOS_ACTIONS_ENABLED` to `false` through
the approved repository configuration path and verify the value. This prevents
new native job assignments; separately inspect any run already queued or
running rather than assuming the flag cancels it. Leave the diagnostic
workflows disabled. The manual-only runner smoke retains its separate scope.

These are source contracts and an operating procedure, not evidence that
cutover, live enablement or native main verification has completed. Evidence
must identify the actual run, runner and exact checked-out commit SHA, and
distinguish pull-request evidence from integrated-main evidence. A queued,
skipped or cancelled job is not passing verification. Neither Linux success
nor this routing contract waives incomplete macOS, native, browser, review,
exact-head CI or release gates.

CHECK-MODIFIED PAT-2702: the synthetic disposable host-refusal check previously
excluded every VM running the approved guest OS, including the distinct CI
runner. Its test-only preflight retains the existing hypervisor and OS
exclusions and now permits the same-OS VM refusal check only when a read-only
OS account observation positively identifies both a different account name and
a different home from the fixed approved `andy` / `/Users/andy` binding. Unknown,
empty or partially matching identity still refuses invocation on that VM.
The host-refusal case always remains counted and retains its `guestMismatch`
and destination/run-parent no-write assertions. No productive guest guard,
installation target, runtime input or live-proof scope changes. These pure
preflight controls and the synthetic suite do not establish installed proof.

CHECK-MODIFIED PAT-2702: the native Chrome test launcher now allocates its
existing short, canonical, private temporary directory on macOS as well as
Linux. On macOS, only the Chrome child receives `HOME`, `CFFIXED_USER_HOME` and
`TMPDIR` set to that fresh owned directory. This directs the child's application
data to isolated test storage rather than the runner account's real Chrome
application data. Ambient home overrides are excluded; missing allocation
refuses before child spawn. Linux retains its exact environment allowlist and
account home, with the existing owned `TMPDIR`. The parent environment remains
unchanged. The retained run still holds the explicit Chrome profile.

The allocation factory and its private captured cleanup identity are unchanged.
Existing disposal paths remove this temporary home only after confirmed child
termination and unchanged ownership, mode, canonical path, device and inode;
unknown termination or replaced storage is retained. Browser arguments,
sandbox defaults, network-denial flags, CDP, TLS and functional assertions are
unchanged. These source changes and inert controls require fresh review and
actual runner verification; they do not establish a successful browser suite
or native main proof.

The approved Linux runner has official Google Chrome 155.0.8059.84 installed at
`/usr/bin/google-chrome` and `/usr/bin/google-chrome-stable`, resolving to
`/opt/google/chrome/google-chrome`. The setup owner verified a headless launch
with the native sandbox enabled; the runner service was active and enabled after
installation. SSH access is restored through the owner-approved destination-only
IPS signature exception. On 16 October 2026, the unchanged full service gate
passed directly on this Linux host in service-only mode, including the existing
Chrome browser suite, within its original 60-minute deadline. All 619 frozen
source files matched after execution and no owned test processes remained.
This dated direct-host pass is historical evidence, not fresh GitHub Actions,
macOS native or platform acceptance.

On 18 October 2026, Andy approved fixing the recorded PAT-2696 findings, followed
by a fresh independent Codex full-diff correctness/security review by
`gpt-6-astra` at `high`, separate from the `gpt-6.1-sol` implementers, and the
required exact-head and integrated-main Linux CI. This ticket-only exception may
satisfy the local independent-review gate after the findings are fixed; it is
not self-review, general reviewer promotion, NVIDIA TOP wrapper success or a
release waiver. The approval authorises this work; it does not establish that
the fixes, independent review or CI have completed. Original limits, macOS pause
and remaining native, platform and client-release gates remain in force.
