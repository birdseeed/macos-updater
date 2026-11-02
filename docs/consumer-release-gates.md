# Consumer release acceptance checklist (PAT-941)

## Beta planning alignment, 27 October 2026

The checklist's older central-download/VM assumptions are conditional, not blanket requirements, under PAT-2724 (26 October). Source-verified metadata and approved vendor-native routes may suffice. Client acceptance still verifies actual downloaded bytes/trust and installed results; do not claim byte checks where none exist. Test mechanisms for new or changed routes against credible failures/risk and representative success, refusal and recovery. Vendors own functional behaviour/data migration; Patched owns route safety/outcome. This does not select a wire format or change current checks. PAT-2693's mapping, native v1/fixture v2, signed-evidence and URL migration acceptance remains outstanding; AutoPkg comparison is deferred.

Starter beta scope is seven PAT-2734 Wave 1 candidates, with evidence-backed growth up to candidate 20, not a 20–40 target. Show supported, detection-only, under validation and unsupported status based on real consumer relevance. Prioritise the end-to-end ordinary app journey (PAT-2661/2710/2673), then scheduling (2668) and attention (2669). Include self-update readiness (2609); keep production signing (941/2603) separate from private ad-hoc test authority. Paid-demand validation and production billing are separate from private engineering proof; any beta entitlement/distribution must meet applicable release acceptance. Defer enterprise, OS/App Store replacement, general package management and CVE work; the optional helper design remains.

**Status: proposal, 8 October 2026. Not release authorisation, and no gate below is verified by this file.** It is a checklist for the owner and reviewers to accept, change or refuse. Base `1da37e2b07643af513168fca8f090237f10c0c7d`. Nothing was run, signed, installed, purchased or published to write it.

## Scope and what this does not change

- Covers the current consumer Mac release path for `Patched-LTD/patched-mac-app` only. The 8 October PAT-941 scope requires no enterprise ruleset restoration. No retired repository, pipeline, Windows collector, VPS or schedule is restored, and old PAT-66 settings are not copied.
- The older root rule to restore upstream review at the first customer is read deliberately as: review this consumer release path. It is not a blanket flip of every retired repository. No Windows CodeQL obligation is carried over.
- No decision to enable or disable any gate or ruleset is recorded or implied. An enforced release interlock needs an owner-reviewed design; none is implemented. Where the owner chooses a protected path, this checklist can be its acceptance plan: repo-local readback plus negative proof that a red PR cannot publish.
- The local NVIDIA compensating review stays mandatory before production. All future logic needs independent OpenCode/NVIDIA review under the canonical review gate; blocked review is not a pass.
- Existing gate: `./scripts/verify.sh` covers the twelve reference cases plus artifact, catalogue, transaction and view checks on source and fixtures ([build-verification.md](build-verification.md)). Merged PR #12 added only the installed-proof runbook. There is no shipped Mac product, production catalogue trust, customer activation or provider lifecycle.

## Gate table

Status values: **satisfied locally**, **partial**, **not verified**.

