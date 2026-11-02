import { assertFixtureEnvironment, type FixtureEnvironment } from '../environment';
import { BILLING_LIMITS, billingSeconds, validateBillingConfig, type BillingConfig, type BillingAdapters, type BillingComposition } from './config';
import { parseBillingEnvelope } from './strictjson';
import { billingSHA256, canonicalBillingEvent } from './canonical';
import { ingestBillingInbox, type BillingIngestInput } from './inbox';

function signatureParts(header: string | null): {timestamp:number; decimal:string; signature:Uint8Array} | undefined {
 if (header === null) return undefined;
 const match = /^t=(0|[1-9][0-9]{0,11});v1=([0-9a-f]{64})$/.exec(header);
 if (!match || match[0] !== header || !billingSeconds(Number(match[1]))) return undefined;
 return {timestamp:Number(match[1]),decimal:match[1],signature:Uint8Array.from(match[2].match(/../g)!,byte=>parseInt(byte,16))};
}
export async function verifyFixtureSignature(raw:Uint8Array,header:string|null,config:BillingConfig,now:number):Promise<boolean> {
 try {
  // Copy both mutable inputs before the first suspension.
  const owned = new Uint8Array(raw), checked = validateBillingConfig(config), parts = signatureParts(header);
  if (!checked || !parts || !billingSeconds(now) || parts.timestamp < now-300 || parts.timestamp > now+30) return false;
  const prefix = new TextEncoder().encode('PAT-2645\n'+parts.decimal+'\n');
  const message = new Uint8Array(prefix.length+owned.length);
  message.set(prefix); message.set(owned,prefix.length);
  const key = await crypto.subtle.importKey('raw',checked.hmacKey as Uint8Array<ArrayBuffer>,{name:'HMAC',hash:'SHA-256'},false,['verify']);
  return await crypto.subtle.verify('HMAC',key,parts.signature as Uint8Array<ArrayBuffer>,message);
 } catch { return false; }
}
function response(status:number,outcome:string): Response {
 return Response.json({fixture:'PAT-2645-synthetic',outcome},{status,headers:{'Cache-Control':'no-store'}});
}
export async function receiveBillingWebhook(request:Request,env:FixtureEnvironment,config:unknown,adapters:BillingAdapters):Promise<Response> {
 try {
  assertFixtureEnvironment(env);
  const checked = validateBillingConfig(config), db = env.FIXTURE_DB;
  if (!checked || !db || !adapters || typeof adapters.now !== 'function' || typeof adapters.attemptID !== 'function' || typeof adapters.fetch !== 'function') return response(503,'unavailable');
  const now = adapters.now(), attemptID = adapters.attemptID();
  if (!billingSeconds(now) || typeof attemptID !== 'string' || !/^[0-9a-f]{32}$/.test(attemptID) || attemptID.length !== 32) return response(503,'unavailable');
  const url = new URL(request.url);
  if (url.pathname !== '/__fixture/billing/webhook' || request.url.includes('?') || request.url.includes('#')) return response(404,'refused');
  if (request.method !== 'POST') return response(405,'refused');
  const media = request.headers.get('Content-Type');
  if (!media || !/^application\/json(?:;\s*charset=utf-8)?$/i.test(media) || request.headers.has('Content-Encoding')) return response(415,'refused');
  const declared = request.headers.get('Content-Length');
  const header = request.headers.get('X-Patched-Fixture-Signature');
  if (declared !== null && (!/^(0|[1-9][0-9]*)$/.test(declared) || Number(declared) > BILLING_LIMITS.bodyBytes)) return response(400,'refused');
  if (!request.body) return response(400,'refused');
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0, count = 0;
  const cancel = async () => { try { await reader.cancel(); } catch { /* no input/error disclosure */ } };
  try {
   for (;;) {
    const item = await reader.read();
    if (item.done) break;
    if (!(item.value instanceof Uint8Array)) { await cancel(); return response(400,'refused'); }
    length += item.value.length;
    if (++count > BILLING_LIMITS.chunks || length > BILLING_LIMITS.bodyBytes) { await cancel(); return response(413,'refused'); }
    chunks.push(new Uint8Array(item.value));
   }
  } catch { await cancel(); return response(400,'refused'); }
  finally { reader.releaseLock(); }
  if (length === 0 || (declared !== null && Number(declared) !== length)) return response(400,'refused');
  const raw = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { raw.set(chunk,offset); offset += chunk.length; }
  if (!await verifyFixtureSignature(raw,header,checked,now)) return response(401,'refused');
  const signatureAt = signatureParts(header)!.timestamp;
  const parsed = parseBillingEnvelope(raw);
  let projection: BillingIngestInput['parsed'];
  if (!parsed.ok) projection = {kind:'invalid',reason:parsed.reason};
  else if (parsed.value.occurred_at > now+30) projection = {kind:'invalid',reason:'schema'};
  else {
   const canonical = canonicalBillingEvent(parsed.value);
   projection = {kind:'event',envelope:parsed.value,canonical,semanticSHA256:await billingSHA256(canonical)};
  }
  const result = await ingestBillingInbox(db,{attemptID,receivedAt:now,signatureAt,raw,rawSHA256:await billingSHA256(raw),parsed:projection});
  return response(result.status,result.outcome);
 } catch { return response(503,'unavailable'); }
}
export async function fixtureBillingFetch(request:Request,env:FixtureEnvironment,composition?:BillingComposition):Promise<Response> {
 if (!composition) return response(503,'unavailable');
 try { return await receiveBillingWebhook(request,env,composition.config,composition.adapters); }
 catch { return response(503,'unavailable'); }
}
