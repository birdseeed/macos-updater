/// <reference types="node" />
import {it,expect,vi} from 'vitest';
import {URL} from 'node:url';
import {readFileSync} from 'node:fs';
import {createPrivateKey,sign,verify,createPublicKey} from 'node:crypto';
import {decideTrial} from '../../src/entitlements';
import {produceLease,type LeaseClaims,type SyntheticSigner} from '../../src/leases';
const seed=Buffer.from('Patched-L1-TEST-ONLY-KEY-SEED-01');
const key=createPrivateKey({key:Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),seed]),format:'der',type:'pkcs8'});
const signer:SyntheticSigner={marker:'PAT-2643-synthetic',keyID:'fixture-only-1',sign:async message=>new Uint8Array(sign(null,message,key))};
function vector(name:string):Buffer {return readFileSync(new URL(`../../../../Fixtures/Licensing/vectors/${name}.json`,import.meta.url));}
function claims(name:string):LeaseClaims {return JSON.parse(Buffer.from(JSON.parse(vector(name).toString()).payload,'base64').toString());}
for(const state of ['paid','grace','beta','trial','none','expired','revoked'])it(`Node producer exactly matches immutable Swift ${state} payload/signature/envelope`,async()=>{
 const expected=vector(`valid-${state}`);const input=claims(`valid-${state}`);const before=structuredClone(input);
 const actual=await produceLease(input,signer);expect(actual).not.toBeNull();expect(Buffer.from(actual!)).toEqual(expected);expect(input).toEqual(before);
 const envelope=JSON.parse(Buffer.from(actual!).toString());expect(verify(null,Buffer.concat([Buffer.from('im.patched.licence.v1\0'),Buffer.from(envelope.payload,'base64')]),createPublicKey(key),Buffer.from(envelope.signature,'base64'))).toBe(true);
});
it('missing signer and fake marker never create a signing identity',async()=>{expect(await produceLease(claims('valid-trial'))).toBeNull();expect(await produceLease(claims('valid-trial'),{...signer,marker:'productive' as never})).toBeNull();});
const base=claims('valid-trial');
for(const field of ['sequence','entitlementRevision','activationRevision','issuedAt','permittedUntil','hardEnd'] as const)for(const value of [-1,0.1,NaN,Infinity,Number.MAX_SAFE_INTEGER+1])it(`invalid ${field} ${value} refuses before signer`,async()=>{const spy=vi.fn(signer.sign);expect(await produceLease({...base,[field]:value},{...signer,sign:spy})).toBeNull();expect(spy).not.toHaveBeenCalled();});
for(const change of [{sequence:0},{entitlementRevision:0},{activationRevision:0},{accountID:'A'.repeat(32)},{activationID:'x'},{deviceKeySHA256:'g'.repeat(64)},{issuer:'other'},{audience:'other'},{schemaVersion:2},{extra:1},{paid:{paidThrough:base.hardEnd}},{trial:{startedAt:1800000000,expiresAt:1801209601}},{hardEnd:base.hardEnd+1},{permittedUntil:base.hardEnd+1},{issuedAt:base.hardEnd}])it(`malformed trial ${JSON.stringify(change)} refuses before signing`,async()=>{const spy=vi.fn(signer.sign);expect(await produceLease({...base,...change} as LeaseClaims,{...signer,sign:spy})).toBeNull();expect(spy).not.toHaveBeenCalled();});
it('signer errors or wrong signature length refuse',async()=>{for(const fn of [async()=>{throw Error('synthetic refusal');},async()=>new Uint8Array(63)])expect(await produceLease(base,{...signer,sign:fn})).toBeNull();});
it('signature domain and deterministic payload ordering reach actual adapter',async()=>{const messages:Uint8Array[]=[];await produceLease(base,{...signer,sign:async m=>{messages.push(m.slice());return signer.sign(m);}});expect(messages.length).toBe(1);const envelope=JSON.parse(vector('valid-trial').toString());expect(Buffer.from(messages[0])).toEqual(Buffer.concat([Buffer.from('im.patched.licence.v1\0'),Buffer.from(envelope.payload,'base64')]));});

for(const state of ['paid','grace','beta','none','expired','revoked'])for(const evidence of ['paid','grace','trial'])if(evidence!==state)it(`${state} refuses extraneous ${evidence} evidence`,async()=>{expect(await produceLease({...claims(`valid-${state}`),[evidence]:base.trial},signer)).toBeNull();});
for(const state of ['paid','grace','trial'])it(`${state} refuses missing evidence`,async()=>{const input=claims(`valid-${state}`);delete input[state as 'paid'|'grace'|'trial'];expect(await produceLease(input,signer)).toBeNull();});
it('beta cannot exceed seven days or disagree with its hard end',async()=>{const input=claims('valid-beta');for(const c of [{permittedUntil:input.issuedAt+604801,hardEnd:input.issuedAt+604801},{hardEnd:input.hardEnd+1},{issuedAt:Number.MAX_SAFE_INTEGER-1,permittedUntil:Number.MAX_SAFE_INTEGER,hardEnd:Number.MAX_SAFE_INTEGER}])expect(await produceLease({...input,...c},signer)).toBeNull();});
it('paid/grace cannot exceed thirty days or redate fixed seven-day grace',async()=>{for(const state of ['paid','grace']){const input=claims(`valid-${state}`);expect(await produceLease({...input,permittedUntil:input.issuedAt+2592001,hardEnd:input.issuedAt+2592001},signer)).toBeNull();}const input=claims('valid-grace');expect(await produceLease({...input,grace:{paidThrough:input.grace!.paidThrough,graceDeadline:input.grace!.graceDeadline+1}},signer)).toBeNull();});
for(const state of ['none','expired','revoked'])it(`${state} may never carry a granting interval`,async()=>expect(await produceLease({...claims(`valid-${state}`),permittedUntil:1800000001},signer)).toBeNull());

it('actual pure producer and trial decision use no ambient clock or fetch',async()=>{
 const deny=vi.fn<typeof fetch>(async()=>{throw Error('ambient fetch denied');});
 const clock=vi.spyOn(Date,'now').mockImplementation(()=>{throw Error('ambient clock denied');});
 vi.stubGlobal('fetch',deny);
 let clockCalls=-1;let lease:Uint8Array|null=null;let decision:ReturnType<typeof decideTrial>|null=null;
 try{lease=await produceLease(base,signer);decision=decideTrial({now:1800000000,trialStartedAt:null,trialEndsAt:null,betaInvited:false,betaEndsAt:null,revoked:false,marker:null});}
 finally{clockCalls=clock.mock.calls.length;clock.mockRestore();vi.unstubAllGlobals();}
 expect(deny).not.toHaveBeenCalled();expect(clockCalls).toBe(0);
 expect(lease).not.toBeNull();expect(decision).toEqual({outcome:'started',startedAt:1800000000,expiresAt:1801209600});
});
