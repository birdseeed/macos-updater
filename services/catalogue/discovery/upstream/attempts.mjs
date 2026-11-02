import { MiB, need, record, list, identifier, integer, hex, text, decode64, byteView, equal,
  identity, owned, without, reasonOf, boundedData } from './contracts.mjs';
import { validateCandidate, validateObservation, verifyCandidate, observationKeys } from './candidates.mjs';

const inputKeys = ['state','expectedStateId','bootstrap','batchId','attemptId','candidate','observation','observedAt','activeMilliseconds','retry'];
const rowKeys = ['attemptId','candidateId','batchId','priorAttemptId','observedAt','activeMilliseconds','candidate','observation','retry','outcome','reason','evidence','publicationAuthority'];
const batchKeys = ['batchId','candidateIds','activeMilliseconds','firstObservedAt','lastObservedAt'];
const savedObservationKeys = observationKeys.map(key => key === 'artifactBytes' ? 'artifactBytesBase64' : key);
const stateLimit = 16 * MiB;
const nextAction = 'Provide changed upstream bytes, a reviewed repair or restored fixture capability within retained limits';

function validateRetry(retry) {
  if (retry === null) return;
  need(retry && typeof retry === 'object');
  // Obtain the discriminator without invoking an input getter.
  const descriptor = Object.getOwnPropertyDescriptor(retry,'kind');
  need(descriptor && Object.hasOwn(descriptor,'value'));
  if (descriptor.value === 'reviewed-repair') {
    record(retry,['kind','component','fromVersion','toVersion','reviewId','rationale']);
    need(['parser','checker','policy','environment'].includes(retry.component));
    identifier(retry.reviewId); text(retry.rationale);
  } else if (descriptor.value === 'route-review') {
    record(retry,['kind','fromVersion','toVersion','reviewId','rationale']);
    identifier(retry.reviewId); text(retry.rationale);
  } else {
    record(retry,['kind','fromVersion','toVersion']); need(retry.kind === 'restored-capability');
  }
  identifier(retry.fromVersion); identifier(retry.toVersion); need(retry.fromVersion !== retry.toVersion);
}
function saveObservation(observation) {
  return { ...without(observation,'artifactBytes'),artifactBytesBase64:byteView(observation.artifactBytes,32*MiB).toString('base64') };
}
function restoreObservation(observation) {
  record(observation,savedObservationKeys);
  return { ...without(observation,'artifactBytesBase64'),artifactBytes:decode64(observation.artifactBytesBase64,32*MiB) };
}
function version(component,candidate,observation) {
  return ['parser','policy'].includes(component) ? candidate[component+'Version'] : observation[component+'Version'];
}
function failureBinding(candidate,observation) {
  return { candidate:without(without(without(candidate,'checkpointId'),'commit'),'tree'),observation };
}
function retryHold(prior,request,savedObservation) {
  if (!prior) { need(request.retry === null,'unexpected-retry'); return null; }
  if (prior.outcome === 'fixture-admitted') { need(request.retry === null,'unexpected-retry'); return null; }
  const retry = request.retry;
  const trustFailure = ['publisher-mismatch','artifact-mismatch'].includes(prior.reason);
  if (trustFailure) {
    if (!(retry?.kind === 'route-review' && prior.candidate.policyVersion !== request.candidate.policyVersion &&
      prior.candidate.route.version !== request.candidate.route.version && retry.fromVersion === prior.candidate.policyVersion && retry.toVersion === request.candidate.policyVersion)) return 'route-review-required';
    return null;
  }
  if (request.candidate.labelSha256 !== prior.candidate.labelSha256 && retry === null) return null;
  if (retry?.kind === 'reviewed-repair') {
    const before = version(retry.component,prior.candidate,prior.observation), after = version(retry.component,request.candidate,savedObservation);
    if (before !== after && retry.fromVersion === before && retry.toVersion === after) return null;
  }
  if (retry?.kind === 'restored-capability' && prior.reason === 'capability-unavailable' && savedObservation.availability === 'available' &&
    retry.fromVersion === prior.observation.capabilityVersion && retry.toVersion === savedObservation.capabilityVersion) return null;
  if (retry === null && equal(failureBinding(prior.candidate,prior.observation),failureBinding(request.candidate,savedObservation))) return 'unchanged-failure';
  return 'retry-not-authorised';
}
function context() { return { attempts:new Set(),candidates:new Map(),batches:new Map(),lastObservedAt:null,rows:0 }; }

