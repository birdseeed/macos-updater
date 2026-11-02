import {closed} from './schema';
import type {LifecycleConfig} from './types';
export function lifecycleConfig(value:unknown):value is LifecycleConfig {
 return closed(value,['fixture','environment','prices','annual'])&&value.fixture==='PAT-2646-synthetic'&&value.environment==='synthetic-sandbox'&&closed(value.prices,['GBP','USD'])&&value.prices.GBP==='fixture-price-gbp-annual'&&value.prices.USD==='fixture-price-usd-annual'&&closed(value.annual,['interval','frequency','quantity','unitAmount','taxInclusive'])&&value.annual.interval==='year'&&value.annual.frequency===1&&value.annual.quantity===1&&value.annual.unitAmount===1999&&value.annual.taxInclusive===true;
}
