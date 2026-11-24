import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { test } from 'node:test';
import { consoleProbe, decodeReward } from './rewards.mjs';
import { roll } from './economy.mjs';
import { start } from './testing/harness.mjs';

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
  assert.equal(decodeReward(signed(payload).replace('key_id=100', 'key_id=99'), keyFor, now), null);
  assert.equal(decodeReward(signed(payload + '&transaction_id=extra'), keyFor, now), null);
  assert.equal(decodeReward(signed(payload), keyFor, now + 3600001), null);
});

test('a console probe must be signed and cannot decode as a reward session', () => {
  const probe = payload.replace(token, consoleProbe);
  assert.equal(decodeReward(signed(probe), keyFor, now), null);
  assert.equal(decodeReward(signed(probe), keyFor, now, true).token, consoleProbe);
  assert.equal(decodeReward(probe, keyFor, now, true), null);
});

const COINS = '1000000001';
const HINT = '1000000002';
const WHEEL = '1000000003';

async function watched(h, p, placement, { unit, kind } = {}) {
  const started = await h.call('POST', `/v1/rewards/start/${placement}`, { token: p.token, body: kind ? { kind } : {} });
  if (started.status !== 200) return { started };
  const { token: session } = started.body;
  const preCallback = await h.call('GET', `/v1/rewards/status/${session}`, { token: p.token });
  const callback = await h.call('GET', `/v1/rewards/callback?${h.ssv(session, { unit: unit ?? COINS })}`);
  const post = await h.call('GET', `/v1/rewards/status/${session}`, { token: p.token });
  const claim = () => h.command(p, 'reward.claim', { token: session });
  return { started, session, preCallback, callback, post, claim };
}

test('coin video: nothing is paid before a signed callback, then the server grants the fixed amount', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const early = await h.call('POST', '/v1/rewards/start/coins', { token: p.token, body: {} });
  assert.equal((await h.command(p, 'reward.claim', { token: early.body.token })).body.error, 'not_verified', 'no callback yet');
  const w = await watched(h, p, 'coins');
  assert.equal(w.preCallback.status, 202);
  assert.equal(w.callback.status, 200);
  assert.equal(w.post.body.verified, true);
  const granted = await w.claim();
  assert.equal(granted.body.wallet.coins, 70);
  assert.equal((await w.claim()).body.error, 'already_claimed');
  assert.equal((await h.state(p)).body.wallet.coins, 70);
});

test('forged, replayed, mis-placed and expired callbacks never grant', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const other = (await h.register()).player;
  const { token: session } = (await h.call('POST', '/v1/rewards/start/coins', { token: p.token, body: {} })).body;
  const wrongKey = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey;
  assert.equal((await h.call('GET', `/v1/rewards/callback?${h.ssv(session, { key: wrongKey })}`)).status, 403, 'forged signature');
  assert.equal((await h.call('GET', `/v1/rewards/callback?${h.ssv(session, { unit: HINT })}`)).status, 403, 'wrong placement unit');
  assert.equal((await h.call('GET', `/v1/rewards/callback?${h.ssv(session, { time: h.clock.time - 7200000 })}`)).status, 403, 'stale');
  assert.equal((await h.call('GET', `/v1/rewards/callback?${h.ssv('f'.repeat(64))}`)).status, 403, 'unknown session');
  assert.equal((await h.call('GET', `/v1/rewards/callback?${h.ssv(session, { transaction: 'same-tx' })}`)).status, 200);
  assert.equal((await h.call('GET', `/v1/rewards/callback?${h.ssv(session, { transaction: 'same-tx' })}`)).status, 200, 'redelivery is idempotent');
  assert.equal((await h.call('GET', `/v1/rewards/callback?${h.ssv(session, { transaction: 'second-tx' })}`)).status, 403, 'one receipt per session');
  assert.equal((await h.command(other, 'reward.claim', { token: session })).status, 404, "another player's session");
  assert.equal((await h.call('GET', `/v1/rewards/status/${session}`, { token: other.token })).status, 404);
  assert.equal((await h.command(p, 'reward.claim', { token: session })).status, 200);
  assert.equal((await h.state(p)).body.wallet.coins, 70);
});

test('the signed console probe verifies the endpoint without creating a reward', async (t) => {
  const h = await start(); t.after(h.close);
  const probe = await h.call('GET', `/v1/rewards/callback?${h.ssv(consoleProbe)}`);
  assert.equal(probe.body.probe, true);
});

