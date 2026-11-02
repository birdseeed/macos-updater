import test from 'node:test';
import assert from 'node:assert/strict';
import { ingestSnapshot } from '../discovery/upstream/snapshot.mjs';
import { snapshot, bootstrapOptions, nextOptions, revise, complete, refused, copy, sha, contentId, path, labelBytes, replaceLabel, addLabel } from './upstream-fixtures.mjs';

test('complete classification retains all original bytes, licence, attribution and computed checkpoint', () => {
  const input = snapshot(), checkpoint = complete(ingestSnapshot(input, bootstrapOptions()));
  assert.equal(checkpoint.schema, 'fixture-checkpoint-v1'); assert.equal(checkpoint.scope, 'fixture-only');
  assert.equal(checkpoint.repository, input.manifest.repository); assert.equal(checkpoint.commit, input.manifest.commit);
  assert.equal(checkpoint.tree, input.manifest.tree); assert.equal(checkpoint.priorCheckpointId, null);
  assert.equal(checkpoint.parserVersion, 'literal-v1'); assert.equal(checkpoint.policyVersion, 'policy-v1');
  assert.equal(checkpoint.checkpointId, contentId(checkpoint, 'checkpointId'));
  assert.deepEqual(checkpoint.inventory.map(x => x.path), input.manifest.inventory.map(x => x.path).sort());
  assert.equal(checkpoint.labels.length, 3); assert.equal(checkpoint.labels.filter(x => x.status === 'held').length, 2);
  for (const p of input.payloads) {
    const label = checkpoint.labels.find(x => x.path === p.path);
    assert.equal(label.sha256, sha(p.bytes)); assert.equal(label.bytesBase64, p.bytes.toString('base64'));
  }
  assert.equal(checkpoint.license.bytesBase64, input.licenseBytes.toString('base64'));
  assert.equal(checkpoint.license.sha256, sha(input.licenseBytes)); assert.equal(checkpoint.attribution, input.manifest.attribution);
  const saved = JSON.stringify(checkpoint); input.payloads[0].bytes.fill(0); input.licenseBytes.fill(0);
  input.manifest.inventory[0].path = 'changed'; assert.equal(JSON.stringify(checkpoint), saved);
});
test('inventory/payload order does not change canonical checkpoint identity', () => {
  const first = complete(ingestSnapshot(snapshot(), bootstrapOptions())); const reordered = snapshot();
  reordered.manifest.inventory.reverse(); reordered.payloads.reverse();
  assert.deepEqual(complete(ingestSnapshot(reordered, bootstrapOptions())), first);
});
test('optional notice bytes are retained exactly and digest-bound', () => {
  const input = snapshot(), bytes = Buffer.from('Synthetic fixture notice\r\n');
  input.manifest.notices = [{ path: 'NOTICE', sha256: sha(bytes), byteLength: bytes.length }];
  input.noticePayloads = [{ path: 'NOTICE', bytes }];
  const c = complete(ingestSnapshot(input, bootstrapOptions()));
  assert.equal(c.notices[0].bytesBase64, bytes.toString('base64'));
  input.noticePayloads[0].bytes = Buffer.from('tampered'); refused(ingestSnapshot(input, bootstrapOptions()));
});
const invalid = {
  'partial': x => { x.manifest.complete = false; },
  'unknown manifest key': x => { x.manifest.trusted = true; },
  'unknown payload key': x => { x.payloads[0].trusted = true; },
  'wrong schema': x => { x.manifest.schema = 'snapshot-v2'; },
  'foreign repository': x => { x.manifest.repository = 'attacker/Installomator'; },
  'short commit': x => { x.manifest.commit = '123'; },
  'uppercase tree': x => { x.manifest.tree = 'A'.repeat(40); },
  'unsafe timestamp': x => { x.manifest.observedAt = Number.MAX_SAFE_INTEGER + 1; },
  'negative timestamp': x => { x.manifest.observedAt = -1; },
  'fractional timestamp': x => { x.manifest.observedAt = 1.5; },
  'overlong version': x => { x.manifest.parserVersion = 'a'.repeat(65); },
  'nonASCII version': x => { x.manifest.policyVersion = 'é'; },
  'missing label bytes': x => { x.payloads.pop(); },
  'extra label bytes': x => { x.payloads.push({ path: 'fragments/labels/extra.sh', bytes: labelBytes() }); },
  'duplicate inventory': x => { x.manifest.inventory.push(copy(x.manifest.inventory[0])); },
  'duplicate payload': x => { x.payloads.push(copy(x.payloads[0])); },
  'absolute path': x => { x.manifest.inventory[0].path = '/fragments/labels/a.sh'; },
  'traversal path': x => { x.manifest.inventory[0].path = 'fragments/labels/../a.sh'; },
  'ambiguous path': x => { x.manifest.inventory[0].path = 'fragments//labels/a.sh'; },
  'wrong prefix': x => { x.manifest.inventory[0].path = 'labels/a.sh'; },
  'symlink label': x => { x.manifest.inventory[0].kind = 'symlink'; },
  'directory label': x => { x.manifest.inventory[0].kind = 'directory'; },
  'device label': x => { x.manifest.inventory[0].kind = 'device'; },
  'symlink ancestor': x => { x.manifest.inventory[0].ancestors[0].kind = 'symlink'; },
  'non-directory ancestor': x => { x.manifest.inventory[0].ancestors[1].kind = 'regular'; },
  'missing ancestor': x => { x.manifest.inventory[0].ancestors.pop(); },
  'wrong ancestor path': x => { x.manifest.inventory[0].ancestors[0].path = 'other'; },
  'unknown ancestor key': x => { x.manifest.inventory[0].ancestors[0].trusted = true; },
  'wrong digest': x => { x.manifest.inventory[0].sha256 = '0'.repeat(64); },
  'uppercase digest': x => { x.manifest.inventory[0].sha256 = 'A'.repeat(64); },
  'wrong byte length': x => { x.manifest.inventory[0].byteLength++; },
  'fractional byte length': x => { x.manifest.inventory[0].byteLength = 1.1; },
  'string instead of bytes': x => { x.payloads[0].bytes = 'not bytes'; },
  'missing licence': x => { x.licenseBytes = null; },
  'changed licence': x => { x.licenseBytes = Buffer.from('not original'); },
  'no attribution': x => { x.manifest.attribution = ''; },
  'case folding collision': x => { addLabel(x, 'Foo'); addLabel(x, 'foo'); },
  'notice traversal': x => { const bytes = Buffer.from('x'); x.manifest.notices = [{ path: '../NOTICE', sha256: sha(bytes), byteLength: 1 }]; x.noticePayloads = [{ path: '../NOTICE', bytes }]; },
};
for (const [name, mutate] of Object.entries(invalid)) test('snapshot refuses ' + name, () => {
  const input = snapshot(); mutate(input); refused(ingestSnapshot(input, bootstrapOptions()));
});
test('label, total, licence, notice count and inventory count bounds refuse', () => {
  let input = snapshot(); replaceLabel(input, Buffer.alloc(1048577, 0x61)); refused(ingestSnapshot(input, bootstrapOptions()));
  input = snapshot(); input.licenseBytes = Buffer.alloc(1048577); Object.assign(input.manifest.license, { sha256: sha(input.licenseBytes), byteLength: input.licenseBytes.length });
  refused(ingestSnapshot(input, bootstrapOptions()));
  input = snapshot(); for (let i = 0; i < 17; i++) { const bytes = Buffer.from('notice'); const p = 'NOTICE-' + i;
    input.manifest.notices.push({ path: p, sha256: sha(bytes), byteLength: bytes.length }); input.noticePayloads.push({ path: p, bytes }); }
  refused(ingestSnapshot(input, bootstrapOptions()));
  input = snapshot(); const big = Buffer.alloc(1048577); input.manifest.notices = [{ path: 'NOTICE', sha256: sha(big), byteLength: big.length }]; input.noticePayloads = [{ path: 'NOTICE', bytes: big }];
  refused(ingestSnapshot(input, bootstrapOptions()));
  input = snapshot(); const desc = copy(input.manifest.inventory[0]); input.manifest.inventory = Array.from({ length: 10001 }, (_, i) => ({ ...desc, path: 'fragments/labels/a'+i+'.sh', sha256: sha(Buffer.from('x')), byteLength: 1 }));
  input.payloads = input.manifest.inventory.map(x => ({ path: x.path, bytes: Buffer.from('x') })); refused(ingestSnapshot(input, bootstrapOptions()));
  input = snapshot(); input.manifest.inventory = []; input.payloads = []; const mb = Buffer.alloc(1048576, 0x23);
  for (let i = 0; i < 33; i++) { const p = 'fragments/labels/large'+i+'.sh'; input.manifest.inventory.push({ ...desc, path: p, sha256: sha(mb), byteLength: mb.length }); input.payloads.push({ path: p, bytes: mb }); }
  refused(ingestSnapshot(input, bootstrapOptions()));
});
test('explicit bootstrap and retained checkpoint head are mandatory', () => {
  const options = bootstrapOptions(); delete options.expectedCheckpointId; refused(ingestSnapshot(snapshot(), options));
  refused(ingestSnapshot(snapshot(), bootstrapOptions({ bootstrap: false })));
  refused(ingestSnapshot(snapshot(), bootstrapOptions({ expectedCheckpointId: 'a'.repeat(64) })));
});
test('complete checkpoint advances with exact predecessor and monotonic time', () => {
  const previous = complete(ingestSnapshot(snapshot(), bootstrapOptions()));
  const next = complete(ingestSnapshot(revise(snapshot(), previous), nextOptions(previous)));
  assert.equal(next.parentCommit, previous.commit); assert.equal(next.priorCheckpointId, previous.checkpointId);
  assert.equal(next.checkpointId, contentId(next, 'checkpointId')); assert.notEqual(next.checkpointId, previous.checkpointId);
});
test('partial next snapshot never replaces prior complete checkpoint or its age', () => {
  const previous = complete(ingestSnapshot(snapshot(), bootstrapOptions())), input = revise(snapshot(), previous);
  input.manifest.complete = false; refused(ingestSnapshot(input, nextOptions(previous)), previous);
});
test('same exact delivery is duplicate and preserves original checkpoint age', () => {
  const previous = complete(ingestSnapshot(snapshot(), bootstrapOptions()));
  const result = ingestSnapshot(snapshot(), nextOptions(previous)); assert.equal(result.status, 'duplicate'); assert.deepEqual(result.checkpoint, previous);
  const input = snapshot(); input.manifest.observedAt = 9999;
  const later = ingestSnapshot(input, nextOptions(previous)); assert.equal(later.status, 'duplicate'); assert.deepEqual(later.checkpoint, previous);
});
test('same commit with changed bytes or inventory refuses even with recomputed input digests', () => {
  const previous = complete(ingestSnapshot(snapshot(), bootstrapOptions()));
  const input = replaceLabel(snapshot(), Buffer.from(labelBytes().toString() + '# changed\n'));
  refused(ingestSnapshot(input, nextOptions(previous)), previous);
});
for (const field of ['parentCommit','priorCheckpointId','observedAt','parserVersion','policyVersion']) test('next checkpoint rejects mismatched ' + field, () => {
  const previous = complete(ingestSnapshot(snapshot(), bootstrapOptions())), input = revise(snapshot(), previous);
  input.manifest[field] = field === 'observedAt' ? 0 : field === 'parentCommit' ? 'f'.repeat(40) : field === 'priorCheckpointId' ? 'f'.repeat(64) : 'unreviewed-v2';
  refused(ingestSnapshot(input, nextOptions(previous)), previous);
});
test('previous checkpoint content is revalidated, not just its supplied ID', () => {
  const previous = complete(ingestSnapshot(snapshot(), bootstrapOptions())); const bad = copy(previous);
  bad.labels[0].bytesBase64 = Buffer.from('tampered').toString('base64');
  refused(ingestSnapshot(revise(snapshot(), previous), nextOptions(bad)), bad);
  bad.checkpointId = contentId(bad, 'checkpointId');
  refused(ingestSnapshot(revise(snapshot(), previous), nextOptions(bad, { expectedCheckpointId: previous.checkpointId })), bad);
  refused(ingestSnapshot(revise(snapshot(), previous), nextOptions(previous, { expectedCheckpointId: 'f'.repeat(64) })), previous);
});
test('stale replay of earlier commit after advancement refuses', () => {
  const first = complete(ingestSnapshot(snapshot(), bootstrapOptions()));
  const second = complete(ingestSnapshot(revise(snapshot(), first), nextOptions(first)));
  refused(ingestSnapshot(snapshot(), nextOptions(second)), second);
});
test('explicit reviewed parser repair records version and rationale; bare version changes refuse', () => {
  const previous = complete(ingestSnapshot(snapshot(), bootstrapOptions())); const input = revise(snapshot(), previous, { parserVersion: 'literal-v2' });
  refused(ingestSnapshot(input, nextOptions(previous, { parserVersion: 'literal-v2' })), previous);
  const repair = { component: 'parser', fromVersion: 'literal-v1', toVersion: 'literal-v2', reviewId: 'fixture-review-1', rationale: 'Reviewed unchanged literal grammar implementation repair' };
  const next = complete(ingestSnapshot(input, nextOptions(previous, { parserVersion: 'literal-v2', repair })));
  assert.deepEqual(next.repair, repair); assert.equal(next.parserVersion, 'literal-v2');
});
test('reviewed same-commit reclassification binds prior classification without inventing freshness or Git ancestry', () => {
  const previous = complete(ingestSnapshot(snapshot(),bootstrapOptions()));
  const input = snapshot(); input.manifest.parserVersion='literal-v2';
  input.manifest.priorCheckpointId=previous.checkpointId; input.manifest.observedAt=9000;
  const repair = { component:'parser',fromVersion:'literal-v1',toVersion:'literal-v2',reviewId:'same-source-review',rationale:'Reviewed implementation repair on identical upstream bytes' };
  const next = complete(ingestSnapshot(input,nextOptions(previous,{ parserVersion:'literal-v2',repair })));
  assert.equal(next.commit,previous.commit); assert.equal(next.tree,previous.tree);
  assert.equal(next.parentCommit,previous.parentCommit); assert.equal(next.priorCheckpointId,previous.checkpointId);
  assert.equal(next.observedAt,previous.observedAt); assert.notEqual(next.checkpointId,previous.checkpointId);
  assert.deepEqual(next.inventory,previous.inventory); assert.deepEqual(next.license,previous.license); assert.deepEqual(next.notices,previous.notices);
  assert.deepEqual(next.repair,repair); assert.equal(next.checkpointId,contentId(next,'checkpointId'));
  refused(ingestSnapshot(input,nextOptions(previous,{ parserVersion:'literal-v2' })),previous);
  input.manifest.parentCommit=previous.commit;
  refused(ingestSnapshot(input,nextOptions(previous,{ parserVersion:'literal-v2',repair })),previous);
});
test('same-commit reviewed repair still refuses changed source bytes with recomputed digests', () => {
  const previous = complete(ingestSnapshot(snapshot(),bootstrapOptions())), input = snapshot();
  input.manifest.parserVersion='literal-v2'; input.manifest.priorCheckpointId=previous.checkpointId;
  replaceLabel(input,Buffer.from(labelBytes().toString()+'# changed upstream bytes\n'));
  const repair={ component:'parser',fromVersion:'literal-v1',toVersion:'literal-v2',reviewId:'same-source-review',rationale:'Reviewed parser repair cannot authorise a changed immutable source' };
  refused(ingestSnapshot(input,nextOptions(previous,{ parserVersion:'literal-v2',repair })),previous);
});
