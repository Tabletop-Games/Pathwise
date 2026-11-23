import { generateKeyPairSync, sign } from 'node:crypto';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { consoleProbe, decodeReward } from './rewards.mjs';

const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const now = 1800000000000;
const token = 'ab'.repeat(32);
const payload = `ad_unit=1234567890&custom_data=${token}&timestamp=${now}&transaction_id=t1`;
function signed(message) {
  return `${message}&signature=${sign('sha256', Buffer.from(message), privateKey).toString('base64url')}&key_id=100`;
}
const keyFor = (id) => id === '100' ? publicKey : undefined;

test('authenticates the exact callback and preserves placement binding fields', () => {
  const result = decodeReward(signed(payload), keyFor, now);
  assert.equal(result.token, token);
  assert.equal(result.unit, '1234567890');
  assert.equal(result.id.length, 64);
  assert.equal(decodeReward(signed(payload).replace('t1', 't2'), keyFor, now), null);
});

test('rejects unknown keys, duplicate fields and stale callbacks', () => {
  assert.equal(decodeReward(signed(payload).replace('key_id=100','key_id=99'), keyFor, now), null);
  assert.equal(decodeReward(signed(payload + '&transaction_id=extra'), keyFor, now), null);
  assert.equal(decodeReward(signed(payload), keyFor, now + 3600001), null);
});

test('a console probe must be signed and cannot decode as a reward session', () => {
  const probe = payload.replace(token, consoleProbe);
  assert.equal(decodeReward(signed(probe), keyFor, now), null);
  assert.equal(decodeReward(signed(probe), keyFor, now, true).token, consoleProbe);
  assert.equal(decodeReward(probe, keyFor, now, true), null);
});
