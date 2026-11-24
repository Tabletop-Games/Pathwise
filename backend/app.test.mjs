import assert from 'node:assert/strict';
import { test } from 'node:test';
import { start } from './testing/harness.mjs';

test('responses are uncacheable JSON and unknown routes are 404', async (t) => {
  const h = await start(); t.after(h.close);
  const res = await fetch(h.origin + '/v1/ping');
  assert.equal(res.headers.get('cache-control'), 'no-store');
  assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(res.headers.get('access-control-allow-origin'), null);
  assert.equal((await h.call('GET', '/v1/nothing')).status, 401, 'authentication precedes routing for protected paths');
  const p = (await h.register()).player;
  assert.equal((await h.call('GET', '/v1/nothing', { token: p.token })).status, 404);
  assert.equal((await h.call('DELETE', '/v1/state', { token: p.token })).status, 404);
});

test('request logs never contain bearer values, purchase tokens or callback query strings', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add('super-secret-purchase-token', 'pathwise_coins_500', p.id);
  await h.call('POST', '/v1/play/verify', { token: p.token, body: { product: 'pathwise_coins_500', token: 'super-secret-purchase-token' } });
  await h.call('GET', `/v1/rewards/callback?${h.ssv('a'.repeat(64))}`);
  const text = h.logs.join('\n');
  for (const secret of [p.token, p.refresh, 'super-secret-purchase-token', 'signature=', 'custom_data']) assert.ok(!text.includes(secret), secret);
  assert.ok(h.logs.every((line) => JSON.parse(line).operation));
});

test('abusive request rates are throttled per session', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const statuses = [];
  for (let i = 0; i < 130; i++) statuses.push((await h.call('GET', '/v1/state', { token: p.token })).status);
  assert.ok(statuses.includes(429));
  assert.equal(statuses[0], 200);
});

test('unexpected storage failures surface as a generic unavailable error', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.db.failNext = 1;
  const failed = await h.command(p, 'tutorial.ack', { id: 'walls' });
  assert.equal(failed.status, 503);
  assert.deepEqual(failed.body, { error: 'service_unavailable' });
  assert.deepEqual((await h.state(p)).body.progress.tutorials, {}, 'a failed commit leaves state untouched');
});

test('a lost response is safe to retry: idempotent replay returns the committed result', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const ref = h.db.collection('pathwise-players').doc(p.id);
  const doc = (await ref.get()).data(); doc.coins = 500; await ref.set(doc);
  const op = 'op-flaky-network-1';
  const first = await h.command(p, 'hint.buy', {}, op);
  assert.equal(first.status, 200);
  // The client never saw the response and retries after reconnecting.
  const retry = await h.command(p, 'hint.buy', {}, op);
  assert.equal(retry.body.wallet.coins, 440);
  assert.equal(retry.body.replayed, true);
});

test('Firestore writes stay bounded: a normal puzzle costs a handful of document writes', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const before = h.db.writes;
  const { buildPuzzle, parsePuzzleKey } = await import('./engine/ids.mjs');
  const route = buildPuzzle(parsePuzzleKey('levels/1')).solution;
  await h.command(p, 'play.start', { key: 'levels/1' });
  h.clock.time += 20000;
  await h.command(p, 'play.complete', { key: 'levels/1', route, ms: 15000 });
  // start: wallet+progress+ledger, complete: wallet+progress+ledger.
  assert.ok(h.db.writes - before <= 6, `writes: ${h.db.writes - before}`);
});
