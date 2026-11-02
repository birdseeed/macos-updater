import test from 'node:test';
import assert from 'node:assert/strict';
import {discoverVendorCandidate,compareVendorVersions,checkVendorArtifact} from '../discovery/vendor/candidates.mjs';
import {input,candidate,artifact,observation,copy,held,noAuthority,canonical,sha} from './vendor-fixtures.mjs';
test('both adapters produce exact positive candidates without authority',()=>{for(const adapter of ['sparkle','electron']){const r=discoverVendorCandidate(input(adapter));assert.equal(r.status,'candidate');assert.deepEqual(r.candidate,candidate(adapter));assert.equal(r.reason,null);noAuthority(r);}});
test('version comparators order numbers and refuse unknown semantics',()=>{
 for(const [comparator,left,right,order]of [['sparkle-dotted-v1','1.9','1.10',-1],['sparkle-dotted-v1','1248','1247',1],['sparkle-dotted-v1','2','2.0',0],['electron-stable-semver-v1','1.9.0','1.10.0',-1],['electron-stable-semver-v1','2.0.0','2.0.0',0]])assert.deepEqual(compareVendorVersions({comparator,left,right}),{status:'compared',order,reason:null});
 for(const v of ['01.0.0','1.0.0-beta','1.0.0+build','1e3','1.2.3.4.5','2147483648.0.0']){const r=compareVendorVersions({comparator:'electron-stable-semver-v1',left:v,right:'2.0.0'});held(r);assert.equal(r.order,null);}held(compareVendorVersions({comparator:'unknown',left:'1',right:'2'}));
});
test('older and equal releases cannot become new update candidates',()=>{for(const baselineVersion of ['2.0.0','3.0.0']){const i=input();i.context.baselineVersion=baselineVersion;held(discoverVendorCandidate(i));}});
test('exact identity and route policy cannot be supplied by feed title or claim',()=>{for(const k of ['productId','bundleId','developerTeamId','channel','edition','architecture']){for(const mode of ['wrong','absent']){const i=input();if(mode==='wrong')i.context[k]='different';else delete i.context[k];held(discoverVendorCandidate(i));}}for(const v of ['beta','unknown']){const i=input();i.context.channel=v;i.route.identity.channel=v;held(discoverVendorCandidate(i));}});
test('feed compatibility/channel disagreement and unsupported OS refuse',()=>{for(const [k,v]of [['channel','beta'],['architecture','x86_64'],['minOS','27.0.0'],['maxOS','15.0.0']]){const i=input();i.metadata.metadata[k]=v;held(discoverVendorCandidate(i));}for(const osVersion of ['14.9.0','28.0.0','unknown']){const i=input();i.context.osVersion=osVersion;held(discoverVendorCandidate(i));}});
test('independent route supplies absent channel/architecture/OS without creating feed claims',()=>{const i=input('electron'),r=discoverVendorCandidate(i);assert.equal(r.status,'candidate');assert.deepEqual(r.candidate.identity,i.route.identity);assert.equal(i.metadata.metadata.architecture,null);assert.equal(i.metadata.metadata.minOS,null);});
test('redirects require exact approved contiguous chain, no new host authority',()=>{
 const i=input();i.redirects=[{from:i.route.feedURL,to:i.route.allowedRedirectURLs[0]}];i.metadata.metadata.feedURL=i.redirects[0].to;const r=discoverVendorCandidate(i);assert.equal(r.status,'candidate');assert.deepEqual(r.candidate.redirects,i.redirects);noAuthority(r);
 for(const target of ['http://cdn.example.test/appcast.xml','https://evil.example.test/appcast.xml','https://127.0.0.1/appcast.xml','https://user@cdn.example.test/appcast.xml','https://cdn.example.test/appcast.xml#x']){const j=copy(i);j.redirects[0].to=target;j.metadata.metadata.feedURL=target;held(discoverVendorCandidate(j));}
 const j=copy(i);j.redirects[0].from='https://wrong.example.test/';held(discoverVendorCandidate(j));
});
test('previous candidate is fully revalidated; exact duplicate unchanged; changed same version held',()=>{
 const i=input();i.previous=candidate();const r=discoverVendorCandidate(i);assert.equal(r.status,'unchanged');noAuthority(r);
 for(const mutate of [j=>j.metadata.sourceDigests.feedSha256='b'.repeat(64),j=>j.metadata.metadata.displayVersion='Changed',j=>j.metadata.metadata.integrityClaim.value='AQ==']){const j=copy(i);mutate(j);held(discoverVendorCandidate(j));}
 for(const k of ['candidateId','policyVersion','version']){const j=copy(i);j.previous[k]='corrupt';held(discoverVendorCandidate(j));}
 const next=copy(i);next.metadata.metadata.version='3.0.0';const n=discoverVendorCandidate(next);assert.equal(n.status,'candidate');assert.notEqual(n.candidate.candidateId,i.previous.candidateId);
});
test('missing metadata and unsupported routes have truthful non-support states',()=>{for(const adapter of ['sparkle','electron']){const i=input(adapter);i.metadata=null;const r=discoverVendorCandidate(i);assert.equal(r.status,'unknown');assert.equal(r.candidate,null);noAuthority(r);}const i=input();i.adapter='squirrel';const r=discoverVendorCandidate(i);assert.equal(r.status,'vendor-updater');assert.equal(r.candidate,null);noAuthority(r);});
test('artifact positives are injected fixture consistency only, never trust',()=>{for(const adapter of ['sparkle','electron']){const i={candidate:candidate(adapter),artifactBytes:artifact(),observation:observation()},r=checkVendorArtifact(i);assert.equal(r.status,'fixture-consistent');assert.match(r.bindingSha256,/^[a-f0-9]{64}$/);noAuthority(r);const before=copy(i);r.bindingSha256='changed';assert.deepEqual(copy(i),before);}});
test('wrong signer, identity, version, digest, length or unknown checks stay refused',()=>{
 for(const k of ['signature','notarisation','container','compatibility'])for(const value of ['failed','unknown','unavailable']){const o=observation();o[k]=value;held(checkVendorArtifact({candidate:candidate(),artifactBytes:artifact(),observation:o}));}
 for(const k of Object.keys(observation().identity)){const o=observation();o.identity[k]='different';held(checkVendorArtifact({candidate:candidate(),artifactBytes:artifact(),observation:o}));}
 const o=observation();o.version='3.0.0';held(checkVendorArtifact({candidate:candidate(),artifactBytes:artifact(),observation:o}));
 const bytes=artifact();bytes[0]^=1;held(checkVendorArtifact({candidate:candidate('electron'),artifactBytes:bytes,observation:observation()}));
 held(checkVendorArtifact({candidate:candidate(),artifactBytes:Buffer.concat([artifact(),Buffer.from('x')]),observation:observation()}));
 const c=candidate();c.version='3.0.0';held(checkVendorArtifact({candidate:c,artifactBytes:artifact(),observation:observation()}));
});
test('candidate identity hashes canonical exact candidate fields',()=>{const r=discoverVendorCandidate(input());assert.equal(r.status,'candidate');const c=copy(r.candidate);delete c.candidateId;assert.equal(r.candidate.candidateId,sha(Buffer.from(canonical(c))));});
