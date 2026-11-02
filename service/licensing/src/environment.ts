// Local proof adapters only. No ambient clock, randomness or transport is bound.
export interface FixtureEnvironment {
  ENVIRONMENT?: string;
  FIXTURE_MARKER?: string;
  PROVIDER_MODE?: string;
  FIXTURE_DB?: D1Database;
}
export interface FixtureAdapters {
  now: () => number;
  randomBytes: (length: number) => Uint8Array;
  fetch: typeof fetch;
}
export function assertFixtureEnvironment(env: FixtureEnvironment): void {
  if (env.ENVIRONMENT !== "local-fixture" || env.FIXTURE_MARKER !== "PAT-2639-local-only" || env.PROVIDER_MODE !== "fake") {
    throw new Error("fixture environment refused");
  }
}
export function fixtureSample(env: FixtureEnvironment, adapters: FixtureAdapters): { time: number; nonce: string } {
  assertFixtureEnvironment(env);
  const time = adapters.now();
  const bytes = adapters.randomBytes(16);
  if (!Number.isSafeInteger(time) || time < 0 || bytes.length !== 16) {
    throw new Error("fixture adapter refused");
  }
  return { time, nonce: Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("") };
}
export async function fixtureOutbound(env: FixtureEnvironment, adapters: FixtureAdapters): Promise<Response> {
  assertFixtureEnvironment(env);
  return adapters.fetch("https://fixture-outbound.invalid/");
}