// This transition routine is shared by incoming requests and full history replay.
// Replay compares every generated row and batch summary to saved data; a recomputed
// caller hash cannot make internally impossible history pass structural validation.
function transition(ctx,request) {
  identifier(request.batchId); identifier(request.attemptId); integer(request.observedAt); integer(request.activeMilliseconds);
  validateCandidate(request.candidate); validateObservation(request.observation); validateRetry(request.retry);
  need(ctx.lastObservedAt === null || request.observedAt >= ctx.lastObservedAt,'regressing-clock');
  need(!ctx.attempts.has(request.attemptId),'duplicate-attempt-id');
  const priorAttempts = ctx.candidates.get(request.candidate.candidateId) ?? [], prior = priorAttempts.at(-1);
  // Refuse obviously oversized saved work before encoding artifact bytes.
  need(4*Math.ceil(request.observation.artifactBytes.byteLength/3) + request.candidate.labelBytesBase64.length <= stateLimit,'state-limit');
  const verified = verifyCandidate(request.candidate,request.observation);
  if (prior?.outcome === 'fixture-admitted' && verified.status === 'fixture-admitted' &&
    prior.evidence.bindingSha256 === verified.evidence.bindingSha256) return { status:'reused',row:prior };
  if (priorAttempts.length >= 3) return { status:'held',reason:'attempt-limit' };
  // Unfinished work retains its originating batch's cumulative active budget.
  const batchId = prior?.outcome === 'held' ? prior.batchId : request.batchId;
  const batch = ctx.batches.get(batchId);
  if (batch && !batch.candidateIds.includes(request.candidate.candidateId) && batch.candidateIds.length >= 10) return { status:'held',reason:'candidate-limit' };
  if (request.activeMilliseconds > 1800000 - (batch?.activeMilliseconds ?? 0)) return { status:'held',reason:'active-time-limit' };
  need(ctx.rows < 30000 && (ctx.candidates.has(request.candidate.candidateId) || ctx.candidates.size < 10000) &&
    (batch || ctx.batches.size < 1000),'state-limit');
  const savedObservation = saveObservation(request.observation), hold = retryHold(prior,request,savedObservation);
  if (hold) return { status:'held',reason:hold };
  const row = { attemptId:request.attemptId,candidateId:request.candidate.candidateId,batchId,
    priorAttemptId:prior?.attemptId ?? null,observedAt:request.observedAt,activeMilliseconds:request.activeMilliseconds,
    candidate:request.candidate,observation:savedObservation,retry:request.retry,outcome:verified.status,
    reason:verified.reason,evidence:verified.evidence,publicationAuthority:false };
  boundedData(row,stateLimit);
  return { status:'recorded',row };
}
function append(ctx,row) {
  ctx.attempts.add(row.attemptId); ctx.rows++; ctx.lastObservedAt = row.observedAt;
  const attempts = ctx.candidates.get(row.candidateId) ?? [];
  attempts.push(row); ctx.candidates.set(row.candidateId,attempts);
  let batch = ctx.batches.get(row.batchId);
  if (!batch) {
    batch = { batchId:row.batchId,candidateIds:[],activeMilliseconds:0,firstObservedAt:row.observedAt,lastObservedAt:row.observedAt };
    ctx.batches.set(row.batchId,batch);
  }
  if (!batch.candidateIds.includes(row.candidateId)) batch.candidateIds.push(row.candidateId);
  batch.activeMilliseconds += row.activeMilliseconds; batch.lastObservedAt = row.observedAt;
}
function validateState(state,expectedStateId) {
  boundedData(state,stateLimit);
  record(state,['schema','scope','history','batches','stateId']);
  need(state.schema === 'fixture-attempt-state-v1' && state.scope === 'fixture-only'); hex(state.stateId); hex(expectedStateId);
  list(state.history,30000,'state-limit'); list(state.batches,1000,'state-limit');
  for (const batch of state.batches) {
    record(batch,batchKeys); list(batch.candidateIds,10000,'state-limit');
  }
  need(state.stateId === expectedStateId,'retained-head-mismatch');
  need(identity(without(state,'stateId')) === state.stateId,'state-id-mismatch');
  const ctx = context();
  for (const row of state.history) {
    record(row,rowKeys);
    const result = transition(ctx,{ batchId:row.batchId,attemptId:row.attemptId,candidate:row.candidate,
      observation:restoreObservation(row.observation),observedAt:row.observedAt,activeMilliseconds:row.activeMilliseconds,retry:row.retry });
    need(result.status === 'recorded' && equal(result.row,row),'invalid-history');
    append(ctx,row);
  }
  need(equal([...ctx.batches.values()],state.batches),'invalid-batch-history');
  return ctx;
}

/** Pure bounded fixture history. Independent supplied heads are not storage authority. */
export function advanceAttempt(input) {
  let state = null;
  try {
    record(input,inputKeys); state = input.state;
    need(typeof input.bootstrap === 'boolean');
    let ctx;
    if (state === null) {
      need(input.bootstrap === true && input.expectedStateId === null,'missing-baseline'); ctx = context();
    } else {
      need(input.bootstrap === false,'unexpected-bootstrap'); ctx = validateState(state,input.expectedStateId);
    }
    const result = transition(ctx,input);
    if (result.status === 'held') return { status:'held',state,attempt:null,reason:result.reason,nextAction };
    if (result.status === 'reused') return { status:'reused',state:owned(state),attempt:owned(result.row),reason:null,nextAction:null };
    append(ctx,result.row);
    const next = { schema:'fixture-attempt-state-v1',scope:'fixture-only',history:[...(state?.history ?? []),result.row],batches:[...ctx.batches.values()] };
    // Traverse/count before serialising, cloning or hashing the accumulated state.
    boundedData(next,stateLimit); next.stateId = identity(next);
    boundedData(next,stateLimit);
    return { status:'recorded',state:owned(next),attempt:owned(result.row),reason:result.row.reason,
      nextAction:result.row.outcome === 'held' ? nextAction : null };
  } catch (error) { return { status:'refused',state,attempt:null,reason:reasonOf(error),nextAction:'Supply valid complete retained fixture history and its independent head within resource limits' }; }
}
