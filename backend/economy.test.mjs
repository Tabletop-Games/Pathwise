import assert from 'node:assert/strict';
import { test } from 'node:test';
import { roll } from './economy.mjs';
import { start } from './testing/harness.mjs';

async function funded(h, coins = 2000) {
  const { player } = await h.register();
  // Production has no grant command, so write the balance directly (test-only).
  const ref = h.db.collection('pathwise-players').doc(player.id);
  const doc = (await ref.get()).data();
  doc.coins += coins; doc.earned += coins;
  await ref.set(doc);
  return player;
}

test('hint purchase spends the server price and cannot overdraw', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const poor = await h.command(p, 'hint.buy');
  assert.equal(poor.status, 402);
  assert.equal((await h.state(p)).body.wallet.coins, 50);
  const rich = await funded(h, 100);
  const bought = await h.command(rich, 'hint.buy');
  assert.equal(bought.status, 200);
  assert.equal(bought.body.wallet.coins, 90);
  assert.equal(bought.body.wallet.hints, 4);
});

test('the same operation id replays one result and never charges twice', async (t) => {
  const h = await start(); t.after(h.close);
  const p = await funded(h, 500);
  const first = await h.command(p, 'hint.buy', {}, 'op-buy-hint-0001');
  const replay = await h.command(p, 'hint.buy', {}, 'op-buy-hint-0001');
  assert.equal(first.body.replayed, undefined);
  assert.equal(replay.body.replayed, true);
  assert.equal(replay.body.wallet.coins, first.body.wallet.coins);
  assert.equal((await h.state(p)).body.wallet.hints, 4);
  // Reusing an id for a different request is a conflict, not a silent replay.
  const conflict = await h.command(p, 'theme.buy', { theme: 'forestMint' }, 'op-buy-hint-0001');
  assert.equal(conflict.status, 409);
  assert.equal((await h.command(p, 'hint.buy', {}, 'short')).status, 422);
});

test('concurrent spends are serialised: only affordable purchases succeed', async (t) => {
  const h = await start(); t.after(h.close);
  const p = await funded(h, 70); // 120 coins = exactly two hints
  const results = await Promise.all(Array.from({ length: 6 }, () => h.command(p, 'hint.buy')));
  assert.equal(results.filter((r) => r.status === 200).length, 2);
  assert.equal(results.filter((r) => r.status === 402).length, 4);
  const wallet = (await h.state(p)).body.wallet;
  assert.equal(wallet.coins, 0);
  assert.equal(wallet.hints, 5);
});

test('concurrent retries of one operation apply it once', async (t) => {
  const h = await start(); t.after(h.close);
  const p = await funded(h, 500);
  const results = await Promise.all(Array.from({ length: 5 }, () => h.command(p, 'hint.buy', {}, 'op-concurrent-1')));
  assert.ok(results.every((r) => r.status === 200));
  assert.equal((await h.state(p)).body.wallet.hints, 4);
});

test('themes: prices come from the server, ownership is permanent and free themes cost nothing', async (t) => {
  const h = await start(); t.after(h.close);
  const p = await funded(h, 100);
  assert.equal((await h.command(p, 'theme.buy', { theme: 'noSuchTheme' })).status, 422);
  assert.equal((await h.command(p, 'theme.buy', { theme: 'neon' })).status, 402);
  const bought = await h.command(p, 'theme.buy', { theme: 'forestMint', price: 0 });
  assert.equal(bought.status, 200, 'client price field is ignored');
  assert.equal(bought.body.wallet.coins, 150 - 90);
  assert.ok(bought.body.wallet.themes.includes('forestMint'));
  assert.equal((await h.command(p, 'theme.buy', { theme: 'forestMint' })).status, 409);
  assert.equal((await h.command(p, 'theme.equip', { theme: 'forestMint' })).status, 200);
  assert.equal((await h.command(p, 'theme.equip', { theme: 'gilded' })).status, 403);
  assert.equal((await h.command(p, 'theme.equip', { theme: 'blackwater' })).status, 200);
});

test('research prices, ranks and prerequisites are enforced', async (t) => {
  const h = await start(); t.after(h.close);
  const p = await funded(h, 5000);
  assert.equal((await h.command(p, 'research.buy', { item: 'tuning' })).body.error, 'locked');
  assert.equal((await h.command(p, 'research.buy', { item: 'magnet' })).body.wallet.coins, 5050 - 55);
  assert.equal((await h.command(p, 'research.buy', { item: 'nope' })).status, 422);
  let wallet;
  for (let i = 0; i < 2; i++) wallet = (await h.command(p, 'research.buy', { item: 'efficiency' })).body.wallet;
  assert.equal(wallet.research.efficiency, 2);
  assert.equal((await h.command(p, 'research.buy', { item: 'tuning' })).body.error, 'locked');
});

test('boosts: purchase, single active slot, server-timed expiry', async (t) => {
  const h = await start(); t.after(h.close);
  const p = await funded(h, 1000);
  assert.equal((await h.command(p, 'boost.buy', { boost: 'doubleThirty' })).status, 403, 'not for sale');
  await h.command(p, 'boost.buy', { boost: 'doubleTen' });
  await h.command(p, 'boost.buy', { boost: 'tripleFifteen' });
  const on = await h.command(p, 'boost.activate', { boost: 'doubleTen' });
  assert.equal(on.status, 200);
  assert.equal(on.body.wallet.active.doubleTen, 10 * 60 * 1000);
  assert.equal((await h.command(p, 'boost.activate', { boost: 'tripleFifteen' })).body.error, 'boost_active');
  h.clock.time += 10 * 60 * 1000 + 1;
  assert.equal((await h.state(p)).body.wallet.active.doubleTen, undefined);
  assert.equal((await h.command(p, 'boost.activate', { boost: 'tripleFifteen' })).status, 200);
});

