import {inspectSchema,terminalSessionCondition,type AuthorizationScope,type AuthorizedPrincipal} from './sessionAuthorization';
import type { FixtureEnvironment } from './environment';

// Explicit synthetic local proof only. No productive credential adapters.
export type Purpose = 'app-sign-in' | 'web-sign-in' | 'app-reauth' | 'web-reauth' | 'email-recovery';
export interface SessionBinding { accountID: string; sessionID: string; }
export interface CodeRequest { email: string; purpose: Purpose; sourceIP: string; binding?: SessionBinding; }
export interface CodeConsume { challengeID: string; purpose: Purpose; code: string; binding?: SessionBinding; }
export interface SessionCredential { sessionID: string; accessToken: string; }
export interface RefreshCredential { sessionID: string; refreshToken: string; }
export interface AccountMutation { accountID: string; expectedRevision: number; nonce: string; failAudit?: boolean; failDependency?: boolean; }
export type AuthBody = { outcome: 'refused' | 'reauthenticated' | 'logged-out' } |
  { outcome: 'accepted'; challengeID: string } |
  { outcome: 'signed-in'; accountID: string; sessionID: string; accessToken: string; accessExpiresAt: number; expiresAt: number; refreshToken?: string } |
  { outcome: 'rotated'; accessToken: string; refreshToken: string; accessExpiresAt: number; expiresAt: number } |
  { outcome: 'authenticated'; accountID: string } |
  { outcome: 'committed'; accountRevision: number };
