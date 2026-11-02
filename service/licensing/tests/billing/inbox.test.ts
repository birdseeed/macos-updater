import {URL} from 'node:url';
import {describe,it,expect,vi} from 'vitest';
import {readFileSync} from 'node:fs';
import {createHmac} from 'node:crypto';
import {receiveBillingWebhook,fixtureBillingFetch} from '../../src/billing/webhook';
import {ingestBillingInbox} from '../../src/billing/inbox';
import type {BillingConfig,BillingAdapters} from '../../src/billing/config';
const raw=new Uint8Array(readFileSync(new URL('../../../../Fixtures/Billing/events/valid.body',import.meta.url)));
const config:BillingConfig={fixture:'PAT-2645-synthetic',environment:'synthetic-sandbox',hmacKey:new Uint8Array(32).fill(66),prices:{GBP:'fixture-price-gbp-annual',USD:'fixture-price-usd-annual'}};
const signature=(body:Uint8Array)=>'t=1700000000;v1='+createHmac('sha256',config.hmacKey).update('PAT-2645\n1700000000\n').update(body).digest('hex');
function setup(){let dbCalls=0,fetchCalls=0;const db={prepare(){dbCalls++;throw Error('DB-TOKEN-SENTINEL-2645');},batch(){dbCalls++;throw Error('DB-TOKEN-SENTINEL-2645');}} as unknown as D1Database;const env={ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake',FIXTURE_DB:db};const adapters:BillingAdapters={now:()=>1700000000,attemptID:()=> '1'.repeat(32),fetch:(async()=>{fetchCalls++;throw Error('NETWORK-SENTINEL-2645');}) as typeof fetch};return {env,adapters,get dbCalls(){return dbCalls;},get fetchCalls(){return fetchCalls;}};}
function request(body:Uint8Array=raw,headers:Record<string,string>={},path='/__fixture/billing/webhook',method='POST'){return new Request('http://fixture.invalid'+path,{method,body:method==='GET'?undefined:body,headers:{'Content-Type':'application/json','X-Patched-Fixture-Signature':signature(body),...headers}});}
async function refusal(req:Request,status:number,configValue?:unknown,change?:(s:ReturnType<typeof setup>)=>void){const s=setup();change?.(s);const r=await receiveBillingWebhook(req,s.env,arguments.length>=3?configValue:config,s.adapters);expect(r.status).toBe(status);expect(r.headers.get('Cache-Control')).toBe('no-store');const text=await r.text();expect(Object.keys(JSON.parse(text)).sort()).toEqual(['fixture','outcome']);expect(JSON.parse(text).fixture).toBe('PAT-2645-synthetic');for(const secret of ['BODY-SENTINEL','DB-TOKEN-SENTINEL','NETWORK-SENTINEL','evt_fixture','sub_fixture','v1='])expect(text).not.toContain(secret);expect(s.dbCalls).toBe(0);expect(s.fetchCalls).toBe(0);}
describe('route/config refusals precede database and network',()=>{
 it('ordinary billing composition refuses',async()=>expect((await fixtureBillingFetch(request(),setup().env)).status).toBe(503));
 for(const mode of ['ENVIRONMENT','FIXTURE_MARKER','PROVIDER_MODE','FIXTURE_DB'] as const)it(`missing ${mode}`,async()=>refusal(request(),503,config,s=>{delete s.env[mode];}));
 for(const value of [undefined,null,{}, {...config,environment:'live'}])it(`missing/mixed config ${JSON.stringify(value)}`,async()=>refusal(request(),503,value));
 for(const now of [-1,1.2,NaN,Infinity,253402300800])it(`invalid clock ${now}`,async()=>refusal(request(),503,config,s=>{s.adapters.now=()=>now;}));
 for(const id of ['', 'a'.repeat(31),'A'.repeat(32),'x'.repeat(32)])it(`invalid attempt ${id}`,async()=>refusal(request(),503,config,s=>{s.adapters.attemptID=()=>id;}));
 it('wrong method',async()=>refusal(request(raw,{},undefined,'GET'),405));
 for(const path of ['/__fixture/billing/no','/__fixture/billing/webhook?x=1','/__fixture/billing/webhook#x','/v1/provider/paddle/webhook'])it(`wrong route ${path}`,async()=>refusal(request(raw,{},path),404));
 for(const type of ['text/plain','application/json; charset=latin1','application/json;extra=yes','application/json, application/json',''])it(`media type ${type}`,async()=>refusal(request(raw,{'Content-Type':type}),415));
 it('content encoding refuses',async()=>refusal(request(raw,{'Content-Encoding':'gzip'}),415));
 it('forged signature refuses with zero storage',async()=>refusal(request(raw,{'X-Patched-Fixture-Signature':'t=1700000000;v1='+'0'.repeat(64)}),401));
});
describe('stream/body resource and privacy checks',()=>{
 for(const length of ['-1','+1','1.0','1e3',' 1','01','262145','999999999999999999999','0'])it(`bad declared length ${length}`,async()=>refusal(request(raw,{'Content-Length':length}),400));
 it('actual length mismatch',async()=>refusal(request(raw,{'Content-Length':String(raw.length+1)}),400));
 it('empty body refuses',async()=>refusal(request(new Uint8Array()),400));
 it('body byte maximum+1 refuses',async()=>refusal(request(new Uint8Array(262145).fill(32)),413));
 function streamRequest(chunks:Uint8Array[],onCancel:()=>void=()=>{},error=false){let i=0;const body=new ReadableStream<Uint8Array>({pull(c){if(error){c.error(Error('STREAM-TOKEN-SENTINEL-2645'));return;}if(i===chunks.length)c.close();else c.enqueue(chunks[i++]);},cancel:onCancel});return new Request('http://fixture.invalid/__fixture/billing/webhook',{method:'POST',headers:{'Content-Type':'application/json','X-Patched-Fixture-Signature':signature(raw)},body,duplex:'half'} as RequestInit);}
 it('4097 chunks refuses and cancels',async()=>{let cancelled=false;await refusal(streamRequest(Array(4097).fill(new Uint8Array([32])),()=>{cancelled=true;}),413);expect(cancelled).toBe(true);});
 it('overflow cancels',async()=>{let cancelled=false;await refusal(streamRequest([new Uint8Array(262144),new Uint8Array(1)],()=>{cancelled=true;}),413);expect(cancelled).toBe(true);});
 it('stream error has bounded generic response and no logs',async()=>{const spies=['log','info','warn','error','debug'].map(k=>vi.spyOn(console,k as 'log').mockImplementation(()=>{}));try{await refusal(streamRequest([],()=>{},true),400);expect(spies.flatMap(x=>x.mock.calls)).toEqual([]);}finally{spies.forEach(x=>x.mockRestore());}});
 for(const [name,chunks] of [['many chunks',Array.from(raw,b=>new Uint8Array([b]))],['UTF8 split',Array.from(raw,b=>new Uint8Array([b]))],['exact4096chunks',[...Array(4095).fill(new Uint8Array()),raw]]] as const)it(`${name} reaches inbox then storage failure`,async()=>{const s=setup();const r=await receiveBillingWebhook(streamRequest([...chunks]),s.env,config,s.adapters);expect(r.status).toBe(503);expect(s.dbCalls).toBeGreaterThan(0);expect(s.fetchCalls).toBe(0);});
 for(const headers of [{},{'Content-Type':'APPLICATION/JSON; CHARSET=UTF-8'}] as Record<string,string>[])it(`valid media/absent length reaches inbox ${JSON.stringify(headers)}`,async()=>{const s=setup();const r=await receiveBillingWebhook(request(raw,headers),s.env,config,s.adapters);expect(r.status).toBe(503);expect(s.dbCalls).toBeGreaterThan(0);});
 it('exact262144 byte valid JSON reaches inbox',async()=>{const body=new Uint8Array(262144).fill(32);body.set(raw);const s=setup();expect((await receiveBillingWebhook(request(body),s.env,config,s.adapters)).status).toBe(503);expect(s.dbCalls).toBeGreaterThan(0);});
 it('DB thrown sentinel is not logged or returned',async()=>{const spies=['log','info','warn','error','debug'].map(k=>vi.spyOn(console,k as 'log').mockImplementation(()=>{}));try{const s=setup();const r=await receiveBillingWebhook(request(),s.env,config,s.adapters);expect(await r.text()).not.toContain('SENTINEL');expect(s.dbCalls).toBeGreaterThan(0);expect(spies.flatMap(x=>x.mock.calls)).toEqual([]);}finally{spies.forEach(x=>x.mockRestore());}});
 it('explicit outbound canary throws; handler never invokes it',async()=>{const s=setup();await expect(s.adapters.fetch('https://fixture.invalid')).rejects.toThrow('NETWORK-SENTINEL');expect(s.fetchCalls).toBe(1);});
 it('inbox never converts thrown database failure to success',async()=>{const s=setup();const result=await ingestBillingInbox(s.env.FIXTURE_DB!,{attemptID:'1'.repeat(32),receivedAt:1700000000,signatureAt:1700000000,raw,rawSHA256:'0'.repeat(64),parsed:{kind:'invalid',reason:'json'}});expect(result).toEqual({outcome:'unavailable',status:503});});
});
