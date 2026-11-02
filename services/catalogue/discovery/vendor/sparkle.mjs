import { vendorBounds } from './contracts.mjs';
import { record, need, string, url, artifactURL, metadataText, digest, version, os, integrity, decimal, parserHeld } from './validation.mjs';

function decode(value) {
  need(!value.includes('<') && !value.includes(']]>'));
  const entities = {amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"};
  need(!/&(?!(?:amp|lt|gt|quot|apos);)/.test(value));
  return value.replace(/&(amp|lt|gt|quot|apos);/g, (_, name) => entities[name]);
}

// Only the documented fixed appcast tree is recognised, without XML extensions.
function tree(source) {
  const declaration = '<?xml version="1.0" encoding="utf-8"?>';
  if (source.startsWith(declaration)) source = source.slice(declaration.length);
  need(!source.includes('<?') && !source.includes('<!'));
  const root = {name:null,children:[],text:''}, stack = [root];
  let offset = 0, items = 0;
  while (offset < source.length) {
    const next = source.indexOf('<', offset);
    const endText = next === -1 ? source.length : next;
    stack.at(-1).text += decode(source.slice(offset, endText));
    offset = endText;
    if (next === -1) break;
    const end = source.indexOf('>', offset);
    need(end !== -1);
    const token = source.slice(offset + 1, end);
    offset = end + 1;
    if (token.startsWith('/')) {
      need(/^\/[A-Za-z][A-Za-z0-9:]*$/.test(token));
      need(stack.length > 1 && stack.at(-1).name === token.slice(1));
      stack.pop(); continue;
    }
    const match = /^([A-Za-z][A-Za-z0-9:]*)([\s\S]*?)(\/?)$/.exec(token);
    need(match);
    const node = {name:match[1],attrs:Object.create(null),children:[],text:''};
    let attributes = match[2];
    while (attributes.trim()) {
      const attribute = /^\s+([A-Za-z][A-Za-z0-9:]*)="([^"<>]*)"/.exec(attributes);
      need(attribute && !Object.hasOwn(node.attrs, attribute[1]));
      node.attrs[attribute[1]] = decode(attribute[2]);
      attributes = attributes.slice(attribute[0].length);
    }
    need(stack.length <= vendorBounds.xmlDepth);
    if (node.name === 'item') need(++items <= vendorBounds.items);
    stack.at(-1).children.push(node);
    if (!match[3]) stack.push(node);
  }
  need(stack.length === 1 && root.text.trim() === '' && root.children.length === 1);
  return root.children[0];
}
function branch(node, name, keys) {
  need(node.name === name && node.text.trim() === ''); record(node.attrs, keys);
}
function leaf(node) {
  record(node.attrs, []); need(node.children.length === 0); return string(node.text.trim());
}

export function parseSparkle(input) {
  try {
    record(input, ['feedURL','bytes','parserVersion']);
    url(input.feedURL); need(input.parserVersion === 'sparkle-subset-v1');
    const {data, decoded} = metadataText(input.bytes);
    const rss = tree(decoded); branch(rss, 'rss', ['version','xmlns:sparkle']);
    need(rss.attrs.version === '2.0' && rss.attrs['xmlns:sparkle'] === 'http://www.andymatuschak.org/xml-namespaces/sparkle');
    need(rss.children.length === 1);
    const channel = rss.children[0]; branch(channel, 'channel', []);
    let item = null, title = false;
    for (const child of channel.children) {
      if (child.name === 'title') { need(!title); leaf(child); title = true; }
      else { need(child.name === 'item' && item === null); item = child; }
    }
    need(item); branch(item, 'item', []);
    const fields = Object.create(null);
    const allowed = ['sparkle:version','sparkle:shortVersionString','sparkle:minimumSystemVersion','sparkle:maximumSystemVersion','sparkle:channel','sparkle:hardwareRequirements','title'];
    let enclosure = null;
    for (const child of item.children) {
      if (child.name === 'enclosure') { need(enclosure === null); enclosure = child; }
      else { need(allowed.includes(child.name) && !Object.hasOwn(fields, child.name)); fields[child.name] = leaf(child); }
    }
    need(enclosure && enclosure.children.length === 0 && enclosure.text.trim() === '');
    record(enclosure.attrs, ['url','sparkle:edSignature','length','type']);
    need(enclosure.attrs.type === 'application/octet-stream');
    version(fields['sparkle:version'], 'sparkle-dotted-v1');
    const minOS = fields['sparkle:minimumSystemVersion'] ?? null, maxOS = fields['sparkle:maximumSystemVersion'] ?? null;
    if (minOS !== null) os(minOS); if (maxOS !== null) os(maxOS);
    const claim = {algorithm:'ed25519',value:enclosure.attrs['sparkle:edSignature']}; integrity(claim, 'ed25519');
    return {status:'extracted',reason:null,metadata:{parserVersion:input.parserVersion,feedURL:input.feedURL,
      version:fields['sparkle:version'],displayVersion:fields['sparkle:shortVersionString'] ?? null,
      artifactURL:artifactURL(enclosure.attrs.url),artifactLength:decimal(enclosure.attrs.length),integrityClaim:claim,
      channel:fields['sparkle:channel'] ?? null,architecture:fields['sparkle:hardwareRequirements'] ?? null,minOS,maxOS},
      sourceDigests:{configSha256:null,feedSha256:digest(data)}};
  } catch (error) { return parserHeld(error); }
}
