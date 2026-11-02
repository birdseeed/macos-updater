import { expect, it, vi } from "vitest";
import worker from "../../src/index";

function environment(batch: () => Promise<unknown>) {
  return {
    ENVIRONMENT: "local-fixture", FIXTURE_MARKER: "PAT-2639-local-only", PROVIDER_MODE: "fake",
    FIXTURE_DB: { prepare: vi.fn(() => ({})), batch } as unknown as D1Database,
  };
}
const request = () => new Request("http://localhost/__fixture/rollback", { method: "POST" });
it.each([
  new Error("fixture database unavailable"),
  new Error("D1_ERROR: UNIQUE constraint failed: unrelated_fixture.id: SQLITE_CONSTRAINT"),
])("unexpected D1 failure refuses instead of claiming rollback", async error => {
  const response = await worker.fetch(request(), environment(async () => { throw error; }));
  expect(response.status).toBe(503);
  expect(await response.json()).toEqual({ fixture: "PAT-2639-local-only", outcome: "refused" });
});
it("a rollback batch that unexpectedly succeeds cannot claim rollback", async () => {
  const response = await worker.fetch(request(), environment(async () => []));
  expect(response.status).toBe(500);
  expect(await response.json()).toEqual({ fixture: "PAT-2639-local-only", outcome: "unexpected-commit" });
});
