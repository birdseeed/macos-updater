import { MiB, need, record, identifier, labelPath, byteView, digest, owned, reasonOf } from './contracts.mjs';

export function validateMetadata(metadata) {
  record(metadata, ['name','type','downloadURL','claimedTeamID']);
  need(Buffer.byteLength(metadata.name) <= 128 && metadata.name.length > 0, 'field-bound');
  need(['dmg','pkg','zip'].includes(metadata.type), 'unsupported-type');
  need(/^[A-Z0-9]{10}$/.test(metadata.claimedTeamID), 'invalid-team-claim');
  const raw = metadata.downloadURL;
  need(typeof raw === 'string' && Buffer.byteLength(raw) <= 2048 && !/[\s#\\]/u.test(raw), 'invalid-url');
  const authority = /^https:\/\/([^/?#]+)/.exec(raw);
  need(authority && !authority[1].includes('@'), 'invalid-url');
  let url;
  try { url = new URL(raw); } catch { need(false, 'invalid-url'); }
  need(url.protocol === 'https:' && url.hostname && !url.username && !url.password && !url.hash, 'invalid-url');
}

/** Narrow literal classification; original bytes never become shell operations. */
export function parseLabel(input) {
  let output = { status:'held',path:null,sha256:null,byteLength:null,bytesBase64:null,
    parserVersion:null,metadata:null,reason:'invalid-input' };
  try {
    record(input, ['path','bytes','parserVersion']);
    // Snapshot ingestion already bounds input before calling the parser. Direct
    // callers also get a bounded refusal without hashing/base64 of giant bytes.
    need(input.bytes instanceof Uint8Array && !(input.bytes.buffer instanceof SharedArrayBuffer));
    output.path = typeof input.path === 'string' && Buffer.byteLength(input.path) <= 1024 ? input.path : null;
    output.parserVersion = typeof input.parserVersion === 'string' && input.parserVersion.length <= 64 ? input.parserVersion : null;
    output.byteLength = input.bytes.byteLength;
    if (input.bytes.byteLength > MiB) { output.reason = 'oversized-not-retained'; return owned(output); }
    const bytes = Buffer.from(byteView(input.bytes, MiB));
    output.sha256 = digest(bytes); output.bytesBase64 = bytes.toString('base64');
    labelPath(input.path); identifier(input.parserVersion);
    need(!(bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf), 'invalid-encoding');
    let source;
    try { source = new TextDecoder('utf-8', { fatal:true }).decode(bytes); }
    catch { need(false, 'invalid-encoding'); }
    need(!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(source) && !/\r(?!\n)/.test(source), 'invalid-control');
    const lines = source.split(/\r?\n/);
    if (lines.at(-1) === '') lines.pop();
    need(lines.length <= 256, 'line-limit');
    const expectedArm = input.path.slice('fragments/labels/'.length, -3) + ')';
    const fields = Object.create(null);
    let state = 'before';
    for (const raw of lines) {
      const line = raw.replace(/^[ \t]*/, '');
      need(!line.includes('\t'), 'invalid-control');
      if (line === '' || line.startsWith('#')) continue;
      if (state === 'before') { need(line === expectedArm, 'invalid-arm'); state = 'fields'; continue; }
      need(state === 'fields', 'extra-shell-form');
      if (line === ';;') { state = 'after'; continue; }
      const match = /^(name|type|downloadURL|expectedTeamID)=(['"])(.+)\2$/.exec(line);
      need(match, 'unsupported-literal');
      const [, key, quote, value] = match;
      need(!Object.hasOwn(fields,key) && !value.includes(quote) && !/[\\$`\x00-\x1f\x7f]/.test(value), 'unsupported-literal');
      fields[key] = value;
    }
    need(state === 'after' && Object.keys(fields).length === 4, 'incomplete-literal');
    const metadata = { name:fields.name,type:fields.type,downloadURL:fields.downloadURL,claimedTeamID:fields.expectedTeamID };
    validateMetadata(metadata);
    output = { ...output,status:'extracted',metadata,reason:null };
  } catch (error) { output.reason = reasonOf(error); }
  return owned(output);
}
