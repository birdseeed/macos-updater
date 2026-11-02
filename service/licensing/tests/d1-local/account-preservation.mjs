// Frozen AST preservation contract; baseline generated once from accepted main.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,rmSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';
import {createHash} from 'node:crypto';
const here=dirname(fileURLToPath(import.meta.url));
const require=createRequire(resolve(here,'../../package.json'));
const ts=require('typescript/unstable/ast');
const {API}=require('typescript/unstable/sync');
const baselinePath=resolve(here,'account-preservation-baseline.json');
const hash=value=>createHash('sha256').update(value).digest('hex');
export function contract(text){
 const build=resolve(here,'../../../../.build');mkdirSync(build,{recursive:true});
 const dir=mkdtempSync(resolve(build,'account-ast-')),file=resolve(dir,'account.ts');writeFileSync(file,text);
 const api=new API();const snapshot=api.updateSnapshot({openFiles:[file]});
 const source=snapshot.getDefaultProjectForFile(file).program.getSourceFile(file);
 try {
 assert.ok(source,'account AST loaded');
 const snapshotAggregations=new Map(),returnTypeWrappers=new Map();
 function unwrapPlumbing(node){while(ts.isAwaitExpression(node)||ts.isParenthesizedExpression(node))node=node.expression;return node;}
 function normal(node){
  if(returnTypeWrappers.has(node))return normal(returnTypeWrappers.get(node));
  if(snapshotAggregations.has(node))return normal(snapshotAggregations.get(node));
  if(ts.isAwaitExpression(node)||ts.isParenthesizedExpression(node))return normal(node.expression);
  const children=[];node.forEachChild(child=>{if(child.kind!==ts.SyntaxKind.AsyncKeyword)children.push(normal(child));});
  return [ts.SyntaxKind[node.kind],children.length?children:node.getText(source)];
 }
 const tests=[],helpers={},sql=[];
 const helperNames=new Set(['count','snapshot','email','post','request','consume','signedIn','credential','binding','refusedConsume']);
 function visit(node){
  if(ts.isCallExpression(node)&&ts.isIdentifier(node.expression)&&node.expression.text==='test')tests.push({name:node.arguments[0]?.text,astSHA256:hash(JSON.stringify(normal(node)))});
  if(ts.isFunctionDeclaration(node)&&helperNames.has(node.name?.text)){
   if(['count','snapshot'].includes(node.name.text)&&node.type&&ts.isTypeReferenceNode(node.type)&&ts.isIdentifier(node.type.typeName)&&node.type.typeName.text==='Promise'){
    assert.ok(node.modifiers?.some(modifier=>modifier.kind===ts.SyntaxKind.AsyncKeyword),'count/snapshot Promise return wrapper requires async declaration');
    assert.equal(node.type.typeArguments?.length,1,'count/snapshot Promise return wrapper needs exactly original type');
    returnTypeWrappers.set(node.type,node.type.typeArguments[0]);
   }
   if(node.name.text==='snapshot'){
    for(const statement of node.body.statements){
     if(!ts.isReturnStatement(statement)||!statement.expression)continue;
     const expression=unwrapPlumbing(statement.expression);
     if(ts.isCallExpression(expression)&&ts.isPropertyAccessExpression(expression.expression)&&ts.isIdentifier(expression.expression.expression)&&expression.expression.expression.text==='Promise'&&expression.expression.name.text==='all'){
      assert.equal(expression.arguments.length,1,'snapshot Promise.all needs exactly its original map argument');
      assert.equal(expression.typeArguments,undefined);assert.equal(expression.questionDotToken,undefined);assert.equal(expression.expression.questionDotToken,undefined);
      snapshotAggregations.set(statement.expression,expression.arguments[0]);
     }
    }
   }
   helpers[node.name.text]=hash(JSON.stringify(normal(node)));
  }
  if((ts.isStringLiteral(node)||node.kind===ts.SyntaxKind.NoSubstitutionTemplateLiteral)&&(/TRIGGER/.test(node.text)||node.text==='migrations/0001_accounts.sql'))sql.push(node.text);
  node.forEachChild(visit);
 }
 visit(source);assert.equal(tests.length,31,'preserve all 31 cases');assert.equal(Object.keys(helpers).length,10);
 return {tests,helpers,sql};
 }finally{snapshot.dispose();api.close();rmSync(dir,{recursive:true});}
}
export function verify(text){
 const baseline=JSON.parse(readFileSync(baselinePath,'utf8'));
 assert.equal(hash(readFileSync(resolve(here,'../../migrations/0001_accounts.sql'))),baseline.migrationSHA256,'account migration0001 changed');
 assert.deepEqual(contract(text),baseline.contract,'account case/assertion/input/order/race/helper/SQL AST changed beyond await/async/parentheses and top-level snapshot Promise.all and async count/snapshot Promise return-type plumbing');
 return baseline.originalSHA256;
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const text=readFileSync(process.argv.slice(2).find(arg=>!arg.startsWith('--'))??resolve(here,'account-concurrency.test.ts'),'utf8');
 if(process.argv.includes('--capture')){
  assert.equal(hash(text),'c7d87961e940d3aef0e11dcdcf8a53db2bb7f376a7c90f960bbd5ad533b3de42','capture requires accepted original bytes');
  writeFileSync(baselinePath,JSON.stringify({originalSHA256:hash(text),migrationSHA256:hash(readFileSync(resolve(here,'../../migrations/0001_accounts.sql'))),contract:contract(text)},null,2)+'\n');
 }else console.log('Account AST preservation OK; original SHA256 '+verify(text));
}
