# PAT-2696 fixture-only workflow contract

Run `node --test Tests/CIWorkflowChecks/workflows.test.mjs` from the repository
root. The checker uses only Node built-ins. It reads configuration and never
executes or writes a workflow. Phase A expects the checked-in workflow case to
fail before implementation.

The fixed interface permits only the exact macOS opt-in job guard, the licensing
manual trigger, the same-repository PR condition, Linux labels
`[self-hosted, Linux, X64]`, a first step asserting runner name
`patched-linux-01` before checkout, and a contract-check step after setup-node
and before Chrome diagnostics. The identity step reports runner name and commit.
GitHub compares the opt-in variable with `true` case-insensitively, so `TRUE`
and `True` also enable it; missing values leave all four existing macOS jobs
paused. The same-repository condition denies fork PRs in this workflow;
effective fork denial also depends on the repository's server settings refusing
fork workflows, since a fork can alter its proposed workflow.
Push and manual dispatch retain their existing repository context.

SHA-256 hashes authenticate the complete original four workflow documents after
removing only those exact permitted insertions and reversing Linux routing.
Exact reconstruction also constrains insertion location and count. This is a
bounded text contract, not an arbitrary YAML parser. Alternate syntax, duplicate
keys, added workflows, reordered steps and unrelated byte changes refuse.
Existing steps, timeouts, permissions, checkout credential refusal, pins and
original path filters remain exact. The CHECK-MODIFIED extension adds only
`Tests/CIWorkflowChecks/**`, `.github/workflows/catalogue-ci-diagnostics.yml`,
`.github/workflows/disposable-ci-diagnostics.yml` and `.github/workflows/verify.yml`
immediately after the existing `.github/workflows/licensing-verify.yml` path in
both `pull_request` and main `push` filters. Thus each event covers the checker
and all four protected workflows. All four original baseline hashes and all
37 original cases remain unchanged. No `pull_request_target` event is permitted.

Inert positive fixtures and negative mutation controls verify guard removal and
bypass, default enabling, fork allowance, wrong runner labels and identity,
identity reordering, timeouts, permissions, persisted credentials, action pins,
weakened verification and removed dispatch or contract steps. Independent literal
event blocks verify the complete expected path lists; additional refusals remove
each new path from each event and all new paths from one event only. A local pass
establishes configuration preservation only. It does not establish runner
availability, a Chrome prerequisite, successful service verification or native
acceptance. No runner provisioning or host installation is part of this check.
