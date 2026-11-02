// Test-owned adapter: HTTP and direct D1 share the accepted native account owner.
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {accountRuntime} from './account-runtime.ts';
import type {AccountRuntime,AccountRuntimeOptions} from './account-runtime.ts';
export interface CleanupRuntime extends AccountRuntime {
 rows(sql:string):Promise<Record<string,unknown>[]>;
 execute(sql:string):Promise<void>;
}
export async function cleanupRuntime(options:AccountRuntimeOptions={}):Promise<CleanupRuntime>{
 const owner=await accountRuntime(options);
 try{
  // This original migration has no triggers or quoted semicolons. Raw test
  // triggers are single prepared statements, never split into migration pieces.
  const migration=readFileSync(resolve(dirname(fileURLToPath(import.meta.url)),'../../migrations/0001_accounts.sql'),'utf8');
  const statements=migration.replace(/^\s*--.*$/mg,'').split(';').map(sql=>sql.trim()).filter(Boolean);
  await owner.db.batch(statements.map(sql=>owner.db.prepare(sql)));
 }catch(error){await owner.dispose();throw error;}
 return {
  run:owner.run,versions:owner.versions,
  get db(){return owner.db;},get origin(){return owner.origin;},get logs(){return owner.logs;},
  restart:owner.restart,outboundCanary:owner.outboundCanary,dispose:owner.dispose,
  async rows(sql){return (await owner.db.prepare(sql).all()).results as Record<string,unknown>[];},
  async execute(sql){await owner.db.prepare(sql).run();},
 };
}
