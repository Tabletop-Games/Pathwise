import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildPuzzle, parsePuzzleKey } from './engine/ids.mjs';
import { start } from './testing/harness.mjs';

const solution = (key) => buildPuzzle(parsePuzzleKey(key)).solution;
const day = (h) => new Date(h.clock.time).toISOString().slice(0, 10);

async function solve(h, p, key, { ms = 20000, route = solution(key), extra = {} } = {}) {
  await h.command(p, 'play.start', { key });
  h.clock.time += ms + 500;
  return h.command(p, 'play.complete', { key, route, ms, ...extra });
}

test('a verified completion pays the server-computed reward once and unlocks the next level', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const done = await solve(h, p, 'levels/1');
  assert.equal(done.status, 200);
  // 5 clear + 20 first-day streak + 20 "Trailhead" achievement on top of 50 welcome coins.
  assert.equal(done.body.reward, 5);
  assert.equal(done.body.wallet.coins, 95);
  assert.equal(done.body.highestUnlocked, 2);
  assert.deepEqual(done.body.achievements, ['trailhead']);
  const again = await solve(h, p, 'levels/1');
  assert.equal(again.status, 200);
  assert.equal(again.body.reward, 0);
  assert.equal(again.body.wallet.coins, 95, 'no second payout for a replayed level');
  assert.equal((await h.state(p)).body.progress.results['levels/1'].ms, 20000);
});

test('the same completion request is idempotent after a network retry', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  await h.command(p, 'play.start', { key: 'levels/1' });
  h.clock.time += 21000;
  const args = { key: 'levels/1', route: solution('levels/1'), ms: 20000 };
  const a = await h.command(p, 'play.complete', args, 'op-complete-retry');
  const b = await h.command(p, 'play.complete', args, 'op-complete-retry');
  assert.equal(b.body.replayed, true);
  assert.equal(b.body.reward, a.body.reward);
  assert.equal(b.body.wallet.coins, 95);
});

test('forged, wrong-puzzle and malformed routes are rejected without side effects', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  await h.command(p, 'play.start', { key: 'levels/1' });
  h.clock.time += 30000;
  const good = solution('levels/1');
  const attempts = [
    [...good].reverse(), good.slice(0, -1), [...good.slice(0, 3), ...good.slice(0, 3)], good.map((c) => c + 100),
    solution('levels/2'), 'solved', null, [], good.map(String),
  ];
  for (const route of attempts) {
    const r = await h.command(p, 'play.complete', { key: 'levels/1', route, ms: 20000 });
    assert.equal(r.status, 422, JSON.stringify(route).slice(0, 40));
  }
  const view = await h.state(p);
  assert.equal(view.body.wallet.coins, 50);
  assert.deepEqual(view.body.progress.results, {});
  assert.equal(view.body.progress.highestUnlocked, 1);
});

test('levels cannot be skipped and clients cannot claim reward amounts or times freely', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  assert.equal((await h.command(p, 'play.start', { key: 'levels/5' })).body.error, 'level_locked');
  assert.equal((await h.command(p, 'play.complete', { key: 'levels/5', route: solution('levels/5'), ms: 20000 })).status, 403);
  assert.equal((await h.command(p, 'play.complete', { key: 'levels/1', route: solution('levels/1'), ms: 20000 })).body.error, 'not_started');
  await h.command(p, 'play.start', { key: 'levels/1' });
  h.clock.time += 5000;
  const tooFast = await h.command(p, 'play.complete', { key: 'levels/1', route: solution('levels/1'), ms: 50 });
  assert.equal(tooFast.body.error, 'implausible_time');
  const tooLong = await h.command(p, 'play.complete', { key: 'levels/1', route: solution('levels/1'), ms: 600000 });
  assert.equal(tooLong.body.error, 'implausible_time', 'cannot claim more time than the server observed');
  const ok = await h.command(p, 'play.complete', { key: 'levels/1', route: solution('levels/1'), ms: 4000, reward: 99999, coins: 1e9 });
  assert.equal(ok.body.reward, 5);
});

test('hints are charged once per use, tracked on the server and reported in the result', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  await h.command(p, 'play.start', { key: 'levels/1' });
  const first = await h.command(p, 'hint.use', { attempt: 'levels/1' }, 'op-hint-use-001');
  const replay = await h.command(p, 'hint.use', { attempt: 'levels/1' }, 'op-hint-use-001');
  assert.equal(first.body.wallet.hints, 2);
  assert.equal(replay.body.wallet.hints, 2, 'a retried request does not charge twice');
  assert.equal((await h.command(p, 'hint.use', { attempt: 'garbage' })).status, 422);
  h.clock.time += 20000;
  const done = await h.command(p, 'play.complete', { key: 'levels/1', route: solution('levels/1'), ms: 15000 });
  assert.equal(done.body.hints, 1);
  const state = await h.state(p);
  assert.equal(state.body.progress.results['levels/1'].unassisted, false);
  for (let i = 0; i < 2; i++) await h.command(p, 'hint.use', { attempt: 'levels/1' });
  assert.equal((await h.command(p, 'hint.use', { attempt: 'levels/1' })).body.error, 'no_hints');
});

test('first-clear rewards use research effects and the active coin boost from the server clock', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const ref = h.db.collection('pathwise-players').doc(p.id);
  const doc = (await ref.get()).data();
  Object.assign(doc, { coins: 1000, research: { magnet: 2 }, inventory: { doubleTen: 1 } });
  await ref.set(doc);
  await h.command(p, 'boost.activate', { boost: 'doubleTen' });
  const done = await solve(h, p, 'levels/1');
  assert.equal(done.body.reward, (5 + 4) * 2);
});

