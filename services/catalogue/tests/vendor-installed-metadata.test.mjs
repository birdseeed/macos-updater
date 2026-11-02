import test from 'node:test';
import assert from 'node:assert/strict';
import {discoverInstalledVendorCandidate as discover} from '../discovery/vendor/installed-metadata.mjs';
import {sparkle,electron,input,candidate,copy,held,noAuthority,sha,change} from './vendor-fixtures.mjs';

// Explicit inert projection, not a native decoder or a live Swift-to-Node pipeline.
function fixture(adapter='sparkle') {
  const base=input(adapter),s=sparkle(),e=electron();
  return {schemaVersion:'installed-vendor-fixture-v1',adapter,
    observation:{metadataDisposition:'observed',claimedBundleIdentifier:base.context.bundleId,
      claimedShortVersion:'1.0.0',claimedBuild:'1.0.0',
      vendorMetadata:{sparkleFeedURL:adapter==='sparkle'?s.feedURL:null,
        electronConfigBytes:adapter==='electron'?e.configBytes:null,
        sparkleDisposition:adapter==='sparkle'?'observed':'unavailable',
        electronDisposition:adapter==='electron'?'observed':'unavailable'}},
    source:{feedURL:base.route.feedURL,feedBytes:adapter==='sparkle'?s.bytes:e.feedBytes,
      configSha256:adapter==='electron'?sha(e.configBytes):null},
    context:base.context,route:base.route,redirects:[],previous:null};
}
function refused(value,status='held') {
  const r=discover(value);
  if(status==='held')held(r);else {assert.equal(r.status,'unknown');assert.equal(r.candidate,null);assert.match(r.reason,/\S/);noAuthority(r);}
  assert.deepEqual(Object.keys(r).sort(),['candidate','installationAllowed','publicationAllowed','reason','scope','status','verificationAllowed'].sort());
}
function positive(i,expected=candidate(i.adapter)) {
  const r=discover(i); assert.equal(r.status,'candidate'); assert.equal(r.reason,null);
  assert.deepEqual(r.candidate,expected); noAuthority(r); return r;
}
for(const adapter of ['sparkle','electron']) {
  test(adapter+' observed projection produces exact existing candidate and source digests',()=>positive(fixture(adapter)));
  test(adapter+' duplicate uses existing fully revalidated previous-candidate machinery',()=>{
    const i=fixture(adapter);i.previous=candidate(adapter);
    const r=discover(i);assert.equal(r.status,'unchanged');assert.equal(r.reason,null);
    assert.deepEqual(r.candidate,i.previous);noAuthority(r);
  });
  test(adapter+' input and returned candidate are detached',()=>{
    const i=fixture(adapter),before=copy(i),r=positive(i);assert.deepEqual(copy(i),before);
    r.candidate.identity.productId='changed';r.candidate.sourceDigests.feedSha256='f'.repeat(64);
    r.candidate.redirects.push({from:'changed',to:'changed'});
    assert.deepEqual(copy(i),before);positive(i);
  });
  test(adapter+' exact independent identity remains caller-owned, never guessed from installed claims',()=>{
    const i=fixture(adapter);i.context.productId='explicit-other-product';i.route.identity.productId=i.context.productId;
    // The existing machinery must recompute its canonical candidate hash.
    const r=discover(i);assert.equal(r.status,'candidate');assert.deepEqual(r.candidate.identity,i.route.identity);
    assert.notEqual(r.candidate.candidateId,candidate(adapter).candidateId);noAuthority(r);
  });
  for(const disposition of ['unavailable','malformed','refused','unknown',null]) {
    test(adapter+' refuses application metadata disposition '+disposition,()=>{
      const i=fixture(adapter);i.observation.metadataDisposition=disposition;refused(i,disposition==='unavailable'?'unknown':'held');
    });
    test(adapter+' refuses selected extraction disposition '+disposition+' even with retained bytes',()=>{
      const i=fixture(adapter);i.observation.vendorMetadata[adapter+'Disposition']=disposition;refused(i,disposition==='unavailable'?'unknown':'held');
    });
  }
  test(adapter+' missing installed claim never borrows baseline or bundle from route',()=>{
    for(const key of ['claimedBundleIdentifier',adapter==='sparkle'?'claimedBuild':'claimedShortVersion'])
      for(const value of [null,'','different']){const i=fixture(adapter);i.observation[key]=value;refused(i);}
  });
  test(adapter+' independent context/route identity, comparator and baseline are exact',()=>{
    for(const key of ['productId','bundleId','developerTeamId','channel','edition','architecture']) {
      const i=fixture(adapter);i.context[key]='different';refused(i);
      const j=fixture(adapter);delete j.context[key];refused(j);
    }
    for(const mutate of [i=>i.context.baselineVersion='0.9.0',i=>i.context.baselineVersion='2.0.0',
      i=>i.route.comparator='unknown',i=>i.context.osVersion='14.0.0',i=>delete i.route.minOS,
      i=>i.route.artifactURLs=['https://other.example.test/other.zip']]){const i=fixture(adapter);mutate(i);refused(i);}
  });
  test(adapter+' previous source mutation/corruption refuses; no continuity inferred',()=>{
    for(const mutate of [i=>i.previous.candidateId='a'.repeat(64),i=>i.previous.sourceDigests.feedSha256='b'.repeat(64),
      i=>i.previous.identity.bundleId='different',i=>i.source.feedBytes=Buffer.concat([i.source.feedBytes,Buffer.from('\n')])]) {
      const i=fixture(adapter);i.previous=candidate(adapter);mutate(i);refused(i);
    }
  });
  test(adapter+' malformed/raw/path/text/shared/oversized feed bytes refuse',()=>{
    for(const value of [null,'/Applications/Example.app/Contents/Resources/feed',sparkle().bytes.toString(),
      new Uint8Array(new SharedArrayBuffer(16)),Buffer.alloc(65537),Buffer.from([0xff]),Buffer.from('malformed')]) {
      const i=fixture(adapter);i.source.feedBytes=value;refused(i);
    }
  });
  test(adapter+' exact closed records refuse missing/unknown/symbol/accessor keys',()=>{
    for(const select of [i=>i,i=>i.observation,i=>i.observation.vendorMetadata,i=>i.source,i=>i.context,i=>i.route,i=>i.route.identity]) {
      for(const mode of ['unknown','missing','symbol','getter']) {
        const i=fixture(adapter),record=select(i),key=Object.keys(record)[0];let reads=0;
        if(mode==='unknown')record.extra=true;
        if(mode==='missing')delete record[key];
        if(mode==='symbol')record[Symbol('unknown')]=true;
        if(mode==='getter')Object.defineProperty(record,key,{enumerable:true,get(){reads++;throw Error('getter executed');}});
        refused(i);assert.equal(reads,0);
      }
    }
  });
  test(adapter+' wrong feed source, unsupported schemas/adapters and forged authority refuse',()=>{
    for(const mutate of [i=>i.source.feedURL='https://wrong.example.test/feed.xml',i=>i.schemaVersion='installed-vendor-fixture-v2',
      i=>i.adapter='squirrel',i=>i.adapter='unknown',
      i=>i.installationAllowed=true,i=>i.observation.path='/Applications/Example.app',
      i=>i.observation.authorityUnknown=false,i=>i.source.fetch=true]){const i=fixture(adapter);mutate(i);refused(i);}
  });
}
test('Sparkle uses machine build, never the unrelated display version',()=>{
  const i=fixture();i.observation.claimedShortVersion='Display 100';positive(i);
  const j=fixture();j.observation.claimedBuild='1247';j.context.baselineVersion='1247';
  j.source.feedBytes=change(j.source.feedBytes,'<sparkle:version>2.0.0</sparkle:version>','<sparkle:version>1248</sparkle:version>');
  const r=discover(j);assert.equal(r.status,'candidate');assert.equal(r.candidate.version,'1248');noAuthority(r);
});
test('Electron uses short semver, never unrelated internal build',()=>{
  const i=fixture('electron');i.observation.claimedBuild='9999';positive(i);
});
test('Sparkle observed SUFeedURL binds exact route start while approved redirects bind feed fixture location',()=>{
  const i=fixture(),to=i.route.allowedRedirectURLs[0];i.source.feedURL=to;
  i.redirects=[{from:i.route.feedURL,to}];
  const r=discover(i);assert.equal(r.status,'candidate');assert.deepEqual(r.candidate.redirects,i.redirects);noAuthority(r);
  for(const mutate of [j=>j.observation.vendorMetadata.sparkleFeedURL=to,
    j=>j.redirects[0].from='https://wrong.example.test/feed',j=>j.redirects[0].to='https://evil.example.test/feed',
    j=>j.route.allowedRedirectURLs=[]]){const j=fixture();j.source.feedURL=to;j.redirects=[{from:j.route.feedURL,to}];mutate(j);refused(j);}
});
test('Sparkle exact URL is required, no normalization, path reading or other-adapter fallback',()=>{
  for(const value of [null,'','/Applications/Example.app/Contents/Info.plist','http://updates.example.test/appcast.xml',
    'https://user@updates.example.test/appcast.xml','https://127.0.0.1/appcast.xml','https://updates.example.test/appcast.xml#x']) {
    const i=fixture();i.observation.vendorMetadata.sparkleFeedURL=value;refused(i);
  }
  const i=fixture();i.source.configSha256='a'.repeat(64);refused(i);
});
test('Electron raw observed config digest is exact and configuration derives only its approved route',()=>{
  for(const value of [null,'','a'.repeat(64),'A'.repeat(64)]){const i=fixture('electron');i.source.configSha256=value;refused(i);}
  for(const value of [null,'/Applications/Example.app/Contents/Resources/app-update.yml',electron().configBytes.toString(),
    new Uint8Array(new SharedArrayBuffer(16)),Buffer.alloc(65537),Buffer.from([0xff])]) {
    const i=fixture('electron');i.observation.vendorMetadata.electronConfigBytes=value;refused(i);
  }
  for(const [from,to] of [['provider: generic','provider: custom'],['url: https://updates.example.test/','url: https://other.example.test/'],
    ['channel: latest','channel: beta']]) {
    const i=fixture('electron');i.observation.vendorMetadata.electronConfigBytes=change(i.observation.vendorMetadata.electronConfigBytes,from,to);
    i.source.configSha256=sha(i.observation.vendorMetadata.electronConfigBytes);refused(i);
  }
});
test('Electron approved redirects preserve config-derived start and final feed binding',()=>{
  const i=fixture('electron'),to='https://cdn.example.test/latest-mac.yml';
  i.route.allowedRedirectURLs=[to];i.source.feedURL=to;i.redirects=[{from:i.route.feedURL,to}];
  const r=discover(i);assert.equal(r.status,'candidate');assert.deepEqual(r.candidate.redirects,i.redirects);noAuthority(r);
  const j=fixture('electron');j.route.feedURL='https://other.example.test/latest-mac.yml';j.source.feedURL=j.route.feedURL;refused(j);
});
test('unavailable nonselected adapter stays inert; selecting it cannot borrow other extraction',()=>{
  const i=fixture();i.observation.vendorMetadata.electronDisposition='refused';positive(i);
  const j=fixture('electron');j.observation.vendorMetadata.sparkleDisposition='malformed';positive(j);
  const k=fixture();k.adapter='electron';refused(k,'unknown');
});
test('invalid top-level types refuse without throwing or acquiring authority',()=>{
  for(const value of [undefined,null,[],42,'/Applications/Example.app',Object.create({})])refused(value);
});
test('raw byte changes reach existing adapters and candidate digest, never precomputed metadata',()=>{
  for(const adapter of ['sparkle','electron']) {
    const i=fixture(adapter);i.source.feedBytes=Buffer.concat([i.source.feedBytes,Buffer.from('\n')]);
    const r=discover(i);assert.equal(r.status,'candidate');assert.equal(r.candidate.sourceDigests.feedSha256,sha(i.source.feedBytes));
    assert.notEqual(r.candidate.candidateId,candidate(adapter).candidateId);noAuthority(r);
  }
  const i=fixture('electron');i.observation.vendorMetadata.electronConfigBytes=Buffer.from(electron().configBytes.toString().replaceAll('\n','\r\n'));
  i.source.configSha256=sha(i.observation.vendorMetadata.electronConfigBytes);
  const r=discover(i);assert.equal(r.status,'candidate');assert.equal(r.candidate.sourceDigests.configSha256,i.source.configSha256);noAuthority(r);
});
test('observed raw feed enforces existing parser channel, artifact and malformed manifest refusals',()=>{
  for(const [adapter,from,to] of [
    ['sparkle','<sparkle:channel>stable</sparkle:channel>','<sparkle:channel>beta</sparkle:channel>'],
    ['sparkle','https://downloads.example.test/app-2.zip','https://evil.example.test/app-2.zip'],
    ['electron','version: 2.0.0','version: 2.0.0\nversion: 3.0.0'],
    ['electron','https://downloads.example.test/app-2.zip','https://evil.example.test/app-2.zip']]) {
    const i=fixture(adapter);i.source.feedBytes=change(i.source.feedBytes,from,to);refused(i);
  }
});
test('projection string bounds and invalid UTF16/control metadata refuse',()=>{
  for(const adapter of ['sparkle','electron']) {
    for(const value of ['x'.repeat(1025),'bad\u0000claim','bad\ud800claim']) {
      const i=fixture(adapter);i.observation.claimedBundleIdentifier=value;refused(i);
    }
    const i=fixture(adapter);i.source.feedURL='https://updates.example.test/'+'x'.repeat(2049);refused(i);
  }
});
test('byte accessors and custom byte prototypes are refused without caller code',()=>{
  for(const adapter of ['sparkle','electron']) {
    for(const selected of ['feed','config']) {
      if(selected==='config' && adapter==='sparkle')continue;
      const i=fixture(adapter),bytes=selected==='feed'?i.source.feedBytes:i.observation.vendorMetadata.electronConfigBytes;
      let reads=0;Object.defineProperty(bytes,'byteLength',{get(){reads++;throw Error('byte accessor executed');}});
      refused(i);assert.equal(reads,0);
      const j=fixture(adapter),custom=new Uint8Array([1,2,3]);Object.setPrototypeOf(custom,Object.create(Uint8Array.prototype));
      if(selected==='feed')j.source.feedBytes=custom;else j.observation.vendorMetadata.electronConfigBytes=custom;
      refused(j);
    }
  }
});