| # | Gate | Trigger | Acceptance evidence | Status | Owner / dependency | Bounded next step |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Reproducible build and provenance | Any release candidate | Exact review SHA, tool and lockfile versions, artifact SHA-256, and a readback of the hash from the published location | partial: source gate and pins exist, no release artifact | Release lead; Swift 6+ toolchain | Define the record format; build nothing yet |
| 2 | Developer ID signing | Candidate artifact exists | `codesign --verify --strict` and `spctl` results on the exact artifact; bundle ID and Team ID match the intended Patched identity | not verified: `security find-identity -v -p codesigning` returned 0 valid identities on 8 Oct, which does not prove Apple membership or absence elsewhere; no Patched Team ID verified | Owner via PAT-7 existing access | First checkable condition: confirm certificate access through PAT-7 |
| 3 | Notarisation and stapling | After gate 2 | Notary submission accepted for the exact artifact, ticket stapled, `stapler validate` and Gatekeeper assessment pass | not verified: no notary profile verified | Owner via PAT-7 | Same dependency as gate 2 |
| 4 | Signing identity hygiene | Any key or identity choice | The Firefox vendor identity `43AQ936H96` is not treated as a Patched signing identity; no reuse of old Windows or Updater keys | satisfied locally as a rule; no identity yet exists to check | Owner | Record the explicit ban in the release record |
| 5 | Pinned artifact evidence | Each pin change | Firefox 157.0.1 Mozilla payload: `codesign`, `spctl` and `stapler` passed on independent read-only proof. Unsigned-container checks remain FAIL and must be reported separately, never masked by a bundle pass | partial | Release lead | Keep both results visible in every report |
| 6 | Catalogue signature, separate from Apple trust | Any catalogue publish | Signature verified against a pinned key; strict identity, freshness, anti-rollback, version fields, pins, signing sequence and exact payload bytes checked ([operator runbook](operator-runbook.md)) | partial: PAT-2583 local fixtures give test-only trust and a fresh inspection to signed catalogue local proof; no production key or public publisher exists | Owner under PAT-2595 | Owner chooses key custody under PAT-2595. This file prescribes no cadence and no new key |
| 7 | Installer and helper boundary | Before any install code is accepted | Written approval of a user-owned install: physical root, symlink, mount, device and concurrent-path protections; no root helper unless explicitly reviewed | partial: fixture transaction exists ([transaction-recovery.md](transaction-recovery.md)); no approved boundary | Owner plus NVIDIA review | Owner decision on the boundary; no code |
| 8 | Fail-closed behaviour | Each install case | No force install, no killing of open apps, no profile copy, no MDM, no Homebrew; refusal is the default | partial: default entry points refuse in fixtures only | Release lead | Add each refusal as a named installed-matrix row |
| 9 | OS checks | Before swap and after install | Tested pre-swap check and post-install check on the installed OS, not fixture replay | not verified | PAT-2584 | Needs the guest OS verifier and harness |
| 10 | Installed matrix | Release candidate | Success, refusal and recovery rows each with hashes, witness and journal, auditable end to end ([installed-proof-runbook.md](installed-proof-runbook.md)) | not verified: PAT-2584 is blocked. Guest `macOS - Staging` UUID `9AAEFEB3-4D36-4ED2-AD13-D2BAADD63246` is started, but login, guest OS, toolchain and paths are unverified, and nothing is installed | Owner gates in the runbook | Next after gate 2 access; no false end-to-end claim before it |
| 11 | Recovery semantics | Failure injection | Recovery restores a validated copy, not just a test reference; an uncertain transaction is reconciled and never repeated automatically | partial: fixture level only | PAT-2584 | One row per uncertain outcome |
| 12 | Supply chain review | Before first release | Review of signing and updater provenance at the NVIDIA Ultra floor, with findings resolved | not verified | Release lead | Run when gates 1 to 3 have evidence |
| 13 | Capability claims | Before public copy | Native, convenience and capability claims appear only after operating proof on the exact desktop and guest UI | not verified | Owner approves copy | Hold all claims |
| 14 | Licence, billing, support | Before any sale | Acceptance, runtime, retention and readiness evidence for [licensing](licensing-contract.md), [device allocation](device-allocation-contract.md), [billing](billing-lifecycle-contract.md) and [support](licence-support-contract.md), even if binary proof passes | not verified: contracts are proposals | Owner | Sequence after binary proof |
| 15 | Privacy | Before release | Approved actual data flows from a local inventory; previewed, opt-in dumps; no zero-collection claim | not verified | Owner | Draft the inventory from real flows |
| 16 | Release owner, publishing, rollback | Before publish | Named owner approval; an established, documented publishing path; outage hold; rollback behaviour validated on the actual installed revision; no manual deploy fallback | not verified: no publishing path chosen | Owner | Choose the path, then add the interlock design |

## Gate order

1. PAT-7 existing certificate and notary access (gates 2, 3). This is the first checkable condition, and PAT-941 stays Blocked on it.
2. PAT-2584 installed proof (gates 9 to 11).
3. Owner decisions on gates 6, 7 and 16.
4. Review, claims, licensing and privacy (gates 12 to 15).

## Limits

- A prepared checklist is not a verified gate. DONE WHEN means each row has its evidence recorded, not that this file exists.
- Reference integrity is against a repository-selected manifest and is not vendor authentication.
- The proof inspector detaches and removes its mount before returning. The installed-stage OS verifier and harness are future work.
- Docs-only: the local 1012-check gate was not rerun for this prose. Required pull request and main CI must pass; those runs verify the source gate, not a released or installed product.
