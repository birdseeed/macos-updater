import type {SessionCredential} from '../auth';
import type {AccountGuard} from '../store';
// Phase A closed declarations; values establish no authority. Validated domains describe values, never authentication/capabilities.
export type Environment = 'synthetic-sandbox';
export type Currency = 'GBP' | 'USD';
export type PriceID = 'fixture-price-gbp-annual' | 'fixture-price-usd-annual';
export type ID = string; // Exactly32 lowercasehex; new identities reject allzero.
export type SHA256 = string; // Exactly64 lowercasehex.
export type SubscriptionID = string; // /^sub_fixture_[A-Za-z0-9-]{1,48}$/
export type TransactionID = string; // /^txn_fixture_[A-Za-z0-9-]{1,48}$/
export type AdjustmentID = string; // /^adj_fixture_[A-Za-z0-9-]{1,48}$/
export type DisputeID = string; // /^dsp_fixture_[A-Za-z0-9-]{1,48}$/
export type BindingID = string; // /^bind_fixture_[A-Za-z0-9-]{1,48}$/
export type EventID = string; // Existing B1 /^evt_fixture_[A-Za-z0-9-]{1,48}$/
export type Second = number; // Safe integer0..253402300799, deadlines exclusive.
export type Generation = number; // Safe integer1..9007199254740991.
export type NonnegativeGeneration = number; // Safe integer0..9007199254740991.
export type AdjustmentAmount = number; // Safe integer1..1999; coverage pairing exact.
export type CanonicalJSON = string; // Closed decoded grammar, exact canonicalUTF8,1..262144bytes.
export type SourceDelta = 0 | 1;
export type LifecycleOperation = 'consume'|'sweep'|'claim'|'reconcile'|'cancel'|'reviewReversal'|'dispatch'|'dispatchResult'|'hold';
export type BillingSubscriptionRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 binding_id: BindingID;
 mapping_revision: Generation;
 revision: Generation;
 provider_updated_at: Second;
 canonical_sha256: SHA256;
 canonical_json: CanonicalJSON;
 status: 'active'|'pastDue'|'cancelled';
 cancellation_state: 'none'|'requested'|'scheduled'|'effective';
 cancellation_effective_at: Second | null;
 renewal_generation: Generation;
 notice_revision: Generation;
 next_charge_json: CanonicalJSON;
 commit_nonce: ID;
}>;
export type BillingExistingTransactionRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 transaction_id: TransactionID;
 commit_nonce: ID;
}>;
export type BillingReconcileRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 wanted: NonnegativeGeneration;
 done: NonnegativeGeneration;
 claim_generation: NonnegativeGeneration;
 claimed_wanted: Generation | null;
 claim_fence: ID | null;
 claim_expires_at: Second | null;
 read_generation: NonnegativeGeneration;
 failures: 0|1|2|3;
 commit_nonce: ID;
}>;
export type BillingEventConsumedRow = Readonly<{
 environment: Environment;
 event_id: EventID;
 subscription_id: SubscriptionID;
 account_id: ID;
 event_sha256: SHA256;
 wanted: Generation;
 commit_nonce: ID;
}>;
export type BillingSnapshotRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 read_generation: Generation;
 claim_generation: Generation;
 claimed_wanted: Generation;
 fence: ID;
 read_started_at: Second;
 read_finished_at: Second;
 canonical_sha256: SHA256;
 canonical_json: CanonicalJSON;
 commit_nonce: ID;
}>;
export type BillingEntityVersionRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 entity_kind: 'subscription'|'transaction'|'adjustment'|'dispute';
 entity_id: SubscriptionID|TransactionID|AdjustmentID|DisputeID;
 updated_at: Second;
 read_generation: Generation;
 canonical_sha256: SHA256;
 canonical_json: CanonicalJSON;
 commit_nonce: ID;
}>;
export type BillingPeriodRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 transaction_id: TransactionID;
 starts_at: Second;
 ends_at: Second;
 price_id: PriceID;
 currency: Currency;
 quantity: 1;
 unit_amount: 1999;
 tax_inclusive: 1;
 origin: 'existing'|'renewal';
 commit_nonce: ID;
}>;
export type BillingPeriodEndRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 transaction_id: TransactionID;
 adjustment_id: AdjustmentID;
 reason: 'refunded'|'charged_back';
 ended_at: Second;
 commit_nonce: ID;
}>;
export type BillingRestorationRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 transaction_id: TransactionID;
 chargeback_id: AdjustmentID;
 reversal_evidence_sha256: SHA256;
 confirmation_id: ID;
 restored_at: Second;
 original_ends_at: Second;
 commit_nonce: ID;
}>;
export type BillingAdjustmentRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 adjustment_id: AdjustmentID;
 transaction_id: TransactionID;
 kind: 'refund'|'chargeback';
 coverage: 'full'|'partial';
 amount: AdjustmentAmount;
 currency: Currency;
 status: 'pending'|'approved'|'rejected'|'reversed';
 updated_at: Second;
 evidence_sha256: SHA256;
 commit_nonce: ID;
}>;
export type BillingDisputeRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 dispute_id: DisputeID;
 transaction_id: TransactionID;
 state: 'warning'|'open'|'customerWon'|'confirmedLoss';
 updated_at: Second;
 evidence_sha256: SHA256;
 commit_nonce: ID;
}>;
export type BillingGraceRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 anchor_transaction_id: TransactionID;
 original_paid_through: Second;
 anchor_source_sha256: SHA256;
 deadline: Second;
 created_at: Second;
 failed_transaction_id: TransactionID;
 failure_read_generation: Generation;
 commit_nonce: ID;
}>;
export type BillingGraceVoidRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 anchor_transaction_id: TransactionID;
 original_paid_through: Second;
 reason: 'recovered'|'cancelled'|'refunded'|'charged_back';
 evidence_sha256: SHA256;
 voided_at: Second;
 commit_nonce: ID;
}>;
export type BillingRenewalStopRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 renewal_generation: Generation;
 state: 'awaitingRefundApproval'|'intent'|'dispatching'|'unknown'|'accepted'|'confirmed'|'notRequired'|'needsOperator';
 dispatch_id: ID | null;
 claimed_at: Second | null;
 confirmation_sha256: SHA256 | null;
 revision: Generation;
 commit_nonce: ID;
}>;
export type BillingStopCauseRow = Readonly<{
 environment: Environment;
 subscription_id: SubscriptionID;
 account_id: ID;
 renewal_generation: Generation;
 cause_kind: 'customerCancel'|'fullRefund'|'chargeback';
 cause_id: ID|AdjustmentID;
 state: 'awaitingApproval'|'enabled'|'closed';
 evidence_sha256: SHA256;
 acknowledgement_json: CanonicalJSON | null;
 commit_nonce: ID;
}>;
export type BillingLifecycleRequestRow = Readonly<{
 account_id: ID;
 operation: 'cancel'|'reviewReversal';
 request_id: ID;
 environment: Environment;
 subscription_id: SubscriptionID;
 request_sha256: SHA256;
 result_json: CanonicalJSON;
 created_at: Second;
 commit_nonce: ID;
}>;
export type BillingReviewConfirmationRow = Readonly<{
 confirmation_id: ID;
 operator_id: ID;
 operator_session_id: ID;
 account_id: ID;
 environment: Environment;
 subscription_id: SubscriptionID;
 transaction_id: TransactionID;
 chargeback_id: AdjustmentID;
 reversal_evidence_sha256: SHA256;
 original_ends_at: Second;
 account_revision: NonnegativeGeneration;
 subscription_revision: Generation;
 authenticated_at: Second;
 expires_at: Second;
 consumed_at: Second;
 commit_nonce: ID;
}>;
export type BillingLifecycleCommitRow = Readonly<{
 commit_nonce: ID;
 account_id: ID;
 environment: Environment;
 subscription_id: SubscriptionID;
 operation: LifecycleOperation;
 account_revision: Generation;
 source_delta: SourceDelta;
 manifest_sha256: SHA256;
 complete: 1;
}>;
export type LifecycleLedger = Readonly<{
 environment:Environment; account:Readonly<{accountID:ID;revokedAt:Second|null;entitlementRevision:NonnegativeGeneration}>; entitlementSources:Readonly<{accountID:ID;trialStartedAt:Second|null;trialEndsAt:Second|null;betaInvited:boolean;betaEndsAt:Second|null}>;
 billing_subscription: readonly BillingSubscriptionRow[];
 billing_existing_transaction: readonly BillingExistingTransactionRow[];
 billing_reconcile: readonly BillingReconcileRow[];
 billing_event_consumed: readonly BillingEventConsumedRow[];
 billing_snapshot: readonly BillingSnapshotRow[];
 billing_entity_version: readonly BillingEntityVersionRow[];
 billing_period: readonly BillingPeriodRow[];
 billing_period_end: readonly BillingPeriodEndRow[];
 billing_restoration: readonly BillingRestorationRow[];
 billing_adjustment: readonly BillingAdjustmentRow[];
 billing_dispute: readonly BillingDisputeRow[];
 billing_grace: readonly BillingGraceRow[];
 billing_grace_void: readonly BillingGraceVoidRow[];
 billing_renewal_stop: readonly BillingRenewalStopRow[];
 billing_stop_cause: readonly BillingStopCauseRow[];
 billing_lifecycle_request: readonly BillingLifecycleRequestRow[];
 billing_review_confirmation: readonly BillingReviewConfirmationRow[];
 billing_lifecycle_commit: readonly BillingLifecycleCommitRow[];
}>;

