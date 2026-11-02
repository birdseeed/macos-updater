import { record, need, metadataText, url, artifactURL, digest, version, integrity, decimal, parserHeld } from './validation.mjs';

// Literal scalar lines only. No YAML expression, coercion or extension runs.
function scalar(line, indent) {
  const match = new RegExp('^' + indent + '([A-Za-z][A-Za-z0-9]*): ([^\\r\\n]+)$').exec(line);
  need(match && !/[#&*!|>{}\[\]`$'"\t]/.test(match[2]));
  need(match[2] === match[2].trim()); return [match[1],match[2]];
}
function insert(target, key, value, allowed) {
  need(allowed.includes(key) && !Object.hasOwn(target,key)); target[key] = value;
}
function lines(value) { return value.replaceAll('\r\n','\n').split('\n').filter(line => line.trim() !== ''); }

export function parseElectron(input) {
  try {
    record(input, ['configBytes','feedBytes','parserVersion']); need(input.parserVersion === 'electron-subset-v1');
    const configText = metadataText(input.configBytes), feedText = metadataText(input.feedBytes);
    const config = Object.create(null);
    for (const line of lines(configText.decoded)) {
      const [key,value] = scalar(line,''); insert(config,key,value,['provider','url','channel']);
    }
    need(config.provider === 'generic' && (config.channel === undefined || config.channel === 'latest'));
    const base = url(config.url); need(!base.search);
    // v26 GenericProvider treats the whole configured pathname as a directory.
    if (!base.pathname.endsWith('/')) base.pathname += '/';
    const feedURL = new URL('latest-mac.yml',base).href; url(feedURL);
    const feed = Object.create(null), file = Object.create(null);
    let inFiles = false, sawFiles = false, sawFile = false;
    for (const line of lines(feedText.decoded)) {
      if (line === 'files:') { need(!sawFiles); sawFiles = true; inFiles = true; continue; }
      if (line.startsWith(' ')) {
        need(inFiles);
        if (line.startsWith('  - ')) {
          need(!sawFile); sawFile = true;
          const [key,value] = scalar(line.slice(4),''); need(key === 'url'); insert(file,key,value,['url']);
        } else {
          need(sawFile); const [key,value] = scalar(line,'    '); insert(file,key,value,['sha512','size']);
        }
      } else {
        inFiles = false; const [key,value] = scalar(line,''); insert(feed,key,value,['version','releaseDate','path','sha512']);
      }
    }
    need(sawFiles && sawFile); record(file,['url','sha512','size']); version(feed.version,'electron-stable-semver-v1');
    if (feed.releaseDate !== undefined) {
      need(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(feed.releaseDate));
      need(Number.isFinite(Date.parse(feed.releaseDate)) && new Date(feed.releaseDate).toISOString() === feed.releaseDate);
    }
    need((feed.path === undefined) === (feed.sha512 === undefined));
    if (feed.path !== undefined) need(feed.path === file.url && feed.sha512 === file.sha512);
    const claim = {algorithm:'sha512',value:file.sha512}; integrity(claim,'sha512');
    return {status:'extracted',reason:null,metadata:{parserVersion:input.parserVersion,feedURL,version:feed.version,
      displayVersion:null,artifactURL:artifactURL(file.url),artifactLength:decimal(file.size),integrityClaim:claim,
      channel:null,architecture:null,minOS:null,maxOS:null},sourceDigests:{configSha256:digest(configText.data),feedSha256:digest(feedText.data)}};
  } catch (error) { return parserHeld(error); }
}
