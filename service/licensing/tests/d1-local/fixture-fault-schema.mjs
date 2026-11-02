// Test-host-only native fixture projection. This is not product schema authority.
// Storage lineage and invalidation before raw DDL are the dedicated host's duty.
export class FixtureFaultSchemaInfrastructureError extends Error {
  constructor(message = 'Invalid fixture-fault-schema operation') {
    super(message);
    this.name = 'FixtureFaultSchemaInfrastructureError';
  }
}
const fail = message => { throw new FixtureFaultSchemaInfrastructureError(message); };
const columns = Object.freeze(['type', 'name', 'tbl_name', 'rootpage', 'sql']);
// Materialized bytes selected and frozen by the parent before implementation.
const creates = new Map([
  {"id":"P3-001","name":"operator_test_required","table":"account_guard","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON account_guard BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-002","name":"operator_test_required","table":"account_guard","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON account_guard BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-003","name":"operator_test_required","table":"account_nonce_history","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON account_nonce_history BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-004","name":"operator_test_required","table":"account_nonce_history","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON account_nonce_history BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-005","name":"operator_test_required","table":"account_audit","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON account_audit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-006","name":"operator_test_required","table":"account_audit","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON account_audit BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-007","name":"operator_test_required","table":"support_request","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON support_request BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-008","name":"operator_test_required","table":"support_request","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON support_request BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-009","name":"operator_test_required","table":"support_human_use","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_human_use BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-010","name":"operator_test_required","table":"support_human_use","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_human_use BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-011","name":"operator_test_required","table":"support_audit","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_audit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-012","name":"operator_test_required","table":"support_audit","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_audit BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-013","name":"operator_test_required","table":"support_commit","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_commit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-014","name":"operator_test_required","table":"support_commit","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_commit BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-015","name":"operator_test_required","table":"accounts","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON accounts BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-016","name":"operator_test_required","table":"accounts","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON accounts BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-017","name":"operator_test_required","table":"activation_slots","sql":"CREATE TRIGGER operator_test_required BEFORE DELETE ON activation_slots BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-018","name":"operator_test_required","table":"activation_slots","sql":"CREATE TRIGGER operator_test_required BEFORE DELETE ON activation_slots BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-019","name":"operator_test_required","table":"activations","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON activations BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-020","name":"operator_test_required","table":"activations","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON activations BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-021","name":"operator_test_required","table":"lease_heads","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON lease_heads BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-022","name":"operator_test_required","table":"lease_heads","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON lease_heads BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-023","name":"operator_test_required","table":"operator_confirmations","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON operator_confirmations BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-024","name":"operator_test_required","table":"operator_confirmations","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON operator_confirmations BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-025","name":"operator_test_required","table":"challenges","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON challenges BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-026","name":"operator_test_required","table":"challenges","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON challenges BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-027","name":"operator_test_required","table":"request_limits","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON request_limits BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-028","name":"operator_test_required","table":"request_limits","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON request_limits BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-029","name":"operator_test_required","table":"support_rate","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_rate BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-030","name":"operator_test_required","table":"support_rate","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_rate BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-031","name":"operator_test_required","table":"support_delivery","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_delivery BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-032","name":"operator_test_required","table":"support_delivery","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_delivery BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-033","name":"operator_test_required","table":"billing_reconcile","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON billing_reconcile BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-034","name":"operator_test_required","table":"billing_reconcile","sql":"CREATE TRIGGER operator_test_required BEFORE UPDATE ON billing_reconcile BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-035","name":"operator_test_required","table":"billing_lifecycle_commit","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON billing_lifecycle_commit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-036","name":"operator_test_required","table":"billing_lifecycle_commit","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON billing_lifecycle_commit BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-037","name":"operator_test_required","table":"billing_renewal_stop","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON billing_renewal_stop BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-038","name":"operator_test_required","table":"billing_renewal_stop","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON billing_renewal_stop BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-039","name":"operator_test_required","table":"billing_stop_cause","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON billing_stop_cause BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-040","name":"operator_test_required","table":"billing_stop_cause","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON billing_stop_cause BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-041","name":"operator_test_required","table":"support_refund","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_refund BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-042","name":"operator_test_required","table":"support_refund","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_refund BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-043","name":"operator_test_required","table":"support_stop_obligation","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_stop_obligation BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-044","name":"operator_test_required","table":"support_stop_obligation","sql":"CREATE TRIGGER operator_test_required BEFORE INSERT ON support_stop_obligation BEGIN SELECT RAISE(ABORT,'operator fault'); END"},
  {"id":"P3-045","name":"operator_test_lookup","table":"support_rate","sql":"CREATE TRIGGER operator_test_lookup BEFORE INSERT ON support_rate BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-046","name":"operator_test_lookup","table":"support_rate","sql":"CREATE TRIGGER operator_test_lookup BEFORE INSERT ON support_rate BEGIN SELECT RAISE(ABORT,'operator lookup fault'); END"},
  {"id":"P3-047","name":"operator_test_lookup","table":"support_lookup","sql":"CREATE TRIGGER operator_test_lookup BEFORE INSERT ON support_lookup BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-048","name":"operator_test_lookup","table":"support_lookup","sql":"CREATE TRIGGER operator_test_lookup BEFORE INSERT ON support_lookup BEGIN SELECT RAISE(ABORT,'operator lookup fault'); END"},
  {"id":"P3-049","name":"operator_test_lookup","table":"support_audit","sql":"CREATE TRIGGER operator_test_lookup BEFORE INSERT ON support_audit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-050","name":"operator_test_lookup","table":"support_audit","sql":"CREATE TRIGGER operator_test_lookup BEFORE INSERT ON support_audit BEGIN SELECT RAISE(ABORT,'operator lookup fault'); END"},
  {"id":"P3-051","name":"operator_test_lookup","table":"support_commit","sql":"CREATE TRIGGER operator_test_lookup BEFORE INSERT ON support_commit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-052","name":"operator_test_lookup","table":"support_commit","sql":"CREATE TRIGGER operator_test_lookup BEFORE INSERT ON support_commit BEGIN SELECT RAISE(ABORT,'operator lookup fault'); END"},
  {"id":"P3-053","name":"operator_test_prepare","table":"support_commit","sql":"CREATE TRIGGER operator_test_prepare BEFORE INSERT ON support_commit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-054","name":"operator_test_prepare","table":"support_commit","sql":"CREATE TRIGGER operator_test_prepare BEFORE INSERT ON support_commit BEGIN SELECT RAISE(ABORT,'operator prepare fault'); END"},
  {"id":"P3-055","name":"operator_test_dispatch","table":"support_audit","sql":"CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_audit WHEN NEW.event='providerDispatch' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-056","name":"operator_test_dispatch","table":"support_audit","sql":"CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_audit WHEN NEW.event='providerDispatch' BEGIN SELECT RAISE(ABORT,'operator dispatch fault'); END"},
  {"id":"P3-057","name":"operator_test_dispatch","table":"support_audit","sql":"CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_audit WHEN NEW.event='providerResult' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-058","name":"operator_test_dispatch","table":"support_audit","sql":"CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_audit WHEN NEW.event='providerResult' BEGIN SELECT RAISE(ABORT,'operator dispatch fault'); END"},
  {"id":"P3-059","name":"operator_test_dispatch","table":"support_commit","sql":"CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_commit WHEN NEW.kind='dispatch' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-060","name":"operator_test_dispatch","table":"support_commit","sql":"CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_commit WHEN NEW.kind='dispatch' BEGIN SELECT RAISE(ABORT,'operator dispatch fault'); END"},
  {"id":"P3-061","name":"operator_test_dispatch","table":"support_commit","sql":"CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_commit WHEN NEW.kind='result' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-062","name":"operator_test_dispatch","table":"support_commit","sql":"CREATE TRIGGER operator_test_dispatch BEFORE INSERT ON support_commit WHEN NEW.kind='result' BEGIN SELECT RAISE(ABORT,'operator dispatch fault'); END"},
  {"id":"P3-063","name":"operator_test_dispatch","table":"support_delivery","sql":"CREATE TRIGGER operator_test_dispatch BEFORE UPDATE ON support_delivery WHEN NEW.state='dispatching' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-064","name":"operator_test_dispatch","table":"support_delivery","sql":"CREATE TRIGGER operator_test_dispatch BEFORE UPDATE ON support_delivery WHEN NEW.state='dispatching' BEGIN SELECT RAISE(ABORT,'operator dispatch fault'); END"},
  {"id":"P3-065","name":"operator_test_dispatch","table":"support_delivery","sql":"CREATE TRIGGER operator_test_dispatch BEFORE UPDATE ON support_delivery WHEN NEW.state='accepted' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-066","name":"operator_test_dispatch","table":"support_delivery","sql":"CREATE TRIGGER operator_test_dispatch BEFORE UPDATE ON support_delivery WHEN NEW.state='accepted' BEGIN SELECT RAISE(ABORT,'operator dispatch fault'); END"},
  {"id":"P3-067","name":"operator_test_dispatch","table":"support_refund","sql":"CREATE TRIGGER operator_test_dispatch BEFORE UPDATE ON support_refund WHEN NEW.state='dispatching' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-068","name":"operator_test_dispatch","table":"support_refund","sql":"CREATE TRIGGER operator_test_dispatch BEFORE UPDATE ON support_refund WHEN NEW.state='dispatching' BEGIN SELECT RAISE(ABORT,'operator dispatch fault'); END"},
  {"id":"P3-069","name":"operator_test_dispatch","table":"support_refund","sql":"CREATE TRIGGER operator_test_dispatch BEFORE UPDATE ON support_refund WHEN NEW.state='accepted' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-070","name":"operator_test_dispatch","table":"support_refund","sql":"CREATE TRIGGER operator_test_dispatch BEFORE UPDATE ON support_refund WHEN NEW.state='accepted' BEGIN SELECT RAISE(ABORT,'operator dispatch fault'); END"},
  {"id":"P3-071","name":"operator_test_activation","table":"challenges","sql":"CREATE TRIGGER operator_test_activation BEFORE UPDATE ON challenges WHEN NEW.superseded_at IS NULL BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-072","name":"operator_test_activation","table":"challenges","sql":"CREATE TRIGGER operator_test_activation BEFORE UPDATE ON challenges WHEN NEW.superseded_at IS NULL BEGIN SELECT RAISE(ABORT,'operator challenge result fault'); END"},
  {"id":"P3-073","name":"operator_test_source_dispatch","table":"account_guard","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE UPDATE ON account_guard BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-074","name":"operator_test_source_dispatch","table":"account_guard","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE UPDATE ON account_guard BEGIN SELECT RAISE(ABORT,'source dispatch fault'); END"},
  {"id":"P3-075","name":"operator_test_source_dispatch","table":"account_nonce_history","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE INSERT ON account_nonce_history BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-076","name":"operator_test_source_dispatch","table":"account_nonce_history","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE INSERT ON account_nonce_history BEGIN SELECT RAISE(ABORT,'source dispatch fault'); END"},
  {"id":"P3-077","name":"operator_test_source_dispatch","table":"account_audit","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE INSERT ON account_audit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-078","name":"operator_test_source_dispatch","table":"account_audit","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE INSERT ON account_audit BEGIN SELECT RAISE(ABORT,'source dispatch fault'); END"},
  {"id":"P3-079","name":"operator_test_source_dispatch","table":"billing_lifecycle_commit","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE INSERT ON billing_lifecycle_commit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-080","name":"operator_test_source_dispatch","table":"billing_lifecycle_commit","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE INSERT ON billing_lifecycle_commit BEGIN SELECT RAISE(ABORT,'source dispatch fault'); END"},
  {"id":"P3-081","name":"operator_test_source_dispatch","table":"accounts","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE UPDATE ON accounts BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-082","name":"operator_test_source_dispatch","table":"accounts","sql":"CREATE TRIGGER operator_test_source_dispatch BEFORE UPDATE ON accounts BEGIN SELECT RAISE(ABORT,'source dispatch fault'); END"},
  {"id":"P3-083","name":"operator_test_obligation_result","table":"support_stop_obligation","sql":"CREATE TRIGGER operator_test_obligation_result BEFORE UPDATE ON support_stop_obligation WHEN NEW.state='closed' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-084","name":"operator_test_obligation_result","table":"support_stop_obligation","sql":"CREATE TRIGGER operator_test_obligation_result BEFORE UPDATE ON support_stop_obligation WHEN NEW.state='closed' BEGIN SELECT RAISE(ABORT,'obligation result fault'); END"},
  {"id":"P3-085","name":"operator_test_capacity_result","table":"support_commit","sql":"CREATE TRIGGER operator_test_capacity_result BEFORE INSERT ON support_commit WHEN NEW.kind='result' BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"P3-086","name":"operator_test_capacity_result","table":"support_commit","sql":"CREATE TRIGGER operator_test_capacity_result BEFORE INSERT ON support_commit WHEN NEW.kind='result' BEGIN SELECT RAISE(ABORT,'capacity result lost'); END"},
  {"id":"B4-087","name":"notices_test_fault_update","table":"account_guard","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON account_guard BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-088","name":"notices_test_fault_update","table":"account_guard","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON account_guard BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-089","name":"notices_test_fault_update","table":"accounts","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON accounts BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-090","name":"notices_test_fault_update","table":"accounts","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON accounts BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-091","name":"notices_test_fault_insert","table":"account_nonce_history","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON account_nonce_history BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-092","name":"notices_test_fault_insert","table":"account_nonce_history","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON account_nonce_history BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-093","name":"notices_test_fault_insert","table":"account_audit","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON account_audit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-094","name":"notices_test_fault_insert","table":"account_audit","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON account_audit BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-095","name":"notices_test_fault_insert","table":"billing_reconcile","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_reconcile BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-096","name":"notices_test_fault_insert","table":"billing_reconcile","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_reconcile BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-097","name":"notices_test_fault_insert","table":"billing_snapshot","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_snapshot BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-098","name":"notices_test_fault_insert","table":"billing_snapshot","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_snapshot BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-099","name":"notices_test_fault_insert","table":"billing_entity_version","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_entity_version BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-100","name":"notices_test_fault_insert","table":"billing_entity_version","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_entity_version BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-101","name":"notices_test_fault_insert","table":"billing_subscription","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_subscription BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-102","name":"notices_test_fault_insert","table":"billing_subscription","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_subscription BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-103","name":"notices_test_fault_insert","table":"billing_lifecycle_commit","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_lifecycle_commit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-104","name":"notices_test_fault_insert","table":"billing_lifecycle_commit","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_lifecycle_commit BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-105","name":"notices_test_fault_insert","table":"billing_reminder","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_reminder BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-106","name":"notices_test_fault_insert","table":"billing_reminder","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_reminder BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-107","name":"notices_test_fault_update","table":"billing_reminder","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_reminder BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-108","name":"notices_test_fault_update","table":"billing_reminder","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_reminder BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-109","name":"notices_test_fault_insert","table":"billing_notice_dispatch","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_dispatch BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-110","name":"notices_test_fault_insert","table":"billing_notice_dispatch","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_dispatch BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-111","name":"notices_test_fault_update","table":"billing_notice_dispatch","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_dispatch BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-112","name":"notices_test_fault_update","table":"billing_notice_dispatch","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_dispatch BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-113","name":"notices_test_fault_insert","table":"billing_notice_commit","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_commit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-114","name":"notices_test_fault_insert","table":"billing_notice_commit","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_commit BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-115","name":"notices_test_fault_update","table":"billing_notice_commit","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_commit BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-116","name":"notices_test_fault_update","table":"billing_notice_commit","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_commit BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-117","name":"notices_test_fault_insert","table":"billing_notice_head","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_head BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-118","name":"notices_test_fault_insert","table":"billing_notice_head","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_head BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-119","name":"notices_test_fault_update","table":"billing_notice_head","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_head BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-120","name":"notices_test_fault_update","table":"billing_notice_head","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_head BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-121","name":"notices_test_fault_insert","table":"billing_notice_receipt","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_receipt BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-122","name":"notices_test_fault_insert","table":"billing_notice_receipt","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_receipt BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-123","name":"notices_test_fault_update","table":"billing_notice_receipt","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_receipt BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-124","name":"notices_test_fault_update","table":"billing_notice_receipt","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_receipt BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-125","name":"notices_test_fault_insert","table":"billing_notice_contact","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_contact BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-126","name":"notices_test_fault_insert","table":"billing_notice_contact","sql":"CREATE TRIGGER notices_test_fault_insert BEFORE INSERT ON billing_notice_contact BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-127","name":"notices_test_fault_update","table":"billing_notice_contact","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_contact BEGIN SELECT RAISE(IGNORE); END"},
  {"id":"B4-128","name":"notices_test_fault_update","table":"billing_notice_contact","sql":"CREATE TRIGGER notices_test_fault_update BEFORE UPDATE ON billing_notice_contact BEGIN SELECT RAISE(ABORT,'synthetic required-write failure'); END"},
  {"id":"B4-129","name":"notices_test_fault","table":"billing_notice_receipt","sql":"CREATE TRIGGER notices_test_fault BEFORE INSERT ON billing_notice_receipt BEGIN SELECT RAISE(IGNORE); END"}
].map(entry => [entry.sql, Object.freeze(entry)]));
const drops = new Map([
  [
    "DROP TRIGGER \"operator_test_required\"",
    "operator_test_required"
  ],
  [
    "DROP TRIGGER \"operator_test_lookup\"",
    "operator_test_lookup"
  ],
  [
    "DROP TRIGGER \"operator_test_prepare\"",
    "operator_test_prepare"
  ],
  [
    "DROP TRIGGER \"operator_test_dispatch\"",
    "operator_test_dispatch"
  ],
  [
    "DROP TRIGGER \"operator_test_activation\"",
    "operator_test_activation"
  ],
  [
    "DROP TRIGGER \"operator_test_source_dispatch\"",
    "operator_test_source_dispatch"
  ],
  [
    "DROP TRIGGER \"operator_test_obligation_result\"",
    "operator_test_obligation_result"
  ],
  [
    "DROP TRIGGER \"operator_test_capacity_result\"",
    "operator_test_capacity_result"
  ],
  [
    "DROP TRIGGER \"notices_test_fault_update\"",
    "notices_test_fault_update"
  ],
  [
    "DROP TRIGGER \"notices_test_fault_insert\"",
    "notices_test_fault_insert"
  ],
  [
    "DROP TRIGGER \"notices_test_fault\"",
    "notices_test_fault"
  ],
  [
    "DROP TRIGGER operator_test_capacity_result",
    "operator_test_capacity_result"
  ],
  [
    "DROP TRIGGER notices_test_fault",
    "notices_test_fault"
  ]
]);
const queryForms = new Map([
  [
    "SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE substr(name,1,8)='support_' OR substr(tbl_name,1,8)='support_' OR substr(name,1,9)='operator_' OR substr(tbl_name,1,9)='operator_' ORDER BY type,name LIMIT 34",
    [
      [
        35,
        48
      ]
    ]
  ],
  [
    "SELECT type,name,tbl_name,rootpage,sql FROM sqlite_schema ORDER BY type,name LIMIT 100",
    [
      [
        44,
        57
      ]
    ]
  ],
  [
    "SELECT count(*) n FROM sqlite_schema WHERE type=? AND name=?",
    [
      [
        23,
        36
      ]
    ]
  ],
  [
    "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type=? AND name=?) present",
    [
      [
        28,
        41
      ]
    ]
  ],
  [
    "SELECT CASE WHEN changes()=1 THEN 1 ELSE json('') END",
    []
  ],
  [
    "SELECT CASE WHEN (SELECT count(*) FROM sqlite_schema WHERE type='trigger')=? AND NOT EXISTS(SELECT 1 FROM sqlite_master WHERE type='trigger' AND name=?) AND (SELECT count(*) FROM sentinel WHERE id=?)=1 THEN 1 ELSE json('') END",
    [
      [
        39,
        52
      ],
      [
        106,
        119
      ]
    ]
  ],
  [
    "INSERT INTO fault_probe (id,value) SELECT ?,? WHERE NOT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='trigger' AND name=?)",
    [
      [
        77,
        90
      ]
    ]
  ]
].map(([sql, spans]) => [sql, Object.freeze(spans.map(span => Object.freeze(span)))]));

// Identity is never reconstructed from public object properties.
const owners = new WeakMap();
const generations = new WeakMap();
const statements = new WeakMap();
const receipts = new WeakMap();
const isObject = value => value !== null && (typeof value === 'object' || typeof value === 'function');
const schemaName = token => token && /^(sqlite_schema|sqlite_master)$/i.test(token.value);

// Bounded tokenization is used only to refuse unsupported active-mask SQL, never
// to infer a new projection form. Offsets for substitutions come from the freeze.
function lex(sql) {
  if (typeof sql !== 'string' || Buffer.byteLength(sql, 'utf8') > 1048576) fail('SQL byte bound/type');
  const tokens = [];
  let i = 0, depth = 0, ended = false;
  function add(value, kind = 'symbol') {
    if (ended) fail('Multiple statements');
    if (tokens.length >= 65536) fail('SQL token bound');
    tokens.push({value, kind});
  }
  while (i < sql.length) {
    const c = sql[i];
    if (/\s/.test(c)) { i++; continue; }
    if (c === '-' && sql[i + 1] === '-') {
      i += 2; while (i < sql.length && sql[i] !== '\n' && sql[i] !== '\r') i++;
      continue;
    }
    if (c === '/' && sql[i + 1] === '*') {
      const end = sql.indexOf('*/', i + 2);
      if (end < 0) fail('Unterminated comment');
      i = end + 2; continue;
    }
    if (c === "'" || c === '"' || c === '`' || c === '[') {
      const close = c === '[' ? ']' : c;
      let value = '', closed = false;
      i++;
      while (i < sql.length) {
        if (sql[i] === close) {
          // SQLite bracket identifiers end at the first ]; quote/backtick
          // delimiters support doubled delimiters.
          if (c !== '[' && sql[i + 1] === close) { value += close; i += 2; continue; }
          i++; closed = true; break;
        }
        value += sql[i++];
      }
      if (!closed) fail('Unterminated quoted token');
      add(value, c === "'" ? 'string' : 'identifier'); continue;
    }
    if (/[A-Za-z_\u0080-\uffff]/.test(c)) {
      const start = i++;
      while (i < sql.length && /[A-Za-z0-9_$\u0080-\uffff]/.test(sql[i])) i++;
      add(sql.slice(start, i), 'word'); continue;
    }
    if (c === '(') { if (++depth > 128) fail('SQL nesting bound'); }
    if (c === ')') { if (--depth < 0) fail('Unbalanced parentheses'); }
    add(c); i++;
    if (c === ';') { if (depth !== 0) fail('Nonterminal semicolon'); ended = true; }
  }
  if (depth !== 0) fail('Unbalanced parentheses');
  return tokens;
}
function hasSchemaRelation(tokens) {
  // Walk relation positions including comma joins and qualified names. Quoted
  // schema words in expression/alias positions are deliberately not relations.
  const contexts = [{from: false, relation: false}];
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i], word = t.kind === 'word' ? t.value.toUpperCase() : '';
    let context = contexts[contexts.length - 1];
    if (t.value === '(' && t.kind === 'symbol') {
      context.relation = false; contexts.push({from: false, relation: false}); continue;
    }
    if (t.value === ')' && t.kind === 'symbol') { contexts.pop(); continue; }
    if (word === 'FROM' || word === 'JOIN' || word === 'UPDATE' || word === 'INTO') {
      context.relation = true; context.from = word === 'FROM' || word === 'JOIN'; continue;
    }
    if (['WHERE','GROUP','ORDER','LIMIT','HAVING','UNION','EXCEPT','INTERSECT','RETURNING','SET','VALUES','ON','USING'].includes(word)) {
      context.from = false; context.relation = false; continue;
    }
    if (t.kind === 'symbol' && t.value === ',' && context.from) { context.relation = true; continue; }
    if (context.relation && (t.kind === 'word' || t.kind === 'identifier')) {
      if (schemaName(t)) return true;
      let j = i;
      while (tokens[j + 1]?.value === '.' && ['word','identifier'].includes(tokens[j + 2]?.kind)) {
        if (schemaName(tokens[j + 2])) return true;
        j += 2;
      }
      context.relation = false;
    }
  }
  return false;
}
function literal(value) {
  if (value === null) return 'NULL';
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value) || value < 0) fail('Unsafe native rootpage');
    return String(value);
  }
  if (typeof value !== 'string') fail('Invalid native schema tuple');
  return "'" + value.replaceAll("'", "''") + "'";
}
function project(g, sql) {
  if (typeof sql !== 'string') fail('SQL must be a string');
  if (g.registry.size === 0) return sql;
  const tokens = lex(sql);
  const first = tokens[0];
  const command = first?.kind === 'word' ? first.value.toUpperCase() : '';
  if (['CREATE','DROP','ALTER','REINDEX','VACUUM','ATTACH','DETACH','WITH'].includes(command)) fail('Unsupported schema mutation/CTE');
  const spans = queryForms.get(sql);
  if (!spans) {
    if (hasSchemaRelation(tokens)) fail('Unfrozen schema relation form');
    return sql;
  }
  if (spans.length === 0) return sql;
  const predicate = [...g.registry.values()].map(record => '(' + columns.map(key => key + ' IS ' + literal(record.tuple[key])).join(' AND ') + ')').join(' OR ');
  const relation = '(SELECT type,name,tbl_name,rootpage,sql FROM main.sqlite_schema WHERE NOT (' + predicate + '))';
  // Frozen forms are ASCII, so their reviewed UTF8 offsets are string offsets.
  let emitted = sql;
  for (let i = spans.length - 1; i >= 0; i--) {
    const [start, end] = spans[i];
    emitted = emitted.slice(0, start) + relation + emitted.slice(end);
  }
  return emitted;
}
function live(g) {
  if (!g.active || owners.get(g.owner).active !== g.handle) fail('Inactive fixture generation');
  if (g.transition) fail('Fixture generation transition in progress');
}
function assertIdle(g) {
  live(g);
  if (g.executing !== 0) fail('Native statements still executing');
}
function captureBinding(value) {
  // The pinned Node proxy serializes bind arguments synchronously. Capture once
  // and give native bind these same values, including its own type validation.
  if (Array.isArray(value)) {
    // Exotic metadata/accessors must reach native bind unchanged. Their replay
    // cannot claim a stable snapshot of the proxy's serialization side effects.
    if (Object.getPrototypeOf(value) !== Array.prototype ||
        Object.hasOwn(value, Symbol.toStringTag) ||
        Object.entries(Object.getOwnPropertyDescriptors(value)).some(([key, d]) =>
          /^(0|[1-9][0-9]*)$/.test(key) && !Object.hasOwn(d, 'value'))) {
      return {value, replayable: false};
    }
    const captured = new Array(value.length);
    for (let i = 0; i < captured.length; i++) {
      if (Object.hasOwn(value, i)) captured[i] = value[i];
    }
    return {value: captured, replayable: true};
  }
  if (value instanceof ArrayBuffer) {
    try { return {value: structuredClone(value), replayable: true}; }
    // A failed snapshot must leave rejection to the original native bind.
    catch { return {value, replayable: false}; }
  }
  if (ArrayBuffer.isView(value)) {
    const prototypes = [DataView, Int8Array, Uint8Array, Uint8ClampedArray,
      Int16Array, Uint16Array, Int32Array, Uint32Array, Float32Array,
      Float64Array, BigInt64Array, BigUint64Array, Buffer].map(type => type.prototype);
    if (!prototypes.includes(Object.getPrototypeOf(value)) ||
        ['constructor', 'buffer', 'byteOffset', 'byteLength'].some(key => Object.hasOwn(value, key))) {
      return {value, replayable: false};
    }
    // The pinned host rejects shared backing stores. Do not promote them to
    // accepted ArrayBuffers; native bind retains its original rejection.
    if (value.buffer instanceof SharedArrayBuffer) return {value, replayable: false};
    // Preserve native element mapping and DataView semantics, not blanket bytes.
    try {
      return {value: Buffer.isBuffer(value) ? Buffer.from(value) : structuredClone(value), replayable: true};
    } catch {
      return {value, replayable: false};
    }
  }
  return {value, replayable: true};
}
function rawStatement(g, s) {
  if (s.revision !== g.revision) {
    if (s.bound && !s.replayable) fail('Exotic native binding cannot be replayed after fixture revision');
    s.native = g.raw.prepare(project(g, s.sql));
    if (s.bound) s.native = s.native.bind(...s.bindings);
    s.revision = g.revision;
  }
  return s.native;
}
function wrapStatement(g, sql, native, bound = false, bindings = [], replayable = true) {
  const s = {generation: g.handle, sql, native, bound, bindings, replayable, revision: g.revision};
  const wrapper = {
    bind(...values) {
      live(g);
      const current = rawStatement(g, s);
      const captured = values.map(captureBinding);
      const bindings = captured.map(binding => binding.value);
      return wrapStatement(g, sql, current.bind(...bindings), true, bindings,
        captured.every(binding => binding.replayable));
    },
  };
  for (const method of ['all','first','raw','run']) wrapper[method] = async (...args) => {
    live(g);
    const prepared = rawStatement(g, s);
    g.executing++;
    try { return await prepared[method](...args); }
    finally { g.executing--; }
  };
  statements.set(wrapper, s);
  return Object.freeze(wrapper);
}
const verificationSQL = 'SELECT type,name,tbl_name,rootpage,sql FROM main.sqlite_schema WHERE type=\'trigger\' AND name=?';
async function readTuple(g, entry) {
  const result = await g.raw.prepare(verificationSQL).bind(entry.name).all();
  if (!Array.isArray(result.results) || result.results.length !== 1) fail('Expected one installed native trigger');
  const row = result.results[0];
  const expectedSQL = entry.sql.endsWith(';') ? entry.sql.slice(0, -1) : entry.sql;
  if (row.type !== 'trigger' || row.name !== entry.name || row.tbl_name !== entry.table || row.sql !== expectedSQL || !Number.isSafeInteger(row.rootpage) || row.rootpage < 0) fail('Installed native tuple differs from catalogue');
  return Object.freeze(Object.fromEntries(columns.map(key => [key, row[key]])));
}
function deactivate(g) {
  g.active = false;
  g.registry.clear();
  g.revision++;
  const owner = owners.get(g.owner);
  if (owner.active === g.handle) owner.active = null;
}

