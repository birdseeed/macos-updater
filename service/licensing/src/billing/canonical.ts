import type { BillingEvent } from './config';
// Restricted integer/scalar domain; callers first validate the complete envelope.
export function canonicalBillingEvent(event: BillingEvent): Uint8Array {
 const encode = (value: unknown): string => {
  if (Array.isArray(value)) return '[' + value.map(encode).join(',') + ']';
  if (value !== null && typeof value === 'object') {
   const record = value as Record<string,unknown>;
   return '{' + Object.keys(record).sort().map(key => JSON.stringify(key)+':'+encode(record[key])).join(',') + '}';
  }
  return JSON.stringify(value);
 };
 return new TextEncoder().encode(encode({event_id:event.event_id,event_type:event.event_type,occurred_at:event.occurred_at,data:event.data}));
}
export async function billingSHA256(bytes: Uint8Array): Promise<string> {
 const owned = new Uint8Array(bytes);
 const digest = await crypto.subtle.digest('SHA-256',owned);
 return Array.from(new Uint8Array(digest),byte=>byte.toString(16).padStart(2,'0')).join('');
}
