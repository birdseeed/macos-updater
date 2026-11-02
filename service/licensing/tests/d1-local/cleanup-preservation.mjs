// Independent contract selected from the exact original cleanup suite, before repair.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,rmSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';
import {createHash} from 'node:crypto';
const here=dirname(fileURLToPath(import.meta.url));
const require=createRequire(resolve(here,'../../package.json'));
const ts=require('typescript/unstable/ast'),{API}=require('typescript/unstable/sync');
const baselinePath=resolve(here,'cleanup-preservation-baseline.json');
const originalSHA256='ba4ab1ae40589fd17f4e08b77b68f268e708e5076e215a30f93e38bc0ad4626e';
const hash=value=>createHash('sha256').update(value).digest('hex');
const helpers=new Set(['count','snapshot','guard','start','deletion','cleanup','email','post','request','consume','signedIn','credential','binding','refusedConsume']);
const asyncHosts=new Set(['rows','d1','count','snapshot','guard','start','deletion','cleanup','post','request','consume','signedIn','refusedConsume']);
const unwrap=node=>{while(ts.isParenthesizedExpression(node)||ts.isAwaitExpression(node))node=node.expression;return node;};
export function contract(text){
 const build=resolve(here,'../../../../.build');mkdirSync(build,{recursive:true});
 const dir=mkdtempSync(resolve(build,'cleanup-ast-')),file=resolve(dir,'cleanup.ts');writeFileSync(file,text);
 const api=new API(),view=api.updateSnapshot({openFiles:[file]});
 const source=view.getDefaultProjectForFile(file).program.getSourceFile(file);
 try{
  assert.ok(source,'cleanup AST loaded');
  const replacements=new Map(),omitted=new Set(),parents=new Map(),aggregators=new Set(),declarations=new Map();
  function index(node,parent){if(parent)parents.set(node,parent);if(ts.isFunctionDeclaration(node))declarations.set(node.name?.text,node);node.forEachChild(c=>index(c,node));}
  index(source);
  function normal(node){
   if(replacements.has(node))return normal(replacements.get(node));
   if(ts.isAwaitExpression(node)||ts.isParenthesizedExpression(node))return normal(node.expression);
   const children=[];node.forEachChild(c=>{if(c.kind!==ts.SyntaxKind.AsyncKeyword&&!omitted.has(c))children.push(normal(c));});
   return [ts.SyntaxKind[node.kind],children.length?children:node.getText(source)];
  }
  function isPromiseAll(node){return ts.isCallExpression(node)&&ts.isPropertyAccessExpression(node.expression)&&ts.isIdentifier(node.expression.expression)&&node.expression.expression.text==='Promise'&&node.expression.name.text==='all';}
  for(const [name,node] of declarations){
   const isAsync=node.modifiers?.some(m=>m.kind===ts.SyntaxKind.AsyncKeyword);
   if(isAsync)assert.ok(asyncHosts.has(name),'async declaration outside selected hosts: '+name);
   if(['count','snapshot','guard'].includes(name)&&node.type&&ts.isTypeReferenceNode(node.type)&&node.type.typeName.getText(source)==='Promise'){
    assert.ok(isAsync,'Promise wrapper requires async '+name);assert.equal(node.type.typeArguments?.length,1);replacements.set(node.type,node.type.typeArguments[0]);
   }
   if(name==='snapshot')for(const statement of node.body.statements){
    if(!ts.isReturnStatement(statement)||!statement.expression)continue;
    const expr=unwrap(statement.expression);
    if(isPromiseAll(expr)){
     assert.equal(expr.arguments.length,1);assert.equal(expr.typeArguments,undefined);assert.equal(expr.questionDotToken,undefined);assert.equal(expr.expression.questionDotToken,undefined);
     replacements.set(statement.expression,expr.arguments[0]);aggregators.add(expr);
    }
   }
   if(['start','cleanup'].includes(name)){
    const parameter=node.parameters.find(p=>p.name.getText(source)==='g');
    if(parameter?.initializer?.getText(source)==='undefined'){
     assert.ok(isAsync,'default guard expansion requires async');
     const first=node.body.statements[0];
     // Exact leading strict-undefined guard, preserving explicit null and every default's counter evaluation.
     assert.equal(first.getText(source).replace(/\s/g,''),'if(g===undefined)g=awaitguard(s);','only selected leading default guard expansion');
     const assignment=first.thenStatement.expression,call=assignment.right.expression;
     assert.ok(ts.isCallExpression(call)&&call.expression.getText(source)==='guard');
     replacements.set(parameter.initializer,call);omitted.add(first);
    }
   }
  }
  function consumed(call){
   let node=call,parent=parents.get(node);
   while(parent&&ts.isParenthesizedExpression(parent)){node=parent;parent=parents.get(node);}
   if(parent&&(ts.isAwaitExpression(parent)||ts.isReturnStatement(parent)))return true;
   // Direct array elements in the original races; contract equality freezes the entire aggregator.
   if(parent&&ts.isArrayLiteralExpression(parent)){
    const outer=parents.get(parent);return outer&&isPromiseAll(outer);
   }
   // The original race Array.from arrow and the precise original snapshot map are implicit returns.
   if(parent&&ts.isArrowFunction(parent)&&parent.body===node){
    const mapping=parents.get(parent),outer=mapping&&parents.get(mapping);
    return !!(mapping&&ts.isCallExpression(mapping)&&outer&&isPromiseAll(outer));
   }
   return false;
  }
  const tests=[],frozenHelpers={},sql=[],constants=[],caseLoops=[],initialAssertions=[];
  function containsTest(node){let found=false;function scan(n){if(ts.isCallExpression(n)&&ts.isIdentifier(n.expression)&&n.expression.text==='test')found=true;n.forEachChild(scan);}scan(node);return found;}
  function visit(node){
   if((node.kind===ts.SyntaxKind.ForOfStatement||node.kind===ts.SyntaxKind.ForStatement)&&containsTest(node))caseLoops.push(hash(JSON.stringify(normal(node))));
   if(ts.isExpressionStatement(node)&&ts.isCallExpression(node.expression)&&node.expression.expression.getText(source)==='assert.equal'&&node.expression.arguments.length&&ts.isCallExpression(unwrap(node.expression.arguments[0]))&&unwrap(node.expression.arguments[0]).expression.getText(source)==='count')initialAssertions.push(normal(node));
   if(node.modifiers?.some(m=>m.kind===ts.SyntaxKind.AsyncKeyword)&&!ts.isFunctionDeclaration(node)){
    // Original test callbacks are already async. No new async arrows elsewhere are permitted.
    assert.ok(ts.isArrowFunction(node)&&ts.isCallExpression(parents.get(node))&&parents.get(node).expression.getText(source)==='test','async outside selected declaration/test callback');
   }
   if(ts.isCallExpression(node)){
    if(ts.isIdentifier(node.expression)&&node.expression.text==='test')tests.push({name:node.arguments[0].getText(source),astSHA256:hash(JSON.stringify(normal(node)))});
    if(ts.isIdentifier(node.expression)){
     const declaration=declarations.get(node.expression.text);
     if(declaration?.modifiers?.some(m=>m.kind===ts.SyntaxKind.AsyncKeyword)&&asyncHosts.has(node.expression.text))assert.ok(consumed(node),'async call must be awaited/returned/original Promise.all element: '+node.getText(source));
    }
   }
   if(ts.isFunctionDeclaration(node)&&helpers.has(node.name?.text))frozenHelpers[node.name.text]=hash(JSON.stringify(normal(node)));
   if(ts.isVariableDeclaration(node)&&['initial','code','emailCounter','requestCounter','ipCounter'].includes(node.name.getText(source)))constants.push(normal(node));
   if((ts.isStringLiteral(node)||node.kind===ts.SyntaxKind.NoSubstitutionTemplateLiteral)&&(/TRIGGER/.test(node.text)||node.text==='migrations/0001_accounts.sql'))sql.push(node.text);
   node.forEachChild(visit);
  }
  visit(source);assert.equal(tests.length,24,'24 original registrations expand to 31 cases');assert.equal(caseLoops.length,2,'original three-boundary and six-protection loops required');assert.equal(Object.keys(frozenHelpers).length,helpers.size,'all selected helpers required');assert.equal(constants.length,5);
  return {expandedCaseCount:31,tests,helpers:frozenHelpers,sql,constants,caseLoops,initialAssertions};
 }finally{view.dispose();api.close();rmSync(dir,{recursive:true});}
}
export function verifyProtected(read=readFileSync){
 const baseline=JSON.parse(read(baselinePath,'utf8'));
 assert.equal(baseline.originalSHA256,originalSHA256,'original cleanup SHA field changed');
 assert.equal(hash(baseline.originalSource),originalSHA256,'original cleanup source changed');
 assert.deepEqual(contract(baseline.originalSource),baseline.contract,'original cleanup AST contract changed');
 // protectedSHA256 is the historical publication receipt, not a permanent repository freeze.
}
export function verify(text){
 const baseline=JSON.parse(readFileSync(baselinePath,'utf8'));verifyProtected();
 assert.deepEqual(contract(text),baseline.contract,'cleanup assertions, cases, helpers, SQL, race/order/counter semantics changed');
 return originalSHA256;
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const file=process.argv.slice(2).find(a=>!a.startsWith('--'))??resolve(here,'cleanup.test.ts'),text=readFileSync(file,'utf8');
 if(process.argv.includes('--capture')){
  assert.equal(hash(text),originalSHA256,'capture requires exact independently selected original');
  const manifest=process.env.PAT_CLEANUP_BASELINE_MANIFEST;assert.ok(manifest,'capture requires independent 507-path manifest');
  const protectedSHA256=JSON.parse(readFileSync(manifest,'utf8'));assert.equal(Object.keys(protectedSHA256).length,507);assert.equal(protectedSHA256['service/licensing/tests/d1-local/cleanup.test.ts'],originalSHA256);
  writeFileSync(baselinePath,JSON.stringify({originalSHA256,originalSource:text,protectedSHA256,contract:contract(text)},null,2)+'\n');
 }else console.log('Cleanup preservation OK: '+verify(text));
}
