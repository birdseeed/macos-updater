import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { assertFixtureEnvironment, fixtureSample, fixtureOutbound, type FixtureAdapters } from "../../src/environment";
import worker from "../../src/index";

const valid = { ENVIRONMENT: "local-fixture", FIXTURE_MARKER: "PAT-2639-local-only", PROVIDER_MODE: "fake" };
const deny = vi.fn<typeof fetch>(async () => { throw new Error("unit network denied"); });
const adapters: FixtureAdapters = {
  now: () => 1_791_734_400_000,
  randomBytes: length => Uint8Array.from({ length }, (_, i) => i),
  fetch: deny,
};
beforeEach(() => { deny.mockClear(); vi.stubGlobal("fetch", deny); });
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

describe("fixture-only environment", () => {
  it("accepts the complete local marker", () => { expect(() => assertFixtureEnvironment(valid)).not.toThrow(); });
  it.each([
    {}, { ...valid, ENVIRONMENT: "production" }, { ...valid, ENVIRONMENT: "sandbox" },
    { ...valid, FIXTURE_MARKER: undefined }, { ...valid, FIXTURE_MARKER: "PAT-2639-local-only " },
    { ...valid, PROVIDER_MODE: "live" }, { ...valid, PROVIDER_MODE: "sandbox" },
  ])("refuses incomplete or mixed environment before adapters: %j", async env => {
    const now = vi.fn(adapters.now); const randomBytes = vi.fn(adapters.randomBytes);
    expect(() => assertFixtureEnvironment(env)).toThrow(/fixture environment refused/);
    expect(() => fixtureSample(env, { ...adapters, now, randomBytes })).toThrow(/fixture environment refused/);
    await expect(fixtureOutbound(env, adapters)).rejects.toThrow(/fixture environment refused/);
    expect(now).not.toHaveBeenCalled(); expect(randomBytes).not.toHaveBeenCalled(); expect(deny).not.toHaveBeenCalled();
  });
});

it("takes clock and bytes only from deterministic injected adapters", () => {
  vi.spyOn(Date, "now").mockImplementation(() => { throw new Error("ambient clock denied"); });
  vi.spyOn(Math, "random").mockImplementation(() => { throw new Error("ambient random denied"); });
  const now = vi.fn(adapters.now); const randomBytes = vi.fn(adapters.randomBytes);
  expect(fixtureSample(valid, { ...adapters, now, randomBytes })).toEqual({ time: 1_791_734_400_000, nonce: "000102030405060708090a0b0c0d0e0f" });
  expect(now).toHaveBeenCalledTimes(1); expect(randomBytes).toHaveBeenCalledExactlyOnceWith(16);
  expect(deny).not.toHaveBeenCalled();
});
it("network-denial canary blocks global fetch without sending bytes", async () => {
  await expect(fetch("https://unit-canary.invalid/")).rejects.toThrow("unit network denied");
  expect(deny).toHaveBeenCalledTimes(1);
});
it("outbound seam reaches the explicit denying adapter, never real network", async () => {
  await expect(fixtureOutbound(valid, adapters)).rejects.toThrow("unit network denied");
  expect(deny).toHaveBeenCalledExactlyOnceWith("https://fixture-outbound.invalid/");
});
it("worker refuses wrong environment before D1", async () => {
  const prepare = vi.fn(() => { throw new Error("D1 must not be touched"); });
  const env = { ...valid, ENVIRONMENT: "production", FIXTURE_DB: { prepare } as unknown as D1Database };
  const result = await worker.fetch(new Request("http://localhost/__fixture/rollback", { method: "POST" }), env);
  expect(result.status).toBe(503); expect(prepare).not.toHaveBeenCalled(); expect(deny).not.toHaveBeenCalled();
});
it("worker exposes no account or licence endpoint", async () => {
  const result = await worker.fetch(new Request("http://localhost/licence"), valid);
  expect(result.status).toBe(404); expect(deny).not.toHaveBeenCalled();
});