test('streak freezes are capped', async (t) => {
  const h = await start(); t.after(h.close);
  const p = await funded(h, 2000);
  assert.equal((await h.command(p, 'freeze.buy')).status, 200);
  assert.equal((await h.command(p, 'freeze.buy')).status, 200);
  assert.equal((await h.command(p, 'freeze.buy')).body.error, 'max_freezes');
});

test('Fortune Wheel: server picks the prize, coins arrive only after settle, cooldown uses the server clock', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  roll.percent = () => 99;
  const spin = await h.command(p, 'wheel.free');
  assert.equal(spin.status, 200);
  assert.equal(spin.body.wallet.coins, 50, 'nothing credited before the animation settles');
  assert.equal(spin.body.pending.prize, 'summit');
  assert.equal((await h.command(p, 'wheel.free')).body.error, 'spin_pending');
  // Interrupted app: pending survives and is visible after a fresh state load.
  assert.equal((await h.state(p)).body.wallet.wheel.pending.prize, 'summit');
  assert.equal((await h.command(p, 'wheel.settle', { id: 'wheel/free/999' })).status, 409);
  const settled = await h.command(p, 'wheel.settle', { id: spin.body.pending.id });
  assert.equal(settled.body.wallet.coins, 150);
  assert.equal((await h.command(p, 'wheel.settle', { id: spin.body.pending.id })).status, 409);
  // A client-supplied clock or header cannot shorten the cooldown.
  const cheat = await h.call('POST', '/v1/command', { token: p.token, headers: { date: 'Mon, 01 Jan 2035 00:00:00 GMT' },
    body: { op: 'op-cheat-0001', type: 'wheel.free', args: { now: 9e15, serverNow: 9e15 } } });
  assert.equal(cheat.status, 429);
  h.clock.time += 24 * 3600 * 1000;
  await h.renew(p);
  assert.equal((await h.command(p, 'wheel.free')).status, 200);
});

test('wheel draws follow the published weights across all 100 rolls', async () => {
  const { pickWheelPrize, wheelPrizes } = await import('./economy-config.mjs');
  const hits = Object.fromEntries(wheelPrizes.map((prize) => [prize.id, 0]));
  for (let value = 0; value < 100; value++) hits[pickWheelPrize(value).id]++;
  for (const prize of wheelPrizes) assert.equal(hits[prize.id], prize.weight);
  assert.throws(() => pickWheelPrize(100), RangeError);
});

test('supply crates: server clock gates drops, prizes are server-rolled and capped per window', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const early = await h.command(p, 'crate.poll');
  assert.equal(early.body.crate, null);
  assert.ok(early.body.retryInMs > 0);
  roll.percent = () => 99;
  h.clock.time += 46000;
  const drop = await h.command(p, 'crate.poll');
  assert.equal(drop.body.crate.coins, 90);
  assert.equal(drop.body.flightMs, 8000);
  assert.equal((await h.command(p, 'crate.poll')).body.crate, null);
  assert.equal((await h.state(p)).body.wallet.coins, 50, 'a crate is worth nothing until its video reward is claimed');
  for (let i = 0; i < 12; i++) { h.clock.time += 151000; if (i % 4 === 3) await h.renew(p); await h.command(p, 'crate.forfeit', { id: `crate/${i}` }); await h.command(p, 'crate.poll'); }
  const wallet = (await h.state(p)).body.wallet;
  assert.ok(wallet.crates.offersRemaining === 0, 'eight offers per rolling window');
});

test('timezone changes are limited so daily rollovers cannot be farmed', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  assert.equal((await h.command(p, 'timezone.set', { tz: 600 })).body.tz, 600);
  assert.equal((await h.command(p, 'timezone.set', { tz: -600 })).body.tz, 600);
  assert.equal((await h.command(p, 'timezone.set', { tz: 5000 })).status, 422);
  h.clock.time += 25 * 3600 * 1000;
  await h.renew(p);
  assert.equal((await h.command(p, 'timezone.set', { tz: -600 })).body.tz, -600);
});

test('preferences and tutorials sync across devices', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  await h.command(p, 'prefs.set', { haptics: false });
  await h.command(p, 'tutorial.ack', { id: 'ice', skipped: true });
  const second = await h.call('POST', '/v1/auth/refresh', { body: { refresh: p.refresh } });
  const view = await h.state({ token: second.body.session.token });
  assert.equal(view.body.progress.prefs.haptics, false);
  assert.equal(view.body.progress.tutorials.ice, 'skipped');
});

test('commands reject unknown types, oversized bodies and development-only grants in production', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  assert.equal((await h.command(p, 'wallet.set', { coins: 1e9 })).status, 422);
  assert.equal((await h.command(p, 'dev.grant', { coins: 1e6 })).status, 422);
  assert.equal((await h.call('POST', '/v1/command', { token: p.token, raw: JSON.stringify({ op: 'x'.repeat(30000) }) })).status, 413);
  const dev = await start({ env: 'development' }); t.after(dev.close);
  const d = (await dev.register()).player;
  assert.equal((await dev.command(d, 'dev.grant', { coins: 500 })).body.wallet.coins, 550);
});
