export interface RateCounts { emailMinute: number; emailHour: number; emailDay: number; ipHour: number; ipDay: number; }
export function sendDecision(counts: RateCounts): 'send' | 'email-limited' | 'ip-limited' | 'refused' {
  if (!counts || Object.keys(counts).sort().join(',') !== 'emailDay,emailHour,emailMinute,ipDay,ipHour' || Object.values(counts).some(n => !Number.isSafeInteger(n) || n < 0)) return 'refused';
  if (counts.ipHour >= 30 || counts.ipDay >= 100) return 'ip-limited';
  if (counts.emailMinute >= 1 || counts.emailHour >= 5 || counts.emailDay >= 20) return 'email-limited';
  return 'send';
}
