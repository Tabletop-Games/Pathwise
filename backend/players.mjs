// Authoritative player state. All economy mutations go through `mutate`, which
// runs one Firestore transaction: it reads the wallet, progress and an
// idempotency ledger entry, applies a pure state change, and writes everything
// atomically. Retrying the same operation id replays the stored result.
import { createHash } from 'node:crypto';
import {
  achievementRewards, boosts, defaultTheme, milestones as milestoneTable, research, researchEffect, rules,
  themePrices, wheelPrizes,
} from './economy-config.mjs';
import { HttpError } from './http.mjs';
import { sha256 } from './tokens.mjs';

export const collections = Object.freeze({
  players: 'pathwise-players', progress: 'pathwise-progress', ledger: 'pathwise-ledger',
  devices: 'pathwise-devices', games: 'pathwise-games-accounts',
});
export const OP_ID = /^[A-Za-z0-9_.:-]{8,80}$/;
const RECENT_LIMIT = 60;

export const localDay = (now, tz = 0) => new Date(now + tz * 60000).toISOString().slice(0, 10);
const calendar = (day) => new Date(`${day}T00:00:00Z`);
const shiftDay = (day, days) => new Date(calendar(day).getTime() + days * 86400000).toISOString().slice(0, 10);

export function billingAccount(playerId) { return sha256(`pathwise-billing|${playerId}`); }

export function newPlayerState(id, now, tz = 0) {
  return {
    v: 1, id, rev: 0, created: now, epoch: 0, tz, tzChanged: 0,
    coins: 0, earned: 0, spent: 0, hints: 0, serial: 0,
    themes: [], equipped: defaultTheme,
    entitlements: { themePass: false, removeAds: false, premium: false, premiumBonus: false },
    research: {}, inventory: {}, active: {},
    streak: { count: 0, longest: 0, freezes: 0, first: null, lastEarned: null, checkedThrough: null, days: {} },
    crates: { nextAt: now + rules.crateFirstWaitMs, drops: [], pending: {}, legendary: 0 },
    wheel: { lastFree: 0, stamps: [], pending: null, counts: {} },
    ads: { day: localDay(now, tz), coins: 0, hint: 0, boostDouble: 0, triple: 0 },
    achievements: [], counters: { levelsSolved: 0, solved: 0, unassisted: 0, precision: 0,
      dailySolved: 0, eligibleDailies: 0, attackBest: 0, attackBestClears: 0, attackFinished: 0, legendary: 0 },
    recent: [], games: null,
  };
}

export function newProgress() {
  return { v: 1, rev: 0, results: {}, stages: {}, highestUnlocked: 1, tutorials: {}, attempts: {},
    hintUse: {}, started: {}, attack: { current: null, history: [] }, prefs: { haptics: true, suggestSharing: true } };
}

// ---- derived values -------------------------------------------------------

export const rank = (state, name) => Math.min(state.research[name] ?? 0, research[name].limit);
export const effect = (state, name) => researchEffect(research[name], rank(state, name));
export const hasThemePass = (state) => state.entitlements.themePass || state.entitlements.premium;
export const adFree = (state) => state.entitlements.removeAds || state.entitlements.premium;
export const ownsTheme = (state, theme) =>
  themePrices[theme] === 0 || hasThemePass(state) || state.themes.includes(theme);
export const ownedThemeCount = (state) =>
  hasThemePass(state) ? Object.keys(themePrices).length : Object.keys(themePrices).filter((t) => ownsTheme(state, t)).length;
export const paidThemeCount = (state) =>
  hasThemePass(state) ? Object.keys(themePrices).length : state.themes.filter((t) => themePrices[t] > 0).length;
export const researchRanks = (state) => Object.keys(research).reduce((sum, name) => sum + rank(state, name), 0);
export const boostRemaining = (state, name, now) => Math.max(0, (state.active[name] ?? 0) - now);
export const coinMultiplier = (state, now) => Object.values(boosts).reduce(
  (value, boost) => (boostRemaining(state, boost.name, now) > 0 ? Math.max(value, boost.multiplier) : value), 1);
export const boostDiscount = (state, price) =>
  Math.trunc((price * (100 - effect(state, 'savings') - effect(state, 'procurement')) + 99) / 100);

