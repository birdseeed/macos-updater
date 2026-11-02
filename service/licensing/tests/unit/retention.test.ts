import { afterEach, expect, it, vi } from "vitest";
import {
  cleanupEligibility, retentionDeadline, trialEligibility, trialMarkerOnDeletion,
  type CleanupInput, type MarkerDeletionInput, type RetentionRecord, type TrialEligibilityInput,
} from "../../src/retention";

const refused = { kind: "refused" };
const invalidNumbers: unknown[] = [-1, 0.5, NaN, Infinity, -Infinity, 253402300800, Number.MAX_SAFE_INTEGER, "0", null, undefined];
const ordinary: ReadonlyArray<readonly [string, RetentionRecord, number]> = [
  ["challenge creation", { category: "challenge", createdAt: 100 }, 86500],
  ["counter fixed bucket end", { category: "counter", bucketEndsAt: 200 }, 86600],
  ["session expiry only", { category: "session", firstExpiresAt: 300, firstRevokedAt: null }, 2592300],
  ["session revocation only", { category: "session", firstExpiresAt: null, firstRevokedAt: 400 }, 2592400],
  ["session earlier expiry", { category: "session", firstExpiresAt: 300, firstRevokedAt: 400 }, 2592300],
  ["session earlier revocation", { category: "session", firstExpiresAt: 400, firstRevokedAt: 300 }, 2592300],
  ["session simultaneous events", { category: "session", firstExpiresAt: 300, firstRevokedAt: 300 }, 2592300],
  ["terminal retry", { category: "ordinary-retry", createdAt: 100, terminalResultAt: 500, abandoned: false }, 2592500],
  ["abandoned retry", { category: "ordinary-retry", createdAt: 100, terminalResultAt: null, abandoned: true }, 2592100],
  ["released Mac", { category: "released-mac", terminalReleasedAt: 600 }, 7776600],
  ["audit leap clamp", { category: "audit", eventAt: 1709210096 }, 1772282096],
  ["trial marker", { category: "trial-marker", marker: { originalDeletedAt: 1709210096, expiresAt: 1740746096 } }, 1740746096],
];
function cleanup(record: RetentionRecord, now: number): CleanupInput {
  return { record, now, maxGrantPermittedUntil: null, pendingProviderIntent: false, reconciliationReference: false, approvedHoldRequiresRow: false };
}
for (const [name, record, deadline] of ordinary) {
  it(`${name}: fixed literal deadline`, () => { expect(retentionDeadline(record)).toEqual({ kind: "deadline", deadline }); });
  for (const [offset, expected] of [ [-1, { kind: "ineligible", reason: "before-deadline" }], [0, { kind: "eligible" }], [1, { kind: "eligible" }] ] as const) {
    it(`${name}: cleanup at deadline ${offset}`, () => { expect(cleanupEligibility(cleanup(record, deadline + offset))).toEqual(expected); });
  }
}
for (const category of ["active-account", "billing-dedup", "financial-ledger"] as const) {
  it(`${category}: no inferred TTL`, () => {
    expect(retentionDeadline({ category })).toEqual({ kind: "none", reason: category === "active-account" ? "active-account" : "separate-financial-schedule" });
    expect(cleanupEligibility(cleanup({ category }, 253402300799))).toEqual({ kind: "ineligible", reason: "no-automatic-schedule" });
  });
}
it("zero UTC epoch is accepted", () => { expect(retentionDeadline({ category: "challenge", createdAt: 0 })).toEqual({ kind: "deadline", deadline: 86400 }); });
it("duration addition exactly reaching maximum is accepted", () => { expect(retentionDeadline({ category: "challenge", createdAt: 253402214399 })).toEqual({ kind: "deadline", deadline: 253402300799 }); });
it("duration addition past maximum refuses", () => { expect(retentionDeadline({ category: "challenge", createdAt: 253402214400 })).toEqual(refused); });
it("calendar target past year 9999 refuses", () => { expect(retentionDeadline({ category: "audit", eventAt: 253402300799 })).toEqual(refused); });
for (const [anchor, deadline] of [
  [1675209599, 1738367999], // Jan 31 +24 months, preserving 23:59:59
  [1704067199, 1767225599], // year rollover
  [951786123, 1014858123], // year 2000 leap day
  [3981315723, 4044387723], // 2096 leap day
] as const) {
  it(`audit calendar addition ${anchor}`, () => { expect(retentionDeadline({ category: "audit", eventAt: anchor })).toEqual({ kind: "deadline", deadline }); });
}
it("session requires at least one effective terminal anchor", () => { expect(retentionDeadline({ category: "session", firstExpiresAt: null, firstRevokedAt: null })).toEqual(refused); });
it("unfinished retry has no terminal retention authority", () => { expect(retentionDeadline({ category: "ordinary-retry", createdAt: 1, terminalResultAt: null, abandoned: false })).toEqual(refused); });
it("terminal result before creation is malformed", () => { expect(retentionDeadline({ category: "ordinary-retry", createdAt: 200, terminalResultAt: 100, abandoned: false })).toEqual(refused); });
it("abandoned and terminal states together refuse", () => { expect(retentionDeadline({ category: "ordinary-retry", createdAt: 1, terminalResultAt: 2, abandoned: true })).toEqual(refused); });
const anchorVariants: Array<(bad: number) => RetentionRecord> = [
  bad => ({ category: "challenge", createdAt: bad }), bad => ({ category: "counter", bucketEndsAt: bad }),
  bad => ({ category: "session", firstExpiresAt: bad, firstRevokedAt: 1 }), bad => ({ category: "session", firstExpiresAt: 1, firstRevokedAt: bad }),
  bad => ({ category: "ordinary-retry", createdAt: bad, terminalResultAt: 100, abandoned: false }),
  bad => ({ category: "ordinary-retry", createdAt: 1, terminalResultAt: bad, abandoned: false }),
  bad => ({ category: "released-mac", terminalReleasedAt: bad }), bad => ({ category: "audit", eventAt: bad }),
];
for (const [index, variant] of anchorVariants.entries()) {
  it.each(index === 2 || index === 3 ? invalidNumbers.filter(value => value !== null) : invalidNumbers)(`anchor branch ${index} refuses malformed number %s even when another anchor wins`, bad => {
    expect(retentionDeadline(variant(bad as number))).toEqual(refused);
  });
}
for (const bad of [null, undefined, {}, { category: "unknown" }, { category: "session" }, { category: "ordinary-retry", createdAt: 1, terminalResultAt: 2 }, { category: "trial-marker", marker: null }]) {
  it(`runtime malformed category/state ${JSON.stringify(bad)}`, () => { expect(retentionDeadline(bad as RetentionRecord)).toEqual(refused); });
}

