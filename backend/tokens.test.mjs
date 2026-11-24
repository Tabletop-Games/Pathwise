import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createSigner, parseKeyRing } from './tokens.mjs';

const ring = 'k1:' + 'a'.repeat(40);

test('signed tokens verify, expire and reject tampering or wrong kind', () => {
  let time = 1000;
  const signer = createSigner(ring, { now: () => time });
  const token = signer.sign('session', { sub: 'p1' }, 5000);
  assert.equal(signer.verify('session', token).sub, 'p1');
  assert.equal(signer.verify('challenge', token), null);
  const [a, b, body, sig] = token.split('.');
  const forged = Buffer.from(JSON.stringify({ k: 'session', sub: 'p2', iat: 1000, exp: 9e12 })).toString('base64url');
  assert.equal(signer.verify('session', [a, b, forged, sig].join('.')), null);
  assert.equal(signer.verify('session', `${a}.${b}.${body}.${sig.slice(0, -2)}AA`), null);
  time = 6001;
  assert.equal(signer.verify('session', token), null);
  assert.equal(signer.verify('session', 'garbage'), null);
  assert.equal(signer.verify('session', undefined), null);
});

test('key rotation keeps old tokens valid and signs with the first key', () => {
  const old = createSigner('old:' + 'b'.repeat(40));
  const rotated = createSigner(`new:${'c'.repeat(40)},old:${'b'.repeat(40)}`);
  assert.ok(rotated.verify('session', old.sign('session', { sub: 'x' }, 60000)));
  assert.equal(createSigner('old:' + 'b'.repeat(40)).verify('session', rotated.sign('session', {}, 60000)), null);
});

test('weak or malformed key rings are rejected', () => {
  assert.throws(() => parseKeyRing(''), /required/);
  assert.throws(() => parseKeyRing('k1:short'), /Invalid/);
  assert.throws(() => parseKeyRing('bad key:' + 'a'.repeat(40)), /Invalid/);
});
