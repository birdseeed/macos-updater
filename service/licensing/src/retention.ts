/** Pure injected retention policy only. No storage, deletion, identity or approval authority. */
export type TrialMarker = Readonly<{ originalDeletedAt: number; expiresAt: number }>;
export type RetentionRecord =
  | Readonly<{ category: "challenge"; createdAt: number }>
  | Readonly<{ category: "counter"; bucketEndsAt: number }>
  | Readonly<{ category: "session"; firstExpiresAt: number | null; firstRevokedAt: number | null }>
  | Readonly<{ category: "ordinary-retry"; createdAt: number; terminalResultAt: number | null; abandoned: boolean }>
  | Readonly<{ category: "released-mac"; terminalReleasedAt: number }>
  | Readonly<{ category: "audit"; eventAt: number }>
  | Readonly<{ category: "trial-marker"; marker: TrialMarker }>
  | Readonly<{ category: "active-account" }>
  | Readonly<{ category: "billing-dedup" }>
  | Readonly<{ category: "financial-ledger" }>;
export type Refused = Readonly<{ kind: "refused" }>;
export type RetentionDeadline =
  | Readonly<{ kind: "deadline"; deadline: number }>
  | Readonly<{ kind: "none"; reason: "active-account" | "separate-financial-schedule" }>
  | Refused;
export type MarkerDeletionInput = Readonly<{
  now: number; deletedAt: number; accountTrialUsed: boolean; existingMarker: TrialMarker | null;
}>;
export type MarkerDecision =
  | Readonly<{ kind: "retain-existing"; marker: TrialMarker }>
  | Readonly<{ kind: "propose-marker"; marker: TrialMarker }>
  | Readonly<{ kind: "none" }>
  | Refused;
export type TrialEligibilityInput = Readonly<{
  now: number; accountTrialUsed: boolean; existingMarker: TrialMarker | null;
}>;
export type TrialEligibility = Readonly<{ kind: "eligible" | "used-account" | "unexpired-marker" }> | Refused;
export type CleanupInput = Readonly<{
  now: number; record: RetentionRecord; maxGrantPermittedUntil: number | null;
  pendingProviderIntent: boolean; reconciliationReference: boolean; approvedHoldRequiresRow: boolean;
}>;
export type CleanupDecision =
  | Readonly<{ kind: "eligible" }>
  | Readonly<{ kind: "ineligible"; reason: "before-deadline" | "protected" | "no-automatic-schedule" }>
  | Refused;

const MAX_TIMESTAMP = 253402300799;
const DAY = 86400;
const refused: Refused = Object.freeze({ kind: "refused" });

type Fields = Record<string, unknown>;
function fields(value: unknown, names: readonly string[]): value is Fields {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const keys = Reflect.ownKeys(value);
  return keys.length === names.length && keys.every(key => typeof key === "string" && names.includes(key));
}
function timestamp(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= MAX_TIMESTAMP;
}
function nullableTimestamp(value: unknown): value is number | null {
  return value === null || timestamp(value);
}
function duration(anchor: number, days: number): RetentionDeadline {
  const deadline = anchor + days * DAY;
  return timestamp(deadline) ? { kind: "deadline", deadline } : refused;
}
function calendarMonths(anchor: number, months: 12 | 24): number | null {
  const original = new Date(anchor * 1000);
  const year = original.getUTCFullYear() + months / 12;
  if (year > 9999) return null;
  const month = original.getUTCMonth();
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const result = Date.UTC(year, month, Math.min(original.getUTCDate(), lastDay),
    original.getUTCHours(), original.getUTCMinutes(), original.getUTCSeconds()) / 1000;
  return timestamp(result) ? result : null;
}
function markerValid(value: unknown): value is TrialMarker {
  return fields(value, ["originalDeletedAt", "expiresAt"]) && timestamp(value.originalDeletedAt)
    && timestamp(value.expiresAt) && calendarMonths(value.originalDeletedAt, 12) === value.expiresAt;
}
function markerAt(value: unknown, now: number): value is TrialMarker | null {
  return value === null || (markerValid(value) && value.originalDeletedAt <= now);
}
function recordDeadline(value: unknown): RetentionDeadline {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return refused;
  const record = value as Fields;
  switch (record.category) {
    case "challenge":
      return fields(record, ["category", "createdAt"]) && timestamp(record.createdAt)
        ? duration(record.createdAt, 1) : refused;
    case "counter":
      return fields(record, ["category", "bucketEndsAt"]) && timestamp(record.bucketEndsAt)
        ? duration(record.bucketEndsAt, 1) : refused;
    case "session": {
      if (!fields(record, ["category", "firstExpiresAt", "firstRevokedAt"])
        || !nullableTimestamp(record.firstExpiresAt) || !nullableTimestamp(record.firstRevokedAt)) return refused;
      const expiry = record.firstExpiresAt;
      const revocation = record.firstRevokedAt;
      if (expiry === null && revocation === null) return refused;
      return duration(expiry === null ? revocation! : revocation === null ? expiry : Math.min(expiry, revocation), 30);
    }
    case "ordinary-retry": {
      if (!fields(record, ["category", "createdAt", "terminalResultAt", "abandoned"])
        || !timestamp(record.createdAt) || !nullableTimestamp(record.terminalResultAt)
        || typeof record.abandoned !== "boolean") return refused;
      if (record.terminalResultAt === null) return record.abandoned ? duration(record.createdAt, 30) : refused;
      return !record.abandoned && record.terminalResultAt >= record.createdAt
        ? duration(record.terminalResultAt, 30) : refused;
    }
    case "released-mac":
      return fields(record, ["category", "terminalReleasedAt"]) && timestamp(record.terminalReleasedAt)
        ? duration(record.terminalReleasedAt, 90) : refused;
    case "audit": {
      if (!fields(record, ["category", "eventAt"]) || !timestamp(record.eventAt)) return refused;
      const deadline = calendarMonths(record.eventAt, 24);
      return deadline === null ? refused : { kind: "deadline", deadline };
    }
    case "trial-marker":
      return fields(record, ["category", "marker"]) && markerValid(record.marker)
        ? { kind: "deadline", deadline: record.marker.expiresAt } : refused;
    case "active-account":
      return fields(record, ["category"]) ? { kind: "none", reason: "active-account" } : refused;
    case "billing-dedup":
    case "financial-ledger":
      return fields(record, ["category"]) ? { kind: "none", reason: "separate-financial-schedule" } : refused;
    default: return refused;
  }
}

