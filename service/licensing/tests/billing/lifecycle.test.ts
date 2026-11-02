import {describe,it,expect} from 'vitest';
import {derive} from '../../src/billing/derive';
import {copy,fixture,index} from './fake-paddle';
describe('independent literal lifecycle derivation contract',()=>{
 for(const name of index.cases as string[]) {
  it(`${name}: exact independently authored outcome and mandatory effects`,()=>{const f=fixture(name);const before=copy(f);const result=derive(f.snapshot,f.ledger,f.now);expect(result.outcome).toBe(f.expected.derive);if(result.outcome==='delta'){const actual=result.operations.map(effect=>{const row:any={...effect.row};for(const key of f.expected.freshFieldsCheckedSeparately){if(Object.hasOwn(row,key)){expect(key).toBe('commit_nonce');expect(row[key]).toMatch(/^[0-9a-f]{32}$/);expect(row[key]).not.toBe('0'.repeat(32));delete row[key];}}return {kind:effect.kind,row};});const sorted=(x:any[])=>[...x].sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));expect(sorted(actual)).toEqual(sorted(f.expected.semanticEffects));}expect(f).toEqual(before);});
 }
 for(const [name,mutate] of [
 ['cross-subscription failure',(s:any)=>s.transactions[1].subscriptionID='sub_fixture_B'],
 ['cross-binding failure',(s:any)=>s.transactions[1].bindingID='bind_fixture_B'],
 ['failure starts at unrelated union end',(s:any)=>s.transactions[1].period.startsAt=1791072000],
 ['pending alone',(s:any)=>s.transactions[1].status='pending'],
 ['failed unpaid currentPeriod',(s:any)=>s.subscription.currentPeriod={transactionID:s.transactions[1].id,...s.transactions[1].period}],
 ['wrong currentPeriod start',(s:any)=>s.subscription.currentPeriod.startsAt++],
 ['wrong currentPeriod end',(s:any)=>s.subscription.currentPeriod.endsAt++],
 ['wrong currentPeriod identity',(s:any)=>s.subscription.currentPeriod.transactionID='txn_fixture_B1'],
 ['active status alone',(s:any)=>s.subscription.status='active'],
 ['scheduled cancellation',(s:any)=>s.subscription.cancellation={state:'scheduled',effectiveAt:1791158400}],
 ['effective cancellation',(s:any)=>s.subscription.cancellation={state:'effective',effectiveAt:1791158400}],
 ['wrong price',(s:any)=>s.transactions[0].priceID='fixture-price-usd-annual'],
 ['wrong quantity',(s:any)=>s.transactions[0].quantity=2],
 ['wrong tax',(s:any)=>s.transactions[0].taxInclusive=false],
 ['nonannual amount',(s:any)=>s.transactions[0].unitAmount=2000],
 ['wrong environment',(s:any)=>s.environment='live'],
 ['duplicate transaction',(s:any)=>s.transactions.push(copy(s.transactions[0]))],
 ['forged custom_data',(s:any)=>s.custom_data={accountID:'a'.repeat(32)}],
 ['forged checkout email',(s:any)=>s.email='fixture@example.invalid'],
 ['forged redirect',(s:any)=>s.redirect='https://fixture.invalid/success'],
 ['unsafe time',(s:any)=>s.transactions[0].period.endsAt=Number.MAX_SAFE_INTEGER+1],
 ['original end overflow',(s:any)=>{s.transactions[0].period.endsAt=253402300000;s.subscription.currentPeriod.endsAt=253402300000;s.transactions[1].period.startsAt=253402300000;}],
 ] as const)it(`grace creation refuses ${name}`,()=>{const f=fixture('failed-renewal');mutate(f.snapshot);const r=derive(f.snapshot,f.ledger,f.now);expect(r.outcome==='delta'?r.operations.some(x=>x.kind==='createGrace'):false).toBe(false);});
 for(const offset of [-1,0,1])it(`fixed original deadline ${offset}`,()=>{const f=fixture('failed-renewal');const r=derive(f.snapshot,f.ledger,1791417600+offset);if(r.outcome==='delta')for(const x of r.operations.filter(x=>x.kind==='createGrace'))expect(x.row.deadline).toBe(1791417600);});
 for(const [name,change] of [
 ['immutable start',(s:any)=>s.transactions[0].period.startsAt++],['immutable end',(s:any)=>s.transactions[0].period.endsAt++],['immutable price',(s:any)=>{s.transactions[0].priceID='fixture-price-usd-annual';s.transactions[0].currency='USD';}],['immutable binding',(s:any)=>s.transactions[0].bindingID='bind_fixture_foreign'],
 ] as const)it(`accepted original period cannot redate ${name}`,()=>{const f=fixture('next-charge-unavailable');change(f.snapshot);expect(derive(f.snapshot,f.ledger,f.now).outcome).toBe('held');});
 for(const [name,mutate] of [['equal time differing contents',(s:any)=>s.subscription.nextCharge={kind:'unavailable',reason:'contradictory'}],['older provider timestamp',(s:any)=>s.subscription.updatedAt--],['omitted retained transaction',(s:any)=>s.transactions=[]]] as const)it(`retained entity history ${name}`,()=>{const f=fixture('next-charge-unavailable');f.ledger.billing_entity_version=[{environment:'synthetic-sandbox',subscription_id:'sub_fixture_A',account_id:'a'.repeat(32),entity_kind:'subscription',entity_id:'sub_fixture_A',updated_at:f.snapshot.subscription.updatedAt,read_generation:1,canonical_sha256:'a'.repeat(64),canonical_json:JSON.stringify(f.snapshot.subscription),commit_nonce:'1'.repeat(32)}];mutate(f.snapshot);expect(derive(f.snapshot,f.ledger,f.now).outcome).toBe('held');});
 for(const status of ['pending','rejected','approved','reversed'])for(const coverage of ['partial','full'])it(`adjustment closed transition ${status}/${coverage}`,()=>{const f=fixture('partial-refund');f.snapshot.adjustments[0].status=status;f.snapshot.adjustments[0].coverage=coverage;f.snapshot.adjustments[0].amount=coverage==='full'?1999:500;const r=derive(f.snapshot,f.ledger,f.now);if(coverage==='partial'&&r.outcome==='delta')expect(r.operations.some(x=>['endPeriod','createGrace','joinStopCause','restoreRemainder'].includes(x.kind))).toBe(false);if(status==='approved'&&coverage==='full')expect(r.outcome==='delta'&&r.operations.some(x=>x.kind==='endPeriod')).toBe(true);});
});
