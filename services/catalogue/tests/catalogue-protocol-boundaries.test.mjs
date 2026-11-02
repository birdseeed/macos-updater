// Additive parent-approved boundary checks; frozen protocol checks are unchanged.
import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyCatalogue } from '../protocol/catalogue-v2.mjs';
import { input, payload } from './catalogue-fixture-support.mjs';

for (const target of ['source URL', 'redirectHosts']) {
  for (const [hostname, status, reason] of [
    ['example.123', 'refused', 'invalid-payload'],
    ['downloads.example.test', 'verified', null],
  ]) {
    test(`${target}: ${hostname} returns ${status}`, () => {
      const catalogue = payload();
      if (target === 'source URL') {
        catalogue.entries[0].source.url = `https://${hostname}/fixture.dmg`;
      } else {
        catalogue.entries[0].source.redirectHosts = [hostname];
      }
      const result = verifyCatalogue(input(catalogue));
      assert.equal(result.status, status);
      assert.equal(result.reason, reason);
      assert.equal(result.scope, 'fixture-only');
      assert.equal(result.installationAuthorized, false);
      assert.equal(result.publicationAuthority, false);
      assert.equal(result.freshOSValidation, false);
    });
  }
}
