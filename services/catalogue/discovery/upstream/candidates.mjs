import { MiB, repository, need, record, list, identifier, integer, hex, labelPath, byteView,
  digest, decode64, identity, owned, reasonOf, evidenceRefs } from './contracts.mjs';
import { parseLabel, validateMetadata } from './literal-parser.mjs';
import { validateCheckpoint } from './snapshot.mjs';

const routeKeys = ['routeId','version','labelPath','name','type','downloadURL','claimedTeamID','channel','artifactSha256','artifactByteLength'];
const candidateKeys = ['schema','scope','candidateId','repository','checkpointId','commit','tree','labelPath','labelSha256','labelByteLength','labelBytesBase64','parserVersion','policyVersion','route','publicationAuthority'];
export const observationKeys = ['schema','checkerVersion','environmentVersion','capabilityVersion','availability','artifactBytes','observedPublisher','checks','evidenceRefs'];
const checkKeys = ['signature','notarisation','container','compatibility'];
function metadataOf(route) {
  return { name:route.name,type:route.type,downloadURL:route.downloadURL,claimedTeamID:route.claimedTeamID };
}
function validateRoute(route) {
  record(route,routeKeys); identifier(route.routeId); identifier(route.version); labelPath(route.labelPath);
  validateMetadata(metadataOf(route)); need(route.channel === 'stable','route-review-required');
  hex(route.artifactSha256); integer(route.artifactByteLength,32*MiB);
}
function routeMatches(route,path,metadata) {
  return route.labelPath === path && Object.keys(metadata).every(key => route[key] === metadata[key]);
}
export function validateCandidate(candidate) {
  record(candidate,candidateKeys);
  need(candidate.schema === 'fixture-candidate-v1' && candidate.scope === 'fixture-only' && candidate.repository === repository && candidate.publicationAuthority === false);
  hex(candidate.candidateId); hex(candidate.checkpointId); hex(candidate.commit,40); hex(candidate.tree,40);
  labelPath(candidate.labelPath); hex(candidate.labelSha256); integer(candidate.labelByteLength,MiB);
  identifier(candidate.parserVersion); identifier(candidate.policyVersion); validateRoute(candidate.route);
  need(candidate.candidateId === digest(Buffer.from(repository+'\n'+candidate.labelPath)),'unstable-candidate-id');
  const bytes = decode64(candidate.labelBytesBase64,MiB);
  need(bytes.length === candidate.labelByteLength && digest(bytes) === candidate.labelSha256,'candidate-content-mismatch');
  const label = parseLabel({ path:candidate.labelPath,bytes,parserVersion:candidate.parserVersion });
  need(label.status === 'extracted' && routeMatches(candidate.route,candidate.labelPath,label.metadata),'route-review-required');
}
export function validateObservation(observation) {
  record(observation,observationKeys); need(observation.schema === 'fixture-observation-v1');
  identifier(observation.checkerVersion); identifier(observation.environmentVersion); identifier(observation.capabilityVersion);
  need(['available','unavailable'].includes(observation.availability));
  byteView(observation.artifactBytes,32*MiB);
  need(typeof observation.observedPublisher === 'string' && /^[A-Z0-9]{10}$/.test(observation.observedPublisher));
  record(observation.checks,checkKeys);
  for (const key of checkKeys) need(['passed','failed','unknown','unavailable'].includes(observation.checks[key]));
  evidenceRefs(observation.evidenceRefs);
}
export function buildCandidate(checkpoint,path,policy) {
  try {
    validateCheckpoint(checkpoint); labelPath(path);
    record(policy,['schema','version','routes']);
    need(policy.schema === 'fixture-route-policy-v1'); identifier(policy.version);
    need(policy.version === checkpoint.policyVersion,'route-review-required'); list(policy.routes,10000);
    const routeIDs = new Set(), paths = new Set();
    for (const route of policy.routes) {
      validateRoute(route); need(!routeIDs.has(route.routeId) && !paths.has(route.labelPath.toLowerCase()),'ambiguous-route');
      routeIDs.add(route.routeId); paths.add(route.labelPath.toLowerCase());
    }
    const label = checkpoint.labels.find(x => x.path === path), route = policy.routes.find(x => x.labelPath === path);
    need(label?.status === 'extracted' && route && routeMatches(route,path,label.metadata),'route-review-required');
    const candidate = { schema:'fixture-candidate-v1',scope:'fixture-only',candidateId:digest(Buffer.from(repository+'\n'+path)),
      repository,checkpointId:checkpoint.checkpointId,commit:checkpoint.commit,tree:checkpoint.tree,
      labelPath:path,labelSha256:label.sha256,labelByteLength:label.byteLength,labelBytesBase64:label.bytesBase64,
      parserVersion:checkpoint.parserVersion,policyVersion:policy.version,route,publicationAuthority:false };
    return { status:'candidate',candidate:owned(candidate),reason:null,publicationAuthority:false };
  } catch (error) { return { status:'held',candidate:null,reason:reasonOf(error),publicationAuthority:false }; }
}
/** Recomputes bytes and binds all fixture observations. No native check is run. */
export function verifyCandidate(candidate,observation) {
  try {
    validateCandidate(candidate); validateObservation(observation);
    const bytes = byteView(observation.artifactBytes,32*MiB), artifactSha256 = digest(bytes), artifactByteLength = bytes.length;
    need(artifactSha256 === candidate.route.artifactSha256 && artifactByteLength === candidate.route.artifactByteLength,'artifact-mismatch');
    need(observation.observedPublisher === candidate.route.claimedTeamID,'publisher-mismatch');
    need(observation.availability === 'available','capability-unavailable');
    need(checkKeys.every(key => observation.checks[key] === 'passed'),'verification-failed');
    const binding = { repository:candidate.repository,labelPath:candidate.labelPath,labelSha256:candidate.labelSha256,
      parserVersion:candidate.parserVersion,policyVersion:candidate.policyVersion,route:candidate.route,
      checkerVersion:observation.checkerVersion,environmentVersion:observation.environmentVersion,capabilityVersion:observation.capabilityVersion,
      artifactSha256,artifactByteLength,observedPublisher:observation.observedPublisher,checks:observation.checks,evidenceRefs:observation.evidenceRefs };
    const evidence = { bindingSha256:identity(binding),artifactSha256,artifactByteLength,
      checkerVersion:observation.checkerVersion,environmentVersion:observation.environmentVersion,capabilityVersion:observation.capabilityVersion,evidenceRefs:observation.evidenceRefs };
    return { status:'fixture-admitted',reason:null,evidence:owned(evidence),publicationAuthority:false };
  } catch (error) { return { status:'held',reason:reasonOf(error),evidence:null,publicationAuthority:false }; }
}
