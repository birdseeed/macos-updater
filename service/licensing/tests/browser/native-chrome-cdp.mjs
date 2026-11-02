// Real existing Chrome, Node WebSocket CDP and disposable owned TLS only.
import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
import {createServer as httpsServer} from 'node:https';
import {createServer as httpServer} from 'node:http';
import {existsSync,mkdirSync,readFileSync,writeFileSync,realpathSync,rmSync,lstatSync,readlinkSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash,X509Certificate} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {observeChromeStartup} from './chrome-startup-diagnostics.mjs';
import {createChromeTemporaryDirectory} from './chrome-temporary-directory.mjs';
import {createChromeLaunchEnvironment} from './chrome-launch-environment.mjs';
const hosts=['account.patched-fixture.invalid','sibling.patched-fixture.invalid','hostile.different-fixture.invalid'];
const documentPath='/__fixture/web/account';
const decodedCodings=new Set(['gzip','x-gzip','br','deflate']);
const netErrors=new Set(['net::ERR_CONTENT_DECODING_FAILED','net::ERR_CONTENT_LENGTH_MISMATCH','net::ERR_INCOMPLETE_CHUNKED_ENCODING','net::ERR_CONNECTION_CLOSED','net::ERR_CONNECTION_RESET','net::ERR_CONNECTION_REFUSED','net::ERR_ABORTED','net::ERR_FAILED','net::ERR_BLOCKED_BY_CLIENT','net::ERR_TIMED_OUT']);
const safeNetError=value=>netErrors.has(value)?value:'other';
function existingChrome(){
 const paths=process.platform==='darwin'?['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']:process.platform==='linux'?['/usr/bin/google-chrome','/usr/bin/google-chrome-stable']:[];
 const chrome=paths.find(path=>existsSync(path));assert.ok(chrome,'INFRA setup: existing Google Chrome required on Linux or macOS; no install or fallback');return chrome;
}
const listen=(server,port=0)=>new Promise((ok,no)=>{server.once('error',no);server.listen(port,'127.0.0.1',()=>ok(server.address().port));});
const close=server=>new Promise(ok=>{server.close(ok);server.closeAllConnections?.();});
export async function ownedTLS(run,reservedPort=0){
 assert.ok(Number.isInteger(reservedPort)&&reservedPort>=0&&reservedPort<=65535);
 assert.equal(realpathSync(run),run);const tls=resolve(run,'tls');mkdirSync(tls,{mode:0o700});
 const env={PATH:'/usr/bin:/bin',HOME:run,TMPDIR:run};
 const key=resolve(tls,'key.pem'),cert=resolve(tls,'cert.pem');
 execFileSync('/usr/bin/openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key,'-out',cert,'-days','1','-subj','/CN=account.patched-fixture.invalid','-addext',`subjectAltName=${hosts.map(h=>'DNS:'+h).join(',')}`],{env,stdio:'ignore',timeout:15000});
 const publicKey=new X509Certificate(readFileSync(cert)).publicKey.export({type:'spki',format:'der'});
 const spki=createHash('sha256').update(publicKey).digest('base64');
 let owner,pendingSourceCookie,denied=0,carried=0;const observed=[],transport=[],policy=[],holds=new Map(),activeHolds=new Set();
 const handler=async(req,res)=>{
  try {
   const authority=req.headers.host??'',host=authority.split(':')[0];
   if(!hosts.includes(host)||authority!==`${host}:${req.socket.encrypted?port:httpPort}`){denied++;res.writeHead(421);res.end();return;}
   // Canary records only presence, never cookie bytes, and is unrelated to account behaviour.
   if(req.url.startsWith('/__infrastructure/')){
    if(req.url==='/__infrastructure/source-cookie'){
     if(!req.socket.encrypted||host!==hosts[0]||req.method!=='GET'){res.writeHead(403,{'Cache-Control':'no-store'});res.end();return;}
     if(!pendingSourceCookie){res.writeHead(409,{'Cache-Control':'no-store'});res.end();return;}
     const response=pendingSourceCookie;pendingSourceCookie=undefined;
     const headers=Object.fromEntries(response.headers);const cookies=response.headers.getSetCookie();if(cookies.length)headers['set-cookie']=cookies;
     res.writeHead(response.status,headers);if(response.body)for await(const chunk of response.body)res.write(chunk);res.end();return;
    }
    if(req.url==='/__infrastructure/policy'){
     res.writeHead(200,{'Content-Type':'text/html','Cache-Control':'no-store','Set-Cookie':'__Host-policy-canary=synthetic; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=60'});
     res.end('<!doctype html><title>Infrastructure</title><p id="canary">native TLS</p>');return;
    }
    if(req.url==='/__infrastructure/expiry'){res.writeHead(200,{'Content-Type':'text/html','Set-Cookie':'__Host-expiry-canary=synthetic; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=2'});res.end('<!doctype html><title>Expiry</title>');return;}
    if(req.url==='/__infrastructure/carriage'){const present=(req.headers.cookie??'').includes('__Host-policy-canary=');carried+=Number(present);policy.push({host,present,shortPresent:(req.headers.cookie??'').includes('__Host-expiry-canary='),origin:req.headers.origin??null});res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify({present}));return;}
    res.writeHead(200,{'Content-Type':'text/html','Cache-Control':'no-store'});res.end('<!doctype html><title>Other fixture site</title>');return;
   }
   if(req.url==='/favicon.ico'){res.writeHead(204);res.end();return;}
   assert.ok(owner,'bridge source owner not attached');assert.equal(host,hosts[0]);
   const headers=new Headers();for(const [k,v] of Object.entries(req.headers))if(v!==undefined&&k!=='host')headers.set(k,Array.isArray(v)?v.join(', '):v);
   // This internal fetch exposes decoded bytes: do not relay compressed-wire framing.
   // Origin, cookies and validation headers retain the browser's original values.
   headers.set('accept-encoding','identity');
   const response=await fetch(owner.origin+req.url,{method:req.method,headers,body:['GET','HEAD'].includes(req.method)?undefined:req,duplex:'half',redirect:'error',signal:AbortSignal.timeout(15000)});
   const encoding=response.headers.get('content-encoding'),length=response.headers.get('content-length');
   const codings=encoding===null?[]:encoding.toLowerCase().split(',').map(x=>x.trim());
   const decoded=codings.length>0&&codings.every(x=>decodedCodings.has(x));
   const identity=codings.length===0||(codings.length===1&&codings[0]==='identity');
   const observation={path:req.url,status:response.status};observed.push(observation);
   const diagnostic=req.url===documentPath&&transport.length<64?{path:documentPath,status:response.status,responseEncoding:identity?'identity':decoded&&codings.length<=5?codings.join(','):'other',responseLength:length===null?null:/^[0-9]{1,15}$/.test(length)?length:'other',streamedByteCount:0}:undefined;
   if(diagnostic)transport.push(diagnostic);
   assert.ok(identity||decoded,'unsupported upstream content encoding');
   const relayHeaders=Object.fromEntries(response.headers);delete relayHeaders['content-length'];
   if(decoded)delete relayHeaders['content-encoding'];
   const cookies=response.headers.getSetCookie();if(cookies.length)relayHeaders['set-cookie']=cookies;
   const held=holds.get(req.url);if(held){holds.delete(req.url);activeHolds.add(held);held.observed();try{await held.wait;}finally{activeHolds.delete(held);}}res.writeHead(response.status,relayHeaders);
   if(response.body)for await(const chunk of response.body){res.write(chunk);if(diagnostic)diagnostic.streamedByteCount+=chunk.byteLength;}res.end();
  }catch{if(res.headersSent)res.destroy();else{res.writeHead(503,{'Cache-Control':'no-store'});res.end();}}
 };
 const server=httpsServer({key:readFileSync(key),cert:readFileSync(cert)},handler);const port=await listen(server,reservedPort);
 const insecure=httpServer(handler);const httpPort=await listen(insecure);
 return {origin:`https://${hosts[0]}:${port}`,port,httpPort,spki,queueSourceCookie(response){assert.ok(response instanceof Response,'actual Response required');assert.equal(response.bodyUsed,false);assert.equal(pendingSourceCookie,undefined,'source response already queued');pendingSourceCookie=response;},setOwner(value){if(owner)assert.throws(()=>owner.origin,'previous owner must be disposed');owner=value;},holdNext(path){assert.ok(path.startsWith('/__fixture/web/account/'));assert.ok(!holds.has(path));let observed,release;const seen=new Promise(ok=>{observed=ok;}),wait=new Promise(ok=>{release=ok;});holds.set(path,{observed,wait,release});return {seen,release};},get observed(){return [...observed];},get policy(){return [...policy];},get denied(){return denied;},get carried(){return carried;},async dispose(){for(const hold of [...holds.values(),...activeHolds])hold.release();holds.clear();await close(server);await close(insecure);assert.equal(realpathSync(tls),tls);rmSync(tls,{recursive:true});writeFileSync(resolve(run,'relay-metadata.json'),JSON.stringify({transport})+'\n');}};
}
export async function nativeChrome(run,bridge){
 assert.equal(process.version,'v24.21.0');assert.equal(typeof WebSocket,'function');
 const chrome=existingChrome(),version=execFileSync(chrome,['--version'],{encoding:'utf8',timeout:10000}).trim(),parsed=version.match(/^Google Chrome (\d+)\.\d+\.\d+\.\d+$/);assert.ok(parsed,'INFRA setup: unrecognised existing Google Chrome version');assert.ok(Number(parsed[1])>=150,'INFRA setup: Google Chrome major >=150 required');console.log('ACCOUNT-BROWSER existing '+version+'; executable '+chrome);
 const profile=resolve(run,'chrome-profile');mkdirSync(profile,{mode:0o700});
 const temporaryDirectory=process.platform==='linux'||process.platform==='darwin'?await createChromeTemporaryDirectory(run):null;let temporaryCleanup=null;
 const env=createChromeLaunchEnvironment({platform:process.platform,run,temporaryDirectory});
 const started=performance.now();
 let child;try{child=spawn(chrome,['--headless=new','--no-first-run','--no-default-browser-check','--password-store=basic','--use-mock-keychain','--disable-background-networking','--disable-component-update','--disable-sync','--disable-extensions','--disable-default-apps','--disable-service-worker','--disable-features=MediaRouter,OptimizationHints,AutofillServerCommunication','--no-proxy-server','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0',`--user-data-dir=${profile}`,`--ignore-certificate-errors-spki-list=${bridge.spki}`,`--host-resolver-rules=${hosts.map(h=>`MAP ${h} 127.0.0.1`).join(', ')+', MAP * ~NOTFOUND'}`,'about:blank'],{env,stdio:['ignore','ignore','pipe']});}catch(error){
  // No owned child termination was observed. Preserve allocated storage.
  temporaryCleanup=temporaryDirectory?await temporaryDirectory.dispose({exitCode:null,signalCode:null}):null;
  assert.equal(realpathSync(run),run);
  const diagnostic=JSON.stringify({phase:'spawn-failed',platform:process.platform,temporaryDirectory:temporaryDirectory?.ownership??null,temporaryCleanup,childCloseObserved:false,stderrDrainComplete:false})+'\n';
  writeFileSync(resolve(run,'chrome-startup-metadata.json'),diagnostic,{mode:0o600});console.log('CHROME-STARTUP '+diagnostic.trimEnd());throw error;
 }
 const startup=observeChromeStartup(child,{run,profile});let closed=false,stderrCaptureStopped=false,startupElapsedMs,startupProcess,cleanupKillRequested=false,portReadError=null;
 child.once('close',()=>{closed=true;});
 const waitForClose=()=>closed?Promise.resolve():Promise.race([new Promise(ok=>child.once('close',ok)),delay(3000)]);
 const finishCapture=()=>{if(!closed){stderrCaptureStopped=true;child.stderr.destroy();}};
 const safeFileError=error=>['ENOENT','EACCES','EPERM','ELOOP','ENOTDIR','EIO'].includes(error?.code)?error.code:'other';
 const directoryMetadata=path=>{
  try{const stat=lstatSync(path);return {canonicalEqual:realpathSync(path)===path,directory:stat.isDirectory(),mode:stat.mode&0o777,ownedByCurrentUser:typeof process.getuid==='function'?stat.uid===process.getuid():null};}
  catch(error){return {canonicalEqual:false,directory:null,mode:null,ownedByCurrentUser:null,errorCode:safeFileError(error)};}
 };
 const releaseTemporaryDirectory=async()=>{
  if(!temporaryDirectory)return;
  try{temporaryCleanup=await temporaryDirectory.dispose({exitCode:child.exitCode,signalCode:child.signalCode});}
  catch(error){temporaryCleanup={removed:false,reason:'cleanup-error',errorCode:safeFileError(error)};}
 };
 const retainStartup=phase=>{
  let activePort,singleton;
  try{const stat=lstatSync(resolve(profile,'DevToolsActivePort'));activePort={exists:true,regular:stat.isFile(),readError:portReadError};}
  catch(error){activePort={exists:error?.code==='ENOENT'?false:null,readError:portReadError,metadataError:safeFileError(error)};}
  try{const path=resolve(profile,'SingletonSocket'),stat=lstatSync(path);singleton={type:stat.isSymbolicLink()?'symlink':stat.isSocket()?'socket':stat.isFile()?'file':stat.isDirectory()?'directory':'other',linkBytes:stat.isSymbolicLink()?readlinkSync(path,{encoding:'buffer'}).length:null};}
  catch(error){singleton={type:error?.code==='ENOENT'?'absent':'unavailable',errorCode:safeFileError(error)};}
  const metadata={phase,platform:process.platform,nodeVersion:process.version,chromeVersion:version,elapsedStartupMs:startupElapsedMs??Math.round(performance.now()-started),startupProcess,cleanupKillRequested,childCloseObserved:closed,stderrDrainComplete:closed&&!stderrCaptureStopped,stderrCaptureStopped,owned:{run:directoryMetadata(run),profile:directoryMetadata(profile)},temporaryDirectory:temporaryDirectory?.ownership??null,temporaryCleanup,devToolsActivePort:activePort,singletonSocket:singleton,observer:startup.snapshot()};
  // Only the already-owned run is writable. Never follow the singleton target.
  assert.equal(realpathSync(run),run);
  const diagnostic=JSON.stringify(metadata)+'\n';
  writeFileSync(resolve(run,'chrome-startup-metadata.json'),diagnostic,{mode:0o600});
  console.log('CHROME-STARTUP '+diagnostic.trimEnd());
 };
 let ws;const pending=new Map();let serial=0,session,denied=0,unexpected=0;const events=[],navigationErrors=[],documentRequests=new Set();let paused=0,nextMutation,rewrites=0;
 const isDocument=url=>{try{const u=new URL(url);return u.origin===bridge.origin&&u.pathname===documentPath&&u.search===''&&u.hash==='';}catch{return false;}};
 const recordError=(phase,errorText)=>{if(navigationErrors.length<64)navigationErrors.push({phase,path:documentPath,error:safeNetError(errorText)});};
 const call=(method,params={},sessionId=session)=>new Promise((ok,no)=>{const id=++serial;const timer=setTimeout(()=>{pending.delete(id);no(Error('CDP timeout: '+method+' paused='+paused+' responses='+events.length));},15000);pending.set(id,{ok,no,timer,documentNavigation:method==='Page.navigate'&&isDocument(params.url)});ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));});
 try {
  let endpoint;for(let i=0;i<150;i++){try{const lines=readFileSync(resolve(profile,'DevToolsActivePort'),'utf8').trim().split('\n');endpoint=`ws://127.0.0.1:${lines[0]}${lines[1]}`;portReadError=null;break;}catch(error){portReadError=safeFileError(error);assert.equal(startup.snapshot().process.terminated,false,'Chrome terminated during setup');await delay(100);}}
  assert.ok(endpoint,'owned Chrome DevTools socket');ws=new WebSocket(endpoint);await new Promise((ok,no)=>{ws.addEventListener('open',ok,{once:true});ws.addEventListener('error',no,{once:true});});
  ws.addEventListener('message',async event=>{const m=JSON.parse(String(event.data));if(m.id){const p=pending.get(m.id);if(p){clearTimeout(p.timer);pending.delete(m.id);if(p.documentNavigation&&m.result?.errorText)recordError('Page.navigate',m.result.errorText);m.error?p.no(Error('CDP '+m.error.message)):p.ok(m.result);}return;}
   if(m.method==='Fetch.requestPaused'){paused++;
    const u=new URL(m.params.request.url);const allowed=hosts.includes(u.hostname)&&((u.protocol==='https:'&&Number(u.port)===bridge.port)||(u.protocol==='http:'&&Number(u.port)===bridge.httpPort));
    if(!allowed){denied++;if(u.hostname!=='denial-canary.invalid')unexpected++;await call('Fetch.failRequest',{requestId:m.params.requestId,errorReason:'BlockedByClient'},m.sessionId);}
    else{let headers;if(nextMutation&&u.hostname===hosts[0]&&u.pathname==='/__fixture/web/account/trial'&&m.params.request.method==='POST'){const mode=nextMutation;nextMutation=undefined;rewrites++;const source=m.params.request.headers;const omit=mode.endsWith('Origin')?'origin':'x-csrf-token';headers=Object.entries(source).filter(([name])=>name.toLowerCase()!==omit).map(([name,value])=>({name,value:String(value)}));if(mode==='wrongOrigin')headers.push({name:'Origin',value:`https://${hosts[1]}:${bridge.port}`});if(mode==='wrongCSRF')headers.push({name:'X-CSRF-Token',value:'a'.repeat(64)});}await call('Fetch.continueRequest',{requestId:m.params.requestId,...(headers?{headers}:{})},m.sessionId);}
   }
   if(m.method==='Network.requestWillBeSent'&&isDocument(m.params.request.url)&&documentRequests.size<64)documentRequests.add(m.params.requestId);
   if(m.method==='Network.loadingFailed'&&documentRequests.delete(m.params.requestId))recordError('Network.loadingFailed',m.params.errorText);
   if(m.method==='Network.loadingFinished')documentRequests.delete(m.params.requestId);
   if(m.method==='Network.responseReceived')events.push({url:m.params.response.url,status:m.params.response.status});
  });
  const target=await call('Target.createTarget',{url:'about:blank'},undefined);const attached=await call('Target.attachToTarget',{targetId:target.targetId,flatten:true},undefined);session=attached.sessionId;
  for(const method of ['Page.enable','Runtime.enable','Network.enable'])await call(method);
  const actual=await call('Browser.getVersion',{},null);assert.ok(actual.product.endsWith('/'+version.split(' ').at(-1)),'INFRA running browser version agrees');
  await call('Network.setBypassServiceWorker',{bypass:true});await call('Fetch.enable',{patterns:[{urlPattern:'*',requestStage:'Request'}]});
  startupElapsedMs=Math.round(performance.now()-started);startupProcess=startup.snapshot().process;retainStartup('ready');
  return {version,call,events,rewriteNextMutation(mode){assert.ok(['missingOrigin','wrongOrigin','missingCSRF','wrongCSRF'].includes(mode));assert.equal(nextMutation,undefined);nextMutation=mode;},get rewrites(){return rewrites;},get denied(){return denied;},get unexpected(){return unexpected;},async evaluate(expression){const r=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.equal(r.exceptionDetails,undefined,'browser expression exception');return r.result.value;},async dispose(){try{await call('Browser.close',{},null);}catch{}ws.close();for(const p of pending.values()){clearTimeout(p.timer);p.no(Error('CDP disposed'));}pending.clear();await waitForClose();if(child.exitCode===null&&child.signalCode===null){cleanupKillRequested=true;child.kill('SIGKILL');await waitForClose();}finishCapture();await releaseTemporaryDirectory();retainStartup('disposed');assert.equal(realpathSync(profile),profile);rmSync(profile,{recursive:true});writeFileSync(resolve(run,'chrome-metadata.json'),JSON.stringify({version,denied,unexpected,navigationErrors})+'\n');}};
 }catch(error){startupElapsedMs??=Math.round(performance.now()-started);startupProcess??=startup.snapshot().process;ws?.close();if(child.exitCode===null&&child.signalCode===null){cleanupKillRequested=true;child.kill('SIGKILL');}await waitForClose();finishCapture();await releaseTemporaryDirectory();retainStartup('failed');assert.equal(realpathSync(profile),profile);rmSync(profile,{recursive:true});throw error;}
}
