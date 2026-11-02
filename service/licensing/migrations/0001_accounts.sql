-- Proposed PAT-2642 local fixture schema. No remote migration authority.
PRAGMA foreign_keys = ON;
CREATE TABLE accounts (
 account_id TEXT PRIMARY KEY, email_hmac TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL,
 revoked_at INTEGER, entitlement_revision INTEGER NOT NULL DEFAULT 0 CHECK(entitlement_revision >= 0),
 activation_revision INTEGER NOT NULL DEFAULT 0 CHECK(activation_revision >= 0)
);
CREATE TABLE account_guard (
 account_id TEXT PRIMARY KEY REFERENCES accounts(account_id),
 account_revision INTEGER NOT NULL DEFAULT 0 CHECK(account_revision >= 0), commit_nonce TEXT NOT NULL
);
CREATE TABLE challenges (
 challenge_id TEXT PRIMARY KEY, email_hmac TEXT NOT NULL, purpose TEXT NOT NULL CHECK(purpose IN ('app-sign-in','web-sign-in','app-reauth','web-reauth','email-recovery')),
 code_hmac TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
 wrong_attempts INTEGER NOT NULL DEFAULT 0 CHECK(wrong_attempts BETWEEN 0 AND 5),
 superseded_at INTEGER, consumed_at INTEGER, consume_nonce TEXT UNIQUE,
 bound_account_id TEXT, bound_session_id TEXT, CHECK(expires_at > created_at)
);
CREATE INDEX challenges_address_purpose ON challenges(email_hmac,purpose);
CREATE TABLE sessions (
 session_id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(account_id), kind TEXT NOT NULL CHECK(kind IN ('app','web')),
 activation_id TEXT, authenticated_at INTEGER NOT NULL, created_at INTEGER NOT NULL,
 access_hmac TEXT NOT NULL UNIQUE, access_expires_at INTEGER NOT NULL,
 refresh_hmac TEXT UNIQUE, refresh_expires_at INTEGER, expires_at INTEGER NOT NULL,
 revoked_at INTEGER, commit_nonce TEXT NOT NULL
);
CREATE TABLE used_refresh_tokens (refresh_hmac TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(session_id), used_at INTEGER NOT NULL);
CREATE TABLE request_limits (request_id TEXT PRIMARY KEY, email_hmac TEXT NOT NULL, ip_hmac TEXT NOT NULL, requested_at INTEGER NOT NULL, sent INTEGER NOT NULL CHECK(sent IN (0,1)));
CREATE INDEX request_email_time ON request_limits(email_hmac,requested_at);
CREATE INDEX request_ip_time ON request_limits(ip_hmac,requested_at);
CREATE TABLE account_requests (account_id TEXT NOT NULL REFERENCES accounts(account_id), route TEXT NOT NULL, request_id TEXT NOT NULL, request_hmac TEXT NOT NULL, commit_nonce TEXT NOT NULL, PRIMARY KEY(account_id,route,request_id));
CREATE TABLE account_audit (
 audit_id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(account_id), action TEXT NOT NULL,
 account_revision INTEGER NOT NULL CHECK(account_revision >= 0), commit_nonce TEXT NOT NULL, created_at INTEGER NOT NULL,
 UNIQUE(account_id,commit_nonce)
);

-- PAT-2643 additive local-only S1b proposal; shared account_guard remains sole fence.
CREATE TABLE entitlement_sources (
 account_id TEXT PRIMARY KEY REFERENCES accounts(account_id),
 trial_started_at INTEGER, trial_ends_at INTEGER,
 beta_invited INTEGER NOT NULL DEFAULT 0 CHECK(beta_invited IN (0,1)), beta_ends_at INTEGER,
 CHECK((trial_started_at IS NULL AND trial_ends_at IS NULL) OR (trial_started_at IS NOT NULL AND trial_ends_at IS NOT NULL AND trial_ends_at=trial_started_at+1209600))
);
CREATE TABLE trial_markers (
 email_hmac TEXT PRIMARY KEY, original_deleted_at INTEGER NOT NULL, expires_at INTEGER NOT NULL
);
CREATE TABLE trial_requests (
 account_id TEXT NOT NULL REFERENCES accounts(account_id), request_id TEXT NOT NULL,
 request_hash TEXT NOT NULL, response_json TEXT NOT NULL, created_at INTEGER NOT NULL, commit_nonce TEXT NOT NULL,
 PRIMARY KEY(account_id,request_id)
);
-- Synthetic pre-A2 issuance snapshot only: no slot allocation or possession authority.
CREATE TABLE lease_heads (
 activation_id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(account_id), device_key_sha256 TEXT NOT NULL,
 activation_revision INTEGER NOT NULL CHECK(activation_revision>0), sequence INTEGER NOT NULL DEFAULT 0,
 released_at INTEGER, last_grant_state TEXT, last_grant_issued_at INTEGER,
 last_grant_permitted_until INTEGER, last_grant_hard_end INTEGER, max_grant_permitted_until INTEGER,
 commit_nonce TEXT NOT NULL
);
-- Closed policy facts, never arbitrary deletion of caller-selected SQL/tables.
CREATE TABLE retention_rows (
 row_id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(account_id), record_json TEXT NOT NULL,
 max_grant_permitted_until INTEGER, pending_provider_intent INTEGER NOT NULL DEFAULT 0 CHECK(pending_provider_intent IN (0,1)),
 reconciliation_reference INTEGER NOT NULL DEFAULT 0 CHECK(reconciliation_reference IN (0,1)),
 approved_hold_requires_row INTEGER NOT NULL DEFAULT 0 CHECK(approved_hold_requires_row IN (0,1)),
 commit_nonce TEXT NOT NULL
);
-- Minimal S1b replay evidence has no automatic TTL while retained state needs it.
-- This local synthetic assumption sets no perpetual real-data/privacy schedule.
CREATE TABLE account_nonce_history (
 account_id TEXT NOT NULL REFERENCES accounts(account_id), commit_nonce TEXT NOT NULL,
 PRIMARY KEY(account_id,commit_nonce)
);
