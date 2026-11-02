import assert from 'node:assert/strict';
import {mkdirSync,mkdtempSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {ownedTLS,nativeChrome} from './native-chrome-cdp.mjs';
import {fixture} from '../billing/fake-paddle.ts';
const selectedVariant=process.argv.find(x=>x.startsWith('--compiled-variant='))?.slice('--compiled-variant='.length);
let compiledVariant,accountWebRuntime,seedMac,billingSetup,dbSnapshot,sourceAPI,composition;
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../../../..');mkdirSync(resolve(root,'.build'),{recursive:true});
const run=mkdtempSync(resolve(root,'.build/account-browser-'));let bridge,browser,r;
async function navigate(url){await browser.call('Page.navigate',{url});for(let i=0;i<100;i++){if(await browser.evaluate('location.href')===url&&await browser.evaluate('document.readyState')==='complete')return;await delay(50);}assert.fail('INFRA navigation did not finish');}
async function deliverSource(response){
 bridge.queueSourceCookie(response);await navigate(bridge.origin+'/__infrastructure/source-cookie');
 const metadata=(await browser.call('Network.getCookies',{urls:[bridge.origin]})).cookies.find(c=>c.name==='__Host-patched-fixture-session');
 assert.ok(metadata,'actual HTTPS source header creates browser cookie');assert.equal(metadata.secure,true);assert.equal(metadata.httpOnly,true);assert.equal(metadata.sameSite,'Strict');assert.equal(metadata.domain,'account.patched-fixture.invalid');assert.equal(metadata.path,'/');
 assert.equal(await browser.evaluate('document.cookie.includes("patched-fixture-session")'),false);return metadata;
}
async function until(expression,label){for(let i=0;i<100;i++){if(await browser.evaluate(expression))return;await delay(50);}assert.fail(label);}
async function click(selector){assert.equal(await browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e||e.disabled)return false;e.click();return true;})()`),true,'actual enabled DOM click '+selector);}
async function request(expression){await browser.evaluate(expression);await delay(100);}
try {
 compiledVariant=selectedVariant?(await import('./account-web-mutants.mjs')).installCompiledVariant(selectedVariant):undefined;
 ({accountWebRuntime}=await import('../d1-local/account-web-runtime.ts'));
 ({seedMac,billingSetup,dbSnapshot,sourceAPI,composition}=await import('../d1-local/account-web.test.ts'));
 bridge=await ownedTLS(run,compiledVariant?Number(new URL(compiledVariant.fixture.allowedOrigin).port):0);if(compiledVariant)assert.equal(bridge.origin,compiledVariant.fixture.allowedOrigin);browser=await nativeChrome(run,bridge);
 await navigate(bridge.origin+'/__infrastructure/policy');assert.equal(await browser.evaluate("document.querySelector('#canary').textContent"),'native TLS');
 const cookies=(await browser.call('Network.getCookies',{urls:[bridge.origin]})).cookies;const canary=cookies.find(c=>c.name==='__Host-policy-canary');
 assert.ok(canary);assert.equal(canary.secure,true);assert.equal(canary.httpOnly,true);assert.equal(canary.sameSite,'Strict');assert.equal(canary.domain,'account.patched-fixture.invalid');assert.equal(canary.path,'/');
 assert.equal(await browser.evaluate('document.cookie'),'');
 await request(`fetch(${JSON.stringify(bridge.origin+'/__infrastructure/carriage')},{credentials:'include'}).then(r=>r.json())`);assert.equal(bridge.policy.at(-1).present,true,'INFRA same-origin cookie carriage');
 await navigate(`https://sibling.patched-fixture.invalid:${bridge.port}/__infrastructure/other`);
 await request(`fetch('/__infrastructure/carriage',{credentials:'include'}).then(r=>r.json())`);assert.equal(bridge.policy.at(-1).present,false,'INFRA host-only absence TO sibling');
 await request(`fetch(${JSON.stringify(bridge.origin+'/__infrastructure/carriage')},{credentials:'include'}).catch(()=>null)`);assert.equal(bridge.policy.at(-1).present,true,'INFRA same-site sibling to account may carry cookie');
 await navigate(`https://hostile.different-fixture.invalid:${bridge.port}/__infrastructure/other`);
 await request(`fetch(${JSON.stringify(bridge.origin+'/__infrastructure/carriage')},{credentials:'include'}).catch(()=>null)`);assert.equal(bridge.policy.at(-1).present,false,'INFRA different-site Strict omission');
 await browser.call('Page.navigate',{url:'about:blank'});
 await navigate(`http://account.patched-fixture.invalid:${bridge.httpPort}/__infrastructure/other`);
 await request("fetch('/__infrastructure/carriage',{credentials:'include'}).then(r=>r.json())");assert.equal(bridge.policy.at(-1).present,false,'INFRA Secure omission over HTTP');
 await navigate(bridge.origin+'/__infrastructure/other');await request("fetch('https://denial-canary.invalid/').catch(()=>null)");assert.equal(browser.denied,1,'INFRA actual CDP denial canary');
 await navigate(bridge.origin+'/__infrastructure/expiry');await request("fetch('/__infrastructure/carriage',{credentials:'include'}).then(r=>r.json())");assert.equal(bridge.policy.at(-1).shortPresent,true,'INFRA short cookie before expiry');
 await delay(2600);await request("fetch('/__infrastructure/carriage',{credentials:'include'}).then(r=>r.json())");assert.equal(bridge.policy.at(-1).shortPresent,false,'INFRA actual browser cookie expiry');assert.equal(bridge.policy.at(-1).present,true,'INFRA long cookie retained');assert.equal(browser.unexpected,0);
 // Independent one-shot transport proof uses only a synthetic noncredential
 // Response. Product issuer remains held; none of its cookie checks run here.
 await navigate(bridge.origin+'/__infrastructure/other');
 const consume=()=>browser.evaluate("fetch('/__infrastructure/source-cookie').then(async r=>({status:r.status,body:await r.text(),proof:r.headers.get('x-infrastructure-proof')}))");
 assert.equal((await consume()).status,409,'INFRA absent source response refuses');
 const synthetic=new Response('synthetic transport bytes \u00a3', {status:202,headers:{'Content-Type':'text/plain; charset=utf-8','X-Infrastructure-Proof':'noncredential-fixed','Set-Cookie':'__Host-delivery-canary=synthetic; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=60'}});
 bridge.queueSourceCookie(synthetic);assert.throws(()=>bridge.queueSourceCookie(new Response('replacement')),/already queued/);
 await navigate(`https://sibling.patched-fixture.invalid:${bridge.port}/__infrastructure/other`);assert.equal((await consume()).status,403,'INFRA sibling cannot consume queued response');
 await navigate(`http://account.patched-fixture.invalid:${bridge.httpPort}/__infrastructure/other`);assert.equal((await consume()).status,403,'INFRA insecure endpoint cannot consume queued response');
 await navigate(bridge.origin+'/__infrastructure/other');assert.deepEqual(await consume(),{status:202,body:'synthetic transport bytes \u00a3',proof:'noncredential-fixed'},'INFRA original status/body/header bytes delivered');
 assert.equal((await consume()).status,409,'INFRA second source consumption refuses');assert.equal(synthetic.bodyUsed,true);
 const delivered=(await browser.call('Network.getCookies',{urls:[bridge.origin]})).cookies.find(c=>c.name==='__Host-delivery-canary');assert.ok(delivered&&delivered.secure&&delivered.httpOnly&&delivered.sameSite==='Strict','INFRA original synthetic Set-Cookie processed by browser');
 r=await accountWebRuntime(compiledVariant?.fixture??{marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:Math.floor(Date.now()/1000),entropySeed:'51'.repeat(16)});bridge.setOwner(r.owner);compiledVariant?.registerOwner(r.owner);
 console.log('ACCOUNT-BROWSER-INFRA passed: '+browser.version+'/NodeWebSocketCDP, one-shot original Response transport, scoped TLS, actual cookie policy/expiry, denied outbound, one actual D1 owner');
 if(process.argv.includes('--infrastructure-only')){
  console.log('PRODUCT assertions not invoked in infrastructure-only preparation');
 }else{
  await navigate(bridge.origin+'/__fixture/web/account');
  const observed=bridge.observed.findLast(x=>x.path==='/__fixture/web/account');
  assert.equal(observed?.status,200,'RED browser navigation actual source page status before DOM selectors');
  const issued=await r.provision({email:'browser@example.invalid',purpose:'web-sign-in',sourceIP:'192.0.2.248'},'52'.repeat(16));
  assert.equal(issued.status,200,'RED source-issued cookie prerequisite; downstream authenticated DOM prospective until this passes');
  const header=issued.headers.get('set-cookie');assert.ok(header);
  const match=header.match(/^__Host-patched-fixture-session=([a-f0-9]{32}\.[a-f0-9]{64}); Path=\/; Secure; HttpOnly; SameSite=Strict; Max-Age=(\d+); Expires=(.+)$/);assert.ok(match,'source cookie exact attributes');
  const issuedMetadata=await deliverSource(issued);assert.ok(Math.abs(issuedMetadata.expires-(Date.now()/1000+Number(match[2])))<3,'actual browser Max-Age precedence');
  await navigate(bridge.origin+'/__fixture/web/account');
  await until("document.querySelector('#slot-count')?.textContent.includes('0')",'initial actual zero-slot state');
  const sourceSession=(await r.owner.db.prepare('SELECT * FROM sessions WHERE session_id=?').bind(match[1].slice(0,32)).first());
  const accountID=sourceSession.account_id;
  const initial=await dbSnapshot(r.owner);await click('#refresh-account');await until("!document.querySelector('#refresh-account').disabled",'state refresh completes');assert.deepEqual(await dbSnapshot(r.owner),initial,'sign-in/navigation/state refresh consumes no trial');
  for(const mode of ['missingOrigin','wrongOrigin','missingCSRF','wrongCSRF']){
   const before=await dbSnapshot(r.owner),count=browser.rewrites;browser.rewriteNextMutation(mode);
   const status=await browser.evaluate(`(async()=>{const state=await (await fetch('/__fixture/web/account/state',{credentials:'same-origin'})).json();const bytes=crypto.getRandomValues(new Uint8Array(16));const requestID=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');return (await fetch('/__fixture/web/account/trial',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','X-CSRF-Token':state.csrfToken},body:JSON.stringify({expectedAccountRevision:state.accountRevision,requestID})})).status;})()`);
   assert.equal(browser.rewrites,count+1,'actual browser request interception reached');assert.equal(status===403,true,'PROPERTY browser '+mode+' refuses mutation');assert.deepEqual(await dbSnapshot(r.owner),before,'rejected browser mutation writes nothing');
  }
  await click('#start-trial');await until("document.querySelector('#licence-status')?.textContent.toLowerCase().includes('trial')",'explicit trial click followed by actual source readback');
  const trial=await r.owner.db.prepare('SELECT * FROM entitlement_sources WHERE account_id=?').bind(accountID).first();assert.equal(trial.trial_ends_at,trial.trial_started_at+1209600);assert.equal(trial.trial_started_at,sourceSession.created_at);
  const names=['<img src=x onerror=1>','</script><script>1</script>','Quotes " & café','Duplicate','Duplicate'];const macs=[];
  for(const [i,name]of names.entries())macs.push(await seedMac(r.owner,accountID,name,i+1,i===3?'1'.repeat(26)+'abcdef':i===4?'2'.repeat(26)+'abcdef':undefined));
  await click('#refresh-account');await until("document.querySelector('#slot-count')?.textContent==='5 of 5 Mac slots used'",'actual source five-slot list');
  for(const name of names)assert.equal(await browser.evaluate(`document.querySelector('#mac-list').textContent.includes(${JSON.stringify(name)})`),true,'literal valid malicious name');
  assert.equal(await browser.evaluate("document.querySelectorAll('#mac-list img,#mac-list script,#mac-list [onerror]').length"),0,'literal names never create executable DOM');
  const duplicateLabels=await browser.evaluate("Array.from(document.querySelectorAll('#mac-list [data-activation-id]')).filter(e=>e.textContent.includes('Duplicate')).map(e=>e.textContent)");assert.equal(duplicateLabels.length,2);assert.notEqual(duplicateLabels[0],duplicateLabels[1],'colliding six-character suffixes extend until unique');
  const target=macs[4].activationID;await click(`#mac-list [data-activation-id="${target}"] button`);
  await until("document.querySelector('#deactivate-confirmation')?.open",'actual target confirmation');
  assert.equal(await browser.evaluate(`document.querySelector('#deactivate-confirmation').textContent.includes(${JSON.stringify(target.slice(-7))})`),true,'confirmation disambiguates exact target');
  const mutationHold=bridge.holdNext('/__fixture/web/account/macs/'+target+'/deactivate'),stateHold=bridge.holdNext('/__fixture/web/account/state');
  try{await click('#confirm-deactivate');await Promise.race([mutationHold.seen,delay(10000).then(()=>{throw Error('mutation hold not reached');})]);
   assert.equal(await browser.evaluate("document.querySelector('#slot-count').textContent==='5 of 5 Mac slots used'"),true,'no optimistic removal while mutation response pending');
   const released=await r.owner.db.prepare('SELECT released_at FROM lease_heads WHERE activation_id=?').bind(target).first();assert.equal(released.released_at,sourceSession.created_at,'real source operation committed');
   mutationHold.release();await Promise.race([stateHold.seen,delay(10000).then(()=>{throw Error('fresh state read not reached');})]);
   assert.equal(await browser.evaluate("document.querySelector('#slot-count').textContent==='5 of 5 Mac slots used'"),true,'confirmed action waits for fresh actual state before removal');stateHold.release();
   await until("document.querySelector('#slot-count')?.textContent.includes('4')",'confirmed source state renders freed slot');
   assert.equal(await browser.evaluate(`document.querySelector('#mac-list [data-activation-id="${target}"]')===null`),true,'exact confirmed target removed');
   assert.equal((await r.owner.db.prepare('SELECT released_at FROM lease_heads WHERE activation_id=?').bind(macs[3].activationID).first()).released_at,null,'same-label other target remains');
  }finally{mutationHold.release();stateHold.release();}
  // Each intentional fixture restart starts a distinct finite worker-entropy epoch.
  // Omission persistence remains independently covered by runtime controls.
  await r.owner.restart({markers:{ENVIRONMENT:'local-fixture',PROVIDER_MODE:'fake'},web:{marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:sourceSession.created_at,entropySeed:'55'.repeat(16)}});await click('#refresh-account');await until("document.querySelector('[role=alert]')?.textContent.length>0",'actual source missing-marker error renders');assert.equal(await browser.evaluate("document.querySelector('#slot-count').textContent.includes('4')"),true,'error preserves confirmed list');
  await r.owner.restart({markers:{ENVIRONMENT:'local-fixture',FIXTURE_MARKER:'PAT-2639-local-only',PROVIDER_MODE:'fake'},web:{marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:sourceSession.created_at,entropySeed:'56'.repeat(16)}});
  const freshnessNow=sourceSession.created_at+600;
  await r.owner.restart({web:{marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:freshnessNow,entropySeed:'57'.repeat(16)}});
  const chronology=await r.owner.db.prepare('SELECT created_at,authenticated_at,expires_at FROM sessions WHERE session_id=?').bind(sourceSession.session_id).first();assert.deepEqual(chronology,{created_at:sourceSession.created_at,authenticated_at:sourceSession.created_at,expires_at:sourceSession.expires_at},'freshness equality advances only source clock; genuine chronology and original deadline unchanged');await click('#refresh-account');await until("document.body.textContent.toLowerCase().includes('reauth')",'exact freshness equality renders reauth');
  const oldState=bridge.holdNext('/__fixture/web/account/state');
  try{await click('#refresh-account');await Promise.race([oldState.seen,delay(10000).then(()=>{throw Error('old state response not held');})]);await click('#logout-account');await until("document.body.textContent.toLowerCase().includes('signed out')||document.body.textContent.toLowerCase().includes('sign in')",'confirmed source logout changes response generation');assert.deepEqual(await r.owner.db.prepare('SELECT created_at,authenticated_at,expires_at,revoked_at FROM sessions WHERE session_id=?').bind(sourceSession.session_id).first(),{created_at:sourceSession.created_at,authenticated_at:sourceSession.created_at,expires_at:sourceSession.expires_at,revoked_at:freshnessNow},'confirmed logout uses advanced source time and preserves genuine chronology/original deadline');oldState.release();await delay(200);assert.equal(await browser.evaluate("document.querySelector('#mac-list')?.textContent.includes('Duplicate')??false"),false,'PROPERTY reversed old state cannot restore private previous-session DOM');}finally{oldState.release();}
  const boundary=await r.provision({email:'browser-boundary@example.invalid',purpose:'web-sign-in',sourceIP:'192.0.2.245'},'54'.repeat(16));assert.equal(boundary.status,200);await deliverSource(boundary);await navigate(bridge.origin+'/__fixture/web/account');await until("document.querySelector('#slot-count')?.textContent.includes('0')",'new real household session replaces prior generation');
  await r.owner.restart({web:{marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:sourceSession.expires_at,entropySeed:'53'.repeat(16)}});await click('#refresh-account');await until("document.body.textContent.toLowerCase().includes('sign in')||document.body.textContent.toLowerCase().includes('expired')",'absolute12h equality refuses existing browser credential');
  assert.equal(await browser.evaluate("document.cookie.includes('patched-fixture-session')"),false);
  assert.equal(await browser.evaluate('localStorage.length===0&&sessionStorage.length===0'),true);
  assert.equal(await browser.evaluate("document.querySelectorAll('iframe,object,embed,form[action^=http],script[src^=http]').length"),0);
  for(const event of browser.events)for(const secret of [sourceSession.session_id,match[1].slice(33)])assert.ok(!event.url.includes(secret),'no session credential in observed URL');
  assert.equal(await browser.evaluate("Array.from(document.querySelectorAll('button,a')).some(e=>/^(activate|replace|buy|purchase|generate key|issue lease|rename)\\b/i.test(e.textContent.trim()))"),false,'no activation/key/lease/purchase control');
  assert.equal(await browser.evaluate("document.querySelectorAll('input[name*=token],input[name*=device]').length"),0);
  assert.equal(browser.unexpected,0);
  for(const name of ['existing-gbp','failed-renewal']){
   await r.dispose();const f=fixture(name);r=await accountWebRuntime({marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:f.now,entropySeed:name==='existing-gbp'?'71'.repeat(16):'72'.repeat(16)});bridge.setOwner(r.owner);
   const setup=await billingSetup(r,name);assert.equal(setup.issued.status,200,'actual source issuer for reconciled billing household');const raw=setup.issued.headers.get('set-cookie'),age=Number(raw.match(/Max-Age=(\d+)/)[1]);
   // Historical billing epochs exercise display only: real browser Set-Cookie Max-Age precedence over past Expires. Original header and source deadlines remain intact.
   await browser.call('Network.clearBrowserCookies');const historicalMetadata=await deliverSource(setup.issued);assert.ok(Math.abs(historicalMetadata.expires-(Date.now()/1000+age))<3,'real historical header Max-Age precedence');
   const before=await dbSnapshot(r.owner);await navigate(bridge.origin+'/__fixture/web/account');await until(`document.querySelector('#licence-status')?.textContent.toLowerCase().includes(${JSON.stringify(setup.selection.state)})`,'actual '+setup.selection.state+' browser state from private B23 selection');assert.deepEqual(await dbSnapshot(r.owner),before,'billing display starts no trial or mutation');
  }
  for(const family of ['beta','expired','unknown']){
   await r.dispose();const wall=Math.floor(Date.now()/1000);r=await accountWebRuntime({marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:wall,entropySeed:family==='beta'?'91'.repeat(16):family==='expired'?'92'.repeat(16):'93'.repeat(16)});bridge.setOwner(r.owner);
   const issued=await r.provision({email:'browser-'+family+'@example.invalid',purpose:'web-sign-in',sourceIP:'192.0.2.244'},family==='beta'?'94'.repeat(16):family==='expired'?'95'.repeat(16):'96'.repeat(16));assert.equal(issued.status,200);const value=issued.headers.get('set-cookie').split(';')[0].split('=')[1],session=await r.owner.db.prepare('SELECT * FROM sessions WHERE session_id=?').bind(value.slice(0,32)).first();
   if(family==='beta')await r.owner.db.prepare('INSERT INTO entitlement_sources(account_id,beta_invited) VALUES(?,1)').bind(session.account_id).run();
   if(family==='expired')await r.owner.db.prepare('INSERT INTO entitlement_sources(account_id,trial_started_at,trial_ends_at) VALUES(?,?,?)').bind(session.account_id,wall-1209600,wall).run();
   if(family==='unknown')await r.owner.db.exec('CREATE TABLE billing_notice_future (id INTEGER);');
   const before=await dbSnapshot(r.owner);await browser.call('Network.clearBrowserCookies');await deliverSource(issued);await navigate(bridge.origin+'/__fixture/web/account');
   if(family==='unknown')await until("document.querySelector('[role=alert]')?.textContent.length>0",'unknown source facts render verification error');
   else await until(`document.querySelector('#licence-status')?.textContent.toLowerCase().includes(${JSON.stringify(family)})`,'actual '+family+' browser state');
   assert.equal(await browser.evaluate("(()=>{const e=document.querySelector('#start-trial');return !e||e.disabled||e.hidden;})()"),true,'unavailable trial cannot be started from '+family+' UI');assert.deepEqual(await dbSnapshot(r.owner),before,'family navigation/state reads never consume trial or mutate');
  }
  // Setup has a bounded measured budget against the original absolute12h
  // deadline. Source clock is aligned only after restart and API bundle setup.
  await r.dispose();const setupStarted=Date.now(),wall=Math.floor(setupStarted/1000),remaining=30,created=wall-43200+remaining;
  r=await accountWebRuntime({marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:created,entropySeed:'81'.repeat(16)});bridge.setOwner(r.owner);
  const old=await r.provision({email:'short-expiry@example.invalid',purpose:'web-sign-in',sourceIP:'192.0.2.246'},'82'.repeat(16));assert.equal(old.status,200);const originalHeader=old.headers.get('set-cookie'),credentialValue=originalHeader.split(';')[0].split('=')[1],sessionID=credentialValue.slice(0,32),accessToken=credentialValue.slice(33),session=await r.owner.db.prepare('SELECT * FROM sessions WHERE session_id=?').bind(sessionID).first();
  assert.equal(session.expires_at,created+43200);
  await r.owner.restart({web:{marker:'PAT-2649-account-runtime-synthetic',allowedOrigin:bridge.origin,now:Math.floor(Date.now()/1000),entropySeed:'83'.repeat(16)}});
  const api=await sourceAPI(r.owner),alignedNow=Math.floor(Date.now()/1000);
  assert.ok(session.expires_at-alignedNow>=10,'INFRA setup failure: restart/API setup exhausted original expiry budget');
  const source=await api.issueConsumedWebSession({status:200,body:{outcome:'signed-in',accountID:session.account_id,sessionID,accessToken,accessExpiresAt:session.access_expires_at,expiresAt:session.expires_at}},{...composition(r.owner,()=>alignedNow),allowedOrigin:bridge.origin});assert.equal(source.status,200);
  const sourceHeader=source.headers.get('set-cookie');assert.ok(sourceHeader.includes('Max-Age='+(session.expires_at-alignedNow)+'; Expires='+new Date(session.expires_at*1000).toUTCString()),'real remainingMaxAge and originalExpires');
  await browser.call('Network.clearBrowserCookies');const metadata=await deliverSource(source);
  assert.ok(session.expires_at*1000-Date.now()>=5000,'INFRA setup failure: source transport exhausted original expiry budget');
  await navigate(bridge.origin+'/__fixture/web/account');assert.equal(await browser.evaluate("fetch('/__fixture/web/account/state',{credentials:'same-origin'}).then(r=>r.status)"),200,'real source cookie carriage before expiry');
  // Max-Age uses integer source seconds; browser acceptance may add a subsecond
  // offset, bounded independently without rewriting either header or deadline.
  assert.ok(Math.abs(metadata.expires-session.expires_at)<2,'actual metadata preserves source original expiry within wall alignment');
  const proof={setupElapsedMs:Date.now()-setupStarted,remainingAtIssue:session.expires_at-alignedNow,sourceExpiresAt:session.expires_at,browserExpiresAt:metadata.expires,secure:metadata.secure,httpOnly:metadata.httpOnly,sameSite:metadata.sameSite,domain:metadata.domain,path:metadata.path};
  writeFileSync(resolve(run,'source-expiry-metadata.json'),JSON.stringify(proof)+'\n');console.log('ACCOUNT-BROWSER source expiry setup '+JSON.stringify(proof));
  await delay(Math.max(0,Math.max(session.expires_at,metadata.expires)*1000-Date.now())+300);
  assert.equal((await browser.call('Network.getCookies',{urls:[bridge.origin]})).cookies.some(c=>c.name==='__Host-patched-fixture-session'),false,'actual source browser cookie absent after same original deadline');
  assert.equal(await browser.evaluate("fetch('/__fixture/web/account/state',{credentials:'same-origin'}).then(r=>r.status)"),401,'actual source-issued browser cookie disappears at expiry');assert.equal((await r.owner.db.prepare('SELECT expires_at FROM sessions WHERE session_id=?').bind(sessionID).first()).expires_at,session.expires_at,'browser expiry never rewrites source deadline');
 }
}finally{try{await browser?.dispose();}finally{try{await r?.dispose();}finally{try{await bridge?.dispose();}finally{compiledVariant?.dispose();}}}}
