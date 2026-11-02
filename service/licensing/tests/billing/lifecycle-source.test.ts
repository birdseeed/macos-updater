import {describe,it,expect} from 'vitest';
import {planSourceSelection,billingSnapshotConditions,billingProtectionDecision} from '../../src/entitlementPlans';
import {fixture} from './fake-paddle';
describe('source-owned opacity, no display/caller grant',()=>{
 for(const forged of [{},fixture('masked-grace').ledger,{state:'paid',paidThrough:1822348800},{accountID:'a'.repeat(32),revoked:false},null])it(`plain snapshot cannot manufacture selection or conditions ${JSON.stringify(forged).slice(0,50)}`,()=>{expect(planSourceSelection(forged as any)).toBeNull();expect(billingSnapshotConditions(forged as any)).toBeNull();expect(billingProtectionDecision(forged as any)).toEqual({outcome:'refused'});});
});
