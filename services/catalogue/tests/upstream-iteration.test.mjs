import test from 'node:test';
import assert from 'node:assert/strict';
import { advanceAttempt } from '../discovery/upstream/attempts.mjs';
import { candidateFixture, candidateForName, observation, attemptInput, continueInput, recorded, heldAttempt,
  copy, contentId, noAuthority, labelBytes, sha, path, scenario } from './upstream-fixtures.mjs';
const failed = () => observation({ checks: { signature: 'failed', notarisation: 'passed', container: 'passed', compatibility: 'passed' } });
const repair = (component, fromVersion, toVersion) => ({ kind: 'reviewed-repair', component, fromVersion, toVersion,
  reviewId: 'review-'+toVersion, rationale: 'Reviewed targeted fixture implementation repair with refusal regression checks' });
function firstFailure() { return recorded(advanceAttempt(attemptInput({ observation: failed() }))); }
function threeFailures() {
  let result = firstFailure();
  for (let i = 2; i <= 3; i++) result = recorded(advanceAttempt(continueInput(result.state, {
    observation: { ...failed(), checkerVersion: 'checker-v'+i }, retry: repair('checker','checker-v'+(i-1),'checker-v'+i) })));
  return result;
}
test('meaningful iteration: a valid initial fixture attempt appends exact immutable history', () => {
  const input = attemptInput(), result = advanceAttempt(input);
  assert.equal(result.status,'recorded','valid iteration must record, so refusing declarations fail a behavioural assertion');
  assert.equal(result.attempt.outcome,'fixture-admitted'); assert.equal(result.attempt.priorAttemptId,null);
  assert.equal(result.state.schema,'fixture-attempt-state-v1'); assert.equal(result.state.scope,'fixture-only');
  assert.equal(result.state.history.length,1); assert.deepEqual(result.state.history[0],result.attempt);
  assert.equal(result.state.stateId,contentId(result.state,'stateId'));
  assert.equal(result.attempt.attemptId,'attempt-1'); assert.equal(result.attempt.candidateId,input.candidate.candidateId);
  assert.deepEqual(result.attempt.candidate,input.candidate);
  assert.equal(result.attempt.observation.artifactBytesBase64,input.observation.artifactBytes.toString('base64'));
  assert.equal(Object.hasOwn(result.attempt.observation,'artifactBytes'),false);
  assert.deepEqual(result.attempt.observation.evidenceRefs,input.observation.evidenceRefs);
  assert.equal(result.attempt.observation.checkerVersion,'checker-v1'); assert.equal(result.attempt.observedAt,1000);
  assert.equal(result.attempt.activeMilliseconds,10); noAuthority(result.attempt);
  assert.equal(result.state.batches[0].activeMilliseconds,10);
  const saved = JSON.stringify(result); input.candidate.route.name = 'mutated'; input.observation.artifactBytes.fill(0);
  assert.equal(JSON.stringify(result),saved);
});
test('unchanged passed evidence reuses old result without appending or refreshing acceptance time', () => {
  const first = recorded(advanceAttempt(attemptInput()));
  const result = advanceAttempt(continueInput(first.state,{ observedAt: 100000 }));
  assert.equal(result.status,'reused'); assert.deepEqual(result.state,first.state); assert.deepEqual(result.attempt,first.attempt);
});
test('new upstream commit with identical bytes does not freshen passed acceptance', () => {
  const first = recorded(advanceAttempt(attemptInput())); const c = candidateFixture({ commit: '3'.repeat(40), tree:'4'.repeat(40), checkpointId:'b'.repeat(64) });
  const result = advanceAttempt(continueInput(first.state,{ candidate:c }));
  assert.equal(result.status,'reused'); assert.deepEqual(result.state,first.state);
});
test('failed unchanged inputs stop with next action, even when caller invents a new batch', () => {
  const { state } = firstFailure();
  heldAttempt(advanceAttempt(continueInput(state,{ observation:failed() })),state,'unchanged-failure');
  heldAttempt(advanceAttempt(continueInput(state,{ batchId:'batch-2',observation:failed() })),state,'unchanged-failure');
});
test('restored capability permits a linked attempt and preserves failed observation', () => {
  const first = recorded(advanceAttempt(attemptInput({ observation:observation({ availability:'unavailable' }) })));
  assert.equal(first.attempt.outcome,'held'); assert.equal(first.attempt.reason,'capability-unavailable');
  const result = recorded(advanceAttempt(continueInput(first.state,{ observation:observation({ capabilityVersion:'capability-v2' }),
    retry:{ kind:'restored-capability', fromVersion:'capability-v1', toVersion:'capability-v2' } })));
  assert.equal(result.attempt.outcome,'fixture-admitted'); assert.equal(result.attempt.priorAttemptId,first.attempt.attemptId);
  assert.deepEqual(result.state.history[0],first.attempt); assert.equal(result.state.history.length,2);
});
test('bare environment/checker version changes cannot restart unchanged failures', () => {
  const { state } = firstFailure();
  heldAttempt(advanceAttempt(continueInput(state,{ observation:{ ...failed(),checkerVersion:'checker-v2' } })),state,'retry-not-authorised');
  heldAttempt(advanceAttempt(continueInput(state,{ observation:{ ...failed(),environmentVersion:'environment-v2' } })),state,'retry-not-authorised');
});
test('reviewed targeted parser/checker repair records new versions and prior attempt then rechecks', () => {
  const first = firstFailure(), retry = repair('checker','checker-v1','checker-v2');
  const second = recorded(advanceAttempt(continueInput(first.state,{ observation:observation({ checkerVersion:'checker-v2' }),retry })));
  assert.equal(second.attempt.outcome,'fixture-admitted'); assert.deepEqual(second.attempt.retry,retry);
  assert.equal(second.attempt.priorAttemptId,first.attempt.attemptId); assert.deepEqual(second.state.history[0],first.attempt);
  assert.notEqual(second.state.stateId,first.state.stateId);
});
test('new upstream bytes permit another non-trust failure attempt with same stable candidate ID', () => {
  const first = firstFailure(), bytes = Buffer.from(labelBytes().toString()+'# reviewed new upstream bytes\n');
  const c = candidateFixture({ commit:'3'.repeat(40),tree:'4'.repeat(40),checkpointId:'b'.repeat(64),labelSha256:sha(bytes),labelByteLength:bytes.length,labelBytesBase64:bytes.toString('base64') });
  const second = recorded(advanceAttempt(continueInput(first.state,{ candidate:c })));
  assert.equal(second.attempt.candidateId,first.attempt.candidateId); assert.equal(second.attempt.outcome,'fixture-admitted');
});
test('publisher mismatch cannot be retried as generic parser/checker repair or restored environment', () => {
  const first = recorded(advanceAttempt(attemptInput({ observation:observation({ observedPublisher:'BBBBBBBBBB' }) })));
  assert.equal(first.attempt.reason,'publisher-mismatch');
  for (const overrides of [
    { observation:observation({ checkerVersion:'checker-v2' }),retry:repair('checker','checker-v1','checker-v2') },
    { observation:observation({ capabilityVersion:'capability-v2' }),retry:{ kind:'restored-capability',fromVersion:'capability-v1',toVersion:'capability-v2' } },
  ]) heldAttempt(advanceAttempt(continueInput(first.state,overrides)),first.state,'route-review-required');
});
test('changed independent route policy plus explicit review can reverify trust mismatch', () => {
  const first = recorded(advanceAttempt(attemptInput({ observation:observation({ observedPublisher:'BBBBBBBBBB' }) })));
  const bytes = Buffer.from(labelBytes().toString().replace('AAAAAAAAAA','BBBBBBBBBB'));
  const c = candidateFixture({ policyVersion:'policy-v2', labelSha256:sha(bytes),labelByteLength:bytes.length,labelBytesBase64:bytes.toString('base64'),
    route:{ ...candidateFixture().route,version:'route-v2',claimedTeamID:'BBBBBBBBBB' } });
  const retry = { kind:'route-review',fromVersion:'policy-v1',toVersion:'policy-v2',reviewId:'independent-route-review',rationale:'Independently reviewed synthetic publisher change' };
  const result = recorded(advanceAttempt(continueInput(first.state,{ candidate:c,observation:observation({ observedPublisher:'BBBBBBBBBB' }),retry })));
  assert.equal(result.attempt.outcome,'fixture-admitted'); noAuthority(result.attempt); assert.deepEqual(result.state.history[0],first.attempt);
});
test('tamper remains immediately held after reviewed repair', () => {
  const first = firstFailure();
  const result = recorded(advanceAttempt(continueInput(first.state,{ observation:observation({ checkerVersion:'checker-v2',artifactBytes:Buffer.from('tampered') }),retry:repair('checker','checker-v1','checker-v2') })));
  assert.equal(result.attempt.outcome,'held'); assert.equal(result.attempt.reason,'artifact-mismatch'); assert.equal(result.attempt.evidence,null);
});
test('three total attempts cap survives serialisation, changed upstream bytes and a new batch', () => {
  const result = threeFailures(); assert.equal(result.state.history.length,scenario.limits.attemptsPerCandidate);
  const state = JSON.parse(JSON.stringify(result.state));
  heldAttempt(advanceAttempt(continueInput(state,{ batchId:'batch-new',observation:observation({ checkerVersion:'checker-v4' }),retry:repair('checker','checker-v3','checker-v4') })),state,'attempt-limit');
  const bytes = Buffer.from(labelBytes().toString()+'# new data\n');
  const c = candidateFixture({ labelSha256:sha(bytes),labelByteLength:bytes.length,labelBytesBase64:bytes.toString('base64') });
  heldAttempt(advanceAttempt(continueInput(state,{ candidate:c,batchId:'another-batch' })),state,'attempt-limit');
});
test('ten candidates batch limit survives restart and caller-reset counters', () => {
  let state = null;
  for (let i = 0; i < 10; i++) {
    const overrides = { candidate:candidateForName('candidate-'+i),attemptId:'candidate-attempt-'+i };
    state = recorded(advanceAttempt(state ? continueInput(state,overrides) : attemptInput(overrides))).state;
  }
  assert.equal(state.batches[0].candidateIds.length,10);
  const restored = JSON.parse(JSON.stringify(state));
  heldAttempt(advanceAttempt(continueInput(restored,{ candidate:candidateForName('candidate-11') })),restored,'candidate-limit');
  const reset = copy(restored); reset.batches[0].candidateIds = [];
  assert.equal(advanceAttempt(continueInput(reset,{ expectedStateId:restored.stateId,candidate:candidateForName('candidate-11') })).status,'refused');
});
test('active work bound is inclusive and cannot be reset by restart or later wall time', () => {
  const first = recorded(advanceAttempt(attemptInput({ activeMilliseconds:1800000 })));
  assert.equal(first.state.batches[0].activeMilliseconds,1800000);
  const restored = JSON.parse(JSON.stringify(first.state));
  heldAttempt(advanceAttempt(continueInput(restored,{ candidate:candidateForName('second'),activeMilliseconds:1,observedAt:9000000 })),restored,'active-time-limit');
  const initial = advanceAttempt(attemptInput({ activeMilliseconds:1800001 })); assert.equal(initial.status,'held'); assert.equal(initial.reason,'active-time-limit');
});
test('unavailable checker records zero active work and no invented waiting charge', () => {
  const r = recorded(advanceAttempt(attemptInput({ observation:observation({ availability:'unavailable' }),activeMilliseconds:0 })));
  assert.equal(r.state.batches[0].activeMilliseconds,0); assert.equal(r.attempt.outcome,'held');
});
for (const value of [-1,1.5,NaN,Infinity,Number.MAX_SAFE_INTEGER+1]) test('unsafe injected active duration '+value+' refuses', () => {
  assert.equal(advanceAttempt(attemptInput({ activeMilliseconds:value })).status,'refused');
});
test('unsafe or regressing observed time refuses without losing history', () => {
  const first = firstFailure();
  for (const observedAt of [-1,999,NaN,Infinity,Number.MAX_SAFE_INTEGER+1]) {
    const result = advanceAttempt(continueInput(first.state,{ observedAt })); assert.equal(result.status,'refused'); assert.deepEqual(result.state,first.state);
  }
});
test('bootstrap requires explicit null retained head and state, and cannot reset a supplied history', () => {
  const input = attemptInput(); delete input.expectedStateId; assert.equal(advanceAttempt(input).status,'refused');
  assert.equal(advanceAttempt(attemptInput({ bootstrap:false })).status,'refused');
  assert.equal(advanceAttempt(attemptInput({ expectedStateId:'a'.repeat(64) })).status,'refused');
  const first = firstFailure(); assert.equal(advanceAttempt(continueInput(first.state,{ bootstrap:true })).status,'refused');
  assert.equal(advanceAttempt(attemptInput({ state:null,bootstrap:true,expectedStateId:first.state.stateId })).status,'refused');
});
test('retained head rejects stale, truncated, tampered and recomputed forged history', () => {
  const first = firstFailure(); const second = recorded(advanceAttempt(continueInput(first.state,{ observation:observation({ checkerVersion:'checker-v2' }),retry:repair('checker','checker-v1','checker-v2') })));
  assert.equal(advanceAttempt(continueInput(first.state,{ expectedStateId:second.state.stateId })).status,'refused');
  for (const mutate of [s => s.history.pop(),s => { s.history[0].observedAt++; },s => { s.history[1].priorAttemptId=null; },s => { s.batches[0].activeMilliseconds=0; }]) {
    const altered = copy(second.state); mutate(altered);
    assert.equal(advanceAttempt(continueInput(altered,{ expectedStateId:second.state.stateId })).status,'refused');
    altered.stateId = contentId(altered,'stateId');
    assert.equal(advanceAttempt(continueInput(altered,{ expectedStateId:second.state.stateId })).status,'refused');
  }
});
test('internally inconsistent history refuses even when a caller recomputes its head', () => {
  const first = firstFailure(); const invalid = copy(first.state); invalid.history[0].candidate.labelSha256='0'.repeat(64);
  invalid.stateId=contentId(invalid,'stateId'); assert.equal(advanceAttempt(continueInput(invalid)).status,'refused');
});
test('duplicate attempt IDs and caller-chosen unstable candidate IDs refuse', () => {
  const first = firstFailure();
  assert.equal(advanceAttempt(continueInput(first.state,{ attemptId:first.attempt.attemptId,observation:observation({ checkerVersion:'checker-v2' }),retry:repair('checker','checker-v1','checker-v2') })).status,'refused');
  assert.equal(advanceAttempt(attemptInput({ candidate:candidateFixture({ candidateId:'f'.repeat(64) }) })).status,'refused');
});
test('changed relevant bindings reverify passed evidence, unrelated history is preserved', () => {
  const first = recorded(advanceAttempt(attemptInput()));
  const unrelated = recorded(advanceAttempt(continueInput(first.state,{ candidate:candidateForName('unrelated') })));
  for (const change of [
    { observation:observation({ checkerVersion:'checker-v2' }) },
    { observation:observation({ environmentVersion:'environment-v2' }) },
    { observation:observation({ capabilityVersion:'capability-v2' }) },
    { candidate:candidateFixture({ parserVersion:'literal-v2' }) },
    { candidate:candidateFixture({ policyVersion:'policy-v2',route:{ ...candidateFixture().route,version:'route-v2' } }) },
  ]) {
    const r = recorded(advanceAttempt(continueInput(unrelated.state,change)));
    assert.deepEqual(r.state.history.slice(0,2),unrelated.state.history);
    assert.equal(r.attempt.priorAttemptId,first.attempt.attemptId);
    assert.notEqual(r.attempt.evidence.bindingSha256,first.attempt.evidence.bindingSha256);
  }
});
test('oversize identifiers, evidence lists, refs, digests and repair rationale refuse', () => {
  const cases = [attemptInput({ attemptId:'a'.repeat(65) }),attemptInput({ batchId:'é' }),
    attemptInput({ observation:observation({ evidenceRefs:Array(17).fill({ ref:'fixture:x',sha256:'a'.repeat(64) }) }) }),
    attemptInput({ observation:observation({ evidenceRefs:[{ ref:'é'.repeat(513),sha256:'a'.repeat(64) }] }) }),
    attemptInput({ observation:observation({ evidenceRefs:[{ ref:'fixture:x',sha256:'A'.repeat(64) }] }) }),
    attemptInput({ retry:{ ...repair('checker','checker-v1','checker-v2'),rationale:'x'.repeat(1025) } }),
    attemptInput({ extra:true })];
  for (const input of cases) assert.equal(advanceAttempt(input).status,'refused');
});
test('saved-state collection and canonical byte ceilings stop without evicting history', () => {
  const first = firstFailure();
  const manyAttempts = copy(first.state); manyAttempts.history=Array(30001).fill(first.attempt);
  const manyBatches = copy(first.state); manyBatches.batches=Array(1001).fill(first.state.batches[0]);
  const manyCandidates = copy(first.state); manyCandidates.batches[0].candidateIds=Array.from({length:10001},(_,i)=>String(i));
  const tooManyBytes = copy(first.state); tooManyBytes.history[0].reason='x'.repeat(16777217);
  for (const state of [manyAttempts,manyBatches,manyCandidates,tooManyBytes]) {
    const r = advanceAttempt(continueInput(state,{ expectedStateId:first.state.stateId }));
    assert.equal(r.status,'refused'); assert.equal(r.reason,'state-limit'); assert.match(r.nextAction,/\S/);
  }
});
test('unfinished candidate cannot escape its originating active-time budget by changing batch', () => {
  const first = recorded(advanceAttempt(attemptInput({ observation:failed(),activeMilliseconds:1800000 })));
  const state = JSON.parse(JSON.stringify(first.state));
  heldAttempt(advanceAttempt(continueInput(state,{ batchId:'batch-2',activeMilliseconds:1,
    observation:observation({ checkerVersion:'checker-v2' }),retry:repair('checker','checker-v1','checker-v2') })),state,'active-time-limit');
  const unrelated = recorded(advanceAttempt(continueInput(state,{ batchId:'batch-independent',candidate:candidateForName('independent'),activeMilliseconds:1 })));
  assert.equal(unrelated.attempt.outcome,'fixture-admitted'); assert.equal(unrelated.state.batches[0].activeMilliseconds,1800000);
});
test('invalid changed observations cannot reuse old passed evidence merely because versions match', () => {
  const first = recorded(advanceAttempt(attemptInput()));
  for (const o of [observation({ observedPublisher:'BBBBBBBBBB' }),observation({ artifactBytes:Buffer.from('tampered') }),failed(),
    observation({ availability:'unavailable' })]) {
    const r = recorded(advanceAttempt(continueInput(first.state,{ observation:o })));
    assert.equal(r.attempt.outcome,'held'); assert.equal(r.attempt.evidence,null);
    assert.deepEqual(r.state.history[0],first.attempt); assert.equal(r.state.history.length,2);
  }
});
test('valid changed evidence references reverify into a newly bound admitted row without reusing old evidence', () => {
  const first = recorded(advanceAttempt(attemptInput()));
  const changedRefs = observation(); changedRefs.evidenceRefs[0].sha256=sha(Buffer.from('different evidence bytes'));
  const changedRefId = observation(); changedRefId.evidenceRefs[0].ref='fixture:other-evidence';
  for (const o of [changedRefs,changedRefId]) {
    const r = recorded(advanceAttempt(continueInput(first.state,{ observation:o })));
    assert.equal(r.attempt.outcome,'fixture-admitted');
    assert.notEqual(r.attempt.evidence.bindingSha256,first.attempt.evidence.bindingSha256);
    assert.deepEqual(r.attempt.evidence.evidenceRefs,o.evidenceRefs);
    assert.equal(r.attempt.priorAttemptId,first.attempt.attemptId);
    assert.deepEqual(r.state.history[0],first.attempt); assert.equal(r.state.history.length,2);
    noAuthority(r.attempt);
  }
});
