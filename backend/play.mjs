// Puzzle sessions, server-side completion validation and Time Attack runs.
import { randomBytes } from 'node:crypto';
import { attackReward, clearReward, levelCountOf, rules } from './economy-config.mjs';
import { buildPuzzle, parsePuzzleKey } from './engine/ids.mjs';
import { isValidPath, validateCompletedRoute } from './engine/puzzle.mjs';
import { HttpError } from './http.mjs';
import {
  awardAchievements, coinMultiplier, credit, effect, localDay, qualifyStreak,
} from './players.mjs';

const fail = (status, code) => { throw new HttpError(status, code); };
const MIN_MS_PER_CELL = 30;
const TIME_SLACK_MS = 5000;
const ATTACK_GRACE_MS = 2000;
const ATTEMPT_LIMIT = 12;

const parseOrFail = (key) => parsePuzzleKey(key) ?? fail(422, 'invalid_puzzle');
const integer = (value, min, max) => (Number.isInteger(value) && value >= min && value <= max ? value : fail(422, 'invalid_argument'));

/** Throws unless this puzzle may be played now. Attack boards are gated by the run, not here. */
function assertPlayable(ctx, parsed) {
  if (parsed.mode === 'attack') fail(422, 'invalid_puzzle');
  if (parsed.mode === 'levels') {
    if (parsed.level > ctx.progress.highestUnlocked) fail(403, 'level_locked');
    return;
  }
  const today = localDay(ctx.now, ctx.state.tz);
  const started = ctx.progress.started[parsed.key];
  const startedDay = started === undefined ? null : localDay(started, ctx.state.tz);
  if (parsed.day !== today && parsed.day !== startedDay) fail(403, 'wrong_day');
  const stage = (n) => ctx.progress.stages[`daily-checkpoint/${parsed.day}/${n}`];
  if (parsed.checkpoint === 2 && !stage(1)) fail(403, 'checkpoint_locked');
  if (parsed.checkpoint === null && !(stage(1) && stage(2))) fail(403, 'checkpoint_locked');
}

function isUnassisted(entry) { return entry.unassisted === true || entry.hints === 0; }

