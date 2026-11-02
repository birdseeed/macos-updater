import {parseStrictJSON} from './strictjson';
// The existing tokenizer owns duplicate/UTF8/resource checks. Its null-prototype
// records are copied into ordinary data records before closed semantic validation.
export function parseLifecycleJSON(raw:Uint8Array):{ok:true;value:unknown}|{ok:false} {
 const decoded=parseStrictJSON(raw);return decoded.ok?{ok:true,value:JSON.parse(JSON.stringify(decoded.value))}:{ok:false};
}