export type LifecycleConfig = Readonly<{
 fixture:'PAT-2646-synthetic'; environment:Environment;
 prices:Readonly<{GBP:'fixture-price-gbp-annual';USD:'fixture-price-usd-annual'}>;
 annual:Readonly<{interval:'year';frequency:1;quantity:1;unitAmount:1999;taxInclusive:true}>;
}>;
export type LifecycleDependencies = Readonly<{
 marker:'PAT-2646-synthetic';db:D1Database;config:unknown;
 now:()=>number;randomBytes:(length:number)=>Uint8Array;syntheticKey:Uint8Array;
 provider:SyntheticLifecycleProvider;reviewVerifier?:SyntheticReversalVerifier;
}>;
// Config, snapshot and verifier boundaries stay unknown/bytes until validated.
export type ReadCommand = Readonly<{environment:Environment;subscriptionID:SubscriptionID;
 bindingID:BindingID;readGeneration:Generation}>;
export type StopCommand = Readonly<{environment:Environment;subscriptionID:SubscriptionID;
 renewalGeneration:Generation;dispatchID:ID;effective:'next-period'}>;
export type ProviderRead = {outcome:'snapshot';bytes:Uint8Array} |
 {outcome:'unavailable'};
export type ProviderStop = {outcome:'accepted'}|{outcome:'ambiguous'}|{outcome:'rejected'};
export interface SyntheticLifecycleProvider {
 marker:'PAT-2646-provider-synthetic';
 read(command:ReadCommand):Promise<ProviderRead>;
 stopRenewal(command:StopCommand):Promise<ProviderStop>;
}
// Ordinary implementation has no dependencies and always refuses; no fetch/API host.