export interface AuthResult { status: 200 | 202 | 400 | 401 | 409 | 429 | 503; body: AuthBody; }
export interface AuthDependencies { requiredSessionKind?:'web'; db: D1Database; now: () => number; randomBytes: (length: number) => Uint8Array; syntheticKey: Uint8Array; delivery: (email: string, code: string) => Promise<void>; }
import { syntheticRecipient } from './email';
const MAX_TIME = 253402300799;
const idPattern = /^[a-f0-9]{32}$/;
function isID(value: unknown): value is string { return typeof value === 'string' && idPattern.test(value); }
const tokenPattern = /^[a-f0-9]{64}$/;
const purposes = ['app-sign-in','web-sign-in','app-reauth','web-reauth'];
function clock(n: number): boolean { return Number.isSafeInteger(n) && n >= 0 && n <= MAX_TIME; }
function deadline(n: number, delta: number): number { if (!clock(n) || !clock(n + delta)) throw new Error('clock refused'); return n + delta; }
function hex(bytes: Uint8Array): string { return Array.from(bytes, b => b.toString(16).padStart(2,'0')).join(''); }
function closed(value: unknown, required: string[], optional: string[] = []): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value) && required.every(k => Object.hasOwn(value,k)) && Object.keys(value).every(k => [...required,...optional].includes(k));
}
function bindingOK(b: unknown): b is SessionBinding { return closed(b,['accountID','sessionID']) && isID(b.accountID) && isID(b.sessionID); }
function purposeOK(p: unknown): p is Purpose { return typeof p === 'string' && purposes.includes(p); }
function boundInput(x: Record<string,unknown>): boolean { return String(x.purpose).endsWith('reauth') ? bindingOK(x.binding) : x.binding === undefined; }
function ipv4(ip: unknown): boolean { return typeof ip === 'string' && ip.split('.').length === 4 && ip.split('.').every(p => /^(0|[1-9][0-9]{0,2})$/.test(p) && Number(p) <= 255); }
function requestOK(x: unknown): x is CodeRequest { return closed(x,['email','purpose','sourceIP'],['binding']) && normalizeEmail(x.email) !== null && purposeOK(x.purpose) && ipv4(x.sourceIP) && boundInput(x); }
function consumeOK(x: unknown): x is CodeConsume { return closed(x,['challengeID','purpose','code'],['binding']) && isID(x.challengeID) && purposeOK(x.purpose) && typeof x.code === 'string' && /^[0-9]{8}$/.test(x.code) && boundInput(x); }
function credentialOK(x: unknown, field: string): boolean { return closed(x,['sessionID',field]) && isID(x.sessionID) && typeof x[field] === 'string' && tokenPattern.test(x[field]); }
function mutationOK(x: unknown): x is AccountMutation { return closed(x,['accountID','expectedRevision','nonce'],['failAudit','failDependency']) && isID(x.accountID) && Number.isSafeInteger(x.expectedRevision) && Number(x.expectedRevision) >= 0 && Number(x.expectedRevision) < Number.MAX_SAFE_INTEGER && typeof x.nonce === 'string' && /^[a-zA-Z0-9-]{1,64}$/.test(x.nonce) && ['failAudit','failDependency'].every(k => x[k] === undefined || typeof x[k] === 'boolean'); }
function refused(status: AuthResult['status'] = 401): AuthResult { return {status,body:{outcome:'refused'}}; }
// Exact-length comparison avoids an early return for a mismatched digest character.
function equalDigest(a: string, b: string): boolean { let difference = a.length ^ b.length; for (let i=0;i<64;i++) difference |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0); return difference === 0; }
export function fixtureRandom(seed: string): ((length: number) => Uint8Array) | null {
  if (!/^[a-f0-9]{32}$/.test(seed)) return null;
  const seedBytes = Uint8Array.from(seed.match(/../g)!, b=>parseInt(b,16)); let offset=0;
  return length => { if (!Number.isSafeInteger(length) || length < 0 || offset+length > 4096) throw new Error('fixture randomness refused'); const out = new Uint8Array(length); for(let j=0;j<length;j++,offset++) out[j]=seedBytes[offset%16] ^ (offset%256) ^ Math.floor(offset/16); return out; };
}
export function normalizeEmail(input: unknown): string | null {
  if (typeof input !== 'string') return null;
  const value=input.replace(/^[\x09-\x0d\x20]+|[\x09-\x0d\x20]+$/g,'');
  return value.length <= 254 && /^[\x21-\x7e]+@[\x21-\x7e]+$/.test(value) && value.split('@').length === 2 ? value.toLowerCase() : null;
}
export function generateCode(bytes: (length: number) => Uint8Array): string | null {
  try { let result=''; for(let i=0;i<4096 && result.length<8;i++) { const sample=bytes(1); if (!(sample instanceof Uint8Array) || sample.length !== 1) return null; if(sample[0]<250) result+=String(sample[0]%10); } return result.length===8?result:null; } catch { return null; }
}
export async function keyedDigest(key: Uint8Array, domain: 'otp' | 'access' | 'refresh' | 'email' | 'ip', parts: readonly string[]): Promise<string | null> {
  try { if (!(key instanceof Uint8Array) || key.length !== 32 || !['otp','access','refresh','email','ip'].includes(domain) || parts.some(p=>typeof p !== 'string' || p.includes('\0'))) return null; const imported=await crypto.subtle.importKey('raw',key as Uint8Array<ArrayBuffer>,{name:'HMAC',hash:'SHA-256'},false,['sign']); return hex(new Uint8Array(await crypto.subtle.sign('HMAC',imported,new TextEncoder().encode([`im.patched.${domain}.v1`,...parts].join('\0'))))); } catch { return null; }
}
type Row = Record<string, string | number | null>;
export class AuthService {
  private readonly requiredSessionKind: unknown;
  constructor(private readonly dependencies: AuthDependencies) { this.requiredSessionKind=dependencies?.requiredSessionKind; }
  private ready(): boolean { const d=this.dependencies; return (this.requiredSessionKind===undefined||this.requiredSessionKind==='web') && !!d && !!d.db && typeof d.now==='function' && typeof d.randomBytes==='function' && d.syntheticKey instanceof Uint8Array && d.syntheticKey.length===32 && typeof d.delivery==='function'; }
  private random(n: number): string { const b=this.dependencies.randomBytes(n); if (!(b instanceof Uint8Array) || b.length!==n) throw new Error('randomness refused'); return hex(b); }
  private async digest(domain: 'otp'|'access'|'refresh'|'email'|'ip', parts: string[]): Promise<string> { const h=await keyedDigest(this.dependencies.syntheticKey,domain,parts); if(!h) throw new Error('digest refused'); return h; }
  private statement(sql: string, ...args: (string|number|null)[]): D1PreparedStatement { return this.dependencies.db.prepare(sql).bind(...args); }
  private requireWinner(): D1PreparedStatement { return this.statement("INSERT INTO account_audit SELECT NULL,NULL,'required',0,'refused',0 WHERE changes()<>1"); }
  private async row(sql: string,...args:(string|number|null)[]): Promise<Row|null> { return this.statement(sql,...args).first<Row>(); }
  async requestCode(input: CodeRequest): Promise<AuthResult> {
    if(!this.ready()) return refused(503); if(!requestOK(input)) return refused(400);
    let challengeID: string; try { challengeID=this.random(16); } catch { return refused(503); }
    const accepted: AuthResult={status:202,body:{outcome:'accepted',challengeID}};
    try {
      const now=this.dependencies.now(), expires=deadline(now,600), email=normalizeEmail(input.email)!;
      const eh=await this.digest('email',[email]), ih=await this.digest('ip',[input.sourceIP]);
      const code=generateCode(this.dependencies.randomBytes); if(!code) return accepted;
      const ch=await this.digest('otp',[challengeID,input.purpose,code]);
      const terminal=terminalSessionCondition(await inspectSchema(this.dependencies.db),{kind:'ordinary'});if(!terminal)return accepted;
      const reauth=input.purpose.endsWith('reauth');
      const target={sql:`EXISTS(SELECT 1 FROM sessions s JOIN accounts a ON a.account_id=s.account_id WHERE s.session_id=? AND s.account_id=? AND s.kind=? AND s.revoked_at IS NULL AND a.revoked_at IS NULL AND s.expires_at>? AND s.created_at<=? AND a.email_hmac=? AND (${terminal.sql}))`,args:[input.binding?.sessionID??null,input.binding?.accountID??null,input.purpose.startsWith('app')?'app':'web',now,now,eh,...terminal.args]};
      if(reauth&&!await this.row(`SELECT 1 AS valid WHERE ${target.sql}`,...target.args))return accepted;

      // The first statement reserves the IP request and its email send quota against
      // primary rows within the same batch. All later writes require that reservation.
      const results=await this.dependencies.db.batch([
        this.statement(`INSERT INTO request_limits SELECT ?,?,?,?,CASE WHEN
          (SELECT COUNT(*) FROM request_limits WHERE email_hmac=? AND sent=1 AND requested_at>?)<1 AND
          (SELECT COUNT(*) FROM request_limits WHERE email_hmac=? AND sent=1 AND requested_at>?)<5 AND
          (SELECT COUNT(*) FROM request_limits WHERE email_hmac=? AND sent=1 AND requested_at>?)<20 THEN 1 ELSE 0 END
          WHERE (SELECT COUNT(*) FROM request_limits WHERE ip_hmac=? AND requested_at>?)<30 AND
          (SELECT COUNT(*) FROM request_limits WHERE ip_hmac=? AND requested_at>?)<100 AND ${reauth?target.sql:'1'}`,challengeID,eh,ih,now,eh,now-60,eh,now-3600,eh,now-86400,ih,now-3600,ih,now-86400,...(reauth?target.args:[])),
        this.statement(`UPDATE challenges SET superseded_at=-1 WHERE email_hmac=? AND purpose=? AND consumed_at IS NULL AND EXISTS(SELECT 1 FROM request_limits WHERE request_id=?)`,eh,input.purpose,challengeID),
        this.statement(`INSERT INTO challenges(challenge_id,email_hmac,purpose,code_hmac,created_at,expires_at,superseded_at,bound_account_id,bound_session_id)
          SELECT ?,?,?,?,?,?,CASE WHEN sent=1 THEN ? ELSE -1 END,?,? FROM request_limits WHERE request_id=?`,challengeID,eh,input.purpose,ch,now,expires,now,input.binding?.accountID??null,input.binding?.sessionID??null,challengeID),
      ]);
      if(results[0].meta.changes!==1) return refused(429);
      const reservation=await this.row('SELECT sent FROM request_limits WHERE request_id=?',challengeID);
      if(reservation?.sent===1 && syntheticRecipient(email)) {
        try { await this.dependencies.delivery(email,code);
          // A later replacement stamps -1, so delayed delivery cannot revive it.
          await this.statement(`UPDATE challenges SET superseded_at=NULL WHERE challenge_id=? AND superseded_at=? AND ${reauth?target.sql:'1'}`,challengeID,now,...(reauth?target.args:[])).run();
        } catch { /* Pending challenge stays unusable; no delivery outcome is exposed. */ }
      }
    } catch (error) {
      // Only a primary-key collision of the freshly supplied entropy is distinct.
      // The batch has rolled back: never return an older usable challenge ID.
      // Match the observed local D1 error and cause, not arbitrary database errors.
      const constraints = ['request_limits.request_id','challenges.challenge_id'].map(column =>
        `UNIQUE constraint failed: ${column}: SQLITE_CONSTRAINT (extended: SQLITE_CONSTRAINT_PRIMARYKEY)`);
      if (error instanceof Error && error.cause instanceof Error && constraints.some(constraint =>
        error.message === `D1_ERROR: ${constraint}` && (error.cause as Error).message === constraint)) return refused(503);
      // All other database and delivery failures retain the generic request shape.
    }
    return accepted;
  }
  async consume(input: CodeConsume): Promise<AuthResult> {
    if(!this.ready()) return refused(503); if(!consumeOK(input)) return refused(400);
    try {
      const now=this.dependencies.now(); if(!clock(now)) return refused();
      const challenge=await this.row('SELECT * FROM challenges WHERE challenge_id=?',input.challengeID);
      if(!challenge || challenge.purpose!==input.purpose || challenge.superseded_at!==null || challenge.consumed_at!==null || Number(challenge.created_at)>now || Number(challenge.expires_at)<=now || Number(challenge.wrong_attempts)>=5 || (challenge.bound_account_id??null)!==(input.binding?.accountID??null) || (challenge.bound_session_id??null)!==(input.binding?.sessionID??null)) return refused();
      const digest=await this.digest('otp',[input.challengeID,input.purpose,input.code]);
      if(!equalDigest(String(challenge.code_hmac),digest)) {
        await this.statement(`UPDATE challenges SET wrong_attempts=wrong_attempts+1 WHERE challenge_id=? AND purpose=? AND consumed_at IS NULL AND superseded_at IS NULL AND wrong_attempts<5 AND expires_at>?`,input.challengeID,input.purpose,now).run(); return refused();
      }
      const nonce=this.random(16), reauth=input.purpose.endsWith('reauth'), kind=input.purpose.startsWith('app')?'app':'web';
      const terminal=terminalSessionCondition(await inspectSchema(this.dependencies.db),{kind:'ordinary'});if(!terminal)return refused();
      const fence='SELECT 1 FROM challenges WHERE challenge_id=? AND consume_nonce=?';
      const statements: D1PreparedStatement[]=[];
      // The fresh nonce cannot match an old stamp anywhere, even on another account.
      statements.push(this.statement(`UPDATE challenges SET consumed_at=?,consume_nonce=? WHERE challenge_id=? AND purpose=? AND code_hmac=? AND consumed_at IS NULL AND superseded_at IS NULL AND wrong_attempts<5 AND created_at<=? AND expires_at>?
        AND NOT EXISTS(SELECT 1 FROM challenges WHERE consume_nonce=?) AND NOT EXISTS(SELECT 1 FROM account_audit WHERE commit_nonce=?)
        AND ${reauth ? `bound_account_id=? AND bound_session_id=? AND EXISTS(SELECT 1 FROM sessions s JOIN accounts a ON a.account_id=s.account_id WHERE s.session_id=? AND s.account_id=? AND s.kind=? AND s.revoked_at IS NULL AND a.revoked_at IS NULL AND s.expires_at>? AND s.created_at<=? AND a.email_hmac=challenges.email_hmac AND (${terminal.sql}))` : `bound_account_id IS NULL AND bound_session_id IS NULL AND NOT EXISTS(SELECT 1 FROM accounts WHERE email_hmac=challenges.email_hmac AND revoked_at IS NOT NULL)`}`,
        now,nonce,input.challengeID,input.purpose,digest,now,now,nonce,nonce,...(reauth?[input.binding!.accountID,input.binding!.sessionID,input.binding!.sessionID,input.binding!.accountID,kind,now,now,...terminal.args]:[])));
      let accountID='',sessionID='',accessToken='',refreshToken='',accessExpiresAt=0,expiresAt=0;
      if(!reauth) {
        accountID=this.random(16); sessionID=this.random(16); accessToken=this.random(32); if(kind==='app') refreshToken=this.random(32);
        accessExpiresAt=deadline(now,kind==='app'?900:43200); expiresAt=deadline(now,kind==='app'?90*86400:43200);
        const ah=await this.digest('access',[accessToken]), rh=refreshToken?await this.digest('refresh',[refreshToken]):null;
        statements.push(this.statement(`INSERT INTO accounts(account_id,email_hmac,created_at) SELECT ?,email_hmac,? FROM challenges WHERE challenge_id=? AND consume_nonce=? AND NOT EXISTS(SELECT 1 FROM accounts WHERE email_hmac=challenges.email_hmac)`,accountID,now,input.challengeID,nonce));
        statements.push(this.statement(`INSERT INTO account_guard SELECT a.account_id,1,? FROM accounts a JOIN challenges c ON c.email_hmac=a.email_hmac WHERE c.challenge_id=? AND c.consume_nonce=? ON CONFLICT(account_id) DO UPDATE SET account_revision=account_revision+1,commit_nonce=excluded.commit_nonce`,nonce,input.challengeID,nonce));
        statements.push(this.statement(`INSERT INTO sessions(session_id,account_id,kind,authenticated_at,created_at,access_hmac,access_expires_at,refresh_hmac,refresh_expires_at,expires_at,commit_nonce)
          SELECT ?,a.account_id,?,?,?,?,?,?,?,?,? FROM accounts a JOIN challenges c ON c.email_hmac=a.email_hmac WHERE c.challenge_id=? AND c.consume_nonce=?`,sessionID,kind,now,now,ah,accessExpiresAt,rh,kind==='app'?expiresAt:null,expiresAt,nonce,input.challengeID,nonce));
      } else {
        statements.push(this.statement(`UPDATE account_guard SET account_revision=account_revision+1,commit_nonce=? WHERE account_id=? AND EXISTS(${fence})`,nonce,input.binding!.accountID,input.challengeID,nonce));
        statements.push(this.statement(`UPDATE sessions SET authenticated_at=?,commit_nonce=? WHERE session_id=? AND account_id=? AND EXISTS(${fence})`,now,nonce,input.binding!.sessionID,input.binding!.accountID,input.challengeID,nonce));
      }
      statements.push(this.statement(`INSERT INTO account_audit SELECT ?,g.account_id,?,g.account_revision,?,? FROM account_guard g JOIN challenges c ON c.email_hmac=(SELECT email_hmac FROM accounts WHERE account_id=g.account_id) WHERE c.challenge_id=? AND c.consume_nonce=? AND g.commit_nonce=?`,nonce,reauth?'reauth':'sign-in',nonce,now,input.challengeID,nonce,nonce));
      // Force a constraint failure if a consumed challenge lacks any required write.
      statements.push(this.statement(`INSERT INTO account_audit(audit_id,account_id,action,account_revision,commit_nonce,created_at) SELECT NULL,NULL,'required',0,?,? WHERE EXISTS(${fence}) AND (NOT EXISTS(SELECT 1 FROM sessions WHERE session_id=? AND commit_nonce=?) OR NOT EXISTS(SELECT 1 FROM account_audit WHERE audit_id=?))`,nonce,now,input.challengeID,nonce,reauth?input.binding!.sessionID:sessionID,nonce,nonce));
      statements.splice(1,0,this.requireWinner());
      const results=await this.dependencies.db.batch(statements); if(results[0].meta.changes!==1) return refused();
      if(reauth) return {status:200,body:{outcome:'reauthenticated'}};
      const s=await this.row('SELECT account_id FROM sessions WHERE session_id=? AND commit_nonce=?',sessionID,nonce); if(!s) return refused();
      return {status:200,body:{outcome:'signed-in',accountID:String(s.account_id),sessionID,accessToken,accessExpiresAt,expiresAt,...(refreshToken?{refreshToken}:{})}};
    } catch { return refused(); }
  }
  async refresh(input: RefreshCredential): Promise<AuthResult> {
    if(!this.ready()) return refused(503); if(!credentialOK(input,'refreshToken')) return refused(400);
    try {
      const now=this.dependencies.now(), accessExpiresAt=deadline(now,900), expiresAt=deadline(now,90*86400);
      const old=await this.digest('refresh',[input.refreshToken]);
      const historical=await this.row('SELECT session_id FROM used_refresh_tokens WHERE refresh_hmac=? AND session_id=?',old,input.sessionID);
      if(historical) { await this.revoke(input.sessionID,now,old,true); return refused(); }
      const nonce=this.random(16), accessToken=this.random(32), refreshToken=this.random(32);
      const ah=await this.digest('access',[accessToken]), rh=await this.digest('refresh',[refreshToken]);
      const fence='SELECT 1 FROM sessions WHERE session_id=? AND commit_nonce=?';
      const result=await this.dependencies.db.batch([
        this.statement(`UPDATE sessions SET access_hmac=?,access_expires_at=?,refresh_hmac=?,refresh_expires_at=?,expires_at=?,commit_nonce=? WHERE session_id=? AND kind='app' AND refresh_hmac=? AND revoked_at IS NULL AND refresh_expires_at>? AND expires_at>? AND created_at<=?
          AND EXISTS(SELECT 1 FROM accounts WHERE account_id=sessions.account_id AND revoked_at IS NULL)
          AND NOT EXISTS(SELECT 1 FROM account_audit WHERE commit_nonce=?) AND NOT EXISTS(SELECT 1 FROM challenges WHERE consume_nonce=?)
          AND NOT EXISTS(SELECT 1 FROM used_refresh_tokens WHERE refresh_hmac=?)`,ah,accessExpiresAt,rh,expiresAt,expiresAt,nonce,input.sessionID,old,now,now,now,nonce,nonce,rh),
        this.requireWinner(),
        this.statement(`INSERT INTO used_refresh_tokens SELECT ?,session_id,? FROM sessions WHERE session_id=? AND commit_nonce=?`,old,now,input.sessionID,nonce),
        this.statement(`UPDATE account_guard SET account_revision=account_revision+1,commit_nonce=? WHERE account_id=(SELECT account_id FROM sessions WHERE session_id=? AND commit_nonce=?)`,nonce,input.sessionID,nonce),
        this.statement(`INSERT INTO account_audit SELECT ?,g.account_id,'refresh',g.account_revision,?,? FROM account_guard g WHERE g.commit_nonce=? AND EXISTS(${fence})`,nonce,nonce,now,nonce,input.sessionID,nonce),
        this.statement(`INSERT INTO account_audit SELECT NULL,NULL,'required',0,?,? WHERE EXISTS(${fence}) AND (NOT EXISTS(SELECT 1 FROM used_refresh_tokens WHERE refresh_hmac=? AND session_id=?) OR NOT EXISTS(SELECT 1 FROM account_audit WHERE audit_id=?))`,nonce,now,input.sessionID,nonce,old,input.sessionID,nonce),
      ]);
      if(result[0].meta.changes!==1) {
        // A concurrent winner has now put the submitted HMAC into history.
        await this.revoke(input.sessionID,now,old,true); return refused();
      }
      return {status:200,body:{outcome:'rotated',accessToken,refreshToken,accessExpiresAt,expiresAt}};
    } catch {
      try { const now=this.dependencies.now(); if(clock(now)) await this.revoke(input.sessionID,now,await this.digest('refresh',[input.refreshToken]),true); } catch { /* Audit failure never grants. */ }
      return refused();
    }
  }
  async authorize(input:SessionCredential,scope:AuthorizationScope):Promise<AuthorizedPrincipal|null> {
    if(!this.ready()||!credentialOK(input,'accessToken'))return null;
    try {const now=this.dependencies.now();if(!clock(now))return null;const terminal=terminalSessionCondition(await inspectSchema(this.dependencies.db),scope);if(!terminal)return null;
      const digest=await this.digest('access',[input.accessToken]);
      const predicate={sql:`s.session_id=? AND s.access_hmac=? AND s.revoked_at IS NULL AND a.revoked_at IS NULL AND s.access_expires_at>? AND s.expires_at>? AND s.created_at<=? AND s.authenticated_at<=? AND (${terminal.sql})`,args:[input.sessionID,digest,now,now,now,now,...terminal.args]};
      const row=await this.row(`SELECT s.* FROM sessions s JOIN accounts a ON a.account_id=s.account_id WHERE ${predicate.sql}`,...predicate.args);
      if(!row||!isID(row.account_id)||!['app','web'].includes(String(row.kind))||!clock(Number(row.authenticated_at)))return null;
      if(this.requiredSessionKind==='web') {
        const fields=['session_id','account_id','kind','activation_id','authenticated_at','created_at','access_hmac','access_expires_at','refresh_hmac','refresh_expires_at','expires_at','revoked_at','commit_nonce'];
        if(row.kind!=='web'||row.activation_id!==null||row.refresh_hmac!==null||row.refresh_expires_at!==null||row.revoked_at!==null||!clock(row.created_at as number)||!clock(row.expires_at as number)||!clock(row.authenticated_at as number)||Number(row.created_at)>now||Number(row.authenticated_at)<Number(row.created_at)||Number(row.authenticated_at)>now||row.access_expires_at!==row.expires_at||Number(row.expires_at)!==Number(row.created_at)+43200||!tokenPattern.test(String(row.access_hmac))||!isID(row.commit_nonce))return null;
        return {accountID:String(row.account_id),sessionID:input.sessionID,kind:'web',activationID:null,authenticatedAt:Number(row.authenticated_at),condition:{sql:`EXISTS(SELECT 1 FROM sessions s JOIN accounts a ON a.account_id=s.account_id WHERE ${predicate.sql} AND ${fields.map(k=>`s.${k} IS ?`).join(' AND ')})`,args:[...predicate.args,...fields.map(k=>row[k])]}};
      }
      return {accountID:String(row.account_id),sessionID:input.sessionID,kind:row.kind as 'app'|'web',activationID:row.activation_id as string|null,authenticatedAt:Number(row.authenticated_at),condition:{sql:`EXISTS(SELECT 1 FROM sessions s JOIN accounts a ON a.account_id=s.account_id WHERE ${predicate.sql} AND s.account_id=? AND s.kind=? AND s.activation_id IS ? AND s.authenticated_at=?)`,args:[...predicate.args,String(row.account_id),String(row.kind),row.activation_id,Number(row.authenticated_at)]}};
    }catch{return null;}
  }
  async authenticate(input: SessionCredential): Promise<AuthResult> {
    if(!this.ready())return refused(503);if(!credentialOK(input,'accessToken'))return refused(400);
    const principal=await this.authorize(input,{kind:'ordinary'});return principal?{status:200,body:{outcome:'authenticated',accountID:principal.accountID}}:refused();
  }
  // Revocation and required audit share the same transaction and account guard.
  private async revoke(sessionID: string, now: number, digest: string, replay: boolean, principal?:AuthorizedPrincipal): Promise<boolean> {
    // Replay revocation has a domain-bound deterministic audit ID, so broken
    // credential entropy cannot prevent revoking a proven historical replay.
    const nonce=replay?await this.digest('refresh',['replay-revocation',sessionID,digest]):this.random(16), fence='SELECT 1 FROM sessions WHERE session_id=? AND commit_nonce=?';
    const result=await this.dependencies.db.batch([
      this.statement(`UPDATE sessions SET revoked_at=?,commit_nonce=? WHERE session_id=? AND revoked_at IS NULL AND created_at<=? AND
        ${replay?'EXISTS(SELECT 1 FROM used_refresh_tokens WHERE session_id=sessions.session_id AND refresh_hmac=?)':'access_hmac=? AND access_expires_at>? AND expires_at>?'}
        AND NOT EXISTS(SELECT 1 FROM account_audit WHERE commit_nonce=?) AND NOT EXISTS(SELECT 1 FROM challenges WHERE consume_nonce=?) ${principal?'AND ('+principal.condition.sql+')':''}`,now,nonce,sessionID,now,digest,...(replay?[]:[now,now]),nonce,nonce,...(principal?.condition.args??[])),
      this.requireWinner(),
      this.statement(`UPDATE account_guard SET account_revision=account_revision+1,commit_nonce=? WHERE account_id=(SELECT account_id FROM sessions WHERE session_id=? AND commit_nonce=?)`,nonce,sessionID,nonce),
      this.statement(`INSERT INTO account_audit SELECT ?,account_id,'logout',account_revision,?,? FROM account_guard WHERE commit_nonce=? AND EXISTS(${fence})`,nonce,nonce,now,nonce,sessionID,nonce),
      this.statement(`INSERT INTO account_audit SELECT NULL,NULL,'required',0,?,? WHERE EXISTS(${fence}) AND NOT EXISTS(SELECT 1 FROM account_audit WHERE audit_id=?)`,nonce,now,sessionID,nonce,nonce),
      // An audit INSERT trigger can also ignore the invalid-row sentinel above.
      // Assert the narrowed web logout's required rows without another write;
      // json('') raises inside this same batch so every prior effect rolls back.
      ...(this.requiredSessionKind==='web'&&!replay?[this.statement(`SELECT CASE WHEN EXISTS(
        SELECT 1 FROM sessions s JOIN account_guard g ON g.account_id=s.account_id
        JOIN account_audit a ON a.account_id=g.account_id AND a.account_revision=g.account_revision
        WHERE s.session_id=? AND s.commit_nonce=? AND s.revoked_at=? AND g.commit_nonce=?
        AND a.audit_id=? AND a.commit_nonce=? AND a.action='logout' AND a.created_at=?
      ) THEN 1 ELSE json('') END AS required_logout`,sessionID,nonce,now,nonce,nonce,nonce,now)]:[]),
    ]);
    return result[0].meta.changes===1;
  }
  async logout(input: SessionCredential): Promise<AuthResult> {
    if(!this.ready()) return refused(503); if(!credentialOK(input,'accessToken')) return refused(400);
    try { const now=this.dependencies.now(); if(!clock(now)) return refused(); const principal=this.requiredSessionKind==='web'?await new AuthService({...this.dependencies,requiredSessionKind:'web',now:()=>now}).authorize(input,{kind:'ordinary'}):undefined;if(this.requiredSessionKind==='web'&&!principal)return refused(); return await this.revoke(input.sessionID,now,await this.digest('access',[input.accessToken]),false,principal??undefined)?{status:200,body:{outcome:'logged-out'}}:refused(); } catch { return refused(); }
  }
  async mutateAccount(input: AccountMutation): Promise<AuthResult> {
    if(!this.ready()) return refused(503); if(!mutationOK(input)) return refused(400);
    try {
      const now=this.dependencies.now(); if(!clock(now)) return refused(409);
      const fence='SELECT 1 FROM account_guard WHERE account_id=? AND account_revision=? AND commit_nonce=?';
      const args=[input.accountID,input.expectedRevision+1,input.nonce] as const;
      const requestHash=await this.digest('access',['fixture-account-mutation',input.accountID,String(input.expectedRevision),input.nonce]);
      const schema=await inspectSchema(this.dependencies.db);if(schema.kind==='unsupported')return refused(409);const noA2=schema.kind==='a2'?'NOT EXISTS(SELECT 1 FROM activations WHERE account_id=account_guard.account_id)':'1';
      const result=await this.dependencies.db.batch([
        this.statement(`UPDATE account_guard SET account_revision=account_revision+1,commit_nonce=? WHERE account_id=? AND account_revision=? AND NOT EXISTS(SELECT 1 FROM account_audit WHERE commit_nonce=?) AND NOT EXISTS(SELECT 1 FROM challenges WHERE consume_nonce=?) AND EXISTS(SELECT 1 FROM accounts WHERE account_id=account_guard.account_id AND revoked_at IS NULL) AND ${noA2}`,input.nonce,input.accountID,input.expectedRevision,input.nonce,input.nonce),
        this.requireWinner(),
        this.statement(`INSERT INTO account_requests SELECT account_id,'fixture-mutate',?, ?,? FROM account_guard WHERE EXISTS(${fence}) AND account_id=?`,input.nonce,requestHash,input.nonce,...args,input.accountID),
        this.statement(`INSERT INTO account_audit SELECT ?,account_id,'account-mutation',account_revision,?,? FROM account_guard WHERE EXISTS(${fence}) AND account_id=?`,input.nonce,input.nonce,now,...args,input.accountID),
        // The explicit failure seams are fixture-only internal writer controls.
        this.statement(`INSERT INTO account_audit SELECT NULL,NULL,'required',0,?,? WHERE EXISTS(${fence}) AND (?=1 OR ?=1 OR NOT EXISTS(SELECT 1 FROM account_requests WHERE account_id=? AND request_id=?) OR NOT EXISTS(SELECT 1 FROM account_audit WHERE audit_id=?))`,input.nonce,now,...args,input.failAudit?1:0,input.failDependency?1:0,input.accountID,input.nonce,input.nonce),
      ]);
      return result[0].meta.changes===1?{status:200,body:{outcome:'committed',accountRevision:input.expectedRevision+1}}:refused(409);
    } catch { return refused(409); }
  }
}
// A bounded recursive parser rejects duplicate object keys after escape decoding.
// It has no reviver or executable input. Depth is independently bounded.
function strictJSON(source: string): unknown {
  let i=0;
  const whitespace=()=>{while(/[\x20\x09\x0a\x0d]/.test(source[i]??'!')) i++;};
  const string=():string=>{const start=i++;while(i<source.length){const c=source[i++];if(c==='"') return JSON.parse(source.slice(start,i)) as string;if(c==='\\')i++;}throw new Error('string refused');};
  const value=(depth:number):unknown=>{
    if(depth>32)throw new Error('depth refused');whitespace();const c=source[i];
    if(c==='"')return string();
    if(c==='{'){i++;whitespace();const out:Record<string,unknown>=Object.create(null);const names=new Set<string>();if(source[i]==='}'){i++;return out;}while(true){whitespace();if(source[i]!=='"')throw new Error('key refused');const key=string();if(names.has(key))throw new Error('duplicate refused');names.add(key);whitespace();if(source[i++]!==':')throw new Error('colon refused');out[key]=value(depth+1);whitespace();const end=source[i++];if(end==='}')return out;if(end!==',')throw new Error('object refused');}}
    if(c==='['){i++;whitespace();const out:unknown[]=[];if(source[i]===']'){i++;return out;}while(true){out.push(value(depth+1));whitespace();const end=source[i++];if(end===']')return out;if(end!==',')throw new Error('array refused');}}
    const match=source.slice(i).match(/^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/);if(!match)throw new Error('value refused');i+=match[0].length;return JSON.parse(match[0]);
  };
  const parsed=value(0);whitespace();if(i!==source.length)throw new Error('trailing refused');return parsed;
}
export async function fixtureAuthFetch(request: Request, env: FixtureEnvironment): Promise<Response> {
  const response=(status:number,body:unknown)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
  const failure=(status:number)=>response(status,{outcome:'refused'});
  const route=new URL(request.url).pathname.slice('/__fixture/accounts/'.length);
  if(!['request','consume','refresh','authenticate','logout','mutate'].includes(route))return failure(404);
  if(request.method!=='POST')return failure(405);
  const seed=request.headers.get('x-fixture-seed')??'',rng=fixtureRandom(seed),rawNow=request.headers.get('x-fixture-now')??'',delivery=request.headers.get('x-fixture-delivery');
  if(env.ENVIRONMENT!=='local-fixture'||env.FIXTURE_MARKER!=='PAT-2639-local-only'||env.PROVIDER_MODE!=='fake'||!env.FIXTURE_DB||request.headers.get('x-fixture-key')!=='PAT-2642-synthetic'||!rng||!/^(0|[1-9][0-9]*)$/.test(rawNow)||!clock(Number(rawNow))||!['capture','refuse'].includes(delivery??''))return failure(503);
  let input:unknown;
  try {
    // Bound streamed bytes before decoding or parsing; Content-Length is untrusted.
    const reader=request.body?.getReader(); const chunks:Uint8Array[]=[];let size=0;
    if(reader)while(true){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>2048){await reader.cancel();return failure(413);}chunks.push(part.value);}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
    input=strictJSON(new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(bytes));
  }catch{return failure(400);}
  const valid=route==='request'?requestOK(input):route==='consume'?consumeOK(input):route==='mutate'?mutationOK(input):credentialOK(input,route==='refresh'?'refreshToken':'accessToken');
  if(!valid)return failure(400);
  // Separate synthetic code stream. Explicit seeded bytes provide IDs and tokens.
  let codeOffset=0;
  const service=new AuthService({db:env.FIXTURE_DB,now:()=>Number(rawNow),syntheticKey:new Uint8Array(32).fill(7),randomBytes:length=>route==='request'&&length===1?Uint8Array.of(codeOffset++%8):rng(length),delivery:async(email,_code)=>{if(delivery!=='capture'||!syntheticRecipient(email))throw new Error('delivery refused');}});
  const result=route==='request'?await service.requestCode(input as unknown as CodeRequest):route==='consume'?await service.consume(input as unknown as CodeConsume):route==='refresh'?await service.refresh(input as unknown as RefreshCredential):route==='authenticate'?await service.authenticate(input as unknown as SessionCredential):route==='logout'?await service.logout(input as unknown as SessionCredential):await service.mutateAccount(input as unknown as AccountMutation);
  return response(result.status,result.body);
}
