import { expect, it } from "vitest";
import { cleanupEligibility, retentionDeadline, trialEligibility, trialMarkerOnDeletion, type CleanupInput, type RetentionRecord, type TrialEligibilityInput, type MarkerDeletionInput } from "../../src/retention";

it("mutating a returned refusal cannot poison later invalid policy decisions", () => {
  const first = retentionDeadline(null as unknown as RetentionRecord);
  try { Object.assign(first, { kind: "eligible" }); } catch { /* An immutable refusal may reject the attempted mutation. */ }
  expect(retentionDeadline(null as unknown as RetentionRecord)).toEqual({ kind: "refused" });
  expect(trialMarkerOnDeletion(null as unknown as MarkerDeletionInput)).toEqual({ kind: "refused" });
  expect(trialEligibility(null as unknown as TrialEligibilityInput)).toEqual({ kind: "refused" });
  expect(cleanupEligibility(null as unknown as CleanupInput)).toEqual({ kind: "refused" });
});