// ---- mutations ------------------------------------------------------------

export function credit(state, now, id, label, amount) {
  if (!Number.isInteger(amount) || amount === 0) return false;
  if (amount < 0 && state.coins + amount < 0) throw new HttpError(402, 'insufficient_coins');
  state.coins += amount;
  if (amount > 0) state.earned += amount; else state.spent -= amount;
  state.recent.push({ id, label, amount, at: now });
  if (state.recent.length > RECENT_LIMIT) state.recent.splice(0, state.recent.length - RECENT_LIMIT);
  return true;
}

export function spend(state, now, id, label, price) {
  if (state.coins < price) throw new HttpError(402, 'insufficient_coins');
  credit(state, now, id, label, -price);
}

/** Resets per-day reward counters when the player's local day changes. */
export function rollDay(state, now) {
  const day = localDay(now, state.tz);
  if (state.ads.day !== day) state.ads = { day, coins: 0, hint: 0, boostDouble: 0, triple: 0 };
  return day;
}

// Streak behaviour mirrors lib/model/play_streak.dart.
export function reconcileStreak(streak, today) {
  const checked = streak.checkedThrough;
  if (!checked || checked >= today) return;
  let cursor = shiftDay(checked, 1);
  while (cursor < today && streak.count > 0) {
    if (streak.freezes === 0) { streak.count = 0; streak.first = null; break; }
    streak.freezes--;
    streak.days[cursor] = 'protected';
    cursor = shiftDay(cursor, 1);
  }
  const yesterday = shiftDay(today, -1);
  if (yesterday > checked) streak.checkedThrough = yesterday;
}

export function qualifyStreak(state, now, today) {
  const streak = state.streak;
  if ((streak.lastEarned && streak.lastEarned >= today) || (streak.checkedThrough && streak.checkedThrough >= today)) return false;
  reconcileStreak(streak, today);
  streak.first ??= today;
  streak.lastEarned = streak.checkedThrough = today;
  streak.days[today] = 'played';
  streak.count++;
  if (streak.count > streak.longest) streak.longest = streak.count;
  const cutoff = shiftDay(today, -14);
  for (const day of Object.keys(streak.days)) if (day < cutoff) delete streak.days[day];
  const reward = Object.hasOwn(milestoneTable, streak.count) ? milestoneTable[streak.count] : null;
  if (reward) {
    if (credit(state, now, `play-streak/${streak.first}/${streak.count}`, `${streak.count}-day streak`, reward.coins)) {
      state.hints += reward.hints;
    }
  }
  if (streak.count % rules.streakInterval === 0) {
    credit(state, now, `play-streak-week/${today}`, `${streak.count}-day streak bonus`,
      rules.streakBonus + effect(state, 'specialist'));
  }
  return true;
}
export function awardAchievements(state, now) {
  const c = {
    ...state.counters, longestStreak: state.streak.longest, themes: paidThemeCount(state),
    researchRanks: researchRanks(state), legendary: state.crates.legendary,
  };
  const earned = [];
  for (const item of achievementRewards) {
    if (item.when(c) && !state.achievements.includes(item.id)) {
      state.achievements.push(item.id);
      credit(state, now, `achievement/${item.id}`, item.id, item.coins + effect(state, 'mastery'));
      earned.push(item.id);
    }
  }
  return earned;
}

// ---- transactional runner ---------------------------------------------------

const stable = (value) => JSON.stringify(value, (_, v) =>
  v && typeof v === 'object' && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => (a < b ? -1 : 1))) : v);
export const argsHash = (args) => createHash('sha256').update(stable(args ?? {})).digest('hex').slice(0, 32);

export async function readPlayer(db, playerId) {
  const [wallet, progress] = await Promise.all([
    db.collection(collections.players).doc(playerId).get(),
    db.collection(collections.progress).doc(playerId).get(),
  ]);
  return { state: wallet.data() ?? null, progress: progress.data() ?? null };
}

/**
 * Applies `fn(ctx)` once per (player, op id). `ctx` exposes mutable `state` and
 * `progress` clones plus `touchProgress()`. `fn` returns the JSON result stored
 * in the ledger. Throwing an HttpError aborts the transaction with no writes.
 */
