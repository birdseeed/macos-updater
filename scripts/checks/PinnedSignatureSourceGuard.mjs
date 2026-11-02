import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Lexical supplement only: actual SDK compilation and native proof remain separate gates.
const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const read = path => readFileSync(join(root, path), 'utf8');
const source = read('Sources/ArtifactInspection/SignatureValidation.swift');
const structured = read('Sources/ArtifactInspection/StructuredSignatureEvidence.swift');
const inspector = read('Sources/ArtifactInspection/Inspector.swift');
const trust = read('Sources/ArtifactInspection/TrustEvidence.swift');
const api = read('Sources/ArtifactInspection/ArtifactInspection.swift');
const errors = [];
function requireContract(condition, message) { if (!condition) errors.push(message); }
// Mask comments and ordinary string literals before identifying executable calls.
function code(text) {
  return text.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"/g, match => match.startsWith('"') ? '""' : ' ');
}
function calls(text, name) {
  const result = [], masked = code(text), matcher = new RegExp(`\\b${name}\\s*\\(`, 'g');
  for (const match of masked.matchAll(matcher)) {
    const open = masked.indexOf('(', match.index);
    let depth = 1, end = open + 1;
    while (end < masked.length && depth) { if (masked[end] === '(') depth++; if (masked[end] === ')') depth--; end++; }
    if (!depth) result.push({ start: match.index, args: masked.slice(open + 1, end - 1), end });
  }
  return result;
}
const names = ['SecStaticCodeCreateWithPath', 'SecRequirementCreateWithString', 'SecStaticCodeCheckValidity', 'SecCodeCopySigningInformation'];
const bound = names.map(name => calls(source, name));
for (let i = 0; i < names.length; i++) requireContract(bound[i].length === 1, `Exactly one executable ${names[i]} call is required`);
if (bound.every(items => items.length === 1)) {
  const [create, requirement, validate, signing] = bound.map(items => items[0]);
  requireContract(create.start < requirement.start && requirement.start < validate.start && validate.start < signing.start,
    'Native validation must precede extraction of signing information');
  const codeOut = create.args.match(/&\s*(\w+)\s*$/)?.[1];
  const requirementOut = requirement.args.match(/&\s*(\w+)\s*$/)?.[1];
  const infoOut = signing.args.match(/&\s*(\w+)\s*$/)?.[1];
  const maskedSource = code(source);
  const requirementText = maskedSource.match(/let\s+(\w+)\s*=\s*try\s+PinnedSignatureRequirement\.make\(teamID:\s*pin\.teamID,\s*bundleID:\s*pin\.bundleID\)/)?.[1];
  requireContract(Boolean(requirementText && new RegExp(`\\b${requirementText}\\b`).test(requirement.args)),
    'The actual parsed requirement must consume the builder result for both catalogue pins');
  const flagsBinding = maskedSource.match(/let\s+(\w+)\s*=\s*SecCSFlags\(rawValue:\s*PinnedSignatureRequirement\.validationFlags\s*\)/)?.[1];
  requireContract(/PinnedSignatureRequirement\.validationFlags/.test(validate.args) ||
    Boolean(flagsBinding && new RegExp(`\\b${flagsBinding}\\b`).test(validate.args)),
    'The actual validity call must consume the independently asserted flags');
  requireContract(Boolean(codeOut && requirementOut && infoOut), 'Native object outputs must be captured');
  if (codeOut && requirementOut) {
    requireContract(new RegExp(`\\b${codeOut}\\b`).test(validate.args) && new RegExp(`\\b${requirementOut}\\b`).test(validate.args),
      'Validity call must consume the actual created code and parsed requirement');
    requireContract(new RegExp(`\\b${codeOut}\\b`).test(signing.args), 'Signing extraction must consume the validated static code');
  }
  // These checks intentionally bind call results to a success comparison, rather than merely require API names.
  const masked = code(source);
  for (const call of [create, requirement, validate, signing]) {
    const before = masked.slice(Math.max(0, call.start - 100), call.start);
    const after = masked.slice(call.end, call.end + 120);
    const assignment = before.match(/(?:let|var)\s+(\w+)\s*=\s*$/)?.[1];
    const checkedAssignment = assignment && new RegExp(`\\b${assignment}\\s*==\\s*errSecSuccess\\b`).test(masked.slice(call.end));
    requireContract(/^[\s\n]*==\s*errSecSuccess\b/.test(after) || Boolean(checkedAssignment),
      'Every native status must have an explicit errSecSuccess check');
  }
  for (const output of [codeOut, requirementOut, infoOut].filter(Boolean)) {
    requireContract(new RegExp(`(?:guard|if)\\s+(?:let|var)\\s+${output}\\b|(?:let|var)\\s+${output}\\s*=\\s*${output}\\b|\\b${output}\\s*!=\\s*nil`).test(masked.slice(create.end)),
      `Native output ${output} must be checked for presence`);
  }
}
for (const flag of ['kSecCSStrictValidate', 'kSecCSCheckAllArchitectures', 'kSecCSCheckNestedCode']) {
  requireContract(new RegExp(`\\b${flag}\\b`).test(code(source)), `Named native flag ${flag} is required`);
}
requireContract(!/kSecCSDoNotValidateResources|kSecCSDoNotValidateExecutable/.test(code(source)), 'Validation must not skip resources or executable');
for (const key of ['kSecCodeInfoTeamIdentifier', 'kSecCodeInfoIdentifier']) {
  requireContract(new RegExp(`\\[\\s*${key}(?:\\s+as\\s+String)?\\s*\\]\\s+as\\?\\s+String`).test(code(source)), `Typed structured signing field ${key} is required`);
}
requireContract(/\bimport\s+Security\b/.test(code(source)), 'Use the platform Security module');
requireContract(/\btry\s+PinnedSignatureRequirement\.make\s*\(/.test(code(source)), 'Parse a requirement constructed from validated catalogue pins');
requireContract(/\bSignatureObservation\s*\(/.test(code(source)), 'Actual native validation must construct the observation');
// Exact internal composition contract selected for this ticket, with no public live-observation seam.
requireContract(/let\s+signature\s*=\s*try\s+collectPinnedSignature\(appPath:\s*app,\s*pin:\s*pin\)/.test(code(inspector)),
  'Owned mounted app must call the actual internal native collector');
requireContract(/signatureObservation:\s*signature\b/.test(code(inspector)) && /schemaVersion:\s*3\b/.test(code(inspector)),
  'Live evidence must carry the collected signature and schema3');
requireContract(/func\s+collectPinnedSignature\(/.test(code(source)) && !/public\s+(?:static\s+)?func\s+collectPinnedSignature/.test(code(source)),
  'Native collector must remain internal');
requireContract(/guard\s+origin\s*!=\s*\.live\s+else\s*\{\s*throw\s+InspectionFailure\.missingEvidence\s*\}/.test(code(trust)),
  'Historical schema1/schema2 assessments must refuse internal live origin');
requireContract(!/public\s+(?:static\s+)?func\s+\w+[^\n]*origin\s*:/.test(code(api)), 'No public caller-selected evidence origin');
requireContract(/func\s+assessPinnedSignatureEvidence\(/.test(code(structured)) && !/notImplemented/.test(code(structured)),
  'Schema3 must have an implemented assessment after the independent red gate');
requireContract(!/\"(?:signature|identity|ticket|containerTicket|architectures)\"\s*:/.test(structured),
  'Current structured command table cannot collect historical app signature, identity or ticket commands');
requireContract(!/\.init\s*\([^)]*freshOSValidation\s*:\s*true/.test(code(source)), 'Signature observation is not authority');
// CHECK-ADDED PAT-2708 F1: lexical binding supplement; no native execution proof.
const bindingSource = read('Sources/ArtifactInspection/SignatureBundleBinding.swift');
const bindingCode = code(bindingSource);
const inspectorCode = code(inspector);
requireContract(/internal\s+struct\s+HeldSignatureBundleBinding\b/.test(bindingCode) &&
  /internal\s+init\(appPath:\s*String,\s*appDescriptor:\s*Int32,\s*executableDescriptor:\s*Int32,\s*infoPlist:\s*Data\)\s*throws/.test(bindingCode),
  'Held bundle binding must use the frozen internal borrowed-descriptor interface');
requireContract(/internal\s+func\s+confirm\(\)\s*throws/.test(bindingCode) && !/notImplemented/.test(bindingCode),
  'Held bundle binding and confirm must be implemented after independent red');
requireContract(!/\bimport\s+Security\b|\bSecStaticCode\w*\s*\(|\bcollectPinnedSignature\s*\(/.test(bindingCode),
  'Identity helper and its opaque Testing SPI must not perform native signature validation');
const bindingConstruction = inspectorCode.match(/let\s+signatureBinding\s*=\s*try\s+HeldSignatureBundleBinding\(appPath:\s*app,\s*appDescriptor:\s*appFD,\s*executableDescriptor:\s*executable,\s*infoPlist:\s*info\)/);
const heldExecutable = inspectorCode.match(/let\s+executable\s*=\s*try\s+SafeFiles\.openPath\(/);
const architectureCollection = inspectorCode.match(/let\s+architectures\s*=\s*try\s+MachOArchitectures\.inspect\(fileDescriptor:\s*executable\)/);
requireContract(Boolean(bindingConstruction && heldExecutable && architectureCollection &&
  heldExecutable.index < bindingConstruction.index && bindingConstruction.index < architectureCollection.index),
  'Capture the actual held app/executable/plist binding after opening the executable and before Mach-O inspection');
// The complete local function is fixed, including both independent mount checks.
const confirmFunction = inspectorCode.match(/func\s+confirmSignatureBinding\(\)\s*throws\s*\{\s*try\s+signatureBinding\.confirm\(\)\s*;?\s*var\s+volume\s*=\s*statfs\(\)\s*;?\s*guard\s+fstatfs\(appFD,\s*&volume\)\s*==\s*0,\s*volume\.f_flags\s*&\s*UInt32\(MNT_RDONLY\)\s*!=\s*0,\s*\(try\s+mountedPaths\(\)\)\.contains\(mount\)\s+else\s*\{\s*throw\s+InspectionFailure\.invalidMount\s*\}\s*\}/);
requireContract(Boolean(confirmFunction),
  'Each local confirmation must check the same identity helper plus held-FD read-only state and current mount containment');
const confirmations = [...inspectorCode.matchAll(/\btry\s+confirmSignatureBinding\(\)/g)];
const nativeCollection = inspectorCode.match(/let\s+signature\s*=\s*try\s+collectPinnedSignature\(appPath:\s*app,\s*pin:\s*pin\)/);
const commandLoop = inspectorCode.match(/for\s+key\s+in\s+expected\.keys\.sorted\(\)\s+where\s+key\s*!=\s*""\s*\{/);
const commandExecution = inspectorCode.match(/observations\[key\]\s*=\s*try\s+runner\.run\(executable:\s*invocation\.0,\s*arguments:\s*invocation\.1,\s*limits:\s*\.init\(\)\)/);
const evidenceConstruction = inspectorCode.match(/let\s+collected\s*=\s*AppEvidence\(/);
requireContract(confirmations.length === 3,
  'Exactly three executed binding confirmations are required');
if (confirmations.length === 3 && nativeCollection && commandLoop && commandExecution && evidenceConstruction) {
  const [before, after, final] = confirmations;
  requireContract(Boolean(confirmFunction && bindingConstruction &&
    bindingConstruction.index < confirmFunction.index && confirmFunction.index < before.index),
    'The local confirming function must close over the actual captured binding before use');
  requireContract(before.index < nativeCollection.index &&
    /^\s*$/.test(inspectorCode.slice(before.index + before[0].length, nativeCollection.index)),
    'Confirm immediately before the actual native collector');
  requireContract(nativeCollection.index < after.index &&
    /^\s*$/.test(inspectorCode.slice(nativeCollection.index + nativeCollection[0].length, after.index)),
    'Confirm immediately after the actual native collector');
  requireContract(after.index < commandLoop.index && commandLoop.index < commandExecution.index &&
    commandExecution.index < final.index && final.index < evidenceConstruction.index &&
    /^\s*\}\s*$/.test(inspectorCode.slice(commandExecution.index + commandExecution[0].length, final.index)) &&
    /^\s*$/.test(inspectorCode.slice(final.index + final[0].length, evidenceConstruction.index)),
    'Confirm after the completed command loop immediately before constructing app evidence');
} else {
  requireContract(false, 'All three confirmations must bind the actual native collector, command loop and evidence construction');
}
for (const error of errors.slice(0, 12)) console.error(`FAIL ${error}`);
assert.equal(errors.length, 0, `PAT-2708 source contract: ${errors.length} failures; at most 12 shown. Lexical checks are not native execution proof.`);
console.log('PAT-2708 native call binding and import boundaries satisfy the lexical supplement; no native or installed proof.');
