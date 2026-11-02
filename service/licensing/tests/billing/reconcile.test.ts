import {describe,it,expect} from 'vitest';
import {BillingLifecycle} from '../../src/billing/reconcile';
import {dependencies,ordinary,cancelInput,copy} from './fake-paddle';
const target={environment:'synthetic-sandbox' as const,subscriptionID:'sub_fixture_A'};
describe('service wire authority and ownership refusal',()=>{
 for(const method of ['consumeInbox','requestSweep','reconcile','cancellationDescriptor','cancel','reviewReversal','dispatchStop','readStatus'] as const)for(const value of [null,[],{},true,{...target,accountID:'a'.repeat(32)},{...target,environment:'live'}])it(`${method} rejects malformed or caller principal ${JSON.stringify(value)}`,async()=>{let calls=0;const db={prepare(){calls++;throw Error('wire must refuse');},batch(){calls++;throw Error('wire must refuse');}} as unknown as D1Database;const s=new BillingLifecycle(dependencies(db));const r=await (s[method] as any)(value);expect(['refused','invalidSession','notFound']).toContain(r.outcome);expect(calls).toBe(0);});
 for(const key of ['credential','guard','requestID','subscriptionID','descriptorSHA256','acknowledgement'])it(`cancel never trusts accessor ${key}`,async()=>{const input=copy(cancelInput);Object.defineProperty(input,key,{enumerable:true,get(){throw Error('accessor touched');}});const r=await new BillingLifecycle(dependencies({} as D1Database)).cancel(input);expect(r.outcome).toBe('refused');});
 it('ordinary credential shape alone never establishes authentication',async()=>{expect(await new BillingLifecycle(dependencies({} as D1Database)).readStatus(ordinary)).toEqual({outcome:'refused'});});
});
