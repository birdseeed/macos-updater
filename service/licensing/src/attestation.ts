// Explicitly synthetic evidence validation; absent evidence conveys no hardware assurance.
import type {DeviceProof,ProofOperation,Assurance} from './deviceProof';
export type FixtureAttestationResult = {keyID:Uint8Array;counter:number};
export type SyntheticAttestationAdapter = {marker:'PAT-2644-synthetic';
 validate(evidence:Uint8Array,keyID:Uint8Array|null,message:Uint8Array,
 assertion:boolean):Promise<FixtureAttestationResult|null>};

export async function validateAttestation(proof:DeviceProof,message:Uint8Array,operation:ProofOperation,existing:FixtureAttestationResult|null,adapter?:SyntheticAttestationAdapter):Promise<{assurance:Assurance;binding:FixtureAttestationResult|null}|null> {
 try{const p=proof;if(p.attestation===null&&p.assertion===null&&p.attestKeyID===null)return {assurance:'secureStorageFallback',binding:existing};
 if(!adapter||adapter.marker!=='PAT-2644-synthetic'||message.length!==164||![1,2,3,4,5].includes(operation)||p.attestation!==null&&p.assertion!==null)return null;
 const assertion=p.assertion!==null;if(assertion&&operation!==3||!assertion&&![1,2,4].includes(operation))return null;if(assertion&&(!existing||p.attestKeyID!==null)||!assertion&&(!p.attestation||!p.attestKeyID))return null;
 const key=assertion?existing!.keyID:p.attestKeyID!,evidence=assertion?p.assertion!:p.attestation!;if(key.length<1||key.length>64||evidence.length<1||evidence.length>(assertion?1024:8192))return null;
 const result=await adapter.validate(evidence,key,message,assertion);if(!result||!(result.keyID instanceof Uint8Array)||result.keyID.length!==key.length||!result.keyID.every((b,i)=>b===key[i])||!Number.isSafeInteger(result.counter)||result.counter<0||assertion&&result.counter<=existing!.counter)return null;
 return {assurance:'fixtureAttested',binding:result};}catch{return null;}
}