export type CustomerRead = {credential:SessionCredential;subscriptionID:SubscriptionID};
export type CancellationDescriptor = Readonly<{
 schemaVersion:1;purpose:'cancelRenewal';subscriptionID:SubscriptionID;
 accountRevision:number;subscriptionRevision:Generation;renewalGeneration:Generation;
 grace:null|Readonly<{anchorTransactionID:TransactionID;originalPaidThrough:Second;
 graceDeadline:Second}>;
 consequence:'paidAccessPreserved'|'graceAccessEndsOnConfirmation';
 descriptorSHA256:SHA256;
}>;
export type CancelRequest = Readonly<{
 credential:SessionCredential;guard:AccountGuard;requestID:ID;
 subscriptionID:SubscriptionID;expectedSubscriptionRevision:Generation;
 descriptorSHA256:SHA256;
 acknowledgement:{kind:'paidAccessPreserved'}|
 {kind:'graceEnds';anchorTransactionID:TransactionID;originalPaidThrough:Second;
 graceDeadline:Second;renewalGeneration:Generation};
}>;
export type ReviewRequest = Readonly<{credential:Uint8Array;guard:AccountGuard;
 subscriptionID:SubscriptionID;transactionID:TransactionID;chargebackID:AdjustmentID;
 reversalEvidenceSHA256:SHA256;requestID:ID;confirmationID:ID}>;
