import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
function sources(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? sources(path) : entry.name.endsWith('.swift') ? [path] : [];
  });
}

// Supplemental source audit, not a behavioural/no-CLT execution proof. A legacy
// command snapshot may remain only in this explicitly named replay definition.
// Parent must separately test that .live never selects the legacy evaluator.
const failures = [];
let legacyDefinitions = 0;
for (const path of sources(join(root, 'Sources'))) {
  let text = readFileSync(path, 'utf8');
  if (relative(root, path) === 'Sources/ArtifactInspection/TrustEvidence.swift') {
    const legacy = /^func legacyExpectedCommands\(app: String, dmg: String\)[^\n]*\{\n[\s\S]*?^\}/gm;
    text = text.replace(legacy, block => {
      legacyDefinitions += 1;
      return block.replaceAll('/usr/bin/lipo', 'LEGACY_REPLAY_SNAPSHOT');
    });
  }
  for (const [index, line] of text.split('\n').entries()) {
    if (line.includes('/usr/bin/lipo')) failures.push(`${relative(root, path)}:${index + 1}: ${line.trim()}`);
  }
}
assert.ok(legacyDefinitions <= 1, 'Only one explicit legacy snapshot definition is permitted');
assert.deepEqual(failures, [], 'Productive source must not define/invoke/allowlist the lipo shim');
console.log(`PAT-2706 source guard: no productive lipo references; ${legacyDefinitions} explicit legacy snapshot definition(s). Source audit is not clean-Mac proof.`);
