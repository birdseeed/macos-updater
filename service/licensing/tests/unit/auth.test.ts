import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { AuthService, type AuthDependencies, fixtureRandom, generateCode, keyedDigest, normalizeEmail } from '../../src/auth';
import { denyOutboundDelivery, syntheticRecipient } from '../../src/email';
import { sendDecision } from '../../src/ratelimit';
import { validAudit } from '../../src/audit';
import { validGuard } from '../../src/store';
import worker from '../../src/index';
const fixtureHeaders = {'x-fixture-key':'PAT-2642-synthetic','x-fixture-now':'1791734400','x-fixture-delivery':'capture','x-fixture-seed':'0'.repeat(31)+'1'};
const marker = { ENVIRONMENT: 'local-fixture', FIXTURE_MARKER: 'PAT-2639-local-only', PROVIDER_MODE: 'fake' };
const deny = vi.fn(async () => { throw new Error('network denied'); });
beforeEach(() => { vi.stubGlobal('fetch', deny); });
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); deny.mockClear(); });
it.each([
 [' \tALICE+one@EXAMPLE.INVALID\r\n', 'alice+one@example.invalid'],
 ['a.b@example.invalid', 'a.b@example.invalid'], ['ab@example.invalid', 'ab@example.invalid'],
 [`${'a'.repeat(238)}@example.invalid`, `${'a'.repeat(238)}@example.invalid`],
])('normalizes ASCII whole-address without alias merging %s', (input, wanted) => expect(normalizeEmail(input)).toBe(wanted));
it.each([null, 1, {}, '', 'a', '@x', 'a@', 'a@@x', 'a b@x', 'a\0@x', 'a\n@x', 'á@x', '\u00a0a@x', `${'a'.repeat(239)}@example.invalid`])('refuses malformed email %j', input => expect(normalizeEmail(input)).toBeNull());
it('generates eight digits by rejection sampling rather than modulo bias', () => {
 let n = 0; const bytes = vi.fn((length: number) => Uint8Array.from({ length }, () => [250,251,252,253,254,255,0,249,1,248,2,247,3,246][n++ % 14]));
 expect(generateCode(bytes)).toBe('09182736'); expect(bytes).toHaveBeenCalled(); expect(deny).not.toHaveBeenCalled();
});
it('refuses unavailable/wrong-size randomness and never uses ambient randomness', () => {
 vi.spyOn(Math, 'random').mockImplementation(() => { throw new Error('ambient random denied'); });
 expect(generateCode(() => new Uint8Array())).toBeNull();
});
it('HMAC uses exact OTP domain and NUL separators', async () => {
 const key = new Uint8Array(32).fill(7);
 const imported = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
 const signed = await crypto.subtle.sign('HMAC', imported, new TextEncoder().encode(['im.patched.otp.v1','challenge','app-sign-in','00123456'].join('\0')));
 const expected = Array.from(new Uint8Array(signed), x => x.toString(16).padStart(2,'0')).join('');
 expect(await keyedDigest(key, 'otp', ['challenge','app-sign-in','00123456'])).toBe(expected);
});
it('HMAC domains and purpose/challenge/key bindings never collide', async () => {
 const key = new Uint8Array(32).fill(7);
 const values = await Promise.all((['otp','access','refresh','email','ip'] as const).map(domain => keyedDigest(key,domain,['a','b','c'])));
 expect(values.every(x => typeof x === 'string' && /^[a-f0-9]{64}$/.test(x))).toBe(true); expect(new Set(values).size).toBe(5);
 expect(await keyedDigest(key,'otp',['c','app-sign-in','12345678'])).not.toBe(await keyedDigest(key,'otp',['c','web-sign-in','12345678']));
 expect(await keyedDigest(key,'otp',['c','app-sign-in','12345678'])).not.toBe(await keyedDigest(new Uint8Array(32).fill(8),'otp',['c','app-sign-in','12345678']));
 expect(await keyedDigest(new Uint8Array(),'otp',['c'])).toBeNull();
});
const counts = { emailMinute:0, emailHour:0,emailDay:0,ipHour:0,ipDay:0 };
it('permits below all send ceilings', () => expect(sendDecision({emailMinute:0,emailHour:4,emailDay:19,ipHour:29,ipDay:99})).toBe('send'));
it.each(['emailMinute','emailHour','emailDay'] as const)('email ceiling suppresses delivery generically %s', field => expect(sendDecision({...counts,[field]:{emailMinute:1,emailHour:5,emailDay:20}[field]})).toBe('email-limited'));
it.each(['ipHour','ipDay'] as const)('IP ceiling is independent %s', field => expect(sendDecision({...counts,[field]:{ipHour:30,ipDay:100}[field]})).toBe('ip-limited'));
it.each([-1,0.5,NaN,Infinity])('refuses invalid limit counts %j', n => expect(sendDecision({...counts,emailMinute:n})).toBe('refused'));
it('IP refusal wins over email refusal', () => expect(sendDecision({...counts,emailMinute:1,ipHour:30})).toBe('ip-limited'));
it('fake delivery recipient accepts only exact synthetic invalid-domain addresses', () => {
 expect(syntheticRecipient('alice@example.invalid')).toBe(true);
 for (const email of ['andy@patched.im','a@example.invalid.evil','a@example.com','a\n@example.invalid']) expect(syntheticRecipient(email)).toBe(false);
});
it('outbound delivery always refuses without any transport', async () => {
 await expect(denyOutboundDelivery('alice@example.invalid','00123456')).rejects.toThrow('outbound delivery denied'); expect(deny).not.toHaveBeenCalled();
});
const audit = { accountID:'account-a',action:'sign-in',revision:1,nonce:'attempt-a',at:1791734400 };
it('accepts closed safe audit metadata', () => expect(validAudit(audit)).toBe(true));
it.each(['email','sourceIP','code','accessToken','refreshToken','sessionID','challengeID'])('audit rejects secret/identity detail field %s', field => expect(validAudit({...audit,[field]:'secret'})).toBe(false));
it('requires unique nonempty guard nonce and bounded revision', () => {
 expect(validGuard({accountID:'account-a',accountRevision:0,commitNonce:'attempt-a'})).toBe(true);
 for (const accountRevision of [-1,0.5,Number.MAX_SAFE_INTEGER+1]) expect(validGuard({accountID:'account-a',accountRevision,commitNonce:'attempt-a'})).toBe(false);
 expect(validGuard({accountID:'account-a',accountRevision:0,commitNonce:''})).toBe(false);
});
it.each(['request','consume','refresh','authenticate','logout','mutate'])('fixture account routes refuse missing marker before DB %s', async route => {
 const prepare = vi.fn(() => { throw new Error('D1 forbidden'); });
 const response = await worker.fetch(new Request(`http://localhost/__fixture/accounts/${route}`,{method:'POST',body:'{}'}),{...marker,FIXTURE_MARKER:undefined,FIXTURE_DB:{prepare} as unknown as D1Database});
 expect(response.status).toBe(503); expect(prepare).not.toHaveBeenCalled();
});
it.each(['/v1/auth/code/request','/v1/auth/code/consume','/v1/auth/session/refresh','/__fixture/accounts/sql'])('exposes no productive or arbitrary SQL endpoint %s', async path => {
 expect((await worker.fetch(new Request('http://localhost'+path,{method:'POST',body:'{}'}),marker)).status).toBe(404);
});
it.each(['{','{"email":"a@example.invalid","email":"b@example.invalid"}','[]','null','{"email":"a@example.invalid","\\u0065mail":"b@example.invalid"}','{"email":"a@example.invalid","purpose":"app-sign-in","sourceIP":"192.0.2.1","unknown":true}','{"email":"a@example.invalid","purpose":"email-recovery","sourceIP":"192.0.2.1"}'])('fixture request closed strict parser refuses %s', async body => {
 const prepare = vi.fn(() => { throw new Error('D1 forbidden'); });
 const response = await worker.fetch(new Request('http://localhost/__fixture/accounts/request',{method:'POST',headers:fixtureHeaders,body}),{...marker,FIXTURE_DB:{prepare} as unknown as D1Database});
 expect(response.status).toBe(400); expect(prepare).not.toHaveBeenCalled();
});
it('fixture body bound rejects before DB', async () => {
 const prepare = vi.fn(() => { throw new Error('D1 forbidden'); });
 expect((await worker.fetch(new Request('http://localhost/__fixture/accounts/request',{method:'POST',headers:fixtureHeaders,body:' '.repeat(2049)}),{...marker,FIXTURE_DB:{prepare} as unknown as D1Database})).status).toBe(413);
 expect(prepare).not.toHaveBeenCalled();
});