export type VerifiedReversalReview = Readonly<{
 marker:'PAT-2646-review-synthetic';purpose:'restoreReversedChargeback';
 operatorID:ID;operatorSessionID:ID;accountID:ID;subscriptionID:SubscriptionID;
 transactionID:TransactionID;chargebackID:AdjustmentID;
 reversalEvidenceSHA256:SHA256;originalEndsAt:Second;
 accountRevision:number;subscriptionRevision:Generation;confirmationID:ID;
 authenticatedAt:Second;expiresAt:Second;
}>;
export interface SyntheticReversalVerifier {
 marker:'PAT-2646-review-synthetic';
 verify(credential:Uint8Array):Promise<VerifiedReversalReview|null>;
}
export type SubscriptionSummary = Readonly<{schemaVersion:1;subscriptionID:SubscriptionID;
 status:'none'|'active'|'cancelling'|'pastDue'|'ended';paidThrough:Second|null;
 renewsAt:Second|null;cancellation:Readonly<{state:'none'|'requested'|'scheduled'|'effective';
 accessEnds:Second|null}>;payment:Readonly<{state:'current'|'failed'|'ended';graceDeadline:Second|null}>;
 refund:'none'|'pending'|'refunded';endReason:null|'expired'|'refunded'|'chargeback'}>;
export type Refusal = {outcome:'refused'|'invalidSession'|'reauthRequired'|'stale'|
 'notFound'|'requestConflict'|'acknowledgementRequired'};
export type ReconcileResult = {outcome:'committed'|'unchanged';done:Generation;wanted:Generation} |
 {outcome:'stale'|'held'|'unavailable'|'refused'};
export type MutationResult = Refusal|{outcome:'requested'|'confirmed';requestID:ID}|
 {outcome:'restored'|'noRemainingTime';requestID:ID};
export type BridgeResult = {outcome:'marked'|'alreadyConsumed'|'ignored'|'held'|'stale'|'refused'};
export type StopResult = {outcome:'claimed'|'pending'|'confirmed'|'needsOperator'|'stale'|'refused'};

export type WithoutNonce<R> = Readonly<Omit<R,'commit_nonce'>>;
export type LifecycleDelta =
 | {kind:'insertPeriod';row:WithoutNonce<BillingPeriodRow>}
 | {kind:'endPeriod';row:WithoutNonce<BillingPeriodEndRow>}
 | {kind:'restoreRemainder';row:WithoutNonce<BillingRestorationRow>}
 | {kind:'createGrace';row:WithoutNonce<BillingGraceRow>}
 | {kind:'voidGrace';row:WithoutNonce<BillingGraceVoidRow>}
 | {kind:'observeAdjustment';row:WithoutNonce<BillingAdjustmentRow>}
 | {kind:'observeDispute';row:WithoutNonce<BillingDisputeRow>}
 | {kind:'updateSubscription';row:WithoutNonce<BillingSubscriptionRow>}
 | {kind:'joinStopCause';row:WithoutNonce<BillingStopCauseRow>}
 | {kind:'confirmStop';row:WithoutNonce<BillingRenewalStopRow>};
export type DeriveResult = {outcome:'delta';operations:readonly LifecycleDelta[]}|{outcome:'unchanged'}|{outcome:'held';reason:'binding'|'contradiction'|'older'|'unsupported'|'capacity'};
