import {URL} from 'node:url';
import {describe,it,expect} from 'vitest';
import {readFileSync} from 'node:fs';
import {createHash,createHmac} from 'node:crypto';
import {validateBillingConfig,type BillingConfig,type BillingEvent} from '../../src/billing/config';
import {verifyFixtureSignature} from '../../src/billing/webhook';
import {parseStrictJSON,parseBillingEnvelope} from '../../src/billing/strictjson';
import {canonicalBillingEvent,billingSHA256} from '../../src/billing/canonical';
const fixtures=new URL('../../../../Fixtures/Billing/events/',import.meta.url);
const bytes=(s:string)=>new TextEncoder().encode(s);
const raw=new Uint8Array(readFileSync(new URL('valid.body',fixtures)));
const meta=JSON.parse(readFileSync(new URL('valid.meta.json',fixtures),'utf8'));
const config:BillingConfig={fixture:'PAT-2645-synthetic',environment:'synthetic-sandbox',hmacKey:new Uint8Array(32).fill(0x42),prices:{GBP:'fixture-price-gbp-annual',USD:'fixture-price-usd-annual'}};
const envelope=JSON.parse(new TextDecoder().decode(raw));
const signed=(body:Uint8Array,t=1700000000)=>`t=${t};v1=${createHmac('sha256',config.hmacKey).update(`PAT-2645\n${t}\n`).update(body).digest('hex')}`;
describe('independently pinned synthetic signature',()=>{
 it('pins literal body, canonical, digest and signature independently of application helpers',()=>{
  expect(createHash('sha256').update(raw).digest('hex')).toBe(meta.rawSHA256);
  expect(signed(raw)).toBe(meta.signature);
  expect(createHash('sha256').update(readFileSync(new URL('valid.canonical',fixtures))).digest('hex')).toBe(meta.semanticSHA256);
 });
 it('accepts exact independently signed bytes',async()=>expect(await verifyFixtureSignature(raw,meta.signature,config,1700000000)).toBe(true));
 for(const t of [1699999700,1700000030])it(`inclusive freshness ${t}`,async()=>expect(await verifyFixtureSignature(raw,signed(raw,t),config,1700000000)).toBe(true));
 for(const t of [1699999699,1700000031])it(`adjacent freshness refusal ${t}`,async()=>expect(await verifyFixtureSignature(raw,signed(raw,t),config,1700000000)).toBe(false));
 for(const header of [null,'',meta.signature+', '+meta.signature,meta.signature+';v1='+ 'a'.repeat(64),meta.signature+';x=1',meta.signature.replace('t=','T='),meta.signature.replace('v1=','V1='),meta.signature.replace('t=1700000000','t=01700000000'),meta.signature.replace('t=1700000000','t=-1'),meta.signature.replace('t=1700000000','t=1.0'),meta.signature.replace('t=1700000000','t=1e9'),meta.signature.replace('t=1700000000','t=253402300800'),'t=9999999999999;v1='+'a'.repeat(64),meta.signature.replace(';','; '),meta.signature.replace(/[a-f]/g,(x:string)=>x.toUpperCase()),meta.signature.slice(0,-1),meta.signature.slice(0,-1)+'z'])it(`refuses exact header grammar ${String(header).slice(0,70)}`,async()=>expect(await verifyFixtureSignature(raw,header,config,1700000000)).toBe(false));
 for(const now of [-1,NaN,Infinity,1.5,Number.MAX_SAFE_INTEGER+1,253402300800])it(`bad clock ${now}`,async()=>expect(await verifyFixtureSignature(raw,meta.signature,config,now)).toBe(false));
 for(const t of [0,253402300799])it(`signature seconds domain boundary ${t}`,async()=>expect(await verifyFixtureSignature(raw,signed(raw,t),config,t)).toBe(true));
 it('rejects wrong key',async()=>expect(await verifyFixtureSignature(raw,meta.signature,{...config,hmacKey:new Uint8Array(32).fill(1)},1700000000)).toBe(false));
 it('rejects changed byte',async()=>{const changed=raw.slice();changed[10]^=1;expect(await verifyFixtureSignature(changed,meta.signature,config,1700000000)).toBe(false);});
 it('rejects changed timestamp',async()=>expect(await verifyFixtureSignature(raw,meta.signature.replace('1700000000','1700000001'),config,1700000000)).toBe(false));
 it('whitespace changes require a new signature',async()=>{const other=new Uint8Array(readFileSync(new URL('reordered.body',fixtures)));expect(await verifyFixtureSignature(other,meta.signature,config,1700000000)).toBe(false);expect(await verifyFixtureSignature(other,signed(other),config,1700000000)).toBe(true);});
 it('owns bytes before asynchronous crypto',async()=>{const mutable=raw.slice();const promise=verifyFixtureSignature(mutable,meta.signature,config,1700000000);mutable.fill(0);expect(await promise).toBe(true);});
});
describe('closed explicit configuration',()=>{
 it('accepts and copies exact fake key',()=>{const c=validateBillingConfig(config);expect(c).toBeDefined();expect(c?.hmacKey).not.toBe(config.hmacKey);expect(c?.hmacKey).toEqual(config.hmacKey);});
 for(const input of [undefined,null,{}, {...config,extra:1},{...config,fixture:'live'},{...config,environment:'sandbox'},{...config,hmacKey:new Uint8Array(31)},{...config,hmacKey:Array(32).fill(66)},{...config,prices:{...config.prices,GBP:config.prices.USD}},{...config,prices:{...config.prices,EUR:'other'}}])it(`refuses wrong/mixed config ${JSON.stringify(input)}`,()=>expect(validateBillingConfig(input)).toBeUndefined());
 for(const key of Object.keys(config))it(`requires ${key}`,()=>{const value:any={...config};delete value[key];expect(validateBillingConfig(value)).toBeUndefined();});
});
describe('strict parser independent resource reachability',()=>{
 for(const text of ['{}','[]','0','-1','9007199254740991','-9007199254740991','"café"','{"a":[true,false,null]}'])it(`accepts bounded JSON ${text}`,()=>expect(parseStrictJSON(bytes(text)).ok).toBe(true));
 for(const text of ['{"a":1,"a":2}','{"x":{"a":1,"a":2}}','{"a":1,"\\u0061":2}','[1,]','{"a":1,}','{}{}','{} true','01','+1','-0','1.0','1e0','NaN','Infinity','9007199254740992','-9007199254740992','"\\ud800"','"\\udfff"','"\\x41"','"\n"','\ufeff{}','"unterminated'])it(`refuses ambiguous JSON ${JSON.stringify(text)}`,()=>expect(parseStrictJSON(bytes(text))).toEqual({ok:false,reason:'json'}));
 it('fatal UTF8',()=>expect(parseStrictJSON(new Uint8Array([0x22,0xc0,0xaf,0x22])).ok).toBe(false));
 for(const [name,at,over] of [
  ['depth','['.repeat(16)+'0'+']'.repeat(16),'['.repeat(17)+'0'+']'.repeat(17)],
  ['members','{'+Array.from({length:2048},(_,i)=>`"k${i}":0`).join(',')+'}','{'+Array.from({length:2049},(_,i)=>`"k${i}":0`).join(',')+'}'],
  ['elements','['+Array(2048).fill('0').join(',')+']','['+Array(2049).fill('0').join(',')+']'],
  ['string','"'+'é'.repeat(2048)+'"','"'+'é'.repeat(2048)+'x"'],
  ['key','{"'+'x'.repeat(4096)+'":0}','{"'+'x'.repeat(4097)+'":0}'],
 ] as const){it(`${name} exact limit reachable`,()=>expect(parseStrictJSON(bytes(at)).ok).toBe(true));it(`${name} limit+1 refuses`,()=>expect(parseStrictJSON(bytes(over)).ok).toBe(false));}
 it('counts members across objects',()=>expect(parseStrictJSON(bytes('['+Array(3).fill('{'+Array.from({length:700},(_,i)=>`"k${i}":0`).join(',')+'}').join(',')+']')).ok).toBe(false));
 it('counts elements across arrays',()=>expect(parseStrictJSON(bytes('['+Array(3).fill('['+Array(700).fill('0').join(',')+']').join(',')+']')).ok).toBe(false));
 it('prototype-looking names are data without mutation',()=>{const parsed=parseStrictJSON(bytes('{"__proto__":{"polluted":true},"constructor":1}'));expect(parsed.ok).toBe(true);expect(({} as any).polluted).toBeUndefined();if(parsed.ok)expect(Object.hasOwn(parsed.value as object,'__proto__')).toBe(true);});
});
describe('closed synthetic envelope, whole accepted data',()=>{
 it('accepts fixture and known field limits',()=>expect(parseBillingEnvelope(raw)).toEqual({ok:true,value:envelope}));
 const paths=[[],['data'],['data','detail']];
 for(const path of paths){const obj=path.reduce((o:any,k)=>o[k],envelope);for(const key of Object.keys(obj)){
  it(`requires ${[...path,key].join('.')}`,()=>{const e=structuredClone(envelope);let o=path.reduce((o:any,k)=>o[k],e);delete o[key];expect(parseBillingEnvelope(bytes(JSON.stringify(e))).ok).toBe(false);});
  for(const invalid of (key==='flags'?[null,{},42,'bad']:key==='occurred_at'||key==='quantity'?[null,[],{},'bad']:[null,[],{},42]))it(`wrong type ${[...path,key].join('.')}=${JSON.stringify(invalid)}`,()=>{const e=structuredClone(envelope);path.reduce((o:any,k)=>o[k],e)[key]=invalid;expect(parseBillingEnvelope(bytes(JSON.stringify(e))).ok).toBe(false);});
 }it(`extra field at ${path.join('.')}`,()=>{const e=structuredClone(envelope);path.reduce((o:any,k)=>o[k],e).extra=1;expect(parseBillingEnvelope(bytes(JSON.stringify(e))).ok).toBe(false);});}
 for(const [field,values] of Object.entries({event_id:['evt_fixture_','evt_fixture_'+ 'a'.repeat(49),'evt_live_a','evt_fixture_a_'],notification_id:['ntf_fixture_','ntf_fixture_'+ 'a'.repeat(49)],event_type:['','A.bad','a'.repeat(65)],occurred_at:[-1,253402300800,1.5]}))for(const value of values)it(`domain ${field}=${value}`,()=>expect(parseBillingEnvelope(bytes(JSON.stringify({...envelope,[field]:value}))).ok).toBe(false));
 for(const patch of [{environment:'live'},{environment:'sandbox'},{subject_id:'sub_fixture_'},{subject_id:'sub_fixture_'+ 'x'.repeat(49)},{price_id:'real-price'},{currency:'EUR'},{price_id:'fixture-price-usd-annual'},{quantity:0},{quantity:2},{quantity:1.5},{detail:{label:'é'.repeat(129),flags:[]}},{detail:{label:'ok',flags:Array(17).fill(true)}},{detail:{label:'ok',flags:[1]}}])it(`data mismatch ${JSON.stringify(patch).slice(0,100)}`,()=>expect(parseBillingEnvelope(bytes(JSON.stringify({...envelope,data:{...envelope.data,...patch}}))).ok).toBe(false));
 for(const patch of [{event_type:'unknown.hint'},{event_id:'evt_fixture_'+ 'a'.repeat(48)},{notification_id:'ntf_fixture_a'},{occurred_at:0},{occurred_at:253402300799}])it(`envelope boundary accepts ${JSON.stringify(patch)}`,()=>expect(parseBillingEnvelope(bytes(JSON.stringify({...envelope,...patch}))).ok).toBe(true));
 it('small integer event time remains valid',()=>expect(parseBillingEnvelope(bytes(JSON.stringify({...envelope,occurred_at:42}))).ok).toBe(true));
 it('empty flags remains valid',()=>{const e=structuredClone(envelope);e.data.detail.flags=[];expect(parseBillingEnvelope(bytes(JSON.stringify(e))).ok).toBe(true);});
 it('label and flags exact maxima accept',()=>{const e=structuredClone(envelope);e.data.detail={label:'é'.repeat(128),flags:Array(16).fill(false)};expect(parseBillingEnvelope(bytes(JSON.stringify(e))).ok).toBe(true);});
});
describe('independent canonical bytes and semantic digest',()=>{
 for(const name of ['valid','reordered','notification','conflict'])it(`canonical literal ${name}`,async()=>{const e=JSON.parse(readFileSync(new URL(name+'.body',fixtures),'utf8'));const before=structuredClone(e);const canonical=canonicalBillingEvent(e);expect(canonical).toEqual(new Uint8Array(readFileSync(new URL(name+'.canonical',fixtures))));expect(await billingSHA256(canonical)).toBe(JSON.parse(readFileSync(new URL(name+'.meta.json',fixtures),'utf8')).semanticSHA256);expect(e).toEqual(before);});
 for(const patch of [{event_type:'unknown.hint'},{occurred_at:1700000001}])it(`projection changes ${JSON.stringify(patch)}`,()=>expect(canonicalBillingEvent({...envelope,...patch})).not.toEqual(canonicalBillingEvent(envelope)));
 it('array order remains significant',()=>{const changed=structuredClone(envelope);changed.data.detail.flags.reverse();expect(canonicalBillingEvent(changed)).not.toEqual(canonicalBillingEvent(envelope));});
 it('does not Unicode-normalise',()=>{const a=structuredClone(envelope),b=structuredClone(envelope);a.data.detail.label='é';b.data.detail.label='e\u0301';expect(canonicalBillingEvent(a)).not.toEqual(canonicalBillingEvent(b));});
 it('escaped equivalent scalar bytes share canonical projection',()=>{const a=JSON.parse(new TextDecoder().decode(raw));const b=JSON.parse(new TextDecoder().decode(raw).replace('café','caf\\u00e9'));expect(canonicalBillingEvent(a)).toEqual(canonicalBillingEvent(b));});
 it('literal supplementary scalar escaping',()=>{const e:BillingEvent={...envelope,data:{...envelope.data,detail:{label:'😀\n"\\',flags:[false,true]}}};const expected='{"data":{"currency":"GBP","detail":{"flags":[false,true],"label":"😀\\n\\"\\\\"},"environment":"synthetic-sandbox","price_id":"fixture-price-gbp-annual","quantity":1,"subject_id":"sub_fixture_unknown"},"event_id":"evt_fixture_one","event_type":"subscription.updated","occurred_at":1700000000}';expect(new TextDecoder().decode(canonicalBillingEvent(e))).toBe(expected);});
});
