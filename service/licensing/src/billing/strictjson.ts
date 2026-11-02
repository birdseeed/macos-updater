import { BILLING_LIMITS, billingSeconds, closedRecord, type BillingEnvelope, type ParseResult } from './config';
export type StrictJSONResult = {ok:true;value:unknown}|{ok:false;reason:'json'};

// Tokenise before constructing values: duplicate names and aggregate resource bounds
// apply to every member, even when the later closed envelope would reject it.
export function parseStrictJSON(raw: Uint8Array): StrictJSONResult {
 try {
  if (!(raw instanceof Uint8Array) || raw.length === 0 || raw.length > BILLING_LIMITS.bodyBytes) throw 0;
  const text = new TextDecoder('utf-8', {fatal:true, ignoreBOM:true}).decode(raw);
  if (text.charCodeAt(0) === 0xfeff) throw 0;
  const encoder = new TextEncoder();
  let pos = 0, members = 0, elements = 0;
  const space = () => { while (pos < text.length && /[ \t\r\n]/.test(text[pos])) pos++; };
  const string = (): string => {
   const start = pos++;
   let ended = false;
   while (pos < text.length) {
    const code = text.charCodeAt(pos++);
    if (code === 34) { ended = true; break; }
    if (code < 32) throw 0;
    if (code === 92) {
     const escape = text[pos++];
     if (escape === 'u') {
      if (!/^[0-9a-fA-F]{4}$/.test(text.slice(pos,pos+4))) throw 0;
      pos += 4;
     } else if (escape === undefined || !'"\\/bfnrt'.includes(escape)) throw 0;
    }
   }
   if (!ended) throw 0;
   const value: string = JSON.parse(text.slice(start,pos));
   for (let i=0;i<value.length;i++) {
    const c = value.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
     const next = value.charCodeAt(++i);
     if (!(next >= 0xdc00 && next <= 0xdfff)) throw 0;
    } else if (c >= 0xdc00 && c <= 0xdfff) throw 0;
   }
   if (encoder.encode(value).length > BILLING_LIMITS.stringBytes) throw 0;
   return value;
  };
  const value = (depth: number): unknown => {
   space();
   const c = text[pos];
   if (c === '"') return string();
   if (c === '{' || c === '[') {
    if (depth + 1 > BILLING_LIMITS.depth) throw 0;
    pos++; space();
    if (c === '{') {
     const object: Record<string,unknown> = Object.create(null);
     if (text[pos] === '}') { pos++; return object; }
     for (;;) {
      if (text[pos] !== '"' || ++members > BILLING_LIMITS.members) throw 0;
      const key = string();
      if (Object.hasOwn(object,key)) throw 0;
      space(); if (text[pos++] !== ':') throw 0;
      object[key] = value(depth+1); space();
      const end = text[pos++];
      if (end === '}') return object;
      if (end !== ',') throw 0;
      space();
     }
    }
    const array: unknown[] = [];
    if (text[pos] === ']') { pos++; return array; }
    for (;;) {
     if (++elements > BILLING_LIMITS.elements) throw 0;
     array.push(value(depth+1)); space();
     const end = text[pos++];
     if (end === ']') return array;
     if (end !== ',') throw 0;
    }
   }
   for (const [token, result] of [['true',true],['false',false],['null',null]] as const) {
    if (text.startsWith(token,pos)) { pos += token.length; return result; }
   }
   const match = /^-?(0|[1-9][0-9]*)/.exec(text.slice(pos));
   if (!match) throw 0;
   pos += match[0].length;
   const number = Number(match[0]);
   if (!Number.isSafeInteger(number) || Object.is(number,-0)) throw 0;
   return number;
  };
  const result = value(0); space();
  if (pos !== text.length) throw 0;
  return {ok:true,value:result};
 } catch { return {ok:false,reason:'json'}; }
}

export function parseBillingEnvelope(raw: Uint8Array): ParseResult {
 const parsed = parseStrictJSON(raw);
 if (!parsed.ok) return parsed;
 const e = parsed.value;
 if (!closedRecord(e,['event_id','event_type','occurred_at','notification_id','data'])) return {ok:false,reason:'schema'};
 const d = e.data;
 if (!closedRecord(d,['environment','subject_id','price_id','currency','quantity','detail']) ||
     !closedRecord(d.detail,['label','flags'])) return {ok:false,reason:'schema'};
 const detail = d.detail;
 if (typeof e.event_id !== 'string' || !/^evt_fixture_[A-Za-z0-9-]{1,48}(?![\s\S])/.test(e.event_id) ||
     typeof e.notification_id !== 'string' || !/^ntf_fixture_[A-Za-z0-9-]{1,48}(?![\s\S])/.test(e.notification_id) ||
     typeof e.event_type !== 'string' || !/^[a-z][a-z0-9_.]{0,63}(?![\s\S])/.test(e.event_type) || !billingSeconds(e.occurred_at) ||
     d.environment !== 'synthetic-sandbox' || typeof d.subject_id !== 'string' || !/^sub_fixture_[A-Za-z0-9-]{1,48}(?![\s\S])/.test(d.subject_id) ||
     !((d.currency === 'GBP' && d.price_id === 'fixture-price-gbp-annual') ||
       (d.currency === 'USD' && d.price_id === 'fixture-price-usd-annual')) || d.quantity !== 1 ||
     typeof detail.label !== 'string' || new TextEncoder().encode(detail.label).length > BILLING_LIMITS.labelBytes ||
     !Array.isArray(detail.flags) || detail.flags.length > BILLING_LIMITS.flags ||
     !detail.flags.every(flag => typeof flag === 'boolean')) return {ok:false,reason:'schema'};
 return {ok:true,value:e as unknown as BillingEnvelope};
}
