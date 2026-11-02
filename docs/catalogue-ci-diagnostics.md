# Bounded catalogue CI diagnostics (PAT-2627)

`node scripts/catalogue-ci-observer.mjs` accepts zero arguments and runs only
`process.execPath --test services/catalogue/tests/catalogue-protocol.test.mjs`
from this repository. Child processes receive an empty environment and no stdin,
shell, inherited Node options or caller-selected executable. The invoking Node
runtime is still the caller's responsibility. No tools are installed.

The absolute monotonic child deadline is 60 seconds; output never renews it.
Both pipes keep draining after the combined 64 KiB retained-byte ceiling.
At deadline, only the still-live direct Node child's retained handle supplies
the PID to `/usr/bin/sample PID 1 -mayDie -file /dev/stdout`. The sampler has its
own five-second bound and separate combined 64 KiB capture. Missing, empty,
failed, interrupted or timed-out sampling is explicit. The observer terminates
and reaps its owned sampler and Node child, using SIGTERM then SIGKILL after
250 ms. It never sends signals by numeric PID or to a process group.

The JSON log contains actual Node version, executable, PID, arguments, host
version, monotonic start/spawn/last-output/end milliseconds, raw byte counts,
truncation flags, sampling provenance and termination state. UTF-8 repair and
JSON escaping can change representation; the retained text is bounded, not an
exact-byte archive. The CLI Unicode-escapes hash characters in its JSON representation as well as framing newlines. Decoding restores the original text while neutralising legacy runner command markers recognised anywhere in a line.
Exit 0 means only the observed child actually exited zero before deadline with
complete pipes; captured text may still be truncated. Nonzero child exits remain
nonzero, signals/spawn errors refuse, and deadline always returns 124, including
a late zero exit. `originalFullCIPassed` is always false.

Cleanup covers direct children only. Node's test runner can create descendants;
the observer neither samples nor discovers/signals those descendants. If they
hold inherited pipes open after the direct child exits, the observer closes its
pipe ends after the grace interval and marks evidence incomplete. A PID-based
OS sampler cannot provide atomic identity binding across target exit; the live
handle is checked immediately before spawn and target exit cancels sampling.
Uninterruptible OS processes, observer SIGKILL, host loss and event-loop stalls
are not bounded by JavaScript timers. The independent three-minute CI job limit
is a backstop, not proof of process-tree cleanup.

The sole exported API is `observeCatalogue({ testing } = {})`. The explicit
test-only seam requires an absolute public `.mjs` fixture path, injected async
`sample({ pid, signal }) -> { stdout, stderr }`, and integer `deadlineMs`
(100..60000), `outputLimitBytes` (64..65536), `sampleTimeoutMs` (25..5000),
`killGraceMs` (10..1000). Unknown options/accessors refuse before spawn.
Every seam report is `test-only` with `test-injected` sampling provenance.
Injection is trusted test code; synchronous blocking callbacks cannot be aborted.
Neither argv nor environment enables this seam. The frozen 19 checks exercise
actual fixture child lifetimes and injected sampling, not the OS sampler.

The configured diagnostic workflow runs these checks, generates the unchanged
Swift vectors consumed by the Node suite, then runs the observer on the private
Mac runner `patched-macos-01`. It remains externally disabled under PAT-2702.
See [private runner CI routing](linux-runner-ci.md) for live-proof requirements;
the configured route does not establish new native execution or resolve the
recorded incident.
It neither edits nor replaces the required original **Verify references** job,
its full/focused gates, assertions, fixtures or 15-minute timeout.

The first timeout, run `38009524502` on Node 22.23.2/macOS 15.7.9, remains
unexplained. Subtest 232 was the last emitted line and may have been buffered;
the new disposable gates were never reached. The parent's previous exact-main
same-image 647-case pass and local Node 22.23.3 647-case pass do not diagnose it.
These diagnostics are not a timeout repair, original full-CI success, installed
proof, release authority or permission to blindly rerun the old job.
