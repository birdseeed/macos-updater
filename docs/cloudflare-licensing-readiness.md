# Cloudflare licensing readiness plan (PAT-2592)

**Status: PREPARATION PARTIAL. The licensing app is not ready.** This is a docs-only plan written at baseline `3b42b8b`. It created no resource, send, DNS record, key, deploy or spend, and ran no production runtime code. The local verification gate checks existing fixture code only. The licensing contracts (`docs/licensing-contract.md` PAT-2587, `device-allocation-contract.md` PAT-2588, `billing-lifecycle-contract.md` PAT-2589, `licence-support-contract.md` PAT-2590) are all **PROPOSED, unaccepted**. Owner acceptance of those contracts precedes any implementation. Nothing here implements them. Labels: **[EVIDENCE]** observed and dated; **[PROPOSAL]** a recommendation that exists nowhere yet.

## 1. Evidence versus proposal

| Item | Status | Detail |
| --- | --- | --- |
| Parent account | [EVIDENCE] | Connected account ID `65cf28592cbb9526a61d3b8a569221be`. |
| Development D1 | [EVIDENCE] | `patched-licensing-dev`, UUID `87cbe6b9-a7e1-439c-9901-f2a7acb24ca0`, EU, 0 tables, 12288 bytes. Its engine designation is `production`; that is the engine label, not an application production environment. |
| Sender domain | [EVIDENCE] | `notify.patched.im`, sender ID `4941c526544e4653ad6e96fb00edf373`: enabled true, preview enabled true, suppression-dropping false, DNS status ready, SPF/DKIM/DMARC configured. |
| Email API quota | [EVIDENCE] 8 Oct | Daily quota 1000, sent 3, over-quota false, reset 9 Oct 09:11:15 UTC. This is a **daily** send quota, not the monthly account bill or the pricing allowance. |
| Subscriptions API | [EVIDENCE] | Account subscriptions query returned `10000 Authentication error`. Actual bill, account-wide Workers and D1 usage and remaining headroom are **not verified**. |
| Earlier dashboard snapshot | [EVIDENCE, dated] | Workers Paid Active, owner activation, renews 30 Oct; setup email Delivered with owner receipt. Superseded by nothing newer, but not re-read this task. |
| PAT-2573 | [EVIDENCE] | A same-Worker email binding sent a welcome that was actually received; the owner content was accepted and test data cleaned up. This proves the **waitlist** path only, not a licensing binding. |
| Licensing resources | [PROPOSAL] | Everything in sections 3 to 8. Nothing below is created. |

## 2. Pricing basis (official pages read 8 Oct 2026; derived summaries only)

| Source | Figures relied on |
| --- | --- |
| https://developers.cloudflare.com/workers/platform/pricing/ | Paid base $5 includes 10M requests and 30M CPU ms. Overage $0.30 per million requests and $0.02 per million CPU ms. |
| https://developers.cloudflare.com/d1/platform/pricing/ | Paid includes 25B rows read, 50M rows written and 5GB storage monthly. Over that: $0.001 per million rows read, $1 per million rows written, $0.75 per GB-month. |
| https://developers.cloudflare.com/email-service/platform/pricing/ | Sending to arbitrary recipients needs Workers Paid. 3000 emails per account billing month included, then $0.35 per 1000 accepted emails. Verified-destination sending is free and not part of the quota. |

Prices can change; recheck before any commitment. None of this is plan, spend or purchase approval, and the £500 cap in `AGENTS.md` is not purchase authority.

**Scenario (illustrative):** 1000 households per month, 120k requests at 10 ms CPU (1.2M CPU ms), 2M rows read, 100k rows written, 0.1GB, 1000 emails. Each figure sits inside the included allowance above, so the marginal charge would be priced within included allowances **only if** the account's actual remaining monthly usage covers it. That remaining usage is unverified (subscriptions query failed). This is not a zero total: the $5 base is owed regardless, and no unused-quota claim is made.

**Caps [PROPOSAL, planned, not configured]:** per-route rate limits, per-address and per-account send limits, a daily send ceiling below the 1000 quota, and a billing alert. Workers CPU limits bound one request, not spend; This proposal has no verified account spending cutoff; application limits and owner usage review still need implementation.

## 3. Proposed names (only the development D1 already exists; no retired key or database reused)

| Tier | Resource | Name [PROPOSAL] | Notes |
| --- | --- | --- | --- |
| fixture | none | `fixtures/Licensing` (repo files) | No provider, no network. Slice L1 of the licensing contract. |
| development | D1 (existing) | `patched-licensing-dev` | Existing EU DB, empty. Worker `patched-licensing-dev`. |
| sandbox | D1 (future, separate) | `patched-licensing-sandbox` | Worker `patched-licensing-sandbox`, separate database. Paddle sandbox only. |
| live | D1 (future, separate) | `patched-licensing-live` | Worker `patched-licensing-live`, separate database; gated by section 9. |
| hostnames | DNS | `licence-api.patched.im`, `account.patched.im` | **Proposed, not activated.** No record created. |
| sender | email | licence sender on existing `notify.patched.im`, distinct fixed address (for example `licence@notify.patched.im`) | Fixed From; no mailbox, no reroute or forwarding. Not the waitlist sender. |

Staging and sandbox hold no production resources, data or keys, and live holds no fixture or sandbox ones.

## 4. D1 design mapped to existing contracts (no new policy)