test('daily video limits use the server day and the fourth video pays the milestone', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  let wallet;
  for (let i = 0; i < 6; i++) wallet = (await (await watched(h, p, 'coins')).claim()).body.wallet;
  assert.equal(wallet.coins, 50 + 6 * 20 + 40);
  assert.equal((await h.call('POST', '/v1/rewards/start/coins', { token: p.token, body: {} })).status, 429, 'no ad is offered past the limit');
  h.clock.time += 25 * 3600 * 1000;
  await h.renew(p);
  assert.equal((await h.call('POST', '/v1/rewards/start/coins', { token: p.token, body: {} })).status, 200);
});

test('a session started before the limit cannot be used to exceed it', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const pending = [];
  for (let i = 0; i < 8; i++) {
    const s = await h.call('POST', '/v1/rewards/start/hint', { token: p.token, body: {} });
    if (s.status === 200) { await h.call('GET', `/v1/rewards/callback?${h.ssv(s.body.token, { unit: HINT })}`); pending.push(s.body.token); }
  }
  const results = [];
  for (const token of pending) results.push((await h.command(p, 'reward.claim', { token })).status);
  assert.equal(results.filter((s) => s === 200).length, 5);
  assert.equal((await h.state(p)).body.wallet.hints, 3 + 5);
});

test('rewarded hint, boost and crate placements pay what the server decides', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const hint = await watched(h, p, 'hint', { unit: HINT });
  assert.equal((await hint.claim()).body.wallet.hints, 4);
  const boost = await watched(h, p, 'boost', { kind: 'doubleTen' });
  assert.equal((await boost.claim()).body.wallet.inventory.doubleTen, 1);
  assert.equal((await h.call('POST', '/v1/rewards/start/boost', { token: p.token, body: { kind: 'tripleFifteen' } })).status, 429, 'needs four coin videos first');
  assert.equal((await h.call('POST', '/v1/rewards/start/boost', { token: p.token, body: { kind: 'free2play' } })).status, 422);
  assert.equal((await h.call('POST', '/v1/rewards/start/crate', { token: p.token, body: { kind: 'crate/0' } })).status, 409, 'no such crate');
  roll.percent = () => 40;
  h.clock.time += 46000;
  const drop = await h.command(p, 'crate.poll');
  assert.equal(drop.body.crate.coins, 35);
  const crate = await watched(h, p, 'crate', { kind: drop.body.crate.id });
  const claimed = await crate.claim();
  assert.equal(claimed.body.coins, 35);
  assert.equal(claimed.body.wallet.coins, 85);
  assert.equal((await h.command(p, 'reward.claim', { token: crate.session })).status, 409);
});

test('video Fortune Wheel spins settle only after the animation, with a server limit of six per rolling day', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  roll.percent = () => 0;
  const spin = await watched(h, p, 'wheel', { unit: WHEEL });
  const granted = await spin.claim();
  assert.equal(granted.body.wallet.coins, 50);
  assert.equal(granted.body.wallet.wheel.pending.prize, 'sprout');
  assert.equal((await h.call('POST', '/v1/rewards/start/wheel', { token: p.token, body: {} })).status, 409, 'settle the pending spin first');
  assert.equal((await h.command(p, 'wheel.settle', { id: granted.body.pending.id })).body.wallet.coins, 58);
  for (let i = 0; i < 5; i++) { const w = await watched(h, p, 'wheel', { unit: WHEEL }); const c = await w.claim(); await h.command(p, 'wheel.settle', { id: c.body.pending.id }); }
  assert.equal((await h.call('POST', '/v1/rewards/start/wheel', { token: p.token, body: {} })).status, 429);
  h.clock.time += 24 * 3600 * 1000 + 1;
  await h.renew(p);
  assert.equal((await h.call('POST', '/v1/rewards/start/wheel', { token: p.token, body: {} })).status, 200);
});

test('rewards are unavailable until publisher units are configured', async (t) => {
  const h = await start({ rewardEnv: { PATHWISE_REWARDS_ENABLED: 'false' } }); t.after(h.close);
  const p = (await h.register()).player;
  assert.equal((await h.call('POST', '/v1/rewards/start/coins', { token: p.token, body: {} })).status, 503);
  const misconfigured = await start({ rewardEnv: { PATHWISE_ADMOB_EXTRA_HINT: 'ca-app-pub-1111111111111111/1000000001' } }); t.after(misconfigured.close);
  const q = (await misconfigured.register()).player;
  assert.equal((await misconfigured.call('POST', '/v1/rewards/start/coins', { token: q.token, body: {} })).status, 503);
});
