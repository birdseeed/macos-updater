// Synthetic recipients only. No transport is available in this module.
export function syntheticRecipient(email: string): boolean {
  return typeof email === 'string' && /^[!-~]+@example\.invalid$/.test(email) && email.split('@').length === 2;
}
export async function denyOutboundDelivery(_email: string, _code: string): Promise<void> { throw new Error('outbound delivery denied'); }
