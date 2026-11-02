# Consumer platform launch contract

PAT-2605/2606/2607/2608/2609/2611, owner decisions refreshed 9 October 2026. **Accepted policy; proposed proof programme.** No build, registration, installation or runtime test was performed for this document.

## Launch boundary

Launch targets macOS 15 or later on Apple silicon, conditional on actual compatibility evidence. macOS 13/14 and Intel Macs are not promised launch coverage. `Package.swift` at app revision `3787360a2b0df56a9664db1bd6f1bddd238ad8d0` still declares `.macOS(.v13)`; that is the pinned historical implementation state, not the accepted product floor. Changing package, packaging, helper APIs, entitlements, Sparkle and licensing fallback belongs to implementation briefs. A dependency requiring a newer floor must trigger a recommendation with tradeoffs, never a silent floor increase. Future OS versions need verification before support claims.

Automatic third-party candidates must have a usable native arm64 route, including every executed installer, helper, tool and required plugin dependency. Universal labels, filenames, recipes and host architecture are insufficient evidence. Intel-only candidates and hidden Intel-only dependencies are excluded from unattended installation. Patched never automatically installs Rosetta; existing Rosetta does not broaden eligibility. Intel apps remain visible. Manual Rosetta workflows need separate scope.

An existing Intel installation may migrate only with independently verified exact product, edition, stable channel, licence eligibility, installed-state/data compatibility and safe transaction/recovery evidence. Matching bundle ID alone proves none of these. No silent paid-generation/channel change or app-data deletion; preserve App Store routing, signature/notarisation, permission, consent and closed-app gates.

## Named proof matrix

These are **proposed matrix identifiers, not provisioned or authorised machines**. Each cell was UNRUN in the 9 October proposal. Current bounded native observations belong to PAT-2673 and its [native journey matrix](native-journey-proof-matrix.md); they do not complete this full launch matrix. Before execution bind each identifier to an approved disposable target, hardware/VM identity, OS build, app/helper signed build, signing Team ID and test source SHA. Do not infer macOS 15/26 proof from the current macOS 27 host or from a build/offscreen test.

| Scenario / owning brief | `launch-macos15-arm64` | `launch-macos26-arm64` | `launch-macos27-arm64` |
| --- | --- | --- | --- |
| Drag Patched to Applications; signed identity, first launch, relocation and upgrade continuity / PAT-7, H3, PAT-2609 | UNRUN | UNRUN | UNRUN |
| App Management not determined, allow, deny, revoke and grant restoration for exact responsible process / H3/H7 | UNRUN | UNRUN | UNRUN |
| Optional helper declined, approved, removed, disabled, reapproved; separate capability and consent reporting / H3/H7 | UNRUN | UNRUN | UNRUN |
| Account-free scan/view, default two roots, explicit extra root, denial, aliases, duplicates and offline volume / C7 | UNRUN | UNRUN | UNRUN |
| Native UI, accessibility, newly supported page, private request status and deduplicated completion fallback / C8 | UNRUN | UNRUN | UNRUN |
| Signed catalogue, unknown key, tamper, expiry, rollback, withdrawal and architecture/dependency refusal / C1/C7/H4 | UNRUN | UNRUN | UNRUN |
| Exact approved native/universal installed success and verified recovery; unsafe migration refusal / C10/H4 | UNRUN | UNRUN | UNRUN |
| Shared Mac, cross-user IPC denial, durable queue, logout/login, FileVault reboot, no login delay / H3/H5/H6 | UNRUN | UNRUN | UNRUN |
| Awake/idle/app closed, updater races, low battery/Low Power Mode, limited data and explicit restart/interactive consent / H6/H7 | UNRUN | UNRUN | UNRUN |
| Secure-key preferred/fallback, household allocation, expired entitlement refusal with safe recovery / PAT-2605 | UNRUN | UNRUN | UNRUN |
| Separate Patched self-update, default automatic/opt-out, expiry, helper quiescence, permission/signature continuity and rollback / PAT-2609 | UNRUN | UNRUN | UNRUN |

Proposed evidence path: `evidence/platform-launch/<matrix-id>/<run-id>/report.json`, introduced by each owning implementation brief. Record exact actions/exit results, before/after identities and hashes, observed permission states and signed responsible app/helper/installer identity, recovery outcome, limitations and review. Redact credentials and personal paths. Proposed native command: `./scripts/prove-platform-launch.sh --target <approved-target-id> --matrix-id <matrix-id>`; script does not exist and has not run. H7 owns introducing the matrix runner, with C10/PAT-2605/PAT-2609 supplying their scoped proof adapters; implementation remains blocked until that integration brief and target authority are accepted. Pure fixture checks and real target checks must be separate. New target installation authority is required before the latter.

## Setup and authority

Accepted customer setup is drag-and-drop Patched into Applications plus an optional administrator-approved helper. App Management consent is separate: neither administrator authentication nor helper approval implies that grant. Scan/view capability remains distinct from permission to mutate protected apps. Identify the actual signed responsible process for each route on every matrix OS; do not promise a single approval or that root bypasses TCC. No programmatic grant, silent Full Disk Access or Accessibility workaround.

Apple describes App Management as controlling apps' ability to change other apps in [macOS 15](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/15.0/mac/15.0), [26](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/26/mac/26) and [27](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/27/mac/27). [ServiceManagement](https://developer.apple.com/documentation/servicemanagement/smappservice) is the separate helper-registration API. Those references do not establish Patched's responsible identity, granted state or working route. Those facts remain native proof gates.

Route evidence scope, 27 October 2026: PAT-2724 does not require central download/VM deployment for each release. Use targeted mechanism tests for new/materially changed routes and credible failures/risk, with representative success, refusal and recovery. Clients verify actual downloaded trust and installed results; vendor function/data migration is not certified by a Patched bundle rollback. This leaves the applicable OS/helper/permission and installed-journey proof gates intact.

DONE-WHEN for launch coverage: each applicable cell has actual approved-target evidence and required independent review; unresolved cells block the corresponding claim/route. Documentation acceptance, compiled targets, merged code and positive inspection alone cannot satisfy this matrix.
