import test from 'node:test';
import assert from 'node:assert/strict';
import {parseElectron} from '../discovery/vendor/electron.mjs';
import {electron,metadata,change,held,expected,sha} from './vendor-fixtures.mjs';
test('Electron generic positive extracts exact files-entry metadata',()=>assert.deepEqual(parseElectron(electron()),metadata('electron')));
test('Electron matching legacy path/hash agrees with files entry',()=>{const i=electron();i.feedBytes=Buffer.concat([i.feedBytes,Buffer.from('path: https://downloads.example.test/app-2.zip\nsha512: '+expected.sha512+'\n')]);assert.equal(parseElectron(i).status,'extracted');});
test('Electron CRLF retains exact feed/config digests',()=>{const i=electron();for(const k of ['configBytes','feedBytes'])i[k]=Buffer.from(i[k].toString().replaceAll('\n','\r\n'));const r=parseElectron(i);assert.equal(r.status,'extracted');assert.equal(r.sourceDigests.configSha256,sha(i.configBytes));assert.equal(r.sourceDigests.feedSha256,sha(i.feedBytes));});
for(const [name,a,b]of [
 ['dynamic provider','provider: generic','provider: custom'],['duplicate config','channel: latest','channel: latest\nchannel: beta'],['config credentials','url: https://updates.example.test/','url: https://user:password@updates.example.test/'],['YAML tags','provider: generic','provider: !!js/function x'],['YAML aliases','provider: generic','provider: &provider generic\nother: *provider'],
])test('Electron refuses '+name,()=>{const i=electron();i.configBytes=change(i.configBytes,a,b);held(parseElectron(i));});
test('Electron refuses unsupported, ambiguous and hostile manifest forms',()=>{
 for(const [a,b]of [['version: 2.0.0','version: 2.0.0\nversion: 3.0.0'],['files:','files: []\nother:'],['releaseDate:','stagingPercentage: 10\nreleaseDate:'],['version: 2.0.0','version: |\n  2.0.0'],['releaseDate:','minimumSystemVersion: 23.1.0\nreleaseDate:'],['sha512: ','sha512: !'],['files:','files:\n  - url: https://evil.example.test/extra.zip'],['releaseDate:','script: $(never-execute)\nreleaseDate:']]){
 const i=electron();i.feedBytes=change(i.feedBytes,a,b);held(parseElectron(i));}
});
test('Electron legacy disagreement cannot override files entry',()=>{const i=electron();i.feedBytes=Buffer.concat([i.feedBytes,Buffer.from('path: https://evil.example.test/other.zip\nsha512: '+expected.sha512+'\n')]);held(parseElectron(i));});
