export interface AccountAudit { accountID: string; action: 'sign-in' | 'reauth' | 'refresh' | 'logout' | 'account-mutation'; revision: number; nonce: string; at: number; }
export function validAudit(event: unknown): boolean {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return false;
  const e = event as Record<string, unknown>;
  return Object.keys(e).sort().join(',') === 'accountID,action,at,nonce,revision' &&
    typeof e.accountID === 'string' && /^[a-zA-Z0-9-]{1,64}$/.test(e.accountID) &&
    typeof e.nonce === 'string' && /^[a-zA-Z0-9-]{1,64}$/.test(e.nonce) &&
    typeof e.action === 'string' && ['sign-in','reauth','refresh','logout','account-mutation'].includes(e.action) &&
    Number.isSafeInteger(e.revision) && Number(e.revision) >= 0 && Number.isSafeInteger(e.at) && Number(e.at) >= 0 && Number(e.at) <= 253402300799;
}
