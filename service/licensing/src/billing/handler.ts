import type {LifecycleDependencies} from './types';
import type {FixtureEnvironment} from '../environment';
import {assertFixtureEnvironment} from '../environment';
import {BillingLifecycle} from './reconcile';
import {lifecycleConfig} from './lifecycleConfig';
import {parseLifecycleJSON} from './snapshot';
import {closed} from './schema';
export type LifecycleComposition=Readonly<Omit<LifecycleDependencies,'db'>>;
export async function fixtureLifecycleFetch(_request:Request,_env:FixtureEnvironment,_composition?:LifecycleComposition):Promise<Response>{
 const reply=(status:number,value:Record<string,unknown>={outcome:'refused'})=>Response.json({fixture:'PAT-2646-synthetic',...value},{status,headers:{'Cache-Control':'no-store'}});
 try{assertFixtureEnvironment(_env);const c=_composition;if(!c||!_env.FIXTURE_DB||c.marker!=='PAT-2646-synthetic'||!lifecycleConfig(c.config)||typeof c.now!=='function'||typeof c.randomBytes!=='function'||!(c.syntheticKey instanceof Uint8Array)||c.syntheticKey.length!==32||c.provider?.marker!=='PAT-2646-provider-synthetic'||typeof c.provider.read!=='function'||typeof c.provider.stopRenewal!=='function')return reply(503);
  const u=new URL(_request.url),routes:Record<string,string>={consume:'consumeInbox',sweep:'requestSweep',reconcile:'reconcile',descriptor:'cancellationDescriptor',cancel:'cancel','review-reversal':'reviewReversal',dispatch:'dispatchStop',status:'readStatus'},route=u.pathname.slice('/__fixture/lifecycle/'.length),method=routes[route];if(!u.pathname.startsWith('/__fixture/lifecycle/')||!method||u.search)return reply(404);if(_request.method!=='POST')return reply(405);
  if(Number(_request.headers.get('Content-Length'))>16384)return reply(413);const reader=_request.body?.getReader();if(!reader)return reply(400);const chunks:Uint8Array[]=[];let length=0;for(;;){const part=await reader.read();if(part.done)break;length+=part.value.length;if(length>16384||chunks.length>=4096){await reader.cancel();return reply(413);}chunks.push(part.value);}const bytes=new Uint8Array(length);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}const parsed=parseLifecycleJSON(bytes);if(!parsed.ok)return reply(400);
  const shapes:Record<string,string[]>={consume:['environment','eventID'],sweep:['environment','subscriptionID'],reconcile:['environment','subscriptionID'],descriptor:['credential','subscriptionID'],cancel:['credential','guard','requestID','subscriptionID','expectedSubscriptionRevision','descriptorSHA256','acknowledgement'],'review-reversal':['credential','guard','subscriptionID','transactionID','chargebackID','reversalEvidenceSHA256','requestID','confirmationID'],dispatch:['environment','subscriptionID'],status:['credential','subscriptionID']};if(!closed(parsed.value,shapes[route]))return reply(400);
  const input:any=parsed.value;if(route==='review-reversal'){if(typeof input.credential!=='string'||!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(input.credential))return reply(400);input.credential=Uint8Array.from(atob(input.credential),x=>x.charCodeAt(0));}
  const service=new BillingLifecycle({...c,db:_env.FIXTURE_DB}),result:any=await (service as any)[method](input);const status=['invalidSession','reauthRequired'].includes(result.outcome)?401:['refused'].includes(result.outcome)?400:['held','stale','unavailable','notFound','requestConflict','acknowledgementRequired','needsOperator'].includes(result.outcome)?409:200;
  return reply(status,['invalidSession','reauthRequired','notFound','requestConflict','acknowledgementRequired','refused'].includes(result.outcome)?{outcome:'refused'}:result);
 }catch{return reply(503);}
}
