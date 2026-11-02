import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {accountRuntime,type AccountWebRuntimeFixture} from './account-runtime.ts';
import type {CodeRequest} from '../../src/auth';
const service=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(resolve(service,'package.json'));
// Independent bounded host stream. Distinct host/worker seeds are required.
export function hostEntropy(seed:string):(n:number)=>Uint8Array {
 assert.match(seed,/^(?!0{32}$)[a-f0-9]{32}$/);const bytes=Buffer.from(seed,'hex');let offset=0;
 return n=>{assert.ok(Number.isSafeInteger(n)&&n>=0&&offset+n<=4096,'host entropy exhausted');const out=new Uint8Array(n);for(let j=0;j<n;j++,offset++)out[j]=bytes[offset%16]^(offset%256)^Math.floor(offset/16);return out;};
}
export async function accountWebRuntime(config:AccountWebRuntimeFixture){
 const selected=Object.freeze({...config});const owner=await accountRuntime({web:selected});
 let disposed=false;
 try {
  // Fixed same-owner migration allowlist, preserving each accepted statement.
  for(const file of ['tests/d1-local/fixture.sql','migrations/0001_accounts.sql','migrations/0002_activations.sql','migrations/0003_billing.sql','migrations/0003b_billing_lifecycle.sql']){
   const raw=readFileSync(resolve(service,file),'utf8').replace(/^\s*--.*$/mg,'');
   assert.ok(!/\bTRIGGER\b|\/\*/i.test(raw),'whole trigger migration needs explicit selection');
   await owner.db.batch(raw.split(';').map(x=>x.trim()).filter(Boolean).map(sql=>owner.db.prepare(sql)));
  }
  const bundle=await require('esbuild').build({absWorkingDir:service,entryPoints:[resolve(service,'tests/d1-local/account-web-source-api.ts')],bundle:true,write:false,format:'esm',platform:'node',target:'node24',logLevel:'silent'});
  const apiPath=resolve(owner.run,'account-web-source-api.mjs');writeFileSync(apiPath,bundle.outputFiles[0].text);assert.equal(realpathSync(apiPath),apiPath);
  const {AuthService,issueConsumedWebSession}=await import(pathToFileURL(apiPath).href);
  assert.equal(typeof AuthService,'function');assert.equal(typeof issueConsumedWebSession,'function');
  const usedSeeds=new Set([selected.entropySeed]);
  return {owner,async provision(input:CodeRequest,entropySeed:string):Promise<Response>{
   assert.deepEqual(Object.keys(input).sort(),['email','purpose','sourceIP']);
   assert.equal(input.purpose,'web-sign-in');assert.match(input.email,/^[a-z0-9.+-]+@example\.invalid$/);
   assert.match(input.sourceIP,/^(?:192\.0\.2|198\.51\.100|203\.0\.113)\.(?:0|[1-9][0-9]{0,2})$/);assert.ok(Number(input.sourceIP.split('.').at(-1))<=255);
   assert.ok(!usedSeeds.has(entropySeed),'host/worker seed reuse');usedSeeds.add(entropySeed);
   const randomBytes=hostEntropy(entropySeed);let captured:string|undefined;
   const auth=new AuthService({db:owner.db,now:()=>selected.now,randomBytes,syntheticKey:new Uint8Array(32).fill(7),delivery:async(email:string,code:string)=>{assert.equal(email,input.email);captured=code;}});
   try {
    const requested=await auth.requestCode({...input});assert.equal(requested.status,202,'INFRA actual S1 request success');assert.equal(requested.body.outcome,'accepted');assert.ok(captured,'INFRA actual synthetic delivery');
    const consumed=await auth.consume({challengeID:requested.body.challengeID,purpose:'web-sign-in',code:captured});
    assert.equal(consumed.status,200,'INFRA actual S1 web consume success');assert.equal(consumed.body.outcome,'signed-in');assert.equal(consumed.body.refreshToken,undefined);
    const row=await owner.db.prepare('SELECT kind,created_at,expires_at,access_expires_at,refresh_hmac,activation_id FROM sessions WHERE session_id=?').bind(consumed.body.sessionID).first();
    assert.equal(row.kind,'web');assert.equal(row.expires_at,selected.now+43200);assert.equal(row.access_expires_at,row.expires_at);assert.equal(row.refresh_hmac,null);assert.equal(row.activation_id,null);
    return await issueConsumedWebSession(consumed,{marker:'PAT-2649-account-web-synthetic',db:owner.db,now:()=>selected.now,randomBytes,syntheticKey:new Uint8Array(32).fill(7),csrfKey:new Uint8Array(32).fill(19),allowedOrigin:selected.allowedOrigin,assets:{html:readFileSync(resolve(service,'web/account/index.html'),'utf8'),js:readFileSync(resolve(service,'web/account/account.js'),'utf8'),css:readFileSync(resolve(service,'web/account/account.css'),'utf8')}});
   } finally {captured=undefined;}
  },async dispose(){if(disposed)return;disposed=true;await owner.dispose();}};
 }catch(error){await owner.dispose();throw error;}
}
