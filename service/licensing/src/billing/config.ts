// PAT-2645 synthetic fixtures only. This configuration confers no authority.
export type BillingEnvironment = 'synthetic-sandbox';
export interface BillingConfig {
 fixture: 'PAT-2645-synthetic'; environment: BillingEnvironment; hmacKey: Uint8Array;
 prices: { GBP: 'fixture-price-gbp-annual'; USD: 'fixture-price-usd-annual' };
}
export interface BillingAdapters { now: () => number; attemptID: () => string; fetch: typeof fetch }
export interface BillingComposition { config: unknown; adapters: BillingAdapters }
export interface BillingEvent {
 event_id: string; event_type: string; occurred_at: number;
 data: { environment: BillingEnvironment; subject_id: string;
 price_id: 'fixture-price-gbp-annual' | 'fixture-price-usd-annual'; currency: 'GBP' | 'USD'; quantity: 1;
 detail: { label: string; flags: boolean[] } };
}
export interface BillingEnvelope extends BillingEvent { notification_id: string }
export type RejectReason = 'configuration' | 'method' | 'route' | 'media-type' | 'body-limit' | 'body-read' | 'signature' | 'clock' | 'json' | 'schema';
export type ParseResult = { ok: true; value: BillingEnvelope } | { ok: false; reason: 'json' | 'schema' };
export type IngestResult = { outcome: 'stored' | 'duplicate'; status: 200 } | { outcome: 'quarantined'; status: 400 | 409 } | { outcome: 'unavailable'; status: 503 };
export const BILLING_LIMITS = Object.freeze({bodyBytes:262144,chunks:4096,depth:16,members:2048,elements:2048,stringBytes:4096,labelBytes:256,flags:16,maxSeconds:253402300799});
// Require a closed own-data record; accessors and prototype properties supply no configuration.
export function closedRecord(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
 if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
 const own = Reflect.ownKeys(value);
 return own.length === keys.length && keys.every(key => {
  const descriptor = Object.getOwnPropertyDescriptor(value, key);
  return descriptor !== undefined && 'value' in descriptor;
 });
}
export function billingSeconds(value: unknown): value is number {
 return typeof value === 'number' && Number.isSafeInteger(value) && !Object.is(value, -0) && value >= 0 && value <= BILLING_LIMITS.maxSeconds;
}
export function validateBillingConfig(value: unknown): BillingConfig | undefined {
 try {
  if (!closedRecord(value, ['fixture','environment','hmacKey','prices']) ||
      value.fixture !== 'PAT-2645-synthetic' || value.environment !== 'synthetic-sandbox' ||
      !(value.hmacKey instanceof Uint8Array) || value.hmacKey.length !== 32 ||
      !closedRecord(value.prices, ['GBP','USD']) ||
      value.prices.GBP !== 'fixture-price-gbp-annual' || value.prices.USD !== 'fixture-price-usd-annual') return undefined;
  return {fixture:'PAT-2645-synthetic', environment:'synthetic-sandbox', hmacKey:new Uint8Array(value.hmacKey),
   prices:{GBP:'fixture-price-gbp-annual', USD:'fixture-price-usd-annual'}};
 } catch { return undefined; }
}
