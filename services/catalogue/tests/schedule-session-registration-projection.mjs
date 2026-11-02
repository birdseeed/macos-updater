// Projects only the exact new call; acceptance still requires the unchanged pinned legacy guard.
export function projectScheduleSessionRegistration(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length > 65536) throw new TypeError('bounded Buffer required');
  const text = bytes.toString('utf8');
  const previous = '    scheduleRecordChecks(checks)\n';
  const line = '    scheduleSessionChecks(checks)\n';
  const next = '    inventoryProjectionChecks(checks)\n';
  const block = previous + line + next;
  if (!Buffer.from(text).equals(bytes) || text.split(line).length !== 2 ||
      text.split(block).length !== 2) throw new TypeError('exact single session registration required');
  const at = text.indexOf(block);
  if (at !== 0 && text[at - 1] !== '\n') throw new TypeError('physical registration line required');
  return Buffer.from(text.replace(block, previous + next));
}
