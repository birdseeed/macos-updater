import test from 'node:test';
import assert from 'node:assert/strict';
import {parseSparkle} from '../discovery/vendor/sparkle.mjs';
import {sparkle,metadata,change,sha,held,copy} from './vendor-fixtures.mjs';
test('Sparkle full positive extracts exact bounded untrusted metadata',()=>{
 const i=sparkle(),r=parseSparkle(i);assert.equal(r.status,'extracted');assert.deepEqual(r,metadata());assert.equal(r.sourceDigests.feedSha256,sha(i.bytes));
});
test('Sparkle CRLF preserves exact bytes rather than normalising provenance',()=>{const i=sparkle();i.bytes=Buffer.from(i.bytes.toString().replaceAll('\n','\r\n'));const r=parseSparkle(i);assert.equal(r.status,'extracted');assert.equal(r.sourceDigests.feedSha256,sha(i.bytes));assert.notEqual(r.sourceDigests.feedSha256,metadata().sourceDigests.feedSha256);});
test('Sparkle display string is independent from machine build version',()=>{const i=sparkle();i.bytes=change(i.bytes,'Display 200','Marketing 999');const r=parseSparkle(i);assert.equal(r.status,'extracted');assert.equal(r.metadata.version,'2.0.0');assert.equal(r.metadata.displayVersion,'Marketing 999');});
test('Sparkle missing optional compatibility/channel uses null, never invented feed evidence',()=>{const i=sparkle();i.bytes=Buffer.from(i.bytes.toString().replace(/      <sparkle:(?:channel|hardwareRequirements|minimumSystemVersion|maximumSystemVersion)>[^<]*<\/sparkle:[^>]+>\n/g,''));const r=parseSparkle(i);assert.equal(r.status,'extracted');for(const k of ['channel','architecture','minOS','maxOS'])assert.equal(r.metadata[k],null);});
const cases=[
 ['DTD','<rss ','<!DOCTYPE rss [<!ENTITY p SYSTEM "file:///etc/passwd">]>\n<rss '],['entity','Inert fixture app','&external;'],['CDATA','Inert fixture app','<![CDATA[x]]>'],['instruction','<channel>','<channel><?execute x?>'],
 ['namespace','http://www.andymatuschak.org/xml-namespaces/sparkle','https://evil.example.test/ns'],['duplicate version','<sparkle:version>2.0.0</sparkle:version>','<sparkle:version>2.0.0</sparkle:version><sparkle:version>3.0.0</sparkle:version>'],
 ['unknown key','<item>','<item><script>never execute</script>'],['delta','<enclosure ','<enclosure sparkle:deltaFrom="1.0.0" '],['informational','<item>','<item><sparkle:informationalUpdate/>'],['paid upgrade','<item>','<item><sparkle:minimumAutoupdateVersion>2.0.0</sparkle:minimumAutoupdateVersion>'],
 ['http','https://downloads.example.test/app-2.zip','http://downloads.example.test/app-2.zip'],['relative','https://downloads.example.test/app-2.zip','app-2.zip'],['credentials','https://downloads.example.test/app-2.zip','https://user:password@downloads.example.test/app-2.zip'],['fragment','app-2.zip"','app-2.zip#x"'],
 ['bad signature','sparkle:edSignature="','sparkle:edSignature="!'],['no signature','sparkle:edSignature=','signature='],['unknown attribute','<enclosure ','<enclosure script="x" '],['conflicting enclosure version','<enclosure ','<enclosure sparkle:version="3.0.0" '],
 ['second enclosure','</item>','<enclosure url="https://downloads.example.test/app-2.zip"/></item>'],['unsupported tar','app-2.zip','app-2.tar.gz'],['truncation','</rss>',''],['mixed content','<item>','<item>text'],['duplicate attribute','length="','length="1" length="'],
];
for(const [name,a,b]of cases)test('Sparkle refuses '+name,()=>{const i=sparkle();i.bytes=change(i.bytes,a,b);held(parseSparkle(i));});
for(const [name,bytes]of [['invalid UTF8',Buffer.from([0xc0,0xaf])],['BOM',Buffer.concat([Buffer.from([239,187,191]),sparkle().bytes])],['NUL',Buffer.from('<rss>\0</rss>')],['oversized',Buffer.alloc(65537)],['line overflow',Buffer.from('\n'.repeat(513))]])test('Sparkle bytes refuse '+name,()=>held(parseSparkle({...sparkle(),bytes})));
test('Sparkle parser does not mutate caller bytes and returns detached metadata',()=>{const i=sparkle(),before=copy(i);const a=parseSparkle(i);assert.equal(a.status,'extracted');a.metadata.version='poison';assert.deepEqual(copy(i),before);assert.equal(parseSparkle(i).metadata.version,'2.0.0');});