it('fixture entropy requires explicit bounded synthetic seed and is deterministic', () => {
 const a=fixtureRandom('0'.repeat(31)+'1'); const b=fixtureRandom('0'.repeat(31)+'1'); const c=fixtureRandom('0'.repeat(31)+'2');
 expect(a).not.toBeNull();expect(b).not.toBeNull();expect(c).not.toBeNull();
 const av=a!(32);expect(av).toEqual(b!(32));expect(av).not.toEqual(c!(32));expect(a!(32)).not.toEqual(av);
 expect(()=>a!(4097)).toThrow();
 for(const seed of ['', '0'.repeat(31),'0'.repeat(33),'G'.repeat(32),'A'.repeat(32)])expect(fixtureRandom(seed)).toBeNull();
});

it.each([{}, {'x-fixture-key':'PAT-2642-synthetic'}, {...fixtureHeaders,'x-fixture-seed':'bad'}, {...fixtureHeaders,'x-fixture-now':'NaN'}, {...fixtureHeaders,'x-fixture-now':'253402300800'}, {...fixtureHeaders,'x-fixture-delivery':'live'}])('missing or mixed fixture controls refuse before DB %j',async headers=>{
 const prepare=vi.fn(()=>{throw new Error('D1 forbidden');});
 const r=await worker.fetch(new Request('http://localhost/__fixture/accounts/request',{method:'POST',headers:headers as Record<string,string>,body:JSON.stringify({email:'a@example.invalid',purpose:'app-sign-in',sourceIP:'192.0.2.1'})}),{...marker,FIXTURE_DB:{prepare} as unknown as D1Database});expect(r.status).toBe(503);expect(prepare).not.toHaveBeenCalled();
});
it.each([
 ['consume',{challengeID:'0'.repeat(32),purpose:'app-sign-in',code:'1'.repeat(9)}],
 ['consume',{challengeID:'0'.repeat(32),purpose:'app-sign-in',code:'1234567x'}],
 ['consume',{challengeID:'0'.repeat(33),purpose:'app-sign-in',code:'12345678'}],
 ['refresh',{sessionID:'x',refreshToken:'0'.repeat(65)}],
 ['authenticate',{sessionID:'x',accessToken:'0'.repeat(64),accountID:'wrong'}],
 ['request',{email:'a@example.invalid',purpose:'app-sign-in',sourceIP:'not-an-ip'}],
 ['request',{email:'a@example.invalid',purpose:'app-reauth',sourceIP:'192.0.2.1'}],
 ['mutate',{accountID:'a',expectedRevision:-1,nonce:'a'}],
])('closed fixture operation rejects malformed %s', async(route,body)=>{
 const prepare=vi.fn(()=>{throw new Error('D1 forbidden');});const r=await worker.fetch(new Request('http://localhost/__fixture/accounts/'+route,{method:'POST',headers:fixtureHeaders,body:JSON.stringify(body)}),{...marker,FIXTURE_DB:{prepare} as unknown as D1Database});expect(r.status).toBe(400);expect(prepare).not.toHaveBeenCalled();
});

it('service has no implicit clock/randomness/key/delivery/database defaults',async()=>{
 const service=new AuthService(undefined as unknown as AuthDependencies);
 expect(await service.requestCode({email:'a@example.invalid',purpose:'app-sign-in',sourceIP:'192.0.2.1'})).toEqual({status:503,body:{outcome:'refused'}});
});
it.each(['GET','PUT','DELETE'])('fixture account route method %s refuses before DB',async method=>{
 const prepare=vi.fn(()=>{throw new Error('D1 forbidden');});const r=await worker.fetch(new Request('http://localhost/__fixture/accounts/request',{method,headers:fixtureHeaders}),{...marker,FIXTURE_DB:{prepare} as unknown as D1Database});expect(r.status).toBe(405);expect(prepare).not.toHaveBeenCalled();
});
