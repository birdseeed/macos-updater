import type { BillingEnvelope, IngestResult } from './config';
export interface BillingIngestInput {
 attemptID:string; receivedAt:number; signatureAt:number; raw:Uint8Array; rawSHA256:string;
 parsed:{kind:'event';envelope:BillingEnvelope;canonical:Uint8Array;semanticSHA256:string}|{kind:'invalid';reason:'json'|'schema'};
}
// Synthetic append-only evidence only; no productive trust or account association.
const SQL_0 = "SELECT CASE WHEN NOT (EXISTS(SELECT 1 FROM billing_webhook_delivery WHERE attempt_id=?1) OR EXISTS(SELECT 1 FROM billing_event_conflict WHERE attempt_id=?1) OR EXISTS(SELECT 1 FROM billing_webhook_quarantine WHERE attempt_id=?1) OR EXISTS(SELECT 1 FROM billing_webhook_audit WHERE attempt_id=?1) OR EXISTS(SELECT 1 FROM billing_inbox_commit WHERE attempt_id=?1) OR EXISTS(SELECT 1 FROM billing_event WHERE first_attempt_id=?1)) THEN 1 ELSE json('') END AS fresh_attempt";
const SQL_1 = "INSERT INTO billing_webhook_body(raw_sha256,raw_bytes) VALUES (?1,?2) ON CONFLICT(raw_sha256) DO NOTHING";
const SQL_2 = "INSERT INTO billing_event(environment,event_id,semantic_sha256,canonical_bytes,event_type,occurred_at,subject_id,first_attempt_id) VALUES ('synthetic-sandbox',?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(environment,event_id) DO NOTHING";
const SQL_3 = "INSERT INTO billing_webhook_delivery(attempt_id,environment,notification_id,event_id,raw_sha256,signature_at,received_at,outcome)\n VALUES (?1,'synthetic-sandbox',?2,?3,?4,?5,?6,\n CASE WHEN ?7='invalid' THEN 'invalid' ELSE\n (SELECT CASE WHEN e.first_attempt_id=?1 THEN 'stored'\n WHEN e.semantic_sha256=?8 AND e.canonical_bytes=?9 THEN 'duplicate' ELSE 'conflict' END\n FROM billing_event e WHERE e.environment='synthetic-sandbox' AND e.event_id=?3) END)";
const SQL_4 = "INSERT INTO billing_event_conflict(attempt_id,environment,event_id,original_semantic_sha256,incoming_semantic_sha256)\n SELECT d.attempt_id,d.environment,d.event_id,e.semantic_sha256,?1\n FROM billing_webhook_delivery d JOIN billing_event e ON e.environment=d.environment AND e.event_id=d.event_id\n WHERE d.attempt_id=?2 AND d.outcome='conflict'";
const SQL_5 = "INSERT INTO billing_webhook_quarantine(attempt_id,reason)\n SELECT attempt_id,CASE WHEN outcome='conflict' THEN 'conflict' ELSE ?1 END\n FROM billing_webhook_delivery WHERE attempt_id=?2 AND outcome IN ('conflict','invalid')";
const SQL_6 = "INSERT INTO billing_webhook_audit(attempt_id,action,raw_sha256,received_at)\n SELECT attempt_id,outcome,raw_sha256,received_at FROM billing_webhook_delivery WHERE attempt_id=?1";
const SQL_7 = "INSERT INTO billing_inbox_commit(attempt_id,complete) VALUES (?1,CASE WHEN (SELECT count(*) FROM billing_webhook_delivery d\n JOIN billing_webhook_body b ON b.raw_sha256=d.raw_sha256\n JOIN billing_webhook_audit a ON a.attempt_id=d.attempt_id\n WHERE d.attempt_id=?1 AND d.environment='synthetic-sandbox'\n AND d.raw_sha256=?2 AND b.raw_bytes=?3\n AND d.signature_at=?4 AND d.received_at=?5\n AND a.action=d.outcome AND a.raw_sha256=d.raw_sha256 AND a.received_at=d.received_at\n AND (\n (?6='invalid' AND d.outcome='invalid' AND d.event_id IS NULL AND d.notification_id IS NULL\n  AND NOT EXISTS(SELECT 1 FROM billing_event WHERE first_attempt_id=?1)\n  AND NOT EXISTS(SELECT 1 FROM billing_event_conflict WHERE attempt_id=?1)\n  AND (SELECT count(*) FROM billing_webhook_quarantine WHERE attempt_id=?1 AND reason=?7)=1)\n OR\n (?6='event' AND d.event_id=?8 AND d.notification_id=?9\n  AND EXISTS(SELECT 1 FROM billing_event e WHERE e.environment=d.environment AND e.event_id=d.event_id\n   AND (\n    (d.outcome IN ('stored','duplicate') AND e.semantic_sha256=?10 AND e.canonical_bytes=?11\n     AND e.event_type=?12 AND e.occurred_at=?13 AND e.subject_id=?14\n     AND ((d.outcome='stored' AND e.first_attempt_id=?1) OR (d.outcome='duplicate' AND e.first_attempt_id<>?1))\n     AND NOT EXISTS(SELECT 1 FROM billing_event_conflict WHERE attempt_id=?1)\n     AND NOT EXISTS(SELECT 1 FROM billing_webhook_quarantine WHERE attempt_id=?1))\n    OR\n    (d.outcome='conflict' AND e.first_attempt_id<>?1\n     AND (e.semantic_sha256<>?10 OR e.canonical_bytes<>?11)\n     AND (SELECT count(*) FROM billing_event_conflict c WHERE c.attempt_id=?1 AND c.environment=e.environment\n      AND c.event_id=e.event_id AND c.original_semantic_sha256=e.semantic_sha256 AND c.incoming_semantic_sha256=?10)=1\n     AND (SELECT count(*) FROM billing_webhook_quarantine WHERE attempt_id=?1 AND reason='conflict')=1)\n   ))\n )\n ))=1 THEN 1 ELSE 0 END)";
const SQL_8 = "SELECT CASE WHEN ((SELECT count(*) FROM billing_webhook_delivery d\n JOIN billing_webhook_body b ON b.raw_sha256=d.raw_sha256\n JOIN billing_webhook_audit a ON a.attempt_id=d.attempt_id\n WHERE d.attempt_id=?1 AND d.environment='synthetic-sandbox'\n AND d.raw_sha256=?2 AND b.raw_bytes=?3\n AND d.signature_at=?4 AND d.received_at=?5\n AND a.action=d.outcome AND a.raw_sha256=d.raw_sha256 AND a.received_at=d.received_at\n AND (\n (?6='invalid' AND d.outcome='invalid' AND d.event_id IS NULL AND d.notification_id IS NULL\n  AND NOT EXISTS(SELECT 1 FROM billing_event WHERE first_attempt_id=?1)\n  AND NOT EXISTS(SELECT 1 FROM billing_event_conflict WHERE attempt_id=?1)\n  AND (SELECT count(*) FROM billing_webhook_quarantine WHERE attempt_id=?1 AND reason=?7)=1)\n OR\n (?6='event' AND d.event_id=?8 AND d.notification_id=?9\n  AND EXISTS(SELECT 1 FROM billing_event e WHERE e.environment=d.environment AND e.event_id=d.event_id\n   AND (\n    (d.outcome IN ('stored','duplicate') AND e.semantic_sha256=?10 AND e.canonical_bytes=?11\n     AND e.event_type=?12 AND e.occurred_at=?13 AND e.subject_id=?14\n     AND ((d.outcome='stored' AND e.first_attempt_id=?1) OR (d.outcome='duplicate' AND e.first_attempt_id<>?1))\n     AND NOT EXISTS(SELECT 1 FROM billing_event_conflict WHERE attempt_id=?1)\n     AND NOT EXISTS(SELECT 1 FROM billing_webhook_quarantine WHERE attempt_id=?1))\n    OR\n    (d.outcome='conflict' AND e.first_attempt_id<>?1\n     AND (e.semantic_sha256<>?10 OR e.canonical_bytes<>?11)\n     AND (SELECT count(*) FROM billing_event_conflict c WHERE c.attempt_id=?1 AND c.environment=e.environment\n      AND c.event_id=e.event_id AND c.original_semantic_sha256=e.semantic_sha256 AND c.incoming_semantic_sha256=?10)=1\n     AND (SELECT count(*) FROM billing_webhook_quarantine WHERE attempt_id=?1 AND reason='conflict')=1)\n   ))\n )\n ))=1) AND (SELECT count(*) FROM billing_inbox_commit WHERE attempt_id=?1 AND complete=1)=1 THEN (SELECT outcome FROM billing_webhook_delivery WHERE attempt_id=?1) ELSE json('') END AS outcome";

