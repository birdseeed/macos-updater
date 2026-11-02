// Strict A1 exact-byte parsing and P-256 possession verification.
export type DeviceOperation = 1|2|3|4|5|6|7;
export type ProofOperation = 1|2|3|4|5;
export type Assurance = 'secureStorageFallback'|'fixtureAttested';
export type ParsedDeviceRequest = {operation:DeviceOperation; actionBytes:Uint8Array;
 actionSHA256:string; requestID:string; publicKey:Uint8Array|null;
 displayName:string|null; activationID:string|null; releaseActivationID:string|null;
 expectedRevision:number|null; caseID:string|null; caseDigest:string|null;
 proof:DeviceProof|null};
export type DeviceProof = {challengeID:string;nonce:Uint8Array;signature:Uint8Array;
 attestation:Uint8Array|null;attestKeyID:Uint8Array|null;assertion:Uint8Array|null};
export type PossessionContext = {accountID:string;activationID:string|null;
 operation:ProofOperation;publicKey:Uint8Array;nonce:Uint8Array;expiresAt:number};
export type SyntheticP256Verifier = {marker:'PAT-2644-synthetic';
 verify(publicKey:Uint8Array,message:Uint8Array,rawSignature:Uint8Array):Promise<boolean>};

export const hex=(b:Uint8Array):string=>Array.from(b,x=>x.toString(16).padStart(2,'0')).join('');
export const unhex=(s:string):Uint8Array=>Uint8Array.from(s.match(/../g)??[],x=>parseInt(x,16));
export const encode=(b:Uint8Array):string=>btoa(String.fromCharCode(...b));
export function decode(s:unknown,min:number,max=min):Uint8Array|null {try{if(typeof s!=='string'||s.length>4*Math.ceil(max/3)||! /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(s))return null;const b=Uint8Array.from(atob(s),c=>c.charCodeAt(0));return b.length>=min&&b.length<=max&&encode(b)===s?b:null;}catch{return null;}}
export const isID=(s:unknown):s is string=>typeof s==='string'&&/^[0-9a-f]{32}$/.test(s);
export const isActivationID=(s:unknown):s is string=>isID(s)&&s!=='0'.repeat(32);
export const isTime=(n:unknown):n is number=>typeof n==='number'&&Number.isSafeInteger(n)&&n>=0&&n<=253402300799;
export function closed(x:unknown,keys:string[]):x is Record<string,unknown>{return !!x&&typeof x==='object'&&!Array.isArray(x)&&Object.keys(x).length===keys.length&&keys.every(k=>Object.hasOwn(x,k));}
// Bounded JSON grammar, including escape-decoded duplicate detection.
export function strictJSON(bytes:Uint8Array,max=65536):unknown {
 if(!(bytes instanceof Uint8Array)||bytes.length>max)throw Error('size');
 const source=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(bytes);if(source.includes('\0')||source.startsWith('\ufeff'))throw Error('encoding');let i=0;
 const ws=()=>{while(/[\x20\x09\x0a\x0d]/.test(source[i]??'!'))i++;};
 const str=():string=>{const start=i++;while(i<source.length){const c=source[i++];if(c==='"')return JSON.parse(source.slice(start,i));if(c==='\\')i++;}throw Error('string');};
 const value=(depth:number):unknown=>{if(depth>4)throw Error('depth');ws();const c=source[i];if(c==='"')return str();if(c==='{'){i++;ws();const o:Record<string,unknown>=Object.create(null);if(source[i]==='}'){i++;return o;}while(true){ws();if(source[i]!=='"')throw Error('key');const k=str();if(Object.hasOwn(o,k))throw Error('duplicate');ws();if(source[i++]!==':')throw Error('colon');o[k]=value(depth+1);ws();const end=source[i++];if(end==='}')return o;if(end!==',')throw Error('object');}}const m=source.slice(i).match(/^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/);if(!m)throw Error('value');i+=m[0].length;return JSON.parse(m[0]);};
 const result=value(0);ws();if(i!==source.length)throw Error('trailing');return result;
}
// Synchronous SHA-256 is needed by the synchronous exact-byte parser. This is
// hashing only: ECDSA verification always goes through the injected crypto API.
export function sha256(bytes:Uint8Array):string {
 const k=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
 const h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19],p=new Uint8Array(Math.ceil((bytes.length+9)/64)*64);p.set(bytes);p[bytes.length]=128;new DataView(p.buffer).setBigUint64(p.length-8,BigInt(bytes.length)*8n);const r=(x:number,n:number)=>(x>>>n)|(x<<(32-n));
 for(let off=0;off<p.length;off+=64){const w=new Uint32Array(64),v=new DataView(p.buffer);for(let i=0;i<16;i++)w[i]=v.getUint32(off+i*4);for(let i=16;i<64;i++)w[i]=w[i-16]+(r(w[i-15],7)^r(w[i-15],18)^(w[i-15]>>>3))+w[i-7]+(r(w[i-2],17)^r(w[i-2],19)^(w[i-2]>>>10));let [a,b,c,d,e,f,g,z]=h;for(let i=0;i<64;i++){const t=(z+(r(e,6)^r(e,11)^r(e,25))+((e&f)^(~e&g))+k[i]+w[i])|0,u=((r(a,2)^r(a,13)^r(a,22))+((a&b)^(a&c)^(b&c)))|0;z=g;g=f;f=e;e=(d+t)|0;d=c;c=b;b=a;a=(t+u)|0;}[a,b,c,d,e,f,g,z].forEach((x,i)=>h[i]=(h[i]+x)|0);}
 return h.map(x=>(x>>>0).toString(16).padStart(8,'0')).join('');
}
export function validPublicKey(k:Uint8Array):boolean {if(!(k instanceof Uint8Array)||k.length!==65||k[0]!==4)return false;const p=0xffffffff00000001000000000000000000000000ffffffffffffffffffffffffn,x=BigInt('0x'+hex(k.slice(1,33))),y=BigInt('0x'+hex(k.slice(33)));return x<p&&y<p&&(y*y-(x*x*x-3n*x+0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604bn))%p===0n;}
const fields:Record<DeviceOperation,string[]>={1:['requestID','devicePublicKey','displayName'],2:['requestID','devicePublicKey','displayName','releaseActivationID','expectedRevision'],3:['requestID','activationID'],4:['requestID','activationID','expectedRevision'],5:['requestID','activationID','caseID','caseDigest'],6:['requestID','activationID','expectedRevision'],7:['requestID','activationID','expectedRevision','displayName']};
export function parseDeviceRequest(bytes:Uint8Array,operation:DeviceOperation,pathActivationID?:string):ParsedDeviceRequest|null {
 try{if(!fields[operation])return null;const o=strictJSON(bytes,operation===1||operation===2||operation===4?16384:4096);if(!closed(o,operation<=5?['action','proof']:['action']))return null;const actionBytes=decode(o.action,1,1024);if(!actionBytes)return null;const a=strictJSON(actionBytes,1024);if(!closed(a,fields[operation])||Object.keys(a).join(',')!==fields[operation].join(',')||JSON.stringify(a)!==new TextDecoder().decode(actionBytes)||!isID(a.requestID))return null;
 let publicKey:Uint8Array|null=null;if(operation<=2){publicKey=decode(a.devicePublicKey,65);if(!publicKey||!validPublicKey(publicKey))return null;}
 if(a.activationID!==undefined&&(!isActivationID(a.activationID)||a.activationID!==pathActivationID))return null;if(a.releaseActivationID!==undefined&&!isActivationID(a.releaseActivationID))return null;
 if(a.expectedRevision!==undefined&&(!Number.isSafeInteger(a.expectedRevision)||Number(a.expectedRevision)<1||Number(a.expectedRevision)>=Number.MAX_SAFE_INTEGER))return null;
 if(a.displayName!==undefined){const n=a.displayName;if(typeof n!=='string'||n!==n.trim()||n!==n.normalize('NFC')||[...n].length<1||[...n].length>64||new TextEncoder().encode(n).length>256||/[\p{Cc}\p{Cs}\u202a-\u202e\u2066-\u2069]/u.test(n))return null;}
 if(operation===5&&(!isID(a.caseID)||typeof a.caseDigest!=='string'||! /^[0-9a-f]{64}$/.test(a.caseDigest)))return null;
 let proof:DeviceProof|null=null;if(operation<=5){const p=o.proof as Record<string,unknown>;if(!p||typeof p!=='object')return null;const extra=Object.hasOwn(p,'attestation')?['attestation','attestKeyID']:Object.hasOwn(p,'assertion')?['assertion']:[];if(!closed(p,['challengeID','nonce','signature',...extra])||!isID(p.challengeID))return null;const nonce=decode(p.nonce,32),signature=decode(p.signature,64),attestation=extra.includes('attestation')?decode(p.attestation,1,8192):null,attestKeyID=extra.includes('attestKeyID')?decode(p.attestKeyID,1,64):null,assertion=extra.includes('assertion')?decode(p.assertion,1,1024):null;if(!nonce||!signature||(extra.includes('attestation')&&(!attestation||!attestKeyID))||(extra.includes('assertion')&&!assertion))return null;proof={challengeID:p.challengeID,nonce,signature,attestation,attestKeyID,assertion};}
 return {operation,actionBytes,actionSHA256:sha256(actionBytes),requestID:a.requestID,publicKey,displayName:a.displayName as string??null,activationID:a.activationID as string??null,releaseActivationID:a.releaseActivationID as string??null,expectedRevision:a.expectedRevision as number??null,caseID:a.caseID as string??null,caseDigest:a.caseDigest as string??null,proof};
 }catch{return null;}
}
export async function possessionMessage(actionBytes:Uint8Array,context:PossessionContext):Promise<Uint8Array|null> {
 try{const c=context;if(!closed(c,['accountID','activationID','operation','publicKey','nonce','expiresAt'])||!isID(c.accountID)||![1,2,3,4,5].includes(c.operation)||!validPublicKey(c.publicKey)||!(c.nonce instanceof Uint8Array)||c.nonce.length!==32||!isTime(c.expiresAt)||(c.operation<=2?c.activationID!==null:!isActivationID(c.activationID)))return null;
 const b=new Uint8Array(164);b.set(new TextEncoder().encode('im.patched.device-proof.v1\0'));b[27]=c.operation;b.set(unhex(c.accountID),28);if(c.activationID)b.set(unhex(c.activationID),44);b.set(unhex(sha256(c.publicKey)),60);b.set(c.nonce,92);b.set(unhex(sha256(actionBytes)),124);new DataView(b.buffer).setBigUint64(156,BigInt(c.expiresAt));return b;
 }catch{return null;}
}
export async function verifyPossession(actionBytes:Uint8Array,proof:DeviceProof,context:PossessionContext,now:number,verifier?:SyntheticP256Verifier):Promise<boolean> {
 try{if(!isTime(now)||!isTime(context.expiresAt)||context.expiresAt<=now||context.expiresAt>now+300||!verifier||verifier.marker!=='PAT-2644-synthetic'||!validPublicKey(context.publicKey)||!(proof.signature instanceof Uint8Array)||proof.signature.length!==64||hex(proof.nonce)!==hex(context.nonce))return false;const n=0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n,r=BigInt('0x'+hex(proof.signature.slice(0,32))),s=BigInt('0x'+hex(proof.signature.slice(32)));if(r<=0||s<=0||r>=n||s>=n)return false;const message=await possessionMessage(actionBytes,context);return !!message&&await verifier.verify(context.publicKey,message,proof.signature)===true;}catch{return false;}
}