export async function mutate(db, { playerId, epoch = null, op, kind, args = {}, now = Date.now }, fn) {
  if (!OP_ID.test(op ?? '')) throw new HttpError(422, 'invalid_operation');
  const hash = argsHash(args);
  const players = db.collection(collections.players).doc(playerId);
  const progressRef = db.collection(collections.progress).doc(playerId);
  const ledgerRef = db.collection(collections.ledger).doc(`${playerId}.${op}`);
  return db.runTransaction(async (tx) => {
    const [walletSnap, progressSnap, ledgerSnap] = await tx.getAll(players, progressRef, ledgerRef);
    if (!walletSnap.exists) throw new HttpError(404, 'player_not_found');
    const state = walletSnap.data();
    if (epoch !== null && epoch !== state.epoch) throw new HttpError(401, 'session_expired');
    if (ledgerSnap.exists) {
      if (ledgerSnap.get('kind') !== kind || ledgerSnap.get('args') !== hash) throw new HttpError(409, 'operation_conflict');
      return { ...JSON.parse(ledgerSnap.get('result')), replayed: true, wallet: publicWallet(state, now()) };
    }
    const progress = progressSnap.data() ?? newProgress();
    const time = now();
    const ctx = { state, progress, now: time, tx, progressTouched: false, touchProgress() { this.progressTouched = true; } };
    const result = await fn(ctx);
    state.rev += 1;
    tx.set(players, state);
    if (ctx.progressTouched) { progress.rev += 1; tx.set(progressRef, progress); }
    // Results are stored as text: Firestore cannot hold arrays nested in arrays.
    tx.set(ledgerRef, { player: playerId, kind, args: hash, result: JSON.stringify(result), at: time, rev: state.rev,
      entries: state.recent.filter((entry) => entry.at === time).slice(-12) });
    return { ...result, wallet: publicWallet(state, time) };
  });
}

/** Client-facing wallet view. Contains no secrets and only the caller's own data. */
export function publicWallet(state, now) {
  const day = localDay(now, state.tz);
  const ads = state.ads.day === day ? state.ads : { coins: 0, hint: 0, boostDouble: 0, triple: 0 };
  const stamps = state.wheel.stamps.filter((stamp) => stamp > now - rules.wheelWindowMs);
  const drops = state.crates.drops.filter((stamp) => stamp > now - rules.crateWindowMs);
  const streak = structuredClone(state.streak);
  reconcileStreak(streak, day);
  return {
    rev: state.rev, serverNow: now, day, coins: state.coins, earned: state.earned, spent: state.spent,
    hints: state.hints, equipped: state.equipped,
    themes: Object.keys(themePrices).filter((theme) => ownsTheme(state, theme)),
    entitlements: { ...state.entitlements, themePass: hasThemePass(state), adFree: adFree(state) },
    research: Object.fromEntries(Object.keys(research).map((name) => [name, rank(state, name)])),
    inventory: state.inventory,
    active: Object.fromEntries(Object.keys(boosts).filter((n) => boostRemaining(state, n, now) > 0)
      .map((n) => [n, boostRemaining(state, n, now)])),
    streak, achievements: state.achievements, counters: state.counters,
    wheel: {
      freeInMs: Math.max(0, state.wheel.lastFree + rules.freeWheelCooldownMs - now),
      videosRemaining: Math.max(0, rules.wheelAdsPerDay - stamps.length),
      pending: state.wheel.pending, counts: state.wheel.counts,
      prizes: wheelPrizes.map(({ id, label, coins }) => ({ id, label, coins })),
    },
    crates: { nextInMs: Math.max(0, state.crates.nextAt - now), offersRemaining: Math.max(0, rules.cratesPerWindow - drops.length),
      pending: state.crates.pending, legendary: state.crates.legendary },
    limits: {
      coinAds: Math.max(0, rules.rewardedAdsPerDay - ads.coins), hintAds: Math.max(0, rules.hintAdsPerDay - ads.hint),
      boostAds: Math.max(0, rules.doubleBoostAdsPerDay - ads.boostDouble), tripleAvailable: ads.coins >= rules.coinAdMilestone && ads.triple === 0,
    },
    recent: state.recent.slice(-RECENT_LIMIT), billingAccount: billingAccount(state.id),
  };
}
