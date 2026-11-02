import type {SyntheticLifecycleProvider,ReadCommand,StopCommand,ProviderRead,ProviderStop} from './types';
export class RefusingLifecycleProvider implements SyntheticLifecycleProvider {
 readonly marker='PAT-2646-provider-synthetic' as const;
 async read(_command:ReadCommand):Promise<ProviderRead>{return {outcome:'unavailable'};}
 async stopRenewal(_command:StopCommand):Promise<ProviderStop>{return {outcome:'rejected'};}
}
