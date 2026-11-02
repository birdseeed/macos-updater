// Infrastructure only. The unchanged full service gate remains mandatory.
import assert from 'node:assert/strict';
import {mkdirSync,mkdtempSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {ownedTLS,nativeChrome} from './native-chrome-cdp.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../../../..');
mkdirSync(resolve(root,'.build'),{recursive:true});
const run=mkdtempSync(resolve(root,'.build/account-browser-'));
let bridge,browser;
try {
 bridge=await ownedTLS(run);
 browser=await nativeChrome(run,bridge);
 assert.match(browser.version,/^Google Chrome \d+\.\d+\.\d+\.\d+$/);
 assert.equal(await browser.evaluate('location.href'),'about:blank','INFRA initial owned page is about:blank');
 console.log('CHROME-STARTUP preflight acquired actual version-checked Chrome/CDP and about:blank; no product assertions executed');
}finally{
 try{await browser?.dispose();}finally{await bridge?.dispose();}
}
