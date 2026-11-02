import {describe,it,expect} from 'vitest';
import {decideTrial,TrialService,type TrialFacts} from '../../src/entitlements';
const now=1800000000;
const fresh=():TrialFacts=>({now,trialStartedAt:null,trialEndsAt:null,betaInvited:false,betaEndsAt:null,revoked:false,marker:null});
describe('S1b explicit trial policy',()=>{
 it('explicit start gives exactly the full fourteen days',()=>expect(decideTrial(fresh())).toEqual({outcome:'started',startedAt:now,expiresAt:now+1209600}));
 it('existing trial never restarts even after expiry',()=>{for(const time of [now,now+1209600,now+9999999])expect(decideTrial({...fresh(),now:time,trialStartedAt:now-1,trialEndsAt:now-1+1209600})).toEqual({outcome:'existing',startedAt:now-1,expiresAt:now-1+1209600});});
 for(const end of [null,now+1])it(`active beta ${end} preserves unused trial`,()=>expect(decideTrial({...fresh(),betaInvited:true,betaEndsAt:end})).toEqual({outcome:'trial-unavailable-during-beta'}));
 for(const end of [now-1,now])it(`ended beta ${end} allows full new trial`,()=>expect(decideTrial({...fresh(),betaInvited:true,betaEndsAt:end})).toEqual({outcome:'started',startedAt:now,expiresAt:now+1209600}));
 it('unexpired marker blocks fresh account',()=>expect(decideTrial({...fresh(),marker:{originalDeletedAt:1768464000,expiresAt:1800000000+1}}).outcome).toBe('refused'));
 it('calendar marker boundary derives from immutable retention policy',()=>{
  // 2024 leap day -> 2025 Feb 28, rather than 365/366-day approximation.
  const marker={originalDeletedAt:1709251199,expiresAt:1740787199};
  expect(decideTrial({...fresh(),now:marker.expiresAt-1,marker}).outcome).toBe('refused');
  for(const time of [marker.expiresAt,marker.expiresAt+1])expect(decideTrial({...fresh(),now:time,marker})).toEqual({outcome:'started',startedAt:time,expiresAt:time+1209600});
 });
 it('revocation wins over unused trial and beta',()=>expect(decideTrial({...fresh(),revoked:true})).toEqual({outcome:'refused'}));
 for(const time of [-1,0.5,NaN,Infinity,253402300799,Number.MAX_SAFE_INTEGER])it(`invalid/overflow clock ${time} refuses`,()=>expect(decideTrial({...fresh(),now:time})).toEqual({outcome:'refused'}));
 for(const change of [{trialStartedAt:now},{trialEndsAt:now+1209600},{trialStartedAt:now,trialEndsAt:now+1209601},{trialStartedAt:now+1,trialEndsAt:now+1+1209600},{betaEndsAt:-1}])it(`inconsistent source ${JSON.stringify(change)} refuses`,()=>expect(decideTrial({...fresh(),...change})).toEqual({outcome:'refused'}));
 it('default real service refuses without adapters',async()=>expect(await new TrialService().start({credential:{sessionID:'a'.repeat(32),accessToken:'b'.repeat(64)},guard:{accountID:'c'.repeat(32),accountRevision:0,commitNonce:'n'},requestID:'request',requestHash:'d'.repeat(64)})).toEqual({outcome:'refused'}));
 it('pure decision reads no ambient clock or network and leaves source unchanged',()=>{const facts=fresh();const before=structuredClone(facts);expect(decideTrial(facts).outcome).toBe('started');expect(facts).toEqual(before);});
});
