import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decodeJobV2, encodeJobV2 } from '../protocol/job-v2.mjs';
import { decodeEvidenceV2, encodeEvidenceV2 } from '../protocol/evidence-v2.mjs';
const cases = [['job', 'sourceURL', decodeJobV2, encodeJobV2], ['evidence', 'finalSourceURL', decodeEvidenceV2, encodeEvidenceV2]];
for (const [kind, field, decode, encode] of cases) {
  for (const host of ['example.123', 'xn--0.test', '127.1', '0x7f000001', '[::1]']) {
    test(`${kind} explicit inert DNS/IP boundary ${host}`, () => {
      const record = JSON.parse(readFileSync(new URL(`../protocol/fixtures/inspection-v2/${kind}.json`, import.meta.url)));
      record[field] = `https://${host}:443/exact%20path`;
      const result = decode(Buffer.from(JSON.stringify(record)));
      const encoded = encode(record);
      const permitted = host === 'example.123' || host === 'xn--0.test';
      assert.equal(result.status, permitted ? 'valid' : 'invalid');
      assert.equal(encoded.status, permitted ? 'encoded' : 'refused');
      for (const value of [result, encoded]) {
        assert.equal(value.scope, 'fixture-only');
        for (const flag of ['authenticated', 'policyAccepted', 'freshOSValidation', 'publicationAllowed', 'installationAllowed']) assert.equal(value[flag], false);
      }
      if (permitted) assert.equal(result[kind === 'job' ? 'job' : 'report'][field], record[field]);
    });
  }
}
