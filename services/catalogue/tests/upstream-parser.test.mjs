import test from 'node:test';
import assert from 'node:assert/strict';
import { parseLabel } from '../discovery/upstream/literal-parser.mjs';
import { labelBytes, path, sha, snapshot } from './upstream-fixtures.mjs';
const parse = (bytes, overrides = {}) => parseLabel({ path, bytes: Buffer.from(bytes), parserVersion: 'literal-v1', ...overrides });
function held(bytes, overrides = {}) {
  const result = parse(bytes, overrides); assert.equal(result.status, 'held');
  assert.equal(result.metadata, null); assert.match(result.reason, /\S/);
  assert.equal(result.sha256, sha(bytes)); assert.equal(result.byteLength, bytes.length);
  assert.equal(result.bytesBase64, Buffer.from(bytes).toString('base64')); return result;
}
const replace = (from, to) => Buffer.from(labelBytes().toString().replace(from, to));
test('meaningful extraction: expectedTeamID maps to untrusted claimedTeamID', () => {
  const result = parse(labelBytes());
  assert.equal(result.status, 'extracted', 'literal fixture must extract, so an always-held parser fails');
  assert.deepEqual(result.metadata, { name: 'Fixture App', type: 'dmg',
    downloadURL: 'https://downloads.example.test/fixture-v1.dmg', claimedTeamID: 'AAAAAAAAAA' });
  assert.equal(result.path, path); assert.equal(result.parserVersion, 'literal-v1');
  assert.equal(result.sha256, sha(labelBytes())); assert.equal(result.bytesBase64, labelBytes().toString('base64'));
});
test('LF and CRLF have equal metadata but retain different exact original digests', () => {
  const lf = parse(labelBytes()), bytes = Buffer.from(labelBytes().toString().replaceAll('\n', '\r\n')), crlf = parse(bytes);
  assert.equal(lf.status, 'extracted'); assert.equal(crlf.status, 'extracted');
  assert.deepEqual(crlf.metadata, lf.metadata); assert.notEqual(crlf.sha256, lf.sha256);
  assert.equal(crlf.sha256, sha(bytes)); assert.equal(crlf.bytesBase64, bytes.toString('base64'));
});
test('single/double quotes and arbitrary required-field order stay literal', () => {
  const bytes = Buffer.from('literal-valid)\n\texpectedTeamID="AAAAAAAAAA"\n type="zip"\n name=\'A Fixture\'\n downloadURL=\'https://example.test/file?x=1&y=2\'\n;;\n');
  const result = parse(bytes); assert.equal(result.status, 'extracted'); assert.equal(result.metadata.type, 'zip');
});
for (const type of ['dmg','pkg','zip']) test('closed valid type ' + type, () => assert.equal(parse(replace("type='dmg'", `type='${type}'`)).status, 'extracted'));
const malformed = {
  'command substitution': ['Fixture App','$(id)'], 'backticks': ['Fixture App','`id`'],
  'variable': ['Fixture App','$HOME'], 'indirection': ['Fixture App','${(P)thing}'],
  'backslash escape': ['Fixture App','Fixture\\ App'], 'concatenation': ['name="Fixture App"','name="Fixture"\'App\''],
  'inline comment': ["type='dmg'","type='dmg' # comment"], 'extra assignment': ['    ;;'," extra='x'\n    ;;"],
  'duplicate required': ['    ;;'," name='Again'\n    ;;"], 'missing required': ["    type='dmg'\n",''],
  'empty literal': ['Fixture App',''], 'unquoted': ["type='dmg'",'type=dmg'],
  'spaces around equals': ["type='dmg'","type = 'dmg'"], 'wrong arm': ['literal-valid)','other)'],
  'alternation': ['literal-valid)','literal-valid|other)'], 'no terminator': [';;',''],
  'extra command': ['    ;;',' id\n    ;;'], 'branch': ['    ;;',' if true; then :; fi\n    ;;'],
  'function': ['    ;;',' foo() { :; }\n    ;;'], 'array': ["type='dmg'","type=('dmg')"],
  'second arm': ['    ;;','    ;;\nsecond)\n;;'], 'postamble': ['    ;;','    ;;\nid'],
  'unsupported type': ["type='dmg'","type='app'"], 'lowercase team': ['AAAAAAAAAA','aaaaaaaaaa'],
  'short team': ['AAAAAAAAAA','AAAA'], 'unicode team': ['AAAAAAAAAA','ÄAAAAAAAAA'],
  'name byte bound': ['Fixture App','é'.repeat(65)], 'url byte bound': ['https://downloads.example.test/fixture-v1.dmg','https://example.test/'+'a'.repeat(2049)],
  'http': ['https://downloads.example.test/fixture-v1.dmg','http://example.test/file'],
  'relative': ['https://downloads.example.test/fixture-v1.dmg','/file'],
  'WHATWG repaired scheme': ['https://downloads.example.test/fixture-v1.dmg','https:example.test/file'],
  'userinfo': ['https://downloads.example.test/fixture-v1.dmg','https://u:p@example.test/file'],
  'empty userinfo': ['https://downloads.example.test/fixture-v1.dmg','https://@example.test/file'],
  'fragment': ['https://downloads.example.test/fixture-v1.dmg','https://example.test/file#part'],
  'empty fragment': ['https://downloads.example.test/fixture-v1.dmg','https://example.test/file#'],
};
for (const [name, [from,to]] of Object.entries(malformed)) test('held grammar: ' + name, () => held(replace(from,to)));
for (const [name, bytes] of [
  ['UTF-8 overlong', Buffer.from([0xc0,0xaf])], ['UTF-8 surrogate', Buffer.from([0xed,0xa0,0x80])],
  ['UTF-8 truncated', Buffer.from([0xe2,0x82])], ['BOM', Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),labelBytes()])],
  ['bare CR', replace('Fixture App','Fixture\rApp')], ['NUL',replace('Fixture App','Fixture\0App')],
  ['DEL',replace('Fixture App','Fixture\x7fApp')], ['tab in value', replace('Fixture App','Fixture\tApp')],
  ['257 lines', Buffer.from(Array(250).fill('# comment').join('\n')+'\n'+labelBytes().toString())],
]) test('held bytes: ' + name, () => held(bytes));
test('boundary name 128 UTF-8 bytes and exactly 256 logical lines are admitted', () => {
  const bytes = replace('Fixture App','é'.repeat(64));
  const lines = bytes.toString().split('\n'); if (lines.at(-1) === '') lines.pop();
  const boundary = Buffer.from(Array(256-lines.length).fill('# blank').join('\n')+'\n'+bytes.toString());
  assert.equal(parse(boundary).status, 'extracted');
});
test('synthetic dynamic and malformed fixture files are visibly held', () => {
  for (const p of snapshot().payloads.filter(p => p.path !== path)) held(p.bytes, { path: p.path });
});
for (const unsafe of ['/fragments/labels/literal-valid.sh','fragments/labels/../literal-valid.sh','fragments/labels/a.b.sh','fragments/labels/é.sh','fragments\\labels\\literal-valid.sh','fragments/labels/literal-valid.sh/']) {
  test('held label path ' + unsafe, () => held(labelBytes(), { path: unsafe }));
}
test('unknown parser version shape/unknown input fields cannot silently accept', () => {
  assert.equal(parse(labelBytes(), { parserVersion: '', extra: true }).status, 'held');
});
test('matching quote inside a value and adjacent quoted fragments are not one literal', () => {
  held(replace('name="Fixture App"','name="Fixture"App"'));
  held(replace('name="Fixture App"',"name='Fixture''App'"));
});
test('opposite quote inside one literal remains inert text', () => {
  const result = parse(replace('name="Fixture App"', "name=\"Fixture's App\""));
  assert.equal(result.status,'extracted'); assert.equal(result.metadata.name,"Fixture's App");
});
test('oversize parser input is refused before digest/base64 allocation with explicit non-retention', () => {
  const bytes=Buffer.alloc(1048577,0x61), result=parse(bytes);
  assert.equal(result.status,'held'); assert.equal(result.metadata,null);
  assert.equal(result.reason,'oversized-not-retained'); assert.equal(result.byteLength,bytes.length);
  assert.equal(result.sha256,null); assert.equal(result.bytesBase64,null);
});
test('at sign in URL path or query is inert and is not authority userinfo', () => {
  const url='https://downloads.example.test/file@v1.dmg?note=user@host';
  const result=parse(replace('https://downloads.example.test/fixture-v1.dmg',url));
  assert.equal(result.status,'extracted'); assert.equal(result.metadata.downloadURL,url);
});
