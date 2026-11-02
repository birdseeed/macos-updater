import {URL} from 'node:url';
import {readFileSync} from 'node:fs';
import type {LifecycleDependencies,LifecycleLedger,ReadCommand,StopCommand,SyntheticLifecycleProvider,ProviderRead,ProviderStop} from '../../src/billing/types';
export const fixtureRoot=new URL('../../../../Fixtures/Billing/',import.meta.url);
export const encode=(x:unknown)=>new TextEncoder().encode(JSON.stringify(x));
export const copy=<T>(x:T):T=>structuredClone(x);
export const index=JSON.parse(readFileSync(new URL('lifecycle-index.json',fixtureRoot),'utf8'));
export function fixture(name:string):{snapshot:any;ledger:any;now:number;expected:any}{return {...JSON.parse(readFileSync(new URL('snapshots/'+name+'.json',fixtureRoot),'utf8')),expected:JSON.parse(readFileSync(new URL('expected/'+name+'.json',fixtureRoot),'utf8'))};}
export class FakePaddle implements SyntheticLifecycleProvider {
 readonly marker='PAT-2646-provider-synthetic' as const;
 readonly reads:ReadCommand[]=[];readonly stops:StopCommand[]=[];
 readOutcome:ProviderRead;stopOutcome:ProviderStop={outcome:'accepted'};
 beforeRead?:()=>Promise<void>;beforeStop?:()=>Promise<void>;
 constructor(bytes:Uint8Array){this.readOutcome={outcome:'snapshot',bytes:new Uint8Array(bytes)};}
 async read(command:ReadCommand):Promise<ProviderRead>{this.reads.push(copy(command));await this.beforeRead?.();const r=this.readOutcome;return r.outcome==='snapshot'?{outcome:'snapshot',bytes:new Uint8Array(r.bytes)}:{...r};}
 async stopRenewal(command:StopCommand):Promise<ProviderStop>{this.stops.push(copy(command));await this.beforeStop?.();return {...this.stopOutcome};}
}
export function dependencies(db:D1Database,name='existing-gbp'):{-readonly [K in keyof LifecycleDependencies]:LifecycleDependencies[K]} {
 const f=fixture(name);let n=32;
 return {marker:'PAT-2646-synthetic',db,config:copy(index.config),now:()=>f.now,randomBytes:length=>new Uint8Array(length).fill(++n),syntheticKey:new Uint8Array(32).fill(66),provider:new FakePaddle(encode(f.snapshot))};
}
export const ordinary={credential:{sessionID:'b'.repeat(32),accessToken:'c'.repeat(64)},subscriptionID:'sub_fixture_A'};
export const guard={accountID:'a'.repeat(32),accountRevision:1,commitNonce:'2'.repeat(32)};
export const cancelInput={...ordinary,guard,requestID:'d'.repeat(32),expectedSubscriptionRevision:1,descriptorSHA256:'a'.repeat(64),acknowledgement:{kind:'paidAccessPreserved' as const}};
