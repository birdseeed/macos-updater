# Explicit local scheduling clock

`NativeScheduleClock` supplies process-local whole-second `ClockSample` values to
the existing scheduler model. Construction performs no I/O. Only an explicit
`sample()` or `reanchor()` reads the clock; there is no timer, observer, app
composition, catalogue check, helper, queue start or installation path here.
Outputs are neither persisted nor sent anywhere by the sampler.

The private native reader uses Darwin `clock_gettime` with `CLOCK_REALTIME` and
sleep-inclusive `CLOCK_MONOTONIC_RAW`. It brackets the real-time read with two
monotonic reads and reads `kern.bootsessionuuid` before and after that bracket.
Each boot read has a fixed 37-byte buffer, requires exactly 36 ASCII UUID bytes
plus the final NUL, and rejects malformed or all-zero identities. The pair must
retain exactly the same UUID bytes, including case. There is no subprocess,
fallback clock, generated boot identity, sizing retry or read retry. Missing OS
facilities and read errors refuse a sample.

A raw pair must be ordered and span at most 50,000,000 nanoseconds. Its midpoint
is `before + (after - before) / 2`, avoiding addition overflow. Wall seconds must
be finite, nonnegative and safely convertible, after flooring, to `Int64`.
Native timespec nanoseconds must be in `0..<1_000_000_000`; conversion to total
monotonic nanoseconds checks multiplication and addition overflow.

The first valid observation anchors independent whole wall and monotonic
seconds. Later samples add `floor(midpoint elapsed nanoseconds / 1_000_000_000)`
to both initial whole-second values using checked arithmetic. Aligning these
increments preserves the existing strict equal-elapsed-seconds predicate even
when the raw clocks have different fractional phases. The raw wall elapsed
value must agree with midpoint elapsed time within 250 milliseconds inclusive.
The sampler also rejects raw wall rollback, a new monotonic bracket beginning
before the preceding bracket ends, and any changed boot identity. This is a
bounded local projection; floating-point wall readings have their native
precision limits and do not authenticate time.

A projected UTC second ahead of the current observed whole-wall second also
refuses and latches invalid time. Even drift within the tolerance cannot make
the projected clock describe a saved UTC pause deadline as reached early.

Any invalid pair, read error or unsafe projection latches this sampler invalid.
Ordinary samples cannot clear that latch. Explicit `reanchor()` validates a
fresh pair and replaces only this sampler's anchor; a failed reanchor retains
the invalid latch. It never mutates `PreferenceSession`. The caller must report
clock invalidation to its session and separately use the existing explicit
session reanchor operation, which retains its full-day cadence deferral and
callback invalidation rules.

The existing `ClockSample.trustedUTC` flag is set solely to satisfy the local
scheduler usability predicate. It does not mean authenticated UTC, licence or
catalogue freshness, OS permission, installation authority or productive trust.
The Testing SPI raw-reader constructor supplies untrusted controlled fixtures,
performs no read during construction and conveys no native or installer
capability. Neither that seam nor the ordinary sampler changes existing strict
clock predicates, preference stores, codecs, accounts or scheduling ownership.

Controlled checks establish deterministic projection and refusal behaviour
only. They do not exercise native clock/sysctl availability, app composition,
guest sleep/wake behaviour or installed updates. Native observations and
source-bound guest proof remain separate verification work.