/** Returns only a policy deadline, never authority to erase a record. */
export function retentionDeadline(record: RetentionRecord): RetentionDeadline {
  try { return recordDeadline(record); } catch { return refused; }
}

/** Proposes a marker value only; HMAC custody, writes and identity verification are absent. */
export function trialMarkerOnDeletion(input: MarkerDeletionInput): MarkerDecision {
  try {
    if (!fields(input, ["now", "deletedAt", "accountTrialUsed", "existingMarker"])
      || !timestamp(input.now) || !timestamp(input.deletedAt) || input.deletedAt > input.now
      || typeof input.accountTrialUsed !== "boolean" || !markerAt(input.existingMarker, input.now)) return refused;
    if (input.existingMarker !== null && input.now < input.existingMarker.expiresAt) {
      return { kind: "retain-existing", marker: { ...input.existingMarker } };
    }
    if (!input.accountTrialUsed) return { kind: "none" };
    const expiresAt = calendarMonths(input.deletedAt, 12);
    return expiresAt === null ? refused : { kind: "propose-marker", marker: { originalDeletedAt: input.deletedAt, expiresAt } };
  } catch { return refused; }
}

/** Existing account history is independent of the separately expiring email marker. */
export function trialEligibility(input: TrialEligibilityInput): TrialEligibility {
  try {
    if (!fields(input, ["now", "accountTrialUsed", "existingMarker"]) || !timestamp(input.now)
      || typeof input.accountTrialUsed !== "boolean" || !markerAt(input.existingMarker, input.now)) return refused;
    if (input.accountTrialUsed) return { kind: "used-account" };
    return input.existingMarker !== null && input.now < input.existingMarker.expiresAt
      ? { kind: "unexpired-marker" } : { kind: "eligible" };
  } catch { return refused; }
}

/** Eligibility is a pure predicate over untrusted injected facts, not deletion approval. */
export function cleanupEligibility(input: CleanupInput): CleanupDecision {
  try {
    if (!fields(input, ["now", "record", "maxGrantPermittedUntil", "pendingProviderIntent", "reconciliationReference", "approvedHoldRequiresRow"])
      || !timestamp(input.now) || !nullableTimestamp(input.maxGrantPermittedUntil)
      || typeof input.pendingProviderIntent !== "boolean" || typeof input.reconciliationReference !== "boolean"
      || typeof input.approvedHoldRequiresRow !== "boolean") return refused;
    const result = recordDeadline(input.record);
    if (result.kind === "refused") return refused;
    if (result.kind === "none") return { kind: "ineligible", reason: "no-automatic-schedule" };
    if (input.now < result.deadline) return { kind: "ineligible", reason: "before-deadline" };
    if ((input.maxGrantPermittedUntil !== null && input.now < input.maxGrantPermittedUntil)
      || input.pendingProviderIntent || input.reconciliationReference || input.approvedHoldRequiresRow) {
      return { kind: "ineligible", reason: "protected" };
    }
    return { kind: "eligible" };
  } catch { return refused; }
}
