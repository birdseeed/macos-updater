-- PAT-2646 additive, synthetic local proof only. No remote migration authority.
PRAGMA foreign_keys = ON;
CREATE TABLE billing_subscription (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 binding_id TEXT NOT NULL CHECK(substr(binding_id,1,13)='bind_fixture_' AND length(binding_id) BETWEEN 14 AND 61 AND substr(binding_id,14) NOT GLOB '*[^A-Za-z0-9-]*'),
 mapping_revision INTEGER NOT NULL CHECK(mapping_revision IS NULL OR typeof(mapping_revision)='integer') CHECK(mapping_revision BETWEEN 1 AND 9007199254740991),
 revision INTEGER NOT NULL CHECK(revision IS NULL OR typeof(revision)='integer') CHECK(revision BETWEEN 1 AND 9007199254740991),
 provider_updated_at INTEGER NOT NULL CHECK(provider_updated_at IS NULL OR typeof(provider_updated_at)='integer') CHECK(provider_updated_at BETWEEN 0 AND 253402300799),
 canonical_sha256 TEXT NOT NULL CHECK(length(canonical_sha256)=64 AND canonical_sha256 NOT GLOB '*[^0-9a-f]*'),
 canonical_json TEXT NOT NULL CHECK(length(CAST(canonical_json AS BLOB)) BETWEEN 1 AND 262144),
 status TEXT NOT NULL CHECK(status IN ('active','pastDue','cancelled')),
 cancellation_state TEXT NOT NULL CHECK(cancellation_state IN ('none','requested','scheduled','effective')),
 cancellation_effective_at INTEGER CHECK(cancellation_effective_at IS NULL OR typeof(cancellation_effective_at)='integer') CHECK((cancellation_effective_at IS NULL OR (cancellation_effective_at BETWEEN 0 AND 253402300799))),
 renewal_generation INTEGER NOT NULL CHECK(renewal_generation IS NULL OR typeof(renewal_generation)='integer') CHECK(renewal_generation BETWEEN 1 AND 9007199254740991),
 notice_revision INTEGER NOT NULL CHECK(notice_revision IS NULL OR typeof(notice_revision)='integer') CHECK(notice_revision BETWEEN 1 AND 9007199254740991),
 next_charge_json TEXT NOT NULL CHECK(length(CAST(next_charge_json AS BLOB)) BETWEEN 1 AND 2048),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,subscription_id),
 FOREIGN KEY(account_id) REFERENCES accounts(account_id),
 UNIQUE(environment,subscription_id,account_id),
 UNIQUE(environment,binding_id),
 CHECK((cancellation_state IN ('none','requested') AND cancellation_effective_at IS NULL) OR (cancellation_state IN ('scheduled','effective') AND cancellation_effective_at IS NOT NULL))
);
CREATE TABLE billing_existing_transaction (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 transaction_id TEXT NOT NULL CHECK(substr(transaction_id,1,12)='txn_fixture_' AND length(transaction_id) BETWEEN 13 AND 60 AND substr(transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,transaction_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 UNIQUE(environment,subscription_id,account_id,transaction_id)
);
CREATE TABLE billing_reconcile (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 wanted INTEGER NOT NULL CHECK(wanted IS NULL OR typeof(wanted)='integer') CHECK(wanted BETWEEN 0 AND 9007199254740991),
 done INTEGER NOT NULL CHECK(done IS NULL OR typeof(done)='integer') CHECK(done BETWEEN 0 AND 9007199254740991),
 claim_generation INTEGER NOT NULL CHECK(claim_generation IS NULL OR typeof(claim_generation)='integer') CHECK(claim_generation BETWEEN 0 AND 9007199254740991),
 claimed_wanted INTEGER CHECK(claimed_wanted IS NULL OR typeof(claimed_wanted)='integer') CHECK((claimed_wanted IS NULL OR (claimed_wanted BETWEEN 1 AND 9007199254740991))),
 claim_fence TEXT CHECK((claim_fence IS NULL OR (length(claim_fence)=32 AND claim_fence NOT GLOB '*[^0-9a-f]*' AND claim_fence<>'00000000000000000000000000000000'))),
 claim_expires_at INTEGER CHECK(claim_expires_at IS NULL OR typeof(claim_expires_at)='integer') CHECK((claim_expires_at IS NULL OR (claim_expires_at BETWEEN 0 AND 253402300799))),
 read_generation INTEGER NOT NULL CHECK(read_generation IS NULL OR typeof(read_generation)='integer') CHECK(read_generation BETWEEN 0 AND 9007199254740991),
 failures INTEGER NOT NULL CHECK(failures IS NULL OR typeof(failures)='integer') CHECK(failures BETWEEN 0 AND 3),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,subscription_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 CHECK(done<=wanted),
 CHECK(claimed_wanted IS NULL OR claimed_wanted<=wanted),
 CHECK((claimed_wanted IS NULL AND claim_fence IS NULL AND claim_expires_at IS NULL) OR (claimed_wanted IS NOT NULL AND claim_fence IS NOT NULL AND claim_expires_at IS NOT NULL))
);
CREATE TABLE billing_event_consumed (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 event_id TEXT NOT NULL CHECK(substr(event_id,1,12)='evt_fixture_' AND length(event_id) BETWEEN 13 AND 60 AND substr(event_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 event_sha256 TEXT NOT NULL CHECK(length(event_sha256)=64 AND event_sha256 NOT GLOB '*[^0-9a-f]*'),
 wanted INTEGER NOT NULL CHECK(wanted IS NULL OR typeof(wanted)='integer') CHECK(wanted BETWEEN 1 AND 9007199254740991),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,event_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 FOREIGN KEY(environment,event_id) REFERENCES billing_event(environment,event_id)
);
CREATE TABLE billing_snapshot (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 read_generation INTEGER NOT NULL CHECK(read_generation IS NULL OR typeof(read_generation)='integer') CHECK(read_generation BETWEEN 1 AND 9007199254740991),
 claim_generation INTEGER NOT NULL CHECK(claim_generation IS NULL OR typeof(claim_generation)='integer') CHECK(claim_generation BETWEEN 1 AND 9007199254740991),
 claimed_wanted INTEGER NOT NULL CHECK(claimed_wanted IS NULL OR typeof(claimed_wanted)='integer') CHECK(claimed_wanted BETWEEN 1 AND 9007199254740991),
 fence TEXT NOT NULL CHECK(length(fence)=32 AND fence NOT GLOB '*[^0-9a-f]*' AND fence<>'00000000000000000000000000000000'),
 read_started_at INTEGER NOT NULL CHECK(read_started_at IS NULL OR typeof(read_started_at)='integer') CHECK(read_started_at BETWEEN 0 AND 253402300799),
 read_finished_at INTEGER NOT NULL CHECK(read_finished_at IS NULL OR typeof(read_finished_at)='integer') CHECK(read_finished_at BETWEEN 0 AND 253402300799),
 canonical_sha256 TEXT NOT NULL CHECK(length(canonical_sha256)=64 AND canonical_sha256 NOT GLOB '*[^0-9a-f]*'),
 canonical_json TEXT NOT NULL CHECK(length(CAST(canonical_json AS BLOB)) BETWEEN 1 AND 262144),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,subscription_id,read_generation),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 CHECK(read_started_at<=read_finished_at)
);
CREATE TABLE billing_entity_version (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 entity_kind TEXT NOT NULL CHECK(entity_kind IN ('subscription','transaction','adjustment','dispute')),
 entity_id TEXT NOT NULL CHECK((entity_kind='subscription' AND substr(entity_id,1,12)='sub_fixture_' AND length(entity_id) BETWEEN 13 AND 60 AND substr(entity_id,13) NOT GLOB '*[^A-Za-z0-9-]*') OR (entity_kind='transaction' AND substr(entity_id,1,12)='txn_fixture_' AND length(entity_id) BETWEEN 13 AND 60 AND substr(entity_id,13) NOT GLOB '*[^A-Za-z0-9-]*') OR (entity_kind='adjustment' AND substr(entity_id,1,12)='adj_fixture_' AND length(entity_id) BETWEEN 13 AND 60 AND substr(entity_id,13) NOT GLOB '*[^A-Za-z0-9-]*') OR (entity_kind='dispute' AND substr(entity_id,1,12)='dsp_fixture_' AND length(entity_id) BETWEEN 13 AND 60 AND substr(entity_id,13) NOT GLOB '*[^A-Za-z0-9-]*')),
 updated_at INTEGER NOT NULL CHECK(updated_at IS NULL OR typeof(updated_at)='integer') CHECK(updated_at BETWEEN 0 AND 253402300799),
 read_generation INTEGER NOT NULL CHECK(read_generation IS NULL OR typeof(read_generation)='integer') CHECK(read_generation BETWEEN 1 AND 9007199254740991),
 canonical_sha256 TEXT NOT NULL CHECK(length(canonical_sha256)=64 AND canonical_sha256 NOT GLOB '*[^0-9a-f]*'),
 canonical_json TEXT NOT NULL CHECK(length(CAST(canonical_json AS BLOB)) BETWEEN 1 AND 262144),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,subscription_id,entity_kind,entity_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id)
);
CREATE TABLE billing_period (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 transaction_id TEXT NOT NULL CHECK(substr(transaction_id,1,12)='txn_fixture_' AND length(transaction_id) BETWEEN 13 AND 60 AND substr(transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 starts_at INTEGER NOT NULL CHECK(starts_at IS NULL OR typeof(starts_at)='integer') CHECK(starts_at BETWEEN 0 AND 253402300799),
 ends_at INTEGER NOT NULL CHECK(ends_at IS NULL OR typeof(ends_at)='integer') CHECK(ends_at BETWEEN 0 AND 253402300799),
 price_id TEXT NOT NULL CHECK(price_id IN ('fixture-price-gbp-annual','fixture-price-usd-annual')),
 currency TEXT NOT NULL CHECK(currency IN ('GBP','USD')),
 quantity INTEGER NOT NULL CHECK(quantity IS NULL OR typeof(quantity)='integer') CHECK(quantity=1),
 unit_amount INTEGER NOT NULL CHECK(unit_amount IS NULL OR typeof(unit_amount)='integer') CHECK(unit_amount=1999),
 tax_inclusive INTEGER NOT NULL CHECK(tax_inclusive IS NULL OR typeof(tax_inclusive)='integer') CHECK(tax_inclusive=1),
 origin TEXT NOT NULL CHECK(origin IN ('existing','renewal')),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,transaction_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 UNIQUE(environment,subscription_id,account_id,transaction_id),
 CHECK(starts_at<ends_at),
 CHECK((price_id='fixture-price-gbp-annual' AND currency='GBP') OR (price_id='fixture-price-usd-annual' AND currency='USD'))
);
CREATE TABLE billing_period_end (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 transaction_id TEXT NOT NULL CHECK(substr(transaction_id,1,12)='txn_fixture_' AND length(transaction_id) BETWEEN 13 AND 60 AND substr(transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 adjustment_id TEXT NOT NULL CHECK(substr(adjustment_id,1,12)='adj_fixture_' AND length(adjustment_id) BETWEEN 13 AND 60 AND substr(adjustment_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 reason TEXT NOT NULL CHECK(reason IN ('refunded','charged_back')),
 ended_at INTEGER NOT NULL CHECK(ended_at IS NULL OR typeof(ended_at)='integer') CHECK(ended_at BETWEEN 0 AND 253402300799),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,transaction_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 FOREIGN KEY(environment,subscription_id,account_id,transaction_id) REFERENCES billing_period(environment,subscription_id,account_id,transaction_id),
 UNIQUE(environment,subscription_id,account_id,transaction_id,adjustment_id),
 FOREIGN KEY(environment,adjustment_id) REFERENCES billing_adjustment(environment,adjustment_id)
);
CREATE TABLE billing_restoration (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 transaction_id TEXT NOT NULL CHECK(substr(transaction_id,1,12)='txn_fixture_' AND length(transaction_id) BETWEEN 13 AND 60 AND substr(transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 chargeback_id TEXT NOT NULL CHECK(substr(chargeback_id,1,12)='adj_fixture_' AND length(chargeback_id) BETWEEN 13 AND 60 AND substr(chargeback_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 reversal_evidence_sha256 TEXT NOT NULL CHECK(length(reversal_evidence_sha256)=64 AND reversal_evidence_sha256 NOT GLOB '*[^0-9a-f]*'),
 confirmation_id TEXT NOT NULL CHECK(length(confirmation_id)=32 AND confirmation_id NOT GLOB '*[^0-9a-f]*' AND confirmation_id<>'00000000000000000000000000000000'),
 restored_at INTEGER NOT NULL CHECK(restored_at IS NULL OR typeof(restored_at)='integer') CHECK(restored_at BETWEEN 0 AND 253402300799),
 original_ends_at INTEGER NOT NULL CHECK(original_ends_at IS NULL OR typeof(original_ends_at)='integer') CHECK(original_ends_at BETWEEN 0 AND 253402300799),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,transaction_id,chargeback_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 UNIQUE(confirmation_id),
 FOREIGN KEY(environment,subscription_id,account_id,transaction_id,chargeback_id) REFERENCES billing_period_end(environment,subscription_id,account_id,transaction_id,adjustment_id),
 FOREIGN KEY(confirmation_id) REFERENCES billing_review_confirmation(confirmation_id),
 CHECK(restored_at<original_ends_at)
);
CREATE TABLE billing_adjustment (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 adjustment_id TEXT NOT NULL CHECK(substr(adjustment_id,1,12)='adj_fixture_' AND length(adjustment_id) BETWEEN 13 AND 60 AND substr(adjustment_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 transaction_id TEXT NOT NULL CHECK(substr(transaction_id,1,12)='txn_fixture_' AND length(transaction_id) BETWEEN 13 AND 60 AND substr(transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 kind TEXT NOT NULL CHECK(kind IN ('refund','chargeback')),
 coverage TEXT NOT NULL CHECK(coverage IN ('full','partial')),
 amount INTEGER NOT NULL CHECK(amount IS NULL OR typeof(amount)='integer') CHECK(amount BETWEEN 1 AND 1999),
 currency TEXT NOT NULL CHECK(currency IN ('GBP','USD')),
 status TEXT NOT NULL CHECK(status IN ('pending','approved','rejected','reversed')),
 updated_at INTEGER NOT NULL CHECK(updated_at IS NULL OR typeof(updated_at)='integer') CHECK(updated_at BETWEEN 0 AND 253402300799),
 evidence_sha256 TEXT NOT NULL CHECK(length(evidence_sha256)=64 AND evidence_sha256 NOT GLOB '*[^0-9a-f]*'),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,adjustment_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 FOREIGN KEY(environment,subscription_id,account_id,transaction_id) REFERENCES billing_period(environment,subscription_id,account_id,transaction_id),
 CHECK((coverage='full' AND amount=1999) OR (coverage='partial' AND amount BETWEEN 1 AND 1998))
);
CREATE TABLE billing_dispute (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 dispute_id TEXT NOT NULL CHECK(substr(dispute_id,1,12)='dsp_fixture_' AND length(dispute_id) BETWEEN 13 AND 60 AND substr(dispute_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 transaction_id TEXT NOT NULL CHECK(substr(transaction_id,1,12)='txn_fixture_' AND length(transaction_id) BETWEEN 13 AND 60 AND substr(transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 state TEXT NOT NULL CHECK(state IN ('warning','open','customerWon','confirmedLoss')),
 updated_at INTEGER NOT NULL CHECK(updated_at IS NULL OR typeof(updated_at)='integer') CHECK(updated_at BETWEEN 0 AND 253402300799),
 evidence_sha256 TEXT NOT NULL CHECK(length(evidence_sha256)=64 AND evidence_sha256 NOT GLOB '*[^0-9a-f]*'),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,dispute_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 FOREIGN KEY(environment,subscription_id,account_id,transaction_id) REFERENCES billing_period(environment,subscription_id,account_id,transaction_id)
);
CREATE TABLE billing_grace (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 anchor_transaction_id TEXT NOT NULL CHECK(substr(anchor_transaction_id,1,12)='txn_fixture_' AND length(anchor_transaction_id) BETWEEN 13 AND 60 AND substr(anchor_transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 original_paid_through INTEGER NOT NULL CHECK(original_paid_through IS NULL OR typeof(original_paid_through)='integer') CHECK(original_paid_through BETWEEN 0 AND 253402300799),
 anchor_source_sha256 TEXT NOT NULL CHECK(length(anchor_source_sha256)=64 AND anchor_source_sha256 NOT GLOB '*[^0-9a-f]*'),
 deadline INTEGER NOT NULL CHECK(deadline IS NULL OR typeof(deadline)='integer') CHECK(deadline BETWEEN 0 AND 253402300799),
 created_at INTEGER NOT NULL CHECK(created_at IS NULL OR typeof(created_at)='integer') CHECK(created_at BETWEEN 0 AND 253402300799),
 failed_transaction_id TEXT NOT NULL CHECK(substr(failed_transaction_id,1,12)='txn_fixture_' AND length(failed_transaction_id) BETWEEN 13 AND 60 AND substr(failed_transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 failure_read_generation INTEGER NOT NULL CHECK(failure_read_generation IS NULL OR typeof(failure_read_generation)='integer') CHECK(failure_read_generation BETWEEN 1 AND 9007199254740991),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,subscription_id,original_paid_through),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 UNIQUE(environment,subscription_id,account_id,anchor_transaction_id,original_paid_through),
 FOREIGN KEY(environment,subscription_id,account_id,anchor_transaction_id) REFERENCES billing_period(environment,subscription_id,account_id,transaction_id),
 FOREIGN KEY(environment,subscription_id,failure_read_generation) REFERENCES billing_snapshot(environment,subscription_id,read_generation),
 CHECK(original_paid_through<=253401695999 AND deadline=original_paid_through+604800)
);
CREATE TABLE billing_grace_void (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 anchor_transaction_id TEXT NOT NULL CHECK(substr(anchor_transaction_id,1,12)='txn_fixture_' AND length(anchor_transaction_id) BETWEEN 13 AND 60 AND substr(anchor_transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 original_paid_through INTEGER NOT NULL CHECK(original_paid_through IS NULL OR typeof(original_paid_through)='integer') CHECK(original_paid_through BETWEEN 0 AND 253402300799),
 reason TEXT NOT NULL CHECK(reason IN ('recovered','cancelled','refunded','charged_back')),
 evidence_sha256 TEXT NOT NULL CHECK(length(evidence_sha256)=64 AND evidence_sha256 NOT GLOB '*[^0-9a-f]*'),
 voided_at INTEGER NOT NULL CHECK(voided_at IS NULL OR typeof(voided_at)='integer') CHECK(voided_at BETWEEN 0 AND 253402300799),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,subscription_id,original_paid_through),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 FOREIGN KEY(environment,subscription_id,account_id,anchor_transaction_id,original_paid_through) REFERENCES billing_grace(environment,subscription_id,account_id,anchor_transaction_id,original_paid_through)
);
CREATE TABLE billing_renewal_stop (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 renewal_generation INTEGER NOT NULL CHECK(renewal_generation IS NULL OR typeof(renewal_generation)='integer') CHECK(renewal_generation BETWEEN 1 AND 9007199254740991),
 state TEXT NOT NULL CHECK(state IN ('awaitingRefundApproval','intent','dispatching','unknown','accepted','confirmed','notRequired','needsOperator')),
 dispatch_id TEXT CHECK((dispatch_id IS NULL OR (length(dispatch_id)=32 AND dispatch_id NOT GLOB '*[^0-9a-f]*' AND dispatch_id<>'00000000000000000000000000000000'))),
 claimed_at INTEGER CHECK(claimed_at IS NULL OR typeof(claimed_at)='integer') CHECK((claimed_at IS NULL OR (claimed_at BETWEEN 0 AND 253402300799))),
 confirmation_sha256 TEXT CHECK((confirmation_sha256 IS NULL OR (length(confirmation_sha256)=64 AND confirmation_sha256 NOT GLOB '*[^0-9a-f]*'))),
 revision INTEGER NOT NULL CHECK(revision IS NULL OR typeof(revision)='integer') CHECK(revision BETWEEN 1 AND 9007199254740991),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,subscription_id,renewal_generation),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 UNIQUE(dispatch_id),
 CHECK((dispatch_id IS NULL AND claimed_at IS NULL) OR (dispatch_id IS NOT NULL AND claimed_at IS NOT NULL)),
 CHECK(state<>'confirmed' OR confirmation_sha256 IS NOT NULL)
);
CREATE TABLE billing_stop_cause (
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 renewal_generation INTEGER NOT NULL CHECK(renewal_generation IS NULL OR typeof(renewal_generation)='integer') CHECK(renewal_generation BETWEEN 1 AND 9007199254740991),
 cause_kind TEXT NOT NULL CHECK(cause_kind IN ('customerCancel','fullRefund','chargeback')),
 cause_id TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('awaitingApproval','enabled','closed')),
 evidence_sha256 TEXT NOT NULL CHECK(length(evidence_sha256)=64 AND evidence_sha256 NOT GLOB '*[^0-9a-f]*'),
 acknowledgement_json TEXT CHECK((acknowledgement_json IS NULL OR (length(CAST(acknowledgement_json AS BLOB)) BETWEEN 1 AND 2048))),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(environment,subscription_id,renewal_generation,cause_kind,cause_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 FOREIGN KEY(environment,subscription_id,renewal_generation) REFERENCES billing_renewal_stop(environment,subscription_id,renewal_generation),
 CHECK((cause_kind='customerCancel' AND acknowledgement_json IS NOT NULL AND length(cause_id)=32 AND cause_id NOT GLOB '*[^0-9a-f]*' AND cause_id<>'00000000000000000000000000000000') OR (cause_kind<>'customerCancel' AND acknowledgement_json IS NULL AND substr(cause_id,1,12)='adj_fixture_' AND length(cause_id) BETWEEN 13 AND 60 AND substr(cause_id,13) NOT GLOB '*[^A-Za-z0-9-]*'))
);
CREATE TABLE billing_lifecycle_request (
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 operation TEXT NOT NULL CHECK(operation IN ('cancel','reviewReversal')),
 request_id TEXT NOT NULL CHECK(length(request_id)=32 AND request_id NOT GLOB '*[^0-9a-f]*' AND request_id<>'00000000000000000000000000000000'),
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 request_sha256 TEXT NOT NULL CHECK(length(request_sha256)=64 AND request_sha256 NOT GLOB '*[^0-9a-f]*'),
 result_json TEXT NOT NULL CHECK(length(CAST(result_json AS BLOB)) BETWEEN 1 AND 2048),
 created_at INTEGER NOT NULL CHECK(created_at IS NULL OR typeof(created_at)='integer') CHECK(created_at BETWEEN 0 AND 253402300799),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(account_id,operation,request_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id)
);
CREATE TABLE billing_review_confirmation (
 confirmation_id TEXT NOT NULL CHECK(length(confirmation_id)=32 AND confirmation_id NOT GLOB '*[^0-9a-f]*' AND confirmation_id<>'00000000000000000000000000000000'),
 operator_id TEXT NOT NULL CHECK(length(operator_id)=32 AND operator_id NOT GLOB '*[^0-9a-f]*' AND operator_id<>'00000000000000000000000000000000'),
 operator_session_id TEXT NOT NULL CHECK(length(operator_session_id)=32 AND operator_session_id NOT GLOB '*[^0-9a-f]*' AND operator_session_id<>'00000000000000000000000000000000'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 transaction_id TEXT NOT NULL CHECK(substr(transaction_id,1,12)='txn_fixture_' AND length(transaction_id) BETWEEN 13 AND 60 AND substr(transaction_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 chargeback_id TEXT NOT NULL CHECK(substr(chargeback_id,1,12)='adj_fixture_' AND length(chargeback_id) BETWEEN 13 AND 60 AND substr(chargeback_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 reversal_evidence_sha256 TEXT NOT NULL CHECK(length(reversal_evidence_sha256)=64 AND reversal_evidence_sha256 NOT GLOB '*[^0-9a-f]*'),
 original_ends_at INTEGER NOT NULL CHECK(original_ends_at IS NULL OR typeof(original_ends_at)='integer') CHECK(original_ends_at BETWEEN 0 AND 253402300799),
 account_revision INTEGER NOT NULL CHECK(account_revision IS NULL OR typeof(account_revision)='integer') CHECK(account_revision BETWEEN 0 AND 9007199254740991),
 subscription_revision INTEGER NOT NULL CHECK(subscription_revision IS NULL OR typeof(subscription_revision)='integer') CHECK(subscription_revision BETWEEN 1 AND 9007199254740991),
 authenticated_at INTEGER NOT NULL CHECK(authenticated_at IS NULL OR typeof(authenticated_at)='integer') CHECK(authenticated_at BETWEEN 0 AND 253402300799),
 expires_at INTEGER NOT NULL CHECK(expires_at IS NULL OR typeof(expires_at)='integer') CHECK(expires_at BETWEEN 0 AND 253402300799),
 consumed_at INTEGER NOT NULL CHECK(consumed_at IS NULL OR typeof(consumed_at)='integer') CHECK(consumed_at BETWEEN 0 AND 253402300799),
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 PRIMARY KEY(confirmation_id),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 FOREIGN KEY(environment,subscription_id,account_id,transaction_id) REFERENCES billing_period(environment,subscription_id,account_id,transaction_id),
 FOREIGN KEY(environment,chargeback_id) REFERENCES billing_adjustment(environment,adjustment_id),
 CHECK(authenticated_at<=consumed_at AND consumed_at<expires_at)
);
CREATE TABLE billing_lifecycle_commit (
 commit_nonce TEXT NOT NULL CHECK(length(commit_nonce)=32 AND commit_nonce NOT GLOB '*[^0-9a-f]*' AND commit_nonce<>'00000000000000000000000000000000'),
 account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*' AND account_id<>'00000000000000000000000000000000'),
 environment TEXT NOT NULL CHECK(environment='synthetic-sandbox'),
 subscription_id TEXT NOT NULL CHECK(substr(subscription_id,1,12)='sub_fixture_' AND length(subscription_id) BETWEEN 13 AND 60 AND substr(subscription_id,13) NOT GLOB '*[^A-Za-z0-9-]*'),
 operation TEXT NOT NULL CHECK(operation IN ('consume','sweep','claim','reconcile','cancel','reviewReversal','dispatch','dispatchResult','hold')),
 account_revision INTEGER NOT NULL CHECK(account_revision IS NULL OR typeof(account_revision)='integer') CHECK(account_revision BETWEEN 1 AND 9007199254740991),
 source_delta INTEGER NOT NULL CHECK(source_delta IS NULL OR typeof(source_delta)='integer') CHECK(source_delta IN (0,1)),
 manifest_sha256 TEXT NOT NULL CHECK(length(manifest_sha256)=64 AND manifest_sha256 NOT GLOB '*[^0-9a-f]*'),
 complete INTEGER NOT NULL CHECK(complete IS NULL OR typeof(complete)='integer') CHECK(complete=1),
 PRIMARY KEY(commit_nonce),
 FOREIGN KEY(environment,subscription_id,account_id) REFERENCES billing_subscription(environment,subscription_id,account_id),
 FOREIGN KEY(account_id,commit_nonce) REFERENCES account_nonce_history(account_id,commit_nonce)
);
CREATE INDEX billing_subscription_lookup ON billing_subscription(account_id,environment,subscription_id);
CREATE INDEX billing_period_lookup ON billing_period(account_id,environment,starts_at,ends_at);
CREATE INDEX billing_reconcile_lookup ON billing_reconcile(environment,done,wanted,claim_expires_at);
CREATE INDEX billing_entity_version_lookup ON billing_entity_version(account_id,environment,subscription_id);
CREATE INDEX billing_stop_cause_lookup ON billing_stop_cause(account_id,environment,subscription_id);
CREATE INDEX billing_lifecycle_request_lookup ON billing_lifecycle_request(account_id,created_at);
