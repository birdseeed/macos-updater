// Shared by future account writers; this is not caller authentication.
export interface AccountGuard { accountID: string; accountRevision: number; commitNonce: string; }
export function validGuard(guard: AccountGuard): boolean {
  return !!guard && Object.keys(guard).sort().join(',') === 'accountID,accountRevision,commitNonce' && typeof guard.accountID === 'string' && /^[a-zA-Z0-9-]{1,64}$/.test(guard.accountID) &&
    Number.isSafeInteger(guard.accountRevision) && guard.accountRevision >= 0 &&
    typeof guard.commitNonce === 'string' && /^[a-zA-Z0-9-]{1,64}$/.test(guard.commitNonce);
}
