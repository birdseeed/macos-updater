-- Additive local A2 metadata only. lease_heads and account_guard remain sole authorities.
CREATE TABLE activations (
 activation_id TEXT PRIMARY KEY REFERENCES lease_heads(activation_id),
 account_id TEXT NOT NULL REFERENCES accounts(account_id) CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*'), public_key BLOB NOT NULL CHECK(length(public_key)=65),
 display_name TEXT NOT NULL CHECK(length(CAST(display_name AS BLOB)) BETWEEN 1 AND 256),
 generation INTEGER NOT NULL CHECK(generation BETWEEN 1 AND 9007199254740991),
 created_at INTEGER NOT NULL CHECK(created_at BETWEEN 0 AND 253402300799),
 last_refresh_at INTEGER CHECK(last_refresh_at IS NULL OR last_refresh_at BETWEEN 0 AND 253402300799),
 release_reason TEXT CHECK(release_reason IN ('ownerDeactivated','replaced','operatorDeactivated','accountDeleted')),
 attest_key_id BLOB, attest_counter INTEGER, commit_nonce TEXT NOT NULL,
 UNIQUE(account_id,activation_id),
 CHECK(length(activation_id)=32 AND activation_id NOT GLOB '*[^0-9a-f]*' AND activation_id<>'00000000000000000000000000000000'),
 CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*'),
 CHECK((attest_key_id IS NULL AND attest_counter IS NULL) OR (attest_key_id IS NOT NULL AND length(attest_key_id) BETWEEN 1 AND 64 AND attest_counter IS NOT NULL AND attest_counter BETWEEN 0 AND 9007199254740991))
);
CREATE TABLE activation_slots (
 account_id TEXT NOT NULL, slot INTEGER NOT NULL CHECK(slot BETWEEN 1 AND 5), activation_id TEXT NOT NULL UNIQUE,
 device_key_sha256 TEXT NOT NULL CHECK(length(device_key_sha256)=64 AND device_key_sha256 NOT GLOB '*[^0-9a-f]*'),
 commit_nonce TEXT NOT NULL, PRIMARY KEY(account_id,slot), UNIQUE(account_id,device_key_sha256),
 FOREIGN KEY(account_id,activation_id) REFERENCES activations(account_id,activation_id)
);
CREATE TABLE device_challenges (
 challenge_id TEXT PRIMARY KEY CHECK(length(challenge_id)=32 AND challenge_id NOT GLOB '*[^0-9a-f]*'),
 account_id TEXT NOT NULL REFERENCES accounts(account_id) CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*'), session_id TEXT NOT NULL REFERENCES sessions(session_id) CHECK(length(session_id)=32 AND session_id NOT GLOB '*[^0-9a-f]*'),
 operation INTEGER NOT NULL CHECK(operation BETWEEN 1 AND 5), activation_id TEXT CHECK(activation_id IS NULL OR (length(activation_id)=32 AND activation_id NOT GLOB '*[^0-9a-f]*' AND activation_id<>'00000000000000000000000000000000')),
 device_key_sha256 TEXT NOT NULL CHECK(length(device_key_sha256)=64 AND device_key_sha256 NOT GLOB '*[^0-9a-f]*'),
 nonce_mac TEXT NOT NULL CHECK(length(nonce_mac)=64 AND nonce_mac NOT GLOB '*[^0-9a-f]*'),
 created_at INTEGER NOT NULL CHECK(created_at BETWEEN 0 AND 253402300499), expires_at INTEGER NOT NULL,
 consumed_by TEXT, commit_nonce TEXT NOT NULL, CHECK(expires_at=created_at+300),
 CHECK((operation IN (1,2) AND activation_id IS NULL) OR (operation IN (3,4,5) AND activation_id IS NOT NULL AND length(activation_id)=32 AND activation_id NOT GLOB '*[^0-9a-f]*' AND activation_id<>'00000000000000000000000000000000'))
);
CREATE TABLE device_requests (
 account_id TEXT NOT NULL REFERENCES accounts(account_id) CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*'), operation INTEGER NOT NULL CHECK(operation BETWEEN 1 AND 7),
 request_id TEXT NOT NULL CHECK(length(request_id)=32 AND request_id NOT GLOB '*[^0-9a-f]*'),
 action_sha256 TEXT NOT NULL CHECK(length(action_sha256)=64 AND action_sha256 NOT GLOB '*[^0-9a-f]*'),
 session_id TEXT NOT NULL REFERENCES sessions(session_id) CHECK(length(session_id)=32 AND session_id NOT GLOB '*[^0-9a-f]*'), activation_id TEXT CHECK(activation_id IS NULL OR (length(activation_id)=32 AND activation_id NOT GLOB '*[^0-9a-f]*' AND activation_id<>'00000000000000000000000000000000')),
 result_json TEXT NOT NULL CHECK(length(CAST(result_json AS BLOB)) BETWEEN 1 AND 16384),
 lease_claims_json TEXT CHECK(lease_claims_json IS NULL OR length(CAST(lease_claims_json AS BLOB)) BETWEEN 1 AND 2048),
 created_at INTEGER NOT NULL CHECK(created_at BETWEEN 0 AND 253402300799), commit_nonce TEXT NOT NULL,
 PRIMARY KEY(account_id,operation,request_id)
);
CREATE TABLE device_request_tombstones (
 account_id TEXT NOT NULL REFERENCES accounts(account_id) CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*'), operation INTEGER NOT NULL CHECK(operation BETWEEN 1 AND 7),
 request_id TEXT NOT NULL CHECK(length(request_id)=32 AND request_id NOT GLOB '*[^0-9a-f]*'),
 action_sha256 TEXT NOT NULL CHECK(length(action_sha256)=64 AND action_sha256 NOT GLOB '*[^0-9a-f]*'), activation_id TEXT CHECK(activation_id IS NULL OR (length(activation_id)=32 AND activation_id NOT GLOB '*[^0-9a-f]*' AND activation_id<>'00000000000000000000000000000000')),
 outcome TEXT NOT NULL CHECK(outcome IN ('activated','reused','limitReached','replaced','released','alreadyReleased','renamed','rebound','leased','revokedLease','stale','notFound','notActive')),
 commit_nonce TEXT NOT NULL, PRIMARY KEY(account_id,operation,request_id)
);
CREATE TABLE operator_confirmations (
 confirmation_id TEXT PRIMARY KEY CHECK(length(confirmation_id)=32 AND confirmation_id NOT GLOB '*[^0-9a-f]*'), operator_id TEXT NOT NULL CHECK(length(operator_id)=32 AND operator_id NOT GLOB '*[^0-9a-f]*'), operator_session_id TEXT NOT NULL CHECK(length(operator_session_id)=32 AND operator_session_id NOT GLOB '*[^0-9a-f]*'),
 account_id TEXT NOT NULL REFERENCES accounts(account_id) CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*'), activation_id TEXT NOT NULL CHECK(length(activation_id)=32 AND activation_id NOT GLOB '*[^0-9a-f]*' AND activation_id<>'00000000000000000000000000000000'),
 descriptor_sha256 TEXT NOT NULL CHECK(length(descriptor_sha256)=64 AND descriptor_sha256 NOT GLOB '*[^0-9a-f]*'),
 consumed_at INTEGER NOT NULL CHECK(consumed_at BETWEEN 0 AND 253402300799), commit_nonce TEXT NOT NULL
);
CREATE INDEX activations_account_key ON activations(account_id,activation_id);
CREATE INDEX device_challenges_expiry ON device_challenges(expires_at);
CREATE INDEX device_requests_created ON device_requests(created_at);