test('unfinished routes are saved server-side, resumable on another device and protected from stale writes', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const route = solution('levels/1');
  await h.command(p, 'play.start', { key: 'levels/1' });
  const save = (args) => h.command(p, 'attempt.save', { key: 'levels/1', ms: 3000, started: true, ...args });
  assert.equal((await save({ path: route.slice(0, 5), base: 0 })).body.v, 1);
  assert.equal((await save({ path: route.slice(0, 7), base: 0 })).status, 409, 'stale base revision');
  assert.equal((await save({ path: route.slice(0, 7), base: 1, history: [route.slice(0, 3), route.slice(0, 5)] })).body.v, 2);
  assert.equal((await save({ path: [3, 4], base: 2 })).status, 422);
  assert.equal((await save({ path: route, base: 2 })).status, 422, 'a finished route is not an attempt');
  const other = await h.call('POST', '/v1/auth/refresh', { body: { refresh: p.refresh } });
  const view = await h.state({ token: other.body.session.token });
  assert.deepEqual(view.body.progress.attempts['levels/1'].path, route.slice(0, 7));
  assert.deepEqual(view.body.progress.attempts['levels/1'].history, [route.slice(0, 3), route.slice(0, 5)], 'undo history survives storage');
  const resumed = await h.command(p, 'play.start', { key: 'levels/1' });
  assert.equal(resumed.body.attempt.v, 2);
  assert.deepEqual(resumed.body.attempt.history[1], route.slice(0, 5));
  const replayed = await h.command(p, 'play.start', { key: 'levels/1', replay: true });
  assert.equal(replayed.body.attempt, null);
});

test('a puzzle resumed from a local save may report its earlier active time', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  await h.command(p, 'play.start', { key: 'levels/1', ms: 90000 });
  h.clock.time += 2000;
  const done = await h.command(p, 'play.complete', { key: 'levels/1', route: solution('levels/1'), ms: 91000 });
  assert.equal(done.status, 200);
  assert.equal(done.body.ms, 91000);
  await h.command(p, 'play.start', { key: 'levels/2', ms: 5000 });
  h.clock.time += 1000;
  const inflated = await h.command(p, 'play.complete', { key: 'levels/2', route: solution('levels/2'), ms: 600000 });
  assert.equal(inflated.body.error, 'implausible_time');
});

test('Daily Challenge enforces the local day, checkpoint order and sums its stages', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const d = day(h);
  assert.equal((await h.command(p, 'play.start', { key: 'daily/1999-01-01' })).body.error, 'wrong_day');
  assert.equal((await h.command(p, 'play.start', { key: `daily/${d}` })).body.error, 'checkpoint_locked');
  assert.equal((await h.command(p, 'play.start', { key: `daily-checkpoint/${d}/2` })).body.error, 'checkpoint_locked');
  const s1 = await solve(h, p, `daily-checkpoint/${d}/1`, { ms: 8000 });
  assert.equal(s1.body.stage, true);
  assert.equal(s1.body.wallet.coins, 50, 'stages pay nothing');
  await solve(h, p, `daily-checkpoint/${d}/2`, { ms: 9000 });
  const final = await solve(h, p, `daily/${d}`, { ms: 10000 });
  assert.equal(final.body.reward, 10);
  assert.equal(final.body.ms, 27000);
  assert.ok(final.body.wallet.streak.count === 1);
});

test('Time Attack runs on the server clock: deadlines cannot be extended by disconnecting', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  assert.equal((await h.command(p, 'attack.start', { minutes: 7 })).status, 422);
  const begun = await h.command(p, 'attack.start', { minutes: 1 });
  const run = begun.body.run;
  assert.equal(run.remainingMs, 60000);
  assert.equal((await h.command(p, 'attack.start', { minutes: 1 })).body.run.id, run.id, 'resumes the live run');
  const clear = async (index) => {
    h.clock.time += 3000;
    return h.command(p, 'attack.clear', { run: run.id, route: solution(`attack/${run.id}/${index}`) });
  };
  assert.equal((await clear(0)).body.run.clears.length, 1);
  assert.equal((await clear(1)).body.run.clears.length, 2);
  assert.equal((await clear(5)).status, 422, 'must solve the board the server expects next');
  assert.equal((await h.command(p, 'attack.finish', { run: run.id })).body.error, 'run_active');
  // The player "goes offline" at 10 s and tries to submit the third board after the 60 s deadline.
  h.clock.time += 120000;
  await h.renew(p);
  const late = await h.command(p, 'attack.clear', { run: run.id, route: solution(`attack/${run.id}/2`) });
  assert.equal(late.body.over, true);
  assert.equal(late.body.run.clears.length, 2, 'the late board does not count');
  assert.equal(late.body.run.finished, true);
  assert.equal(late.body.wallet.coins, 50 + 6 + 20, 'two boards pay 2×3 coins, plus the first-day streak milestone');
});

test('Time Attack finalises exactly once and an abandoned run pays nothing', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  const run = (await h.command(p, 'attack.start', { minutes: 1 })).body.run;
  assert.equal((await h.command(p, 'attack.stop', { run: run.id })).status, 200);
  assert.equal((await h.command(p, 'attack.finish', { run: run.id })).status, 409);
  const next = (await h.command(p, 'attack.start', { minutes: 1 })).body.run;
  assert.notEqual(next.id, run.id);
  h.clock.time += 61000;
  const first = await h.command(p, 'attack.finish', { run: next.id });
  const second = await h.command(p, 'attack.finish', { run: next.id });
  assert.equal(first.body.reward, 0);
  assert.equal(second.body.wallet.coins, first.body.wallet.coins);
  assert.equal((await h.state(p)).body.wallet.coins, 50);
});
