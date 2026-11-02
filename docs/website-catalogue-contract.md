# Public website catalogue contract

PAT-2611, 9 October 2026. **Design only, no public coverage claim or publication.** Companion: [bounded implementation plan](website-catalogue-implementation-plan.md), [catalogue authority](catalogue-service-architecture.md), [platform launch contract](platform-launch-contract.md). Exact fields, limits and paths below are proposals for independent review.

## Current source and release boundary

App source: `Patched-LTD/patched-mac-app` revision `3787360a2b0df56a9664db1bd6f1bddd238ad8d0`. Website source: `Patched-LTD/website` remote `main` confirmed read-only at `d35bfd82dd8a80cddb9250260bdd4d1197bc57c8`. The preserved PAT-2594 worktree is `d068bf803f1890a3f406fc5d7d37d59e5fb4960d`; the canonical website checkout at `4a577bcccf16c4a77377ea88cf5080ded5d362af` is older retired-site source and was not treated as current. Current website files were read using `git show origin/main:<path>` without checkout/ref changes.

Live PAT-2594 records the completed consumer SEO release, PR179 and its dated Workers version/readback. Current source additionally includes the waitlist Worker and welcome-email work. Neither that ticket's old deployment evidence nor the current source SHA establishes today's deployed version. Implementation must refresh the active deployment separately.

`wrangler.jsonc` currently serves static assets from `.` through `ASSETS`; `worker/index.mjs` handles `/public/waitlist` and otherwise delegates to assets. Selective `run_worker_first` covers waitlist paths. The same runtime has `WAITLIST_DB`, `EMAIL`, `WELCOME_EMAIL` and a five-minute scheduled waitlist task. Catalogue code must receive a narrow public-read transport, never these bindings. Module isolation is not runtime isolation; the separate catalogue-serving Worker owns publication/trust, and website deploy authority remains security-sensitive.

Established release path is Cloudflare Workers Builds after merge/push to website `main`, check **Workers Builds: patched-im-website**. GitHub workflows verify, not deploy. No manual fallback on a failed established queue deployment. Website AGENTS still describes Patched as in development; no download/buy/start-trial or unsupported feature claim is unlocked by this design. Legal PR189 exact-copy approval remains separate. The requirements/feature matrix stays internal.

## One authoritative support record

Catalogue publisher generates public support metadata from accepted route policy and successfully verified, published evidence. Research candidates, queue success, user notes, old fixture catalogue records and recipe labels cannot create public support. The client newly supported page and website consume this same projection and revision; neither keeps a hand-edited list. Detection-only requires independent validated matching/provenance evidence, and must say it cannot establish an installation route. Installation-route coverage requires actual approved native installation/recovery proof for the declared scope, beyond artifact inspection.

Proposed strict `PublicSupportRecordV1`, closed schema with unknown/duplicate fields rejected:

| Field | Meaning / proposed bounds |
| --- | --- |
| `supportID`, `productID`, `scopeID` | Stable opaque IDs, <=128 ASCII characters each; distinct edition/channel/route scope, never customer/request IDs. |
| `appName`, `developerName` | Plain display text <=128 characters each; independently verified names. No HTML/Markdown. |
| `scope` | Explicit edition/generation label, stable channel, minimum/maximum tested OS and usable native architectures; unknown boundaries remain unknown. Bounds <=128 characters per label. |
| `coverage` | `detectionOnly` or `verifiedUpdateRoute`; `routeKind` is bounded reviewed enum when applicable, never executable instructions. |
| `verifiedVersion`, `verifiedAt`, `validUntil` | Exact evidenced version (<=128), UTC timestamps; omit version only for explicitly version-independent detection evidence. No date invented from request/research creation. |
| `firstSupportedAt`, `supportChangeID` | Publisher-assigned first verified publication of the title and scoped meaningful coverage transition; routine versions do not reset first-supported date. |
| `officialVendorURL` | Reviewed HTTPS public product page <=2048 characters, approved host, no credentials/query/fragment; no installer, internal job, receipt or status-token URL. |
| `limitations` | <=512 plain characters of reviewed compatibility/edition limitations, not copied private notes. |

Launch scope follows [platform and architecture eligibility](platform-launch-contract.md). OS/version labels reflect evidence, not a blanket promise for every Mac or future OS. A row does not authorise fresh-app installation, change licence rights, override App Store routing or prove the visitor's installed edition is eligible. Client installed-app matching remains local.

Prohibited fields: inventory/paths, account/licence/activation data, request tokens/notes/vendor suggestions, worker identities/evidence/logs, source credentials, signed private URLs, pricing/entitlement or internal requirements. Generate with an explicit allowlist from typed accepted evidence, never serialise a database object then remove known secrets. Website search is local and sends no query or installed-app information to the catalogue service.

## Signed projection and atomic publication