const originalMarker = { originalDeletedAt: 1709210096, expiresAt: 1740746096 };
const deletion: MarkerDeletionInput = { now: 1709210096, deletedAt: 1709210096, accountTrialUsed: true, existingMarker: null };
it("used trial deletion proposes exactly twelve months with leap clamp", () => {
  expect(trialMarkerOnDeletion(deletion)).toEqual({ kind: "propose-marker", marker: originalMarker });
});
it("unused trial deletion proposes no marker", () => { expect(trialMarkerOnDeletion({ ...deletion, accountTrialUsed: false })).toEqual({ kind: "none" }); });
for (const accountTrialUsed of [false, true]) {
  it(`unexpired original marker wins without extension; account used=${accountTrialUsed}`, () => {
    expect(trialMarkerOnDeletion({ ...deletion, now: 1740746095, deletedAt: 1740746000, accountTrialUsed, existingMarker: originalMarker })).toEqual({ kind: "retain-existing", marker: originalMarker });
  });
}
for (const now of [1740746096, 1740746097]) {
  it(`expired marker permits a new account trial at ${now}`, () => {
    expect(trialEligibility({ now, accountTrialUsed: false, existingMarker: originalMarker })).toEqual({ kind: "eligible" });
    expect(trialEligibility({ now, accountTrialUsed: true, existingMarker: originalMarker })).toEqual({ kind: "used-account" });
  });
}
it("one second before marker expiry blocks fresh account", () => { expect(trialEligibility({ now: 1740746095, accountTrialUsed: false, existingMarker: originalMarker })).toEqual({ kind: "unexpired-marker" }); });
it("existing used account never resets without a marker", () => { expect(trialEligibility({ now: 2000000000, accountTrialUsed: true, existingMarker: null })).toEqual({ kind: "used-account" }); });
it("unused fresh account without marker is eligible", () => { expect(trialEligibility({ now: 0, accountTrialUsed: false, existingMarker: null })).toEqual({ kind: "eligible" }); });
it("expired marker is replaced from new used-account deletion, not old marker or current access", () => {
  expect(trialMarkerOnDeletion({ now: 1772282096, deletedAt: 1740746096, accountTrialUsed: true, existingMarker: originalMarker })).toEqual({ kind: "propose-marker", marker: { originalDeletedAt: 1740746096, expiresAt: 1772282096 } });
});
it("unused account drops expired marker proposal", () => { expect(trialMarkerOnDeletion({ ...deletion, now: 1740746096, existingMarker: originalMarker, accountTrialUsed: false })).toEqual({ kind: "none" }); });
for (const [anchor, expiry] of [[1675209599, 1706745599], [1704067199, 1735689599], [4075923723, 4107459723]] as const) {
  it(`trial calendar month/year/century ${anchor}`, () => { expect(trialMarkerOnDeletion({ ...deletion, now: anchor, deletedAt: anchor })).toEqual({ kind: "propose-marker", marker: { originalDeletedAt: anchor, expiresAt: expiry } }); });
}
for (const field of ["now", "deletedAt"] as const) {
  it.each(invalidNumbers)(`marker ${field} malformed %s (unused branch also validates)`, bad => {
    expect(trialMarkerOnDeletion({ ...deletion, accountTrialUsed: false, [field]: bad } as MarkerDeletionInput)).toEqual(refused);
  });
}
it("future deletion anchor refuses", () => { expect(trialMarkerOnDeletion({ ...deletion, deletedAt: 1709210097 })).toEqual(refused); });
it("marker calendar overflow refuses", () => { expect(trialMarkerOnDeletion({ ...deletion, now: 253402300799, deletedAt: 253402300799 })).toEqual(refused); });
for (const marker of [
  { originalDeletedAt: -1, expiresAt: 1740746096 }, { originalDeletedAt: 1709210096, expiresAt: NaN },
  { originalDeletedAt: 1709210096, expiresAt: 1740746097 }, { originalDeletedAt: 1740746096, expiresAt: 1709210096 },
  { originalDeletedAt: 253402300799, expiresAt: 253402300799 }, {}, undefined,
]) {
  it(`malformed marker fails closed in every API ${JSON.stringify(marker)}`, () => {
    expect(trialMarkerOnDeletion({ ...deletion, existingMarker: marker } as MarkerDeletionInput)).toEqual(refused);
    expect(trialEligibility({ now: 2000000000, accountTrialUsed: true, existingMarker: marker } as TrialEligibilityInput)).toEqual(refused);
    expect(retentionDeadline({ category: "trial-marker", marker } as RetentionRecord)).toEqual(refused);
  });
}
it("marker from future deletion is malformed for current evaluation", () => {
  expect(trialEligibility({ now: 1, accountTrialUsed: false, existingMarker: originalMarker })).toEqual(refused);
});
it.each(invalidNumbers)("eligibility rejects malformed now %s even with used account", bad => {
  expect(trialEligibility({ now: bad, accountTrialUsed: true, existingMarker: null } as TrialEligibilityInput)).toEqual(refused);
});
for (const accountTrialUsed of [undefined, null, 0, "false"]) {
  it(`explicit trial-used boolean required ${accountTrialUsed}`, () => {
    expect(trialMarkerOnDeletion({ ...deletion, accountTrialUsed } as unknown as MarkerDeletionInput)).toEqual(refused);
    expect(trialEligibility({ now: 1, existingMarker: null, accountTrialUsed } as unknown as TrialEligibilityInput)).toEqual(refused);
  });
}

