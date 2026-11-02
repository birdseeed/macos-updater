import {checkLifecycleBudget} from '../../src/accountBatch';
import {describe,it,expect} from 'vitest';
import {derive} from '../../src/billing/derive';
import {fixture,copy} from './fake-paddle';
describe('closed input resource boundaries',()=>{
 for(const [field,limit] of [['transactions',32],['adjustments',64],['disputes',64]] as const)for(const overflow of [false,true])it(`coherent snapshot ${field} ${limit+(overflow?1:0)} exact boundary`,()=>{const f=fixture(field==='transactions'?'existing-gbp':field==='adjustments'?'partial-refund':'open-dispute');const row=copy(f.snapshot[field][0]);f.snapshot[field]=Array.from({length:limit+(overflow?1:0)},(_,i)=>{if(field==='transactions'&&i===0)return copy(row);const r={...copy(row),id:(field==='transactions'?'txn':field==='adjustments'?'adj':'dsp')+'_fixture_'+i};if(field==='transactions'){r.origin='renewal';r.period={startsAt:1790812800+(i-1)*31536000,endsAt:1790812800+i*31536000};}return r;});const result=derive(f.snapshot,f.ledger,f.now);if(overflow)expect(result).toEqual({outcome:'held',reason:'capacity'});else expect(result.outcome).toBe('delta');});
 // Fragmentary rows are structural negatives, never count-boundary evidence.
 for(const table of ['billing_subscription','billing_period','billing_adjustment','billing_dispute','billing_grace','billing_period_end','billing_restoration','billing_snapshot','billing_entity_version','billing_lifecycle_request','billing_review_confirmation','billing_lifecycle_commit','billing_event_consumed','billing_stop_cause','billing_renewal_stop'])it(`malformed retained ${table} fragments cannot propose effects`,()=>{const f=fixture('failed-renewal');f.ledger[table]=[{account_id:'a'.repeat(32)}];expect(derive(f.snapshot,f.ledger,f.now).outcome).toBe('held');});

});

describe('selected pure budget policy boundaries; no provider reachability claim',()=>{
 for(const [effectRows,statementCount,maxBindings,outcome] of [[364,1024,100,'within'],[365,1024,100,'exceeded'],[364,1025,100,'exceeded'],[364,1024,101,'exceeded'],[0,0,0,'within']] as const)it(`${effectRows}/${statementCount}/${maxBindings} is ${outcome}`,()=>{expect(checkLifecycleBudget({effectRows,statementCount,maxBindings})).toEqual({outcome});});
 for(const input of [null,[],{},true,{effectRows:-1,statementCount:1,maxBindings:1},{effectRows:1.5,statementCount:1,maxBindings:1},{effectRows:Number.MAX_SAFE_INTEGER+1,statementCount:1,maxBindings:1},{effectRows:1,statementCount:1,maxBindings:1,sql:'SELECT 1'},Object.create({effectRows:1,statementCount:1,maxBindings:1}),Object.defineProperty({statementCount:1,maxBindings:1},'effectRows',{enumerable:true,get(){throw Error('must not touch accessor');}})])it('malformed/prototype/accessor metrics create no plan',()=>{expect(checkLifecycleBudget(input)).toEqual({outcome:'invalid'});});
});
