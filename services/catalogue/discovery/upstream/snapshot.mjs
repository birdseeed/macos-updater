import { MiB, repository, need, record, list, text, identifier, integer, hex, labelPath, byteView,
  digest, decode64, equal, identity, without, copy, validateRepair, reasonOf, boundedData } from './contracts.mjs';
import { parseLabel } from './literal-parser.mjs';

const manifestKeys = ['schema','repository','commit','tree','parentCommit','priorCheckpointId','parserVersion','policyVersion','observedAt','complete','inventory','license','notices','attribution'];
const checkpointKeys = ['schema','scope','repository','commit','tree','parentCommit','priorCheckpointId','parserVersion','policyVersion','observedAt','inventory','labels','license','notices','attribution','repair','checkpointId'];
const ancestors = [{ path:'fragments',kind:'directory' },{ path:'fragments/labels',kind:'directory' }];
const descriptorKeys = ['path','sha256','byteLength'];
const labelKeys = ['status','path','sha256','byteLength','bytesBase64','parserVersion','metadata','reason'];

function descriptor(value, notice = false) {
  record(value, descriptorKeys); hex(value.sha256); integer(value.byteLength, MiB);
  need(typeof value.path === 'string' && (notice ? /^NOTICE(?:-[A-Za-z0-9_-]+)?$/.test(value.path) : value.path === 'LICENSE'));
  text(value.path, 1024);
}
function validateManifest(m) {
  boundedData(m,128*MiB);
  record(m, manifestKeys);
  need(m.schema === 'fixture-snapshot-v1' && m.repository === repository && m.complete === true, 'incomplete-snapshot');
  hex(m.commit,40); hex(m.tree,40);
  if (m.parentCommit !== null) hex(m.parentCommit,40);
  if (m.priorCheckpointId !== null) hex(m.priorCheckpointId);
  identifier(m.parserVersion); identifier(m.policyVersion); integer(m.observedAt); text(m.attribution);
  list(m.inventory,10000); list(m.notices,16); descriptor(m.license);
  const paths = new Set(); let total = 0;
  for (const item of m.inventory) {
    record(item, ['path','kind','ancestors','sha256','byteLength']); labelPath(item.path);
    need(item.kind === 'regular'); list(item.ancestors,2); need(item.ancestors.length === 2);
    for (const ancestor of item.ancestors) record(ancestor,['path','kind']);
    need(equal(item.ancestors,ancestors), 'unsafe-ancestor');
    hex(item.sha256); integer(item.byteLength,MiB); total += item.byteLength;
    need(total <= 32 * MiB,'byte-limit');
    need(!paths.has(item.path.toLowerCase()),'ambiguous-path'); paths.add(item.path.toLowerCase());
  }
  const notices = new Set();
  for (const item of m.notices) { descriptor(item,true); need(!notices.has(item.path),'ambiguous-path'); notices.add(item.path); }
}
function payloadMap(payloads, maximum) {
  list(payloads,maximum); const result = new Map();
  for (const p of payloads) {
    record(p,['path','bytes']); need(typeof p.path === 'string' && Buffer.byteLength(p.path) <= 1024 && !result.has(p.path),'ambiguous-path');
    byteView(p.bytes,MiB); result.set(p.path,p.bytes);
  }
  return result;
}
function retain(desc, bytes) {
  const view = byteView(bytes,MiB);
  need(view.length === desc.byteLength && digest(view) === desc.sha256,'content-mismatch');
  return { ...copy(desc),bytesBase64:view.toString('base64') };
}
function assemble(input) {
  record(input,['manifest','payloads','licenseBytes','noticePayloads']);
  const m = input.manifest; validateManifest(m);
  const payloads = payloadMap(input.payloads,10000), notices = payloadMap(input.noticePayloads,16);
  need(payloads.size === m.inventory.length && notices.size === m.notices.length,'incomplete-snapshot');
  // Bound actual payload sizes as well as declared lengths before classification.
  let total = 0;
  for (const bytes of payloads.values()) { total += bytes.byteLength; need(total <= 32 * MiB,'byte-limit'); }
  const inventory = [...m.inventory].sort((a,b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  const labels = inventory.map(desc => {
    need(payloads.has(desc.path),'incomplete-snapshot'); const bytes = payloads.get(desc.path);
    const view = byteView(bytes,MiB); need(view.length === desc.byteLength && digest(view) === desc.sha256,'content-mismatch');
    return parseLabel({ path:desc.path,bytes:view,parserVersion:m.parserVersion });
  });
  const license = retain(m.license,input.licenseBytes);
  const retainedNotices = [...m.notices].sort((a,b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0).map(desc => {
    need(notices.has(desc.path),'incomplete-snapshot'); return retain(desc,notices.get(desc.path));
  });
  return { schema:'fixture-checkpoint-v1',scope:'fixture-only',repository:m.repository,
    commit:m.commit,tree:m.tree,parentCommit:m.parentCommit,priorCheckpointId:m.priorCheckpointId,
    parserVersion:m.parserVersion,policyVersion:m.policyVersion,observedAt:m.observedAt,
    inventory:copy(inventory),labels,license,notices:retainedNotices,attribution:m.attribution };
}
function manifestFrom(checkpoint) {
  return { schema:'fixture-snapshot-v1',repository:checkpoint.repository,commit:checkpoint.commit,tree:checkpoint.tree,
    parentCommit:checkpoint.parentCommit,priorCheckpointId:checkpoint.priorCheckpointId,
    parserVersion:checkpoint.parserVersion,policyVersion:checkpoint.policyVersion,observedAt:checkpoint.observedAt,
    complete:true,inventory:checkpoint.inventory,license:without(checkpoint.license,'bytesBase64'),
    notices:checkpoint.notices.map(n => without(n,'bytesBase64')),attribution:checkpoint.attribution };
}

/** Internal structural verification, not authentication of an upstream or stored head. */
export function validateCheckpoint(checkpoint) {
  boundedData(checkpoint,128*MiB);
  record(checkpoint,checkpointKeys);
  need(checkpoint.schema === 'fixture-checkpoint-v1' && checkpoint.scope === 'fixture-only');
  hex(checkpoint.checkpointId); list(checkpoint.labels,10000); list(checkpoint.notices,16);
  record(checkpoint.license,[...descriptorKeys,'bytesBase64']);
  for (const notice of checkpoint.notices) record(notice,[...descriptorKeys,'bytesBase64']);
  const manifest = manifestFrom(checkpoint); validateManifest(manifest);
  validateRepair(checkpoint.repair,['parser','policy']);
  if (checkpoint.repair !== null) need(checkpoint.repair.toVersion === checkpoint[checkpoint.repair.component+'Version']);
  need(checkpoint.labels.length === checkpoint.inventory.length);
  // Check descriptors and all encoded lengths before allocating decoded buffers.
  for (const label of checkpoint.labels) {
    record(label,labelKeys); integer(label.byteLength,MiB);
    need(typeof label.bytesBase64 === 'string' && label.bytesBase64.length <= 4*Math.ceil(MiB/3));
  }
  const input = { manifest,payloads:checkpoint.labels.map(label => ({ path:label.path,bytes:decode64(label.bytesBase64,MiB) })),
    licenseBytes:decode64(checkpoint.license.bytesBase64,MiB),noticePayloads:checkpoint.notices.map(n => ({ path:n.path,bytes:decode64(n.bytesBase64,MiB) })) };
  const reconstructed = { ...assemble(input),repair:checkpoint.repair };
  need(equal(reconstructed,without(checkpoint,'checkpointId')),'checkpoint-content-mismatch');
  need(identity(reconstructed) === checkpoint.checkpointId,'checkpoint-id-mismatch');
  return checkpoint;
}
function sourceBinding(c) {
  return { repository:c.repository,commit:c.commit,tree:c.tree,parentCommit:c.parentCommit,inventory:c.inventory,
    license:c.license,notices:c.notices,attribution:c.attribution,
    labels:c.labels.map(({path,sha256,byteLength,bytesBase64}) => ({path,sha256,byteLength,bytesBase64})) };
}
function validateVersionTransition(previous,current,repair) {
  const changed = ['parser','policy'].filter(part => previous[part+'Version'] !== current[part+'Version']);
  if (changed.length === 0) { need(repair === null,'unnecessary-repair'); return; }
  need(changed.length === 1 && repair !== null,'version-review-required');
  validateRepair(repair,['parser','policy']);
  need(repair.component === changed[0] && repair.fromVersion === previous[changed[0]+'Version'] && repair.toVersion === current[changed[0]+'Version'],'version-review-required');
}
/** Validate relation separately so diff cannot accept a forged unrelated successor. */
export function validateCheckpointRelation(previous,current) {
  need(current.observedAt >= previous.observedAt,'stale-observation');
  if (current.checkpointId === previous.checkpointId) return;
  need(current.priorCheckpointId === previous.checkpointId,'wrong-predecessor');
  validateVersionTransition(previous,current,current.repair);
  if (current.commit === previous.commit) {
    need(current.repair !== null && equal(sourceBinding(previous),sourceBinding(current)),'immutable-source-changed');
    need(current.observedAt === previous.observedAt,'reclassification-freshness');
  } else {
    need(current.parentCommit === previous.commit && current.commit !== previous.parentCommit,'wrong-predecessor');
  }
}
export function ingestSnapshot(input,options) {
  let previous = null;
  try {
    record(options,['previous','expectedCheckpointId','bootstrap','parserVersion','policyVersion','repair']);
    previous = options.previous;
    identifier(options.parserVersion); identifier(options.policyVersion); validateRepair(options.repair,['parser','policy']);
    need(typeof options.bootstrap === 'boolean');
    if (previous === null) {
      need(options.bootstrap === true && options.expectedCheckpointId === null && options.repair === null,'missing-baseline');
    } else {
      need(options.bootstrap === false,'unexpected-bootstrap'); hex(options.expectedCheckpointId);
      validateCheckpoint(previous); need(previous.checkpointId === options.expectedCheckpointId,'retained-head-mismatch');
    }
    const current = assemble(input);
    need(current.parserVersion === options.parserVersion && current.policyVersion === options.policyVersion,'version-policy-mismatch');
    if (previous === null) need(current.parentCommit === null && current.priorCheckpointId === null,'wrong-predecessor');
    else {
      need(current.observedAt >= previous.observedAt,'stale-observation');
      validateVersionTransition(previous,current,options.repair);
      if (current.commit === previous.commit) {
        need(equal(sourceBinding(previous),sourceBinding(current)),'immutable-source-changed');
        if (options.repair === null) {
          need(current.priorCheckpointId === previous.priorCheckpointId || current.priorCheckpointId === previous.checkpointId,'wrong-predecessor');
          return { status:'duplicate',checkpoint:copy(previous),reason:null,nextAction:null };
        }
        need(current.priorCheckpointId === previous.checkpointId,'wrong-predecessor');
        current.observedAt = previous.observedAt;
      } else need(current.parentCommit === previous.commit && current.priorCheckpointId === previous.checkpointId && current.commit !== previous.parentCommit,'wrong-predecessor');
    }
    current.repair = options.repair === null ? null : copy(options.repair);
    boundedData(current,128*MiB);
    current.checkpointId = identity(current);
    return { status:'complete',checkpoint:copy(current),reason:null,nextAction:null };
  } catch (error) {
    return { status:'refused',checkpoint:previous,reason:reasonOf(error),nextAction:'Supply a complete valid fixture snapshot and retained checkpoint head' };
  }
}
