/** Synthetic L1 producer. No default identity, clock or key custody. */
export type LeaseState = 'paid' | 'grace' | 'beta' | 'trial' | 'none' | 'expired' | 'revoked';
export interface LeaseClaims {
 schemaVersion: 1; issuer: 'im.patched.licence'; audience: 'im.patched.mac';
 accountID: string; activationID: string; deviceKeySHA256: string; state: LeaseState;
 entitlementRevision: number; activationRevision: number; sequence: number;
 issuedAt: number; permittedUntil: number; hardEnd: number;
 paid?: {paidThrough: number}; grace?: {paidThrough: number; graceDeadline: number};
 trial?: {startedAt: number; expiresAt: number};
}
export interface SyntheticSigner { marker: 'PAT-2643-synthetic'; keyID: 'fixture-only-1'; sign: (message: Uint8Array) => Promise<Uint8Array>; }
function exact(value: unknown, keys: string[]): value is Record<string,unknown> {
 return !!value && typeof value==='object' && !Array.isArray(value) && Reflect.ownKeys(value).length===keys.length && keys.every(k=>Object.hasOwn(value,k));
}
const integer=(n:unknown):n is number=>typeof n==='number' && Number.isSafeInteger(n) && n>=0;
function base64(bytes:Uint8Array):string {return btoa(Array.from(bytes,b=>String.fromCharCode(b)).join(''));}
export async function produceLease(claims: LeaseClaims, signer?: SyntheticSigner): Promise<Uint8Array | null> {
 try {
  if(!signer || signer.marker!=='PAT-2643-synthetic'||signer.keyID!=='fixture-only-1'||typeof signer.sign!=='function')return null;
  const c=claims, extra=['paid','grace','trial'].includes(c.state)?[c.state]:[];
  if(!exact(c,['schemaVersion','issuer','audience','accountID','activationID','deviceKeySHA256','state','entitlementRevision','activationRevision','sequence','issuedAt','permittedUntil','hardEnd',...extra]) || c.schemaVersion!==1||c.issuer!=='im.patched.licence'||c.audience!=='im.patched.mac'||!['paid','grace','beta','trial','none','expired','revoked'].includes(c.state)||!/^[a-f0-9]{32}$/.test(c.accountID)||!/^[a-f0-9]{32}$/.test(c.activationID)||!/^[a-f0-9]{64}$/.test(c.deviceKeySHA256))return null;
  if(![c.entitlementRevision,c.activationRevision,c.sequence].every(n=>integer(n)&&n>0)||![c.issuedAt,c.permittedUntil,c.hardEnd].every(integer))return null;
  const sum=(a:number,b:number)=>integer(a+b)?a+b:-1;
  if(['none','expired','revoked'].includes(c.state)){if(c.permittedUntil!==c.issuedAt||c.hardEnd!==c.issuedAt)return null;}
  else {
   if(c.issuedAt>=c.permittedUntil||c.permittedUntil>c.hardEnd)return null;
   if(c.state==='beta'&&(c.hardEnd!==c.permittedUntil||c.permittedUntil>sum(c.issuedAt,604800)))return null;
   if(c.state==='paid'&&(!exact(c.paid,['paidThrough'])||!integer(c.paid.paidThrough)||c.hardEnd!==c.paid.paidThrough||c.permittedUntil>Math.min(sum(c.issuedAt,2592000),c.paid.paidThrough)))return null;
   if(c.state==='grace'&&(!exact(c.grace,['paidThrough','graceDeadline'])||!integer(c.grace.paidThrough)||!integer(c.grace.graceDeadline)||c.grace.graceDeadline!==sum(c.grace.paidThrough,604800)||c.hardEnd!==c.grace.graceDeadline||c.permittedUntil>Math.min(sum(c.issuedAt,2592000),c.grace.graceDeadline)))return null;
   if(c.state==='trial'&&(!exact(c.trial,['startedAt','expiresAt'])||!integer(c.trial.startedAt)||!integer(c.trial.expiresAt)||c.trial.expiresAt!==sum(c.trial.startedAt,1209600)||c.hardEnd!==c.trial.expiresAt||c.trial.startedAt>c.issuedAt||c.issuedAt>=c.trial.expiresAt))return null;
  }
  const ordered={schemaVersion:c.schemaVersion,issuer:c.issuer,audience:c.audience,accountID:c.accountID,activationID:c.activationID,deviceKeySHA256:c.deviceKeySHA256,state:c.state,entitlementRevision:c.entitlementRevision,activationRevision:c.activationRevision,sequence:c.sequence,issuedAt:c.issuedAt,permittedUntil:c.permittedUntil,hardEnd:c.hardEnd,...(c.state==='paid'?{paid:{paidThrough:c.paid!.paidThrough}}:c.state==='grace'?{grace:{paidThrough:c.grace!.paidThrough,graceDeadline:c.grace!.graceDeadline}}:c.state==='trial'?{trial:{startedAt:c.trial!.startedAt,expiresAt:c.trial!.expiresAt}}:{})};
  const payload=new TextEncoder().encode(JSON.stringify(ordered));const domain=new TextEncoder().encode('im.patched.licence.v1\0');const message=new Uint8Array(domain.length+payload.length);message.set(domain);message.set(payload,domain.length);
  const signature=await signer.sign(message);if(!(signature instanceof Uint8Array)||signature.length!==64)return null;
  return new TextEncoder().encode(JSON.stringify({keyID:signer.keyID,payload:base64(payload),signature:base64(signature)}));
 }catch{return null;}
}
