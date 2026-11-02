// Fixed test-owned transport mapping; never an HTTP-selected authority.
import {fixtureApplicationFetch} from '../../src/index';
import {fixtureRandom} from '../../src/auth';
import type {AccountWebComposition} from '../../src/web/account';
import type {FixtureEnvironment} from '../../src/environment';
import html from 'index.html?account-web-asset';
import js from 'account.js?account-web-asset';
import css from 'account.css?account-web-asset';
declare const __PAT2649_ACCOUNT_RUNTIME__:{allowedOrigin:string;now:number;entropySeed:string};
const config=Object.freeze({...__PAT2649_ACCOUNT_RUNTIME__});
const randomBytes=fixtureRandom(config.entropySeed)!;
export default {fetch(request:Request,env:FixtureEnvironment){
 const parsed=new URL(request.url);
 if(parsed.pathname==='/__fixture/web/account'||parsed.pathname.startsWith('/__fixture/web/account/')){
  // URL.search loses a trailing bare '?'. Replacing only the serialized origin preserves it.
  request=new Request(config.allowedOrigin+request.url.slice(parsed.origin.length),request);
 }
 const web:AccountWebComposition={marker:'PAT-2649-account-web-synthetic',db:env.FIXTURE_DB!,now:()=>config.now,randomBytes,syntheticKey:new Uint8Array(32).fill(7),csrfKey:new Uint8Array(32).fill(19),allowedOrigin:config.allowedOrigin,assets:{html,js,css}};
 return fixtureApplicationFetch(request,env,undefined,undefined,web);
}};