export async function ingestBillingInbox(db:D1Database,input:BillingIngestInput):Promise<IngestResult> {
 try {
  // Own bytes and snapshot all scalar bindings synchronously, before batch I/O.
  const parsed = input.parsed, event = parsed.kind === 'event' ? parsed.envelope : undefined;
  const bindings: Record<string,string|number|Uint8Array|null> = {
   attemptID:input.attemptID, receivedAt:input.receivedAt, signatureAt:input.signatureAt,
   raw:new Uint8Array(input.raw), rawSHA256:input.rawSHA256, kind:parsed.kind,
   invalidReason:parsed.kind === 'invalid' ? parsed.reason : null,
   eventID:event?.event_id ?? null, notificationID:event?.notification_id ?? null,
   semanticSHA256:parsed.kind === 'event' ? parsed.semanticSHA256 : null,
   canonical:parsed.kind === 'event' ? new Uint8Array(parsed.canonical) : null,
   eventType:event?.event_type ?? null, occurredAt:event?.occurred_at ?? null, subjectID:event?.data.subject_id ?? null
  };
  const statements: D1PreparedStatement[] = [];
  statements.push(db.prepare(SQL_0).bind(bindings.attemptID));
  statements.push(db.prepare(SQL_1).bind(bindings.rawSHA256,bindings.raw));
  if (parsed.kind === 'event') {
  statements.push(db.prepare(SQL_2).bind(bindings.eventID,bindings.semanticSHA256,bindings.canonical,bindings.eventType,bindings.occurredAt,bindings.subjectID,bindings.attemptID));
  }
  statements.push(db.prepare(SQL_3).bind(bindings.attemptID,bindings.notificationID,bindings.eventID,bindings.rawSHA256,bindings.signatureAt,bindings.receivedAt,bindings.kind,bindings.semanticSHA256,bindings.canonical));
  statements.push(db.prepare(SQL_4).bind(bindings.semanticSHA256,bindings.attemptID));
  statements.push(db.prepare(SQL_5).bind(bindings.invalidReason,bindings.attemptID));
  statements.push(db.prepare(SQL_6).bind(bindings.attemptID));
  statements.push(db.prepare(SQL_7).bind(bindings.attemptID,bindings.rawSHA256,bindings.raw,bindings.signatureAt,bindings.receivedAt,bindings.kind,bindings.invalidReason,bindings.eventID,bindings.notificationID,bindings.semanticSHA256,bindings.canonical,bindings.eventType,bindings.occurredAt,bindings.subjectID));
  statements.push(db.prepare(SQL_8).bind(bindings.attemptID,bindings.rawSHA256,bindings.raw,bindings.signatureAt,bindings.receivedAt,bindings.kind,bindings.invalidReason,bindings.eventID,bindings.notificationID,bindings.semanticSHA256,bindings.canonical,bindings.eventType,bindings.occurredAt,bindings.subjectID));
  const results = await db.batch<{outcome:string}>(statements);
  if (results.length !== statements.length || results.some(result => !result.success)) return {outcome:'unavailable',status:503};
  const rows = results[results.length-1].results;
  if (!rows || rows.length !== 1) return {outcome:'unavailable',status:503};
  switch (rows[0].outcome) {
   case 'stored': return {outcome:'stored',status:200};
   case 'duplicate': return {outcome:'duplicate',status:200};
   case 'invalid': return {outcome:'quarantined',status:400};
   case 'conflict': return {outcome:'quarantined',status:409};
   default: return {outcome:'unavailable',status:503};
  }
 } catch { return {outcome:'unavailable',status:503}; }
}
