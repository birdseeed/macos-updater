import { equal, owned, reasonOf } from './contracts.mjs';
import { validateCheckpoint, validateCheckpointRelation } from './snapshot.mjs';

/** Discovery facts only: neither removal of support nor publication authority. */
export function diffSnapshots(previous,current) {
  try {
    validateCheckpoint(current);
    if (previous !== null) { validateCheckpoint(previous); validateCheckpointRelation(previous,current); }
    const old = new Map((previous?.labels ?? []).map(label => [label.path,label]));
    const next = new Map(current.labels.map(label => [label.path,label]));
    const paths = [...new Set([...old.keys(),...next.keys()])].sort();
    const versionChanged = previous !== null && (previous.parserVersion !== current.parserVersion || previous.policyVersion !== current.policyVersion);
    const events = [];
    for (const path of paths) {
      const before = old.get(path), after = next.get(path);
      if (before && after && before.sha256 === after.sha256 && !versionChanged && equal(before,after)) continue;
      events.push({ kind:!before ? 'added' : !after ? 'withdrawn-upstream' : 'changed',path,
        previousSha256:before?.sha256 ?? null,sha256:after?.sha256 ?? null,
        previousBytesBase64:before?.bytesBase64 ?? null,bytesBase64:after?.bytesBase64 ?? null,
        invalidateAcceptance:Boolean(before),removeApprovedSupport:false,publicationAuthority:false });
    }
    return { status:'compared',events:owned(events),reason:null };
  } catch (error) { return { status:'refused',events:[],reason:reasonOf(error) }; }
}