- **Atomic batch:** state changes use one `batch()` with conditional SQL; zero rows affected is never success (licensing section 8 and 9; device-allocation section 6; billing section 6 and 7).
- **Idempotency:** client idempotency key for trial start; `requestID` plus action digest for activation; raw-body and semantic digests for webhooks; fenced reconcile claims. As written in the contracts.
- **Index:** partial unique indexes for single-active rows are a candidate only and **untested on remote D1** (licensing section 9).
- **Reconciliation:** billing section 7 sweep (at least every 24 hours, proposed) repairs missed events. Device and support contracts add their own revision rules.
- **Backup and restore [PROPOSAL]:** record a D1 recovery point before each approved migration, retain encrypted owner-restricted exports under the approved retention policy, and rehearse restoration into a separate disposable database. Refuse live activation and lease grants during recovery. Compare restored accounts, provider events, activation revisions and idempotency records with authoritative provider state; reconcile forward before reopening. Database identity, retention, recovery window and restore support must be verified before live use. No restore or export was performed.
- **Atomicity proof:** **no actual remote atomicity evidence exists.** Emulator results are not remote proof (licensing section 12). Required: concurrent challenge consume, trial start and slot activation against the development database, once the contract is accepted.
- **Reads:** primary only for licence decisions; no replica reads (licensing section 9).

## 5. Keys and custody (names and process only; no values here)

| Purpose | Name [PROPOSAL] | Custody and rotation |
| --- | --- | --- |
| Lease signing | `LICENCE_LEASE_SIGNING_KEY_V1` | Worker secret per tier, distinct per tier. Public key ID shipped in the app. Rotation adds a new `keyID`; old public keys stay verifiable until leases lapse. |
| Sign-in challenge HMAC | `LICENCE_OTP_HMAC_KEY_V1` | Separate Worker secret per tier; review challenge invalidation on rotation. |
| Session protection | `LICENCE_SESSION_HMAC_KEY_V1` | Separate Worker secret per tier; session invalidation and overlap policy need review. |
| Runtime bindings | `LICENCE_DB`, `LICENCE_EMAIL` | Proposed bindings to the exact tier database and fixed licence sender; no account API token in runtime. |
| Provider API and webhook | `PADDLE_API_KEY`, `PADDLE_WEBHOOK_SECRET` | Sandbox and live separate. Not created in this task. |
| Operator identity | allowlist entries, no secret | Per the support contract. |

Rotation owner and offline backup custody are unresolved (section 10). No key is generated, read or stored by this document.

## 6. Least privilege

- **Runtime Worker:** bindings only to its own tier's D1 and email send binding; no account token, no DNS or deploy rights.
- **Scoped CI [PROPOSAL]:** minimum supported Workers/D1 deploy permissions, no DNS authority. Verify actual provider scoping and secret-access behaviour before provisioning; do not assume a token can be restricted to one Worker. Separate approved sandbox and live credentials, protected environments and an explicit resource-ID allowlist in deployment checks.
- **Operator:** support actions through the audited prepare-confirm-commit route, not raw database access.
- The intended isolation is separate tier resources and credentials. It is not configured or proven here.

## 7. Mail adapter

One adapter operation (recipient, template, parameters), per owner policy O9. Sender suppression-dropping is false; verify the adapter response semantics before implementation. An accepted send is not proof of delivery. Definitive suppression or permanent bounce is a known failure; an unknown or lost outcome is ambiguous. A lost or unclear send result is recorded `ambiguous` and **never blindly retried** (billing section 10). Sign-in code requests use the same non-enumerating response. Tests use fixtures; any real send needs separate owner approval.

## 8. Release path

Source-controlled and reviewed: a PR is required, checks must be green, and a provider workflow deploys. After deploy, verify the version and run live checks. Rollback is to the previous Worker version, then forward data reconciliation, since a database rollback is not assumed safe. **No new release workflow is added now and there is no manual fallback.** Real logic also needs the independent review gate in `AGENTS.md`.

## 9. Unresolved owner and actions

| # | Owner / action | Recommendation and reason | UNBLOCKS-WHEN |
| --- | --- | --- | --- |
| R1 | Andy: accept the four licensing contracts | Accept after review; implementation is otherwise unauthorised. | Each contract's status line reads accepted with a dated owner ruling. |
| R2 | Andy or parent: actual bill and usage | Fix the token or read the dashboard; the scenario cannot be claimed without it. | A dated record of account-wide Workers, D1 and email usage for the current billing month. |
| R3 | Parent: remote atomicity | Run concurrency checks on `patched-licensing-dev` after R1. | Recorded results for consume, trial and slot races on the remote database. |
| R4 | Parent: backup and restore rehearsal | Rehearse on a throwaway database; Time Travel is unverified here. | A recorded restore with reconciliation counts. |
| R5 | Andy: hostnames and sender | Approve `licence-api.patched.im`, `account.patched.im` and a distinct licence sender. | Written owner approval naming each hostname and address. |
| R6 | Andy: separate sandbox and live databases and spend | Create only when needed; sandbox first. | Owner approval of the resource and a monthly spend ceiling. |
| R7 | Andy: key custody and rotation owner | Name an owner and offline backup location before generating keys. | Recorded custodian and rotation interval. |
| R8 | Parent: abuse and cost caps | Implement application limits and verify the available billing controls. | Limits configured and shown in a test. |
| R9 | Andy: toolchain and service placement (G4) | Keep `service/licensing/` in this repository and amend `AGENTS.md` in that slice. | `AGENTS.md` amended by an accepted PR. |
| R10 | Andy: retention and deletion (G3) | Adopt licensing section 10 as the review baseline. | Dated retention approval. |
| R11 | Parent: mail production eligibility and bounce handling | Confirm any sending limits and suppression behaviour with a read-only check. | Written provider evidence of limits and bounce behaviour. |

## 10. What this proves and does not

Proven: the account, empty development database and sender configuration were observed as dated above. Not proven: actual bill and remaining usage, licensing Worker binding, remote atomicity, backup and restore, key custody, hostnames, licensing sender, production sending eligibility, any cost. **Cloudflare preparation is partial; the licensing app is not ready.**