Extend the proposed v2 signed catalogue payload with a `publicSupport` projection descriptor: schema, exact SHA-256/length, catalogue sequence, policy digest and validity. Generate canonical projection bytes first, then bind their digest inside the signed catalogue. This is a proposed protocol extension, not a capability of current v1 fixtures. Client and website independently validate the same catalogue signature with separately app/website-distributed trusted public keys, then exact projection bytes/digest/schema/validity. Online catalogue data cannot introduce a replacement root. Ordinary key rotation uses independently authenticated signed app releases and separately reviewed website deployments, preserving PAT-2606 compromise gates. Website verification runs server-side; the browser does not independently pin catalogue trust. Compromise of website server/deploy authority can still falsify public claims, a residual risk requiring deployment review and monitoring.

Projection envelope contains matching `catalogueID`, sequence, schema, issued/expiry, sorted complete records and explicit withdrawn scope IDs. Proposed limits: 1 MiB projection, 1000 records, bounded record/text lengths, no arbitrary nested objects. Existing catalogue envelope limits remain separate. Growth beyond bounds needs reviewed pagination-by-signed-manifest chunk digests; do not truncate silently or load unbounded data.

Publisher stages immutable catalogue and projection objects in R2, reads both back, verifies bytes/signature/digests and applicability, then atomically compare-and-swaps one existing publication pointer to their immutable identities. Pointer change follows the publication intent/sequence rules in PAT-2606; do not assume multi-object R2 writes are atomic. Final serving readback verifies the pair before reporting publication. Failure before pointer change retains the previous committed revision; failure after it reports degraded until readback succeeds. Never mark a request supported from a partial upload. No website deployment is needed for an ordinary data publication.

Corrections/withdrawals advance the signed sequence and carry explicit scope tombstones; never resurrect old coverage by moving a pointer backwards. Emergency rollback is a new higher-sequence corrected publication, not acceptance of old signatures. Title withdrawal suppresses the active-support row and completion eligibility. Reintroduction preserves title history; new scope availability has its own change ID. Exact release-copy approval remains required before initial public claims, even if data is cryptographically valid.

## Website/client serving and freshness

Propose website routes `GET /catalogue`, `GET /catalogue.html` and `GET /public/catalogue`, with selective Worker-first routing. A pure website catalogue module fetches only a fixed approved public catalogue origin and immutable digest-bound paths; it cannot follow arbitrary URLs/redirects or read licence/request services. Server verifies before rendering accessible HTML; JSON returns only the validated projection. Browser enhancement filters/pages that same revision, escaping all text, with no raw HTML insertion. The static template fallback states that current support data is unavailable and makes no populated coverage assertion.

Recommended current-pointer refresh <=5 minutes on visits, conditional ETag requests, bounded timeouts/response bytes and coalesced fetches. ETag includes sequence and projection digest; a 304 is accepted only for the exact previously validated revision and unexpired bytes. Cache TTL never exceeds signed validity; this is a proposed cost/freshness budget, not an instant-withdrawal guarantee. Immutable objects may cache long, but current status always checks the bounded pointer age. No browser timer when hidden, per-keystroke requests or background polling by every site visitor. Record aggregate fetch/cache/verification/degraded counts without query strings, inventory or private tokens; unknown operational spend stays unknown.

Client checks at its ordinary catalogue opportunity and page open under the same bounded policy. Client/website may briefly differ within the explicit refresh interval; display revision and last successful verified time. Expired data never displays current verified coverage or triggers completion. Offline/stale views say last checked/unavailable, disable current-support assertions and retain explanatory history only. An upstream outage with unexpired cached bytes is labelled cached and dated; after expiry show unavailable. Mismatched signatures, revisions, malformed metadata and unverified records are rejected, not substituted by an unvalidated fallback.

Recommended UI: server-rendered title, scope and coverage labels; alphabetical search and 50 rows/page, deterministic ordering, keyboard focus/labels, live result count, semantic headings/table or list and mobile readable layout. Newly supported order is `firstSupportedAt` plus stable ID; ordinary version changes stay version updates. Empty verified projection says no published support entries yet; failed fetch says unavailable; zero search results differ from both. No installer/download buttons. Links are reviewed HTTPS and safely escaped; no arbitrary logos, embeds or third-party tracking requests.

Private request status/completion remains a separate verified-household-session interface with account-bound request IDs and no active-paid requirement. Launch has in-app status/completion and the general client page; optional requester-only opt-in email PAT-2610 is later Backlog, no broadcast. Listing support cannot reveal who requested it or send messages.

## Future SME boundary review

Public support, local discovery/matching, trust, transaction/recovery and helper operations use stable opaque product/scope identities independent of household UI, five-Mac limits, pricing and sign-in flow. Consumer entitlement/allocation stays behind explicit policy/service interfaces. A later shared-codebase self-service small-business product could consume those boundaries for organisation ownership/roles, configuration, deployment and business billing, after concrete scope and migration review. Consumer launch comes first; no fork, tenants, remote commands, enterprise procurement/questionnaires, numerical business cutoff or automatic household migration is introduced. Permission and signing authority never comes from a product-mode flag; some future rework remains likely.
