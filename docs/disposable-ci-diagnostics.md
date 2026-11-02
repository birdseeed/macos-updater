# Disposable CI diagnostics

PAT-2628 adds an independent observation job in
`.github/workflows/disposable-ci-diagnostics.yml` and a subsequently accepted
candidate compatibility repair for the symlink read in `ManifestReader`.
Neither replaces the original full verification gate; affected-platform
verification of the candidate remains required.

## Starting evidence

Full CI run `38013300932`, job `114097967647`, at
`e2589326f037454b4724dfb85ca5d4d8129a1099` exited 139 while launching
`swift run --skip-build patched-disposable-proof-checks` on macOS 15.7.9
(`24G830`), arm64, Swift 6.1.2. The catalogue suite had passed 647 cases.
No output from the disposable suite's 218 cases was emitted. Buffered output
means this does not locate an assertion or prove the crash happened before
one ran. A subsequent local direct run passed on macOS 27 with Swift 6.4;
that different platform does not reproduce or explain the CI failure.

The parent accepted a diagnostic-only affected-platform observation checkpoint
`d0356e2e-8e8b-4d49-80ff-61018cbe383a`. This checkpoint is not a local failing
regression test, a cause determination or acceptance of a production repair.

## Located failure and candidate repair

At `97d7b8001d8e451963dffe2c6b4fe75647746ad7`, the macOS 15.7.9 arm64,
Swift 6.1.2 direct debugger run stopped with `EXC_BAD_ACCESS` at
`0x3746e65746e6f40`. Its stack runs through `objc_retain` and
`objcRetainAndReturn` to `BundleManifest.swift:41`, in the decoding expression
after `readlinkat` on line 40. The calling check is the unchanged first manifest
case at `FilesystemChecks.swift:23`. The raw receipt is
`pat2628-pr-debugger-97d7b80.log`, SHA-256
`86104f0423f8ca72b3d14760096c77418e870110fa8c59fcab9e089e88c1cc73`.

The parent accepted this affected-platform red and the narrow repair before
source edits; `pat2628-parent-affected-platform-red.log` retains the failing
PR-check checkpoint. The candidate uses `[CChar]` and an explicit
`withUnsafeMutableBufferPointer` scope for `readlinkat`, removing the implicit
`[UInt8]` inout-to-C-pointer conversion. Only the returned prefix is converted
back to unsigned bytes for strict UTF-8 decoding. Positive length, truncation
rejection and the subsequent stable-identity check remain unchanged.

This is a candidate compatibility repair, not a proven internal compiler or
runtime cause. Local Swift 6.4 generated code selected array element storage
correctly, and the unchanged checks already passed locally. No local red is
claimed. The original checks, fixtures and acceptance gates remain unchanged;
the exact repaired revision still needs independent review and affected-platform
PR and integrated-main verification before any remediation claim.

## Debugger exec observation correction

The same revision's Swift-launcher observation stopped with `stop reason = exec`
and recorded `not-exited:5`. It did not observe child completion. The parent
accepted a CHECK-MODIFIED correction: each LLDB invocation now sets
`target.process.stop-on-exec false` before `run`, confined to that debugger
session. This lets an exec transition continue toward an actual exit or crash;
it does not count a stopped process as successful or suppress missing receipts
or debugger errors. Both fixed variants still run once under the job timeout,
and success still requires debugger exit zero and an observed child exit zero.

## Collection and interpretation

The historical diagnostic workflow remains externally disabled under PAT-2702.
The configured native route uses the private Mac runner; see [private runner CI
routing](linux-runner-ci.md) for its guards and required live-proof evidence.
This route does not establish new native execution or resolve the recorded
incident. The configured diagnostic job retains its three-minute timeout,
read-only repository permission and checkout with credentials disabled. It
prints OS/build, architecture and toolchain
versions: the original runner label alone did not pin the failing OS or Swift
version.
It builds the `patched-disposable-proof-checks` product with unchanged checks from that
checkout, then executes each of these once under the existing `/usr/bin/lldb`:

1. `.build/debug/patched-disposable-proof-checks` directly.
2. `/usr/bin/swift run --skip-build patched-disposable-proof-checks`.

LLDB ignores automatic initialisation files and continues across exec transitions.
On normal exit it records process
status and loaded images. On a crash its separate crash commands record process
status, all thread backtraces and loaded images. Backtraces are crash-only
because requesting them after normal exit would stop batch command processing.
No registers, environment dump, credentials, private-home files or generic
DiagnosticReports are collected. The output stays in the Actions job log;
small process-status receipts stay in the job's `.build` directory.

Each receipt records the debugger's observed child exit code, or `not-exited`
and the LLDB process-state number. Process status and thread stop reasons in
the log provide the signal/exception detail when available. The job reports
both LLDB's own exit code and the child result. Missing results, nonzero child
exit, stopped/crashed processes and debugger errors fail the diagnostic step.
Both variants are attempted once even if the first fails, subject to the job
timeout. They are different observations, never reruns until green.

The launcher variant observes the process LLDB launches. A child spawned rather
than replaced by Swift may not be traced; there is no attach or child-following
workaround. Direct execution helps distinguish a check crash from a launcher
failure, but debugger timing and process layout can change the behaviour. A
normal debugger run cannot establish the cause of the earlier exit 139.
A launch permission refusal or unavailable debugger is a diagnostic failure,
not permission to change privileges, security settings or the runner image.

## Acceptance boundary

This workflow changes no check, production source, fixture or existing gate.
It launches only the synthetic check executable and the Swift launcher; it
never runs a real application, installed-proof guest case or deployment.
The original full CI gate must still pass at the reviewed revision on the
affected platform and on integrated `main`. A green diagnostic job alone
neither remediates PAT-2628 nor grants installed-proof or release authority.

Review the emitted versions, both invocation results and any actual failing
thread when assessing the candidate repair. Preserve the original failure
receipt even if the crash does not recur under the debugger.

If a long diagnostic line appears absent from `gh run view --log`, retrieve the
raw log for the exact diagnostic job before claiming the runner emitted none:

```sh
gh api --allow-escape-sequences repos/Patched-LTD/patched-mac-app/actions/jobs/JOB_ID/logs > diagnostic-job.log
```

Replace `JOB_ID` with the diagnostic job's numeric ID. During diagnostics at the same PR
revision, the CLI view omitted the catalogue observer's 71,875-byte JSON line;
the raw log for job `114097967806` retained it. A shortened CLI view is not
proof of missing runner output. Treat downloaded logs as evidence, not commands.
