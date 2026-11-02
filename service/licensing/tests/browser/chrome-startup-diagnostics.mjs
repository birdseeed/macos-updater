// Observation only: the caller retains all process and filesystem authority.
import {StringDecoder} from 'node:string_decoder';
const limit=65536;
const safeCodes=new Set(['ENOENT','EACCES','EPERM','ENOEXEC','EAGAIN','ENOMEM','EMFILE','ENFILE','EIO','EINVAL']);
export function observeChromeStartup(child,{run,profile}){
 const retained=Buffer.alloc(limit),paths={runBytes:Buffer.byteLength(run),profileBytes:Buffer.byteLength(profile)};
 let length=0,stderrBytes=0,terminated=false;const events=[];
 const record=(kind,detail={})=>{if(events.length<64)events.push({kind,at:new Date().toISOString(),...detail});};
 child.on('error',error=>{terminated=true;record('error',{errorCode:safeCodes.has(error?.code)?error.code:'other'});});
 child.on('spawn',()=>record('spawn'));
 for(const kind of ['exit','close'])child.on(kind,(code,signal)=>{terminated=true;record(kind,{code:code??null,signal:signal??null});});
 child.stderr.on('data',chunk=>{
  const bytes=Buffer.isBuffer(chunk)?chunk:Buffer.from(chunk);
  stderrBytes+=bytes.length;const count=Math.min(bytes.length,limit-length);
  if(count){bytes.copy(retained,length,0,count);length+=count;}
 });
 return {snapshot(){
  // Do not complete a cut UTF8 character with replacement bytes at the cap.
  const decoded=new StringDecoder('utf8').write(retained.subarray(0,length));
  const encoded=Buffer.from(decoded);
  const stderr=encoded.length<=limit?decoded:new StringDecoder('utf8').write(encoded.subarray(0,limit));
  const exitCode=child.exitCode??null,signalCode=child.signalCode??null;
  return {stderr,stderrBytes,stderrTruncated:stderrBytes>limit,events:events.map(event=>({...event})),process:{exitCode,signalCode,terminated:terminated||exitCode!==null||signalCode!==null},paths:{...paths}};
 }};
}
