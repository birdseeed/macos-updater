import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../../../Fixtures/VendorDiscovery/',import.meta.url);
const xml=readFileSync(new URL('sparkle.xml',root));
const config=readFileSync(new URL('app-update.yml',root));
const feed=readFileSync(new URL('latest-mac.yml',root));
const policy=JSON.parse(readFileSync(new URL('route.json',root)));
export const expected=JSON.parse(readFileSync(new URL('expected.json',root)));
export const copy=x=>structuredClone(x);
export const sha=x=>createHash('sha256').update(x).digest('hex');
export const canonical=x=>Array.isArray(x)?'['+x.map(canonical).join(',')+']':x!==null&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}':JSON.stringify(x);
export const route=()=>copy(policy);
export const sparkle=()=>({feedURL:policy.feedURL,bytes:Buffer.from(xml),parserVersion:'sparkle-subset-v1'});
export const electron=()=>({configBytes:Buffer.from(config),feedBytes:Buffer.from(feed),parserVersion:'electron-subset-v1'});
export function change(bytes,from,to) { assert.ok(bytes.toString().includes(from),'mutation must alter fixture'); return Buffer.from(bytes.toString().replace(from,to)); }
export const context=()=>({...copy(policy.identity),osVersion:'26.0.0',baselineVersion:'1.0.0'});
export function metadata(adapter='sparkle') {
  return {status:'extracted',reason:null,metadata:{parserVersion:adapter+'-subset-v1',feedURL:adapter==='sparkle'?policy.feedURL:'https://updates.example.test/latest-mac.yml',version:'2.0.0',displayVersion:adapter==='sparkle'?'Display 200':null,
    artifactURL:policy.artifactURLs[0],artifactLength:expected.artifactLength,
    integrityClaim:{algorithm:adapter==='sparkle'?'ed25519':'sha512',value:adapter==='sparkle'?expected.sparkleSignatureClaim:expected.sha512},channel:adapter==='sparkle'?'stable':null,architecture:adapter==='sparkle'?'arm64':null,minOS:adapter==='sparkle'?'15.0.0':null,maxOS:adapter==='sparkle'?'27.9.9':null},
    sourceDigests:{configSha256:adapter==='sparkle'?null:sha(config),feedSha256:sha(adapter==='sparkle'?xml:feed)}};
}
export function input(adapter='sparkle') {
 const p=route(); if(adapter==='electron'){p.feedURL='https://updates.example.test/latest-mac.yml';p.comparator='electron-stable-semver-v1';}
 return {adapter,metadata:metadata(adapter),context:context(),route:p,redirects:[],previous:null};
}
export function candidate(adapter='sparkle') {
 const i=input(adapter),m=i.metadata.metadata;
 const c={scope:'fixture-only',routeId:i.route.routeId,policyVersion:i.route.policyVersion,adapter,parserVersion:m.parserVersion,identity:copy(i.route.identity),version:m.version,displayVersion:m.displayVersion,artifactURL:m.artifactURL,artifactLength:m.artifactLength,integrityClaim:copy(m.integrityClaim),sourceDigests:copy(i.metadata.sourceDigests),redirects:[]};
 return {candidateId:sha(Buffer.from(canonical(c))),...c};
}
export const artifact=()=>Buffer.from(expected.artifactBase64,'base64');
export const observation=()=>({identity:copy(policy.identity),version:'2.0.0',signature:'passed',notarisation:'passed',container:'passed',compatibility:'passed'});
export function noAuthority(r){assert.equal(r.scope,'fixture-only');for(const k of ['verificationAllowed','installationAllowed','publicationAllowed'])assert.equal(r[k],false);assert.equal(Object.hasOwn(r,'nativeEvidence'),false);}
export function held(r){assert.equal(r.status,'held');assert.match(r.reason,/\S/);if(Object.hasOwn(r,'candidate')){assert.equal(r.candidate,null);noAuthority(r);}if(Object.hasOwn(r,'metadata'))assert.equal(r.metadata,null);if(Object.hasOwn(r,'bindingSha256')){assert.equal(r.bindingSha256,null);noAuthority(r);}}
