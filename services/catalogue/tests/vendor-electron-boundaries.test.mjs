import test from 'node:test';
import assert from 'node:assert/strict';
import {parseElectron} from '../discovery/vendor/electron.mjs';
import {electron,held,sha} from './vendor-fixtures.mjs';

// Supplemental independent controls. Original Phase A checks remain frozen.
// v26.0.12 newBaseUrl appends a slash to the entire directory pathname:
// https://raw.githubusercontent.com/electron-userland/electron-builder/v26.0.12/packages/electron-updater/src/util.ts
// GenericProvider consumes that base before resolving the channel filename:
// https://raw.githubusercontent.com/electron-userland/electron-builder/v26.0.12/packages/electron-updater/src/providers/GenericProvider.ts
function withBase(base) {
  const i=electron();
  i.configBytes=Buffer.from('provider: generic\nurl: '+base+'\nchannel: latest\n');
  return i;
}
function extractedAt(base,expectedURL) {
  const i=withBase(base),r=parseElectron(i);
  assert.equal(r.status,'extracted','valid generic directory base must extract: '+base);
  assert.equal(r.reason,null);
  assert.equal(r.metadata.feedURL,expectedURL);
  assert.equal(r.metadata.artifactURL,'https://downloads.example.test/app-2.zip');
  assert.equal(r.sourceDigests.configSha256,sha(i.configBytes));
  assert.equal(r.sourceDigests.feedSha256,sha(i.feedBytes));
}
function refuseBoth(makeBytes) {
  for(const key of ['configBytes','feedBytes']) {
    const i=electron();i[key]=makeBytes(i[key]);
    const r=parseElectron(i);held(r);
    assert.equal(r.sourceDigests,null,'refused '+key+' must not expose extracted provenance');
  }
}

test('Electron root directory bases with and without terminal slash resolve literal channel URL',()=>{
  extractedAt('https://updates.example.test','https://updates.example.test/latest-mac.yml');
  extractedAt('https://updates.example.test/','https://updates.example.test/latest-mac.yml');
});
test('Electron subdirectory bases with and without terminal slash preserve complete directory',()=>{
  extractedAt('https://updates.example.test/updates','https://updates.example.test/updates/latest-mac.yml');
  extractedAt('https://updates.example.test/updates/','https://updates.example.test/updates/latest-mac.yml');
});
test('Electron invalid UTF8 refuses independently in config and feed',()=>{
  for(const bytes of [Buffer.from([0xc0,0xaf]),Buffer.from([0xed,0xa0,0x80]),Buffer.from([0xe2,0x82])])
    refuseBoth(original=>Buffer.concat([original,bytes]));
});
test('Electron BOM and NUL refuse independently in config and feed',()=>{
  refuseBoth(original=>Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),original]));
  refuseBoth(original=>Buffer.concat([original,Buffer.from([0])]));
});
test('Electron line overflow refuses independently in config and feed',()=>{
  refuseBoth(original=>Buffer.concat([original,Buffer.from('\n'.repeat(513))]));
});
test('Electron shared byte storage refuses independently in config and feed',()=>{
  refuseBoth(original=>{
    const bytes=new Uint8Array(new SharedArrayBuffer(original.byteLength));
    bytes.set(original);return bytes;
  });
});
test('Electron metadata byte overflow refuses independently in config and feed',()=>{
  refuseBoth(original=>Buffer.concat([original,Buffer.alloc(65537-original.byteLength,32)]));
});
test('Electron malformed, credential, private and query bases remain refused',()=>{
  for(const base of [
    'https:updates.example.test/updates','/updates','http://updates.example.test/updates',
    'https://user:password@updates.example.test/updates','https://@updates.example.test/updates',
    'https://127.0.0.1/updates','https://10.0.0.1/updates','https://192.168.0.1/updates',
    'https://[::1]/updates','https://localhost/updates',
    'https://updates.example.test/updates?token=inert','https://updates.example.test/updates#fragment',
  ]) held(parseElectron(withBase(base)));
});
