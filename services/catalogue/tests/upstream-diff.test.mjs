import test from 'node:test';
import assert from 'node:assert/strict';
import { ingestSnapshot } from '../discovery/upstream/snapshot.mjs';
import { diffSnapshots } from '../discovery/upstream/diff.mjs';
import { buildCandidate, verifyCandidate } from '../discovery/upstream/candidates.mjs';
import { parseLabel } from '../discovery/upstream/literal-parser.mjs';
import { snapshot, bootstrapOptions, nextOptions, revise, complete, copy, path, labelBytes, replaceLabel, policy,
  expectedEvents, candidateFixture, observation, noAuthority, sha, canonical } from './upstream-fixtures.mjs';
const first = () => complete(ingestSnapshot(snapshot(), bootstrapOptions()));
function diff(previous, current) {
  const result = diffSnapshots(previous, current); assert.equal(result.status, 'compared'); return result.events;
}

test('complete initial snapshot emits sorted added discovery facts including held labels', () => {
  const events = diff(null, first()); assert.deepEqual(events.map(({ kind,path }) => ({ kind,path })), expectedEvents.initial);
  for (const event of events) { noAuthority(event); assert.equal(event.removeApprovedSupport, false); }
});
test('duplicate snapshot and next commit with identical bytes create no work or acceptance refresh', () => {
  const previous = first(); assert.deepEqual(diff(previous, previous), []);
  const next = complete(ingestSnapshot(revise(snapshot(), previous), nextOptions(previous)));
  assert.deepEqual(diff(previous, next), expectedEvents.unchanged);
});
test('changed label retains old/new digests and invalidates only affected acceptance', () => {
  const previous = first(), input = revise(snapshot(), previous);
  const bytes = Buffer.from(labelBytes().toString()+'# inert changed provenance\n'); replaceLabel(input, bytes);
  const current = complete(ingestSnapshot(input, nextOptions(previous))), events = diff(previous, current);
  assert.equal(events.length, 1); const event = events[0]; assert.equal(event.kind, 'changed'); assert.equal(event.path, path);
  assert.equal(event.previousSha256, sha(labelBytes())); assert.equal(event.sha256, sha(bytes));
  assert.equal(event.invalidateAcceptance, true); assert.equal(event.removeApprovedSupport, false); noAuthority(event);
  assert.equal(event.previousBytesBase64, labelBytes().toString('base64')); assert.equal(event.bytesBase64, bytes.toString('base64'));
});
test('withdrawal is a discovery fact and cannot delete support or publish', () => {
  const previous = first(), input = revise(snapshot(), previous);
  input.manifest.inventory = input.manifest.inventory.filter(x => x.path !== path); input.payloads = input.payloads.filter(x => x.path !== path);
  const events = diff(previous, complete(ingestSnapshot(input, nextOptions(previous))));
  assert.deepEqual(events.map(({ kind,path }) => ({ kind,path })), expectedEvents.withdrawn);
  assert.equal(events[0].invalidateAcceptance, true); assert.equal(events[0].removeApprovedSupport, false); noAuthority(events[0]);
});
test('diff rejects corrupt or non-successor checkpoint without emitting work', () => {
  const previous = first(), corrupt = copy(previous); corrupt.labels[0].sha256 = '0'.repeat(64);
  const result = diffSnapshots(previous, corrupt); assert.equal(result.status, 'refused'); assert.deepEqual(result.events, []);
  const unrelated = first(); unrelated.priorCheckpointId = 'a'.repeat(64);
  assert.equal(diffSnapshots(previous, unrelated).status, 'refused');
});
test('independent exact route builds a stable candidate and admits recomputed fixture artifact only', () => {
  const result = buildCandidate(first(), path, policy()); assert.equal(result.status, 'candidate');
  assert.equal(result.candidate.candidateId, sha(Buffer.from('Installomator/Installomator\n'+path)));
  noAuthority(result); noAuthority(result.candidate);
  const verified = verifyCandidate(result.candidate, observation());
  assert.equal(verified.status, 'fixture-admitted', 'at least one routed literal must pass complete fixture verification'); noAuthority(verified);
  assert.equal(verified.evidence.artifactSha256, sha(observation().artifactBytes));
  assert.equal(verified.evidence.artifactByteLength, observation().artifactBytes.length);
  assert.equal(verified.evidence.checkerVersion, 'checker-v1');
});
for (const [field, value] of Object.entries({ name: 'Wrong name', type: 'pkg', downloadURL: 'https://evil.example.test/file', claimedTeamID: 'BBBBBBBBBB', labelPath: 'fragments/labels/other.sh', channel: 'beta' })) {
  test('independent route mismatch is held: ' + field, () => {
    const routes = policy(); routes.routes[0][field] = value;
    const result = buildCandidate(first(), path, routes); assert.equal(result.status, 'held'); assert.equal(result.candidate, null); noAuthority(result);
  });
}
test('label changes URL or claimed publisher never self-approve against unchanged route policy', () => {
  for (const [from,to] of [['https://downloads.example.test/fixture-v1.dmg','https://evil.example.test/file'], ['AAAAAAAAAA','BBBBBBBBBB']]) {
    const previous = first(), input = revise(snapshot(), previous); replaceLabel(input, Buffer.from(labelBytes().toString().replace(from,to)));
    const current = complete(ingestSnapshot(input, nextOptions(previous)));
    const result = buildCandidate(current, path, policy()); assert.equal(result.status, 'held'); assert.equal(result.reason, 'route-review-required');
  }
});
test('absent, duplicate, unknown-schema and mismatched-version policy cannot approve', () => {
  const checkpoint = first(); const duplicate = policy(); duplicate.routes.push(copy(duplicate.routes[0]));
  const wrong = policy(); wrong.version = 'policy-v2';
  for (const routes of [null, { ...policy(), schema: 'future' }, duplicate, wrong, { ...policy(), approved: true }, { ...policy(), routes: [] }]) {
    assert.equal(buildCandidate(checkpoint,path,routes).status, 'held');
  }
  assert.equal(buildCandidate(checkpoint, 'fragments/labels/dynamic-held.sh', policy()).status, 'held');
});
test('wrong publisher and tampered artifact remain held despite injected passed booleans', () => {
  for (const input of [observation({ observedPublisher: 'BBBBBBBBBB' }), observation({ artifactBytes: Buffer.from('tampered') }), observation({ artifactBytes: Buffer.from('fixture artifact v1!') })]) {
    const result = verifyCandidate(candidateFixture(), input); assert.equal(result.status, 'held'); noAuthority(result); assert.equal(result.evidence, null);
    assert.match(result.reason, /publisher-mismatch|artifact-mismatch/);
  }
});
test('artifact claimed digest/length cannot override independently recomputed bytes', () => {
  const o = observation({ artifactBytes: Buffer.from('tampered'), artifactSha256: candidateFixture().route.artifactSha256, artifactByteLength: candidateFixture().route.artifactByteLength });
  assert.equal(verifyCandidate(candidateFixture(), o).status, 'held');
});
for (const name of ['signature','notarisation','container','compatibility']) for (const value of ['failed','unknown','unavailable',true]) {
  test(`fixture check ${name}=${value} cannot pass`, () => {
    const o = observation(); o.checks[name] = value;
    const r = verifyCandidate(candidateFixture(),o); assert.equal(r.status, 'held'); noAuthority(r); assert.equal(r.evidence,null);
  });
}
test('missing observation, incomplete checks and unavailable checker are visibly held', () => {
  const incomplete = observation(); delete incomplete.checks.container;
  const badVersion = observation({ checkerVersion: 'x'.repeat(65) });
  for (const o of [null, incomplete, observation({ availability: 'unavailable' }), badVersion, { ...observation(), nativeEvidence: true }]) {
    const r = verifyCandidate(candidateFixture(),o); assert.equal(r.status,'held'); assert.match(r.reason,/\S/); noAuthority(r);
  }
});
test('deliberately broken literal field mapping refuses, exact targeted fixture repair extracts', () => {
  const bad = Buffer.from(labelBytes().toString().replace('expectedTeamID=', 'expectedTeamId='));
  const wrong = parseLabel({ path, bytes: bad, parserVersion: 'literal-v1' }); assert.equal(wrong.status,'held');
  const repaired = parseLabel({ path, bytes: labelBytes(), parserVersion: 'literal-v1' }); assert.equal(repaired.status,'extracted');
  assert.equal(repaired.metadata.claimedTeamID,'AAAAAAAAAA');
  assert.equal(verifyCandidate(candidateFixture(),observation({ observedPublisher: 'BBBBBBBBBB' })).status,'held');
});
test('accepted artifact/evidence bytes are copied and no native trust appears', () => {
  const c = candidateFixture(), o = observation(), r = verifyCandidate(c,o); assert.equal(r.status,'fixture-admitted');
  const saved = JSON.stringify(r); o.artifactBytes.fill(0); o.evidenceRefs[0].sha256 = '0'.repeat(64); c.route.name = 'mutated';
  assert.equal(JSON.stringify(r),saved); noAuthority(r);
});
test('reviewed same-byte parser reclassification invalidates affected acceptance without claiming new source bytes', () => {
  const previous=first(), input=snapshot(); input.manifest.parserVersion='literal-v2'; input.manifest.priorCheckpointId=previous.checkpointId;
  const repair={ component:'parser',fromVersion:'literal-v1',toVersion:'literal-v2',reviewId:'same-source-review',rationale:'Reviewed parser repair reclassifies identical bytes' };
  const current=complete(ingestSnapshot(input,nextOptions(previous,{ parserVersion:'literal-v2',repair })));
  const events=diff(previous,current); assert.equal(events.length,previous.labels.length);
  for (const event of events) {
    assert.equal(event.kind,'changed'); assert.equal(event.invalidateAcceptance,true);
    assert.equal(event.previousSha256,event.sha256); assert.equal(event.previousBytesBase64,event.bytesBase64);
    assert.equal(event.removeApprovedSupport,false); noAuthority(event);
  }
});
test('evidence identity binds verified actual bytes, publisher, all checks and exact evidence references', () => {
  const c=candidateFixture(), o=observation(), r=verifyCandidate(c,o);
  assert.equal(r.status,'fixture-admitted');
  const binding={ repository:c.repository,labelPath:c.labelPath,labelSha256:c.labelSha256,
    parserVersion:c.parserVersion,policyVersion:c.policyVersion,route:c.route,
    checkerVersion:o.checkerVersion,environmentVersion:o.environmentVersion,capabilityVersion:o.capabilityVersion,
    artifactSha256:sha(o.artifactBytes),artifactByteLength:o.artifactBytes.length,observedPublisher:o.observedPublisher,
    checks:o.checks,evidenceRefs:o.evidenceRefs };
  assert.equal(r.evidence.bindingSha256,sha(Buffer.from(canonical(binding))));
  const changed=observation(); changed.evidenceRefs[0].ref='fixture:changed-evidence';
  const other=verifyCandidate(c,changed); assert.equal(other.status,'fixture-admitted');
  assert.notEqual(other.evidence.bindingSha256,r.evidence.bindingSha256);
});