/** A trusted test host owns one stable owner and the underlying storage lineage. */
export function createFixtureFaultSchemaOwner() {
  const owner = Object.freeze({
    beginGeneration(rawNativeDB) {
      const state = owners.get(owner);
      if (state.active) fail('Overlapping fixture generations');
      const previous = state.last && generations.get(state.last);
      if (previous && (previous.transition || previous.executing)) fail('Previous native generation still executing');
      if (!isObject(rawNativeDB) || typeof rawNativeDB.prepare !== 'function' || typeof rawNativeDB.batch !== 'function') fail('Invalid raw native database');
      state.number++;
      // Only an immediately succeeding generation can redeem a retired receipt.
      if (state.pending && receipts.get(state.pending).next !== state.number) {
        receipts.get(state.pending).valid = false; state.pending = null;
      }
      const g = {owner, raw: rawNativeDB, active: true, transition: false, executing: 0, registry: new Map(), revision: 0, handle: null};
      const projectedDB = Object.freeze({
        prepare(sql) {
          live(g);
          return wrapStatement(g, sql, g.raw.prepare(project(g, sql)));
        },
        async batch(items) {
          live(g);
          if (!Array.isArray(items)) fail('Native batch requires an array');
          const mapped = items.map(item => {
            const s = isObject(item) ? statements.get(item) : undefined;
            if (!s || s.generation !== g.handle) fail('Foreign/stale native batch statement');
            return s;
          });
          const native = mapped.map(s => rawStatement(g, s));
          g.executing++;
          try { return await g.raw.batch(native); }
          finally { g.executing--; }
        },
      });
      const handle = Object.freeze({
        projectedDB,
        async executeFixtureDDL(exactSQL) {
          assertIdle(g);
          if (arguments.length !== 1 || typeof exactSQL !== 'string') fail('Fixture DDL forbids bindings/extra arguments');
          const create = creates.get(exactSQL), dropName = drops.get(exactSQL);
          if (!create && !dropName) fail('DDL outside frozen catalogue');
          if (create && g.registry.has(create.name)) fail('Duplicate fixture registration');
          if (dropName) { g.registry.delete(dropName); g.revision++; }
          g.transition = true;
          try {
            await g.raw.prepare(exactSQL).run();
            if (create) {
              const tuple = await readTuple(g, create);
              if (!g.active) fail('Invalidated during fixture installation');
              g.registry.set(create.name, Object.freeze({entry: create, tuple}));
              g.revision++;
            }
          } finally { g.transition = false; }
        },
        invalidate() {
          const state = owners.get(owner);
          // An explicit host reset/canary/disposal burns even a retired receipt.
          if (state.pending) { receipts.get(state.pending).valid = false; state.pending = null; }
          deactivate(g);
        },
        retireForKnownRestart() {
          assertIdle(g);
          const state = owners.get(owner);
          if (state.pending) { receipts.get(state.pending).valid = false; state.pending = null; }
          const installed = Object.freeze([...g.registry.values()]);
          const receipt = Object.freeze({});
          receipts.set(receipt, {owner, previous: g.handle, next: state.number + 1, installed, valid: true});
          state.pending = receipt;
          deactivate(g);
          return receipt;
        },
        async reopenKnownInstalledFixtures(receipt) {
          assertIdle(g);
          const state = owners.get(owner);
          const saved = isObject(receipt) ? receipts.get(receipt) : undefined;
          // Reopen is an all-or-none transition: even rejection leaves no mask.
          g.registry.clear(); g.revision++;
          const permitted = saved && saved.owner === owner && saved.next === state.number && saved.valid && state.pending === receipt;
          if (state.pending) { receipts.get(state.pending).valid = false; state.pending = null; }
          // Burn the pending identity before any asynchronous native verification.
          if (!permitted) fail('Invalid/foreign/stale restart receipt');
          saved.valid = false;
          g.transition = true;
          try {
            const restored = [];
            for (const record of saved.installed) {
              if (creates.get(record.entry.sql) !== record.entry) fail('Restart catalogue identity mismatch');
              const tuple = await readTuple(g, record.entry);
              if (!columns.every(key => tuple[key] === record.tuple[key])) fail('Persisted trigger tuple changed');
              restored.push(record);
            }
            if (!g.active) fail('Invalidated during fixture reopen');
            for (const record of restored) g.registry.set(record.entry.name, record);
            g.revision++;
          } finally { g.transition = false; }
        },
      });
      g.handle = handle;
      generations.set(handle, g);
      state.active = handle;
      state.last = handle;
      return handle;
    },
  });
  owners.set(owner, {number: 0, active: null, pending: null, last: null});
  return owner;
}