export const playCommands = {
  'play.start': (ctx, args) => {
    const parsed = parseOrFail(args.key);
    assertPlayable(ctx, parsed);
    const { progress } = ctx;
    const replay = args.replay === true;
    if (replay) delete progress.attempts[parsed.key];
    const attempt = progress.attempts[parsed.key];
    if (!attempt) progress.hintUse[parsed.key] = 0;
    // A resumed puzzle has already consumed some active play time. The client reports it; claiming
    // less only lowers the player's own best time bound, claiming more only makes it worse.
    const day = 24 * 3600 * 1000;
    const claimed = Number.isInteger(args.ms) && args.ms >= 0 ? Math.min(args.ms, day) : null;
    const resumed = replay ? 0 : claimed ?? (attempt ? Math.min(attempt.ms, day) : 0);
    progress.started[parsed.key] = ctx.now - resumed;
    const keys = Object.keys(progress.started);
    if (keys.length > 40) for (const old of keys.slice(0, keys.length - 40)) delete progress.started[old];
    ctx.touchProgress();
    return { serverNow: ctx.now, attempt: attempt && !replay ? attemptView(attempt) : null,
      hintsUsed: progress.hintUse[parsed.key] ?? 0 };
  },

  // Debounced snapshot of an unfinished route so another device can resume it.
  'attempt.save': (ctx, args) => {
    const parsed = parseOrFail(args.key);
    assertPlayable(ctx, parsed);
    const board = buildPuzzle(parsed);
    const path = args.path;
    if (!isValidPath(board.puzzle, path) || path.length >= board.puzzle.area) fail(422, 'invalid_route');
    const history = Array.isArray(args.history) ? args.history.slice(-16) : [];
    if (!history.every((step) => isValidPath(board.puzzle, step))) fail(422, 'invalid_route');
    const hintCell = args.hintCell === null || args.hintCell === undefined ? null : integer(args.hintCell, 0, board.puzzle.area - 1);
    const current = ctx.progress.attempts[parsed.key];
    if ((current?.v ?? 0) !== (args.base ?? 0)) throw new HttpError(409, 'stale_attempt', { attempt: current });
    // Firestore cannot store arrays directly inside arrays, so steps are strings.
    ctx.progress.attempts[parsed.key] = {
      v: (current?.v ?? 0) + 1, path, history: history.map((step) => step.join(',')), hintCell, hints: ctx.progress.hintUse[parsed.key] ?? 0,
      ms: integer(args.ms, 0, 24 * 3600 * 1000), started: args.started === true, usedClear: args.usedClear !== false, at: ctx.now,
    };
    const keys = Object.keys(ctx.progress.attempts);
    if (keys.length > ATTEMPT_LIMIT) {
      const oldest = keys.sort((a, b) => ctx.progress.attempts[a].at - ctx.progress.attempts[b].at)[0];
      delete ctx.progress.attempts[oldest];
    }
    ctx.touchProgress();
    return { v: ctx.progress.attempts[parsed.key].v };
  },

  'play.complete': (ctx, args) => {
    const parsed = parseOrFail(args.key);
    assertPlayable(ctx, parsed);
    const { progress, state } = ctx;
    const board = buildPuzzle(parsed);
    if (!validateCompletedRoute(board.puzzle, args.route)) fail(422, 'invalid_route');
    const started = progress.started[parsed.key];
    if (started === undefined) fail(409, 'not_started');
    const claimed = integer(args.ms, 0, 24 * 3600 * 1000);
    if (claimed < board.puzzle.area * MIN_MS_PER_CELL) fail(422, 'implausible_time');
    if (claimed > ctx.now - started + TIME_SLACK_MS) fail(422, 'implausible_time');
    const hints = progress.hintUse[parsed.key] ?? 0;
    delete progress.attempts[parsed.key];
    delete progress.started[parsed.key];
    progress.hintUse[parsed.key] = 0;
    ctx.touchProgress();

    if (parsed.mode === 'daily' && parsed.checkpoint !== null) {
      progress.stages[parsed.key] ??= { ms: claimed, hints };
      return { stage: true };
    }

    const stages = parsed.mode === 'daily'
      ? [1, 2].map((n) => progress.stages[`daily-checkpoint/${parsed.day}/${n}`]).filter(Boolean) : [];
    const totalMs = stages.reduce((sum, s) => sum + s.ms, claimed);
    const totalHints = stages.reduce((sum, s) => sum + s.hints, hints);
    const previous = progress.results[parsed.key];
    const improved = !previous || totalMs < previous.ms;
    progress.results[parsed.key] = {
      ms: improved ? totalMs : previous.ms, hints: improved ? totalHints : previous.hints,
      unassisted: totalHints === 0 || (previous?.unassisted ?? false),
    };
    let reward = 0;
    let earned = [];
    if (!previous) {
      const c = state.counters;
      if (totalHints === 0 && args.usedClear === false && stages.length === 0) c.precision++;
      if (parsed.mode === 'levels') {
        c.levelsSolved++;
        progress.highestUnlocked = Math.max(progress.highestUnlocked, Math.min(parsed.level + 1, levelCountOf()));
      }
      c.solved++;
      if (parsed.mode === 'daily') {
        c.dailySolved++;
        const last = state.dailyEligible;
        if (!last || (parsed.day > last.day && ctx.now - last.at >= 20 * 3600 * 1000)) {
          state.dailyEligible = { day: parsed.day, at: ctx.now };
          c.eligibleDailies = (c.eligibleDailies ?? 0) + 1;
        }
      }
      const base = clearReward[parsed.mode] +
        (parsed.mode === 'levels' ? effect(state, 'magnet') : 0) +
        (parsed.mode === 'daily' ? effect(state, 'fortune') : 0) +
        (totalHints === 0 ? effect(state, 'golden') : 0) +
        (parsed.mode === 'levels' && c.levelsSolved % 5 === 0 ? effect(state, 'momentum') : 0);
      reward = base * coinMultiplier(state, ctx.now);
      credit(state, ctx.now, `clear/${parsed.key}`, `Completed ${parsed.key}`, reward);
      qualifyStreak(state, ctx.now, localDay(ctx.now, state.tz));
    }
    state.counters.unassisted = Object.values(progress.results).filter(isUnassisted).length;
    const before = state.coins;
    earned = awardAchievements(state, ctx.now);
    return { reward, newBest: improved, ms: progress.results[parsed.key].ms, hints: progress.results[parsed.key].hints,
      achievements: earned, achievementCoins: state.coins - before, streak: state.streak.count,
      highestUnlocked: progress.highestUnlocked };
  },

  'attack.start': (ctx, args) => {
    const minutes = args.minutes;
    if (![1, 3, 5].includes(minutes)) fail(422, 'invalid_argument');
    finalizeIfExpired(ctx);
    const { attack } = ctx.progress;
    ctx.touchProgress();
    if (attack.current && !attack.current.finished && args.restart !== true) return { run: runView(attack.current, ctx.now) };
    const previousBest = attack.history.filter((r) => r.minutes === minutes).reduce((best, r) => Math.max(best, r.score), 0);
    attack.current = {
      id: `v2-${randomBytes(9).toString('hex')}`, minutes, startedAt: ctx.now, deadline: ctx.now + minutes * 60000,
      puzzleStartedAt: ctx.now, clears: [], unassisted: true, finished: false, coins: 0, previousBest,
    };
    return { run: runView(attack.current, ctx.now) };
  },

  'attack.clear': (ctx, args) => {
    const run = ctx.progress.attack.current;
    if (!run || run.id !== args.run) fail(409, 'no_such_run');
    if (run.finished) return { over: true, run: runView(run, ctx.now) };
    if (ctx.now > run.deadline + ATTACK_GRACE_MS) {
      const summary = finalize(ctx);
      return { over: true, ...summary, run: runView(ctx.progress.attack.history.at(-1), ctx.now) };
    }
    const parsed = parseOrFail(`attack/${run.id}/${run.clears.length}`);
    const board = buildPuzzle(parsed);
    if (!validateCompletedRoute(board.puzzle, args.route)) fail(422, 'invalid_route');
    const elapsed = ctx.now - run.puzzleStartedAt;
    if (elapsed < board.puzzle.area * MIN_MS_PER_CELL) fail(422, 'implausible_time');
    run.clears.push(elapsed);
    run.puzzleStartedAt = ctx.now;
    ctx.touchProgress();
    return { over: false, run: runView(run, ctx.now) };
  },

  'attack.finish': (ctx, args) => {
    const run = ctx.progress.attack.current;
    if (!run || run.id !== args.run) fail(409, 'no_such_run');
    if (!run.finished && ctx.now < run.deadline - ATTACK_GRACE_MS) fail(409, 'run_active');
    return run.finished ? { run: runView(run, ctx.now) } : { ...finalize(ctx), run: runView(ctx.progress.attack.history.at(-1), ctx.now) };
  },

  'attack.stop': (ctx, args) => {
    const attack = ctx.progress.attack;
    if (attack.current?.id === args.run && !attack.current.finished) { attack.current = null; ctx.touchProgress(); }
    return {};
  },
};

