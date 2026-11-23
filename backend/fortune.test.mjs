import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import test from 'node:test';

import { fortunePrizes, pickFortune, wheelWindow } from './fortune.mjs';
import { rewardRequest } from './rewards.mjs';

test('published wheel weights match all 100 possible authoritative draws', () => {
  const hits = Object.fromEntries(fortunePrizes.map(item => [item.id, 0]));
  for (let roll = 0; roll < 100; roll++) hits[pickFortune(roll)]++;
  for (const prize of fortunePrizes) assert.equal(hits[prize.id], prize.weight);
  assert.throws(() => pickFortune(100), RangeError);
});

class MemoryFirestore {
  rows = new Map();
  queue = Promise.resolve();
  snapshot(key) {
    const value = this.rows.get(key);
    return { exists: value !== undefined, data: () => value, get: field => value?.[field] };
  }
  collection(name) {
    return {
      doc: id => {
        const key = `${name}/${id}`;
        return { key, get: () => this.snapshot(key) };
      },
    };
  }
  runTransaction(work) {
    const result = this.queue.then(() => work({
      get: ref => this.snapshot(ref.key),
      getAll: (...refs) => refs.map(ref => this.snapshot(ref.key)),
      create: (ref, value) => {
        assert.equal(this.rows.has(ref.key), false);
        this.rows.set(ref.key, value);
      },
      set: (ref, value) => this.rows.set(ref.key, value),
      update: (ref, value) => this.rows.set(ref.key, { ...this.rows.get(ref.key), ...value }),
    }));
    this.queue = result.then(() => {});
    return result;
  }
}

test('signed wheel receipts are idempotent, cap concurrent claims, and expire by server time', async t => {
  const env = {
    PATHWISE_REWARDS_ENABLED: 'true',
    PATHWISE_ADMOB_REWARDED: '1234567890',
    PATHWISE_ADMOB_EXTRA_HINT: '1234567891',
    PATHWISE_ADMOB_HINT_REFILL: '1234567892',
    PATHWISE_ADMOB_WHEEL: '1234567893',
  };
  for (const [key, value] of Object.entries(env)) {
    const previous = process.env[key];
    process.env[key] = value;
    t.after(() => previous === undefined ? delete process.env[key] : process.env[key] = previous);
  }
  const {privateKey, publicKey} = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const headers = { authorization: 'Bearer ' + 'a'.repeat(64) };
  const db = new MemoryFirestore();
  let now = 2000000000000;
  const options = { keySet: async () => new Map([['17', publicKey]]), nowMs: () => now };
  const request = (method, url, auth = headers) => rewardRequest({ method, url, headers: auth }, db, options);
  async function ticket() {
    now += 15000;
    const [code, body] = await request('POST', '/v1/rewards/start/wheel');
    assert.equal(code, 200);
    return body.token;
  }
  function callback(token, id, unit = '1234567893') {
    const raw = `ad_unit=${unit}&custom_data=${token}&timestamp=${now}&transaction_id=${id}`;
    const signature = sign('sha256', Buffer.from(raw), privateKey).toString('base64url');
    return '/v1/rewards/callback?' + raw + '&signature=' + signature + '&key_id=17';
  }
  const cancelled = await ticket();
  assert.equal((await request('GET', '/v1/rewards/status/' + cancelled))[0], 202);
  assert.deepEqual((await request('GET', '/v1/rewards/wheel'))[1].counts, {});
  const tickets = [];
  for (let i = 0; i < 5; i++) tickets.push(await ticket());
  const invalid = callback(tickets[4], 'wrong-placement', '1234567890');
  assert.equal((await request('GET', invalid))[0], 403);
  const urls = tickets.map((token, i) => callback(token, 'wheel-' + i));
  const responses = await Promise.all(urls.map(url => request('GET', url)));
  assert.equal(responses.filter(row => row[0] === 200).length, 4);
  assert.equal((await request('GET', urls[0]))[0], 200);
  const [status, state] = await request('GET', '/v1/rewards/wheel');
  assert.equal(status, 200);
  assert.equal(state.stamps.length, 4);
  assert.equal(Object.values(state.counts).reduce((a, b) => a + b), 4);
  assert.equal((await request('POST', '/v1/rewards/start/wheel'))[0], 429);
  assert.equal((await request('GET', '/v1/rewards/wheel', {}))[0], 403);
  now += wheelWindow;
  assert.deepEqual((await request('GET', '/v1/rewards/wheel'))[1].stamps, []);
  const next = await ticket();
  assert.equal((await request('GET', callback(next, 'wheel-next')))[0], 200);
  const recovered = (await request('GET', '/v1/rewards/wheel'))[1];
  assert.equal(Object.values(recovered.counts).reduce((a, b) => a + b), 5);
});
