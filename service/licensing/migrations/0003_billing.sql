-- PAT-2645 synthetic local inbox only. Additive; 0002 is deliberately not a prerequisite.
PRAGMA foreign_keys=ON;
CREATE TABLE billing_webhook_body (
 raw_sha256 TEXT NOT NULL CHECK(length(raw_sha256)=64 AND raw_sha256 NOT GLOB '*[^0-9a-f]*') PRIMARY KEY,
 raw_bytes BLOB NOT NULL CHECK(typeof(raw_bytes)='blob' AND length(raw_bytes) BETWEEN 1 AND 262144)
);
CREATE TABLE billing_event (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'), event_id TEXT NOT NULL CHECK(length(event_id) BETWEEN 13 AND 60 AND substr(event_id,1,12)='evt_fixture_' AND substr(event_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 semantic_sha256 TEXT NOT NULL CHECK(length(semantic_sha256)=64 AND semantic_sha256 NOT GLOB '*[^0-9a-f]*'),
 canonical_bytes BLOB NOT NULL CHECK(typeof(canonical_bytes)='blob' AND length(canonical_bytes) BETWEEN 1 AND 262144),
 event_type TEXT NOT NULL CHECK(length(event_type) BETWEEN 1 AND 64 AND substr(event_type,1,1) GLOB '[a-z]' AND event_type NOT GLOB '*[^a-z0-9_.]*'), occurred_at INTEGER NOT NULL CHECK(typeof(occurred_at)='integer' AND occurred_at BETWEEN 0 AND 253402300799), subject_id TEXT NOT NULL CHECK(length(subject_id) BETWEEN 13 AND 60 AND substr(subject_id,1,12)='sub_fixture_' AND substr(subject_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 first_attempt_id TEXT NOT NULL UNIQUE CHECK(length(first_attempt_id)=32 AND first_attempt_id NOT GLOB '*[^0-9a-f]*'),
 PRIMARY KEY(environment,event_id)
);
CREATE TABLE billing_webhook_delivery (
 attempt_id TEXT NOT NULL CHECK(length(attempt_id)=32 AND attempt_id NOT GLOB '*[^0-9a-f]*') PRIMARY KEY, environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'), notification_id TEXT CHECK(length(notification_id) BETWEEN 13 AND 60 AND substr(notification_id,1,12)='ntf_fixture_' AND substr(notification_id,13) NOT GLOB '*[^A-Za-z0-9-]*'), event_id TEXT CHECK(length(event_id) BETWEEN 13 AND 60 AND substr(event_id,1,12)='evt_fixture_' AND substr(event_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 raw_sha256 TEXT NOT NULL REFERENCES billing_webhook_body(raw_sha256),
 signature_at INTEGER NOT NULL CHECK(typeof(signature_at)='integer' AND signature_at BETWEEN 0 AND 253402300799), received_at INTEGER NOT NULL CHECK(typeof(received_at)='integer' AND received_at BETWEEN 0 AND 253402300799),
 outcome TEXT NOT NULL CHECK(outcome IN ('stored','duplicate','conflict','invalid')),
 CHECK((outcome='invalid' AND notification_id IS NULL AND event_id IS NULL) OR (outcome<>'invalid' AND notification_id IS NOT NULL AND event_id IS NOT NULL))
);
CREATE TABLE billing_event_conflict (
 attempt_id TEXT NOT NULL CHECK(length(attempt_id)=32 AND attempt_id NOT GLOB '*[^0-9a-f]*') PRIMARY KEY REFERENCES billing_webhook_delivery(attempt_id),
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'), event_id TEXT NOT NULL CHECK(length(event_id) BETWEEN 13 AND 60 AND substr(event_id,1,12)='evt_fixture_' AND substr(event_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 original_semantic_sha256 TEXT NOT NULL CHECK(length(original_semantic_sha256)=64 AND original_semantic_sha256 NOT GLOB '*[^0-9a-f]*'), incoming_semantic_sha256 TEXT NOT NULL CHECK(length(incoming_semantic_sha256)=64 AND incoming_semantic_sha256 NOT GLOB '*[^0-9a-f]*'),
 FOREIGN KEY(environment,event_id) REFERENCES billing_event(environment,event_id)
);
CREATE TABLE billing_webhook_quarantine (
 attempt_id TEXT NOT NULL CHECK(length(attempt_id)=32 AND attempt_id NOT GLOB '*[^0-9a-f]*') PRIMARY KEY REFERENCES billing_webhook_delivery(attempt_id),
 reason TEXT NOT NULL CHECK(reason IN ('json','schema','conflict'))
);
CREATE TABLE billing_webhook_audit (
 attempt_id TEXT NOT NULL CHECK(length(attempt_id)=32 AND attempt_id NOT GLOB '*[^0-9a-f]*') PRIMARY KEY REFERENCES billing_webhook_delivery(attempt_id),
 action TEXT NOT NULL CHECK(action IN ('stored','duplicate','conflict','invalid')),
 raw_sha256 TEXT NOT NULL REFERENCES billing_webhook_body(raw_sha256), received_at INTEGER NOT NULL CHECK(typeof(received_at)='integer' AND received_at BETWEEN 0 AND 253402300799)
);
CREATE TABLE billing_inbox_commit (
 attempt_id TEXT NOT NULL CHECK(length(attempt_id)=32 AND attempt_id NOT GLOB '*[^0-9a-f]*') PRIMARY KEY REFERENCES billing_webhook_delivery(attempt_id),
 complete INTEGER NOT NULL CHECK(typeof(complete)='integer' AND complete=1)
);