/** Decodes a stored attempt for clients. */
export function attemptView(attempt) {
  return { ...attempt, history: (attempt.history ?? []).map((step) =>
    (typeof step === 'string' && step ? step.split(',').map(Number) : [])) };
}

function runView(run, now) {
  return {
    id: run.id, minutes: run.minutes, deadline: run.deadline, remainingMs: run.finished ? 0 : Math.max(0, run.deadline - now),
    clears: run.clears, score: run.clears.length * 100, finished: run.finished === true, coins: run.coins,
    unassisted: run.unassisted, previousBest: run.previousBest, serverNow: now,
  };
}

function finalizeIfExpired(ctx) {
  const run = ctx.progress.attack.current;
  if (run && !run.finished && ctx.now >= run.deadline) finalize(ctx);
}

function finalize(ctx) {
  const { progress, state } = ctx;
  const run = progress.attack.current;
  run.finished = true;
  const solves = run.clears.length;
  const payout = attackReward(solves);
  if (payout > 0) credit(state, ctx.now, `attack/${run.id}`, 'Time Attack reward', payout);
  run.coins = payout;
  const score = solves * 100;
  state.counters.attackFinished = 1;
  state.counters.attackBest = Math.max(state.counters.attackBest, score);
  state.counters.attackBestClears = Math.max(state.counters.attackBestClears, solves);
  if (solves >= 2) qualifyStreak(state, ctx.now, localDay(ctx.now, state.tz));
  const before = state.coins;
  const earned = awardAchievements(state, ctx.now);
  run.coins += state.coins - before;
  progress.attack.history.push({ ...run, score, record: score > run.previousBest });
  if (progress.attack.history.length > 30) progress.attack.history.shift();
  progress.attack.current = progress.attack.history.at(-1);
  ctx.touchProgress();
  return { reward: payout, achievements: earned };
}
