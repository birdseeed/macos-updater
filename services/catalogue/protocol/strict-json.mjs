// Bounded JSON parser for the protocol's nonnegative safe-integer subset.
// No I/O and no JSON.parse repair/coercion: signed bytes remain separate.
const byteLengthGetter = Object.getOwnPropertyDescriptor(
  Object.getPrototypeOf(Uint8Array.prototype), 'byteLength',
).get;

export function parseStrictJSON(bytes, bounds) {
  const fail = () => { throw new SyntaxError('Invalid bounded protocol JSON'); };
  if (!(bytes instanceof Uint8Array) || bounds === null || typeof bounds !== 'object') fail();
  const prototype = Object.getPrototypeOf(bounds);
  if (prototype !== Object.prototype && prototype !== null) fail();
  const keys = Reflect.ownKeys(bounds);
  if (keys.length !== 2 || !keys.includes('maximumBytes') || !keys.includes('maximumDepth')) fail();
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(bounds, key);
    if (!descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) fail();
  }
  const maximumBytes = bounds.maximumBytes;
  const maximumDepth = bounds.maximumDepth;
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1
      || maximumBytes > 2097152 || maximumDepth !== 16) fail();
  try { if (byteLengthGetter.call(bytes) > maximumBytes) fail(); }
  catch { fail(); }
  let text;
  try {
    // ignoreBOM:true retains the BOM so the parser rejects it rather than strips it.
    text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch { fail(); }
  let offset = 0;
  const whitespace = () => {
    while (offset < text.length && ' \t\r\n'.includes(text[offset])) offset++;
  };
  function string() {
    if (text[offset++] !== '"') fail();
    let value = '';
    while (offset < text.length) {
      const character = text[offset++];
      if (character === '"') {
        // Reject lone surrogate code units after decoding both raw and escaped text.
        for (let i = 0; i < value.length; i++) {
          const unit = value.charCodeAt(i);
          if (unit >= 0xd800 && unit <= 0xdbff) {
            const next = value.charCodeAt(++i);
            if (!(next >= 0xdc00 && next <= 0xdfff)) fail();
          } else if (unit >= 0xdc00 && unit <= 0xdfff) fail();
        }
        return value;
      }
      if (character.charCodeAt(0) < 0x20) fail();
      if (character !== '\\') { value += character; continue; }
      if (offset >= text.length) fail();
      const escape = text[offset++];
      if (escape === 'u') {
        const digits = text.slice(offset, offset + 4);
        if (!/^[0-9a-fA-F]{4}$/.test(digits)) fail();
        value += String.fromCharCode(Number.parseInt(digits, 16));
        offset += 4;
      } else {
        const escapes = { '"': '"', '\\': '\\', '/': '/', b: '\b', f: '\f', n: '\n', r: '\r', t: '\t' };
        if (!Object.hasOwn(escapes, escape)) fail();
        value += escapes[escape];
      }
    }
    fail();
  }
  function value(depth) {
    whitespace();
    const character = text[offset];
    if (character === '"') return string();
    if (character === '{' || character === '[') {
      if (depth + 1 > maximumDepth) fail();
      offset++;
      const object = character === '{';
      const result = object ? {} : [];
      const keys = new Set();
      const closing = object ? '}' : ']';
      whitespace();
      if (text[offset] === closing) { offset++; return result; }
      while (offset < text.length) {
        whitespace();
        if (object) {
          const key = string();
          if (keys.has(key)) fail();
          keys.add(key);
          whitespace();
          if (text[offset++] !== ':') fail();
          Object.defineProperty(result, key, {
            value: value(depth + 1), enumerable: true, writable: true, configurable: true,
          });
        } else result.push(value(depth + 1));
        whitespace();
        if (text[offset] === closing) { offset++; return result; }
        if (text[offset++] !== ',') fail();
      }
      fail();
    }
    for (const [token, literal] of [['true', true], ['false', false], ['null', null]]) {
      if (text.startsWith(token, offset)) { offset += token.length; return literal; }
    }
    // Scan a whole token before conversion. Rounding must not turn a fraction or
    // an oversized integer into an apparently valid protocol integer.
    const start = offset;
    while (offset < text.length && !' \t\r\n,]}'.includes(text[offset])) offset++;
    const token = text.slice(start, offset);
    if (!/^(0|[1-9][0-9]*)$/.test(token) || token.length > 16) fail();
    const number = Number(token);
    if (!Number.isSafeInteger(number)) fail();
    return number;
  }
  const result = value(0);
  whitespace();
  if (offset !== text.length) fail();
  return result;
}