const ready = cleanup({ category: "challenge", createdAt: 100 }, 86500);
for (const field of ["pendingProviderIntent", "reconciliationReference", "approvedHoldRequiresRow"] as const) {
  it(`${field} independently prevents cleanup`, () => { expect(cleanupEligibility({ ...ready, [field]: true })).toEqual({ kind: "ineligible", reason: "protected" }); });
  for (const bad of [undefined, null, 0, 1, "false"]) {
    it(`${field} requires explicit runtime boolean ${bad}`, () => { expect(cleanupEligibility({ ...ready, [field]: bad } as CleanupInput)).toEqual(refused); });
  }
}
it("combined financial/security/grant protections prevent cleanup", () => { expect(cleanupEligibility({ ...ready, maxGrantPermittedUntil: 90000, pendingProviderIntent: true, reconciliationReference: true, approvedHoldRequiresRow: true })).toEqual({ kind: "ineligible", reason: "protected" }); });
for (const [now, kind] of [[89999, "ineligible"], [90000, "eligible"], [90001, "eligible"]] as const) {
  it(`grant bound ${now} is exclusive`, () => { expect(cleanupEligibility({ ...ready, now, maxGrantPermittedUntil: 90000 })).toEqual(kind === "eligible" ? { kind } : { kind, reason: "protected" }); });
}
it.each(invalidNumbers)("cleanup rejects malformed now %s", bad => { expect(cleanupEligibility({ ...ready, now: bad } as CleanupInput)).toEqual(refused); });
it.each(invalidNumbers.filter(value => value !== null))("cleanup rejects malformed grant bound %s even behind hold", bad => { expect(cleanupEligibility({ ...ready, maxGrantPermittedUntil: bad, approvedHoldRequiresRow: true } as CleanupInput)).toEqual(refused); });
it("cleanup rejects malformed category despite hold", () => { expect(cleanupEligibility({ ...ready, record: { category: "unknown" }, approvedHoldRequiresRow: true } as unknown as CleanupInput)).toEqual(refused); });
it("cleanup rejects missing runtime input", () => { expect(cleanupEligibility(undefined as unknown as CleanupInput)).toEqual(refused); });
it("missing marker input is not implicit absence", () => {
  expect(trialMarkerOnDeletion({ ...deletion, existingMarker: undefined } as unknown as MarkerDeletionInput)).toEqual(refused);
  expect(trialEligibility({ now: 0, accountTrialUsed: false } as TrialEligibilityInput)).toEqual(refused);
});
afterEach(() => { vi.restoreAllMocks(); });
it("deterministic calls/replays/access preserve inputs and original deadlines", () => {
  vi.spyOn(Date, "now").mockImplementation(() => { throw new Error("ambient clock denied"); });
  vi.spyOn(Math, "random").mockImplementation(() => { throw new Error("ambient random denied"); });
  const record = Object.freeze({ category: "ordinary-retry" as const, createdAt: 100, terminalResultAt: 500, abandoned: false });
  const frozenMarker = Object.freeze({ ...originalMarker });
  const input = Object.freeze({ ...deletion, now: 1740746095, deletedAt: 1740746000, existingMarker: frozenMarker });
  for (let replay = 0; replay < 3; replay++) {
    expect(retentionDeadline(record)).toEqual({ kind: "deadline", deadline: 2592500 });
    expect(trialMarkerOnDeletion(input)).toEqual({ kind: "retain-existing", marker: originalMarker });
    expect(cleanupEligibility(Object.freeze(cleanup(record, 2592500)))).toEqual({ kind: "eligible" });
  }
  expect(record).toEqual({ category: "ordinary-retry", createdAt: 100, terminalResultAt: 500, abandoned: false });
  expect(frozenMarker).toEqual(originalMarker);
});
