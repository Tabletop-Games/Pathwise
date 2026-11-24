// Single authoritative source for prices, rewards and limits. Values mirror
// lib/model/economy.dart and lib/model/progression.dart. A test compares the
// two so a rate change cannot silently diverge. Final economy rates are still
// under review: change them here (and in the Dart display constants) only.
import { readFileSync } from 'node:fs';

export const configVersion = 1;
export const appPackages = Object.freeze({
  production: 'com.shenmareparas.pathwise',
  development: 'com.shenmareparas.pathwise.debug',
});

export const rules = Object.freeze({
  starterCoins: 50, starterHints: 3, hintPrice: 60, freezePrice: 250, maxFreezes: 2,
  streakBonus: 25, streakInterval: 7, premiumBonus: 1000,
  rewardedAdCoins: 20, rewardedAdsPerDay: 6, hintAdsPerDay: 5, coinAdMilestone: 4,
  coinAdMilestoneBonus: 40, doubleBoostAdsPerDay: 3, wheelAdsPerDay: 6, cratesPerWindow: 8,
  freeWheelCooldownMs: 24 * 3600 * 1000, wheelWindowMs: 24 * 3600 * 1000,
  crateWindowMs: 24 * 3600 * 1000, crateBaseWaitSeconds: 150, crateFirstWaitMs: 45000,
  automaticAdGapMs: 3 * 60 * 1000, afterRewardedGapMs: 60 * 1000, exitsPerInterstitial: 5,
  crateTopPrize: 90, adSessionTtlMs: 15 * 60 * 1000,
});

export const levelCountOf = () => 1000;
export const clearReward = Object.freeze({ levels: 5, daily: 10 });
export const attackReward = (solves) => (solves < 2 ? 0 : Math.min(solves, 8) * 3);
export const milestones = Object.freeze({
  1: { coins: 20, hints: 0 }, 3: { coins: 50, hints: 0 }, 7: { coins: 100, hints: 1 },
  14: { coins: 200, hints: 1 }, 30: { coins: 400, hints: 2 }, 60: { coins: 600, hints: 2 },
  100: { coins: 1000, hints: 3 }, 150: { coins: 1200, hints: 3 }, 200: { coins: 1500, hints: 3 },
});

export const themePrices = Object.freeze({
  field: 0, blackwater: 0, terracotta: 0, signal: 0, forestMint: 90, warmWalnut: 90,
  glacier: 140, midnightSlate: 140, oceanicBreeze: 220, royalVelvet: 220, chalk: 500,
  amoledCarbon: 500, canyon: 4500, tidal: 12000, parchment: 500, violet: 500, koi: 1000,
  crt: 1000, neon: 30000, gilded: 60000, basinGold: 1000, copperSky: 4500, highPass: 12000,
});
export const defaultTheme = 'field';

// [name, base, limit, increment, advanced, prerequisite]
const researchRows = [
  ['magnet', 55, 10, 2, false], ['golden', 100, 8, 2, false], ['fortune', 100, 8, 4, false],
  ['mastery', 180, 6, 5, false], ['hunter', 120, 8, 4, false], ['collector', 90, 9, 1, false],
  ['efficiency', 160, 8, 5, false], ['savings', 140, 6, 3, false], ['momentum', 150, 8, 4, false],
  ['specialist', 210, 6, 8, false], ['tuning', 190, 8, 4, true, 'efficiency'],
  ['procurement', 160, 8, 2, true, 'savings'], ['scout', 200, 8, 3, true, 'hunter'],
];
const advancedPrices = [1, 3, 7, 16, 38, 80, 150, 260, 420, 600];
export const research = Object.freeze(Object.fromEntries(researchRows.map(
  ([name, base, limit, increment, advanced, prerequisite = null]) => [name, Object.freeze({
    name, base, limit, increment, advanced, prerequisite,
  })])));
export const researchEffect = (item, rank) => {
  const owned = Math.min(Math.max(rank, 0), item.limit);
  const extra = owned > 8 ? 2 * (owned - 8) : 0;
  return (owned + extra) * item.increment;
};
export const researchPrice = (item, rank) => {
  if (!Number.isInteger(rank) || rank < 0 || rank >= item.limit) throw new RangeError('rank');
  return item.advanced ? item.base * advancedPrices[rank] : Math.trunc((item.base * (rank + 2) * (rank + 3)) / 6);
};

// [name, minutes, price, multiplier, buyable]
const boostRows = [
  ['doubleTen', 10, 20, 2, true], ['doubleFifteen', 15, 36, 2, false], ['doubleThirty', 30, 72, 2, false],
  ['doubleSixty', 60, 100, 2, true], ['tripleFifteen', 15, 60, 3, true], ['quadrupleTen', 10, 70, 4, true],
  ['crateFrequency', 15, 28, 1, false],
];
export const boosts = Object.freeze(Object.fromEntries(boostRows.map(
  ([name, minutes, price, multiplier, buyable]) => [name, Object.freeze({
    name, minutes, price, multiplier, buyable, slot: multiplier > 1 ? 'coins' : name,
  })])));

export const crateCoins = (roll) => {
  if (!Number.isInteger(roll) || roll < 0 || roll > 99) throw new RangeError('roll');
  return roll < 35 ? 20 : roll < 65 ? 35 : roll < 85 ? 55 : roll < 95 ? 75 : rules.crateTopPrize;
};

export const wheelPrizes = JSON.parse(readFileSync(new URL('./fortune-prizes.json', import.meta.url)));
export const pickWheelPrize = (roll) => {
  if (!Number.isInteger(roll) || roll < 0 || roll > 99) throw new RangeError('roll');
  let end = 0;
  for (const prize of wheelPrizes) { end += prize.weight; if (roll < end) return prize; }
  throw new Error('Invalid wheel catalogue');
};

export const wheelPrizeById = (id) => wheelPrizes.find((prize) => prize.id === id) ?? null;

// Coin achievements (Dart: enum Achievement). `when` receives server counters.
export const achievementRewards = Object.freeze([
  { id: 'trailhead', coins: 20, when: (c) => c.levelsSolved >= 1 },
  { id: 'trailblazer', coins: 40, when: (c) => c.levelsSolved >= 12 },
  { id: 'pathfinder', coins: 80, when: (c) => c.levelsSolved >= 50 },
  { id: 'dailyHabit', coins: 25, when: (c) => c.longestStreak >= 3 },
  { id: 'weeklyRitual', coins: 45, when: (c) => c.longestStreak >= 7 },
  { id: 'unaided', coins: 35, when: (c) => c.unassisted >= 10 },
  { id: 'collector', coins: 30, when: (c) => c.themes >= 6 },
  { id: 'timeTrial', coins: 25, when: (c) => c.attackBestClears >= 3 },
  { id: 'twentyFive', coins: 50, when: (c) => c.levelsSolved >= 25 },
  { id: 'hundred', coins: 100, when: (c) => c.levelsSolved >= 100 },
  { id: 'fiveHundred', coins: 250, when: (c) => c.levelsSolved >= 500 },
  { id: 'thousand', coins: 500, when: (c) => c.levelsSolved >= 1000 },
  { id: 'researcher', coins: 50, when: (c) => c.researchRanks >= 10 },
  { id: 'legendaryCrate', coins: 60, when: (c) => c.legendary >= 1 },
]);

export const products = Object.freeze({
  pathwise_coins_500: { coins: 500 }, pathwise_coins_1250: { coins: 1250 },
  pathwise_coins_3000: { coins: 3000 }, pathwise_coins_7500: { coins: 7500 },
  pathwise_coins_18000: { coins: 18000 },
  pathwise_themes_forever: { entitlement: 'themePass' },
  pathwise_remove_ads: { entitlement: 'removeAds' },
  pathwise_premium: { entitlement: 'premium' },
});

/** Ad placements: server issues sessions only for these. */
export const placements = Object.freeze({
  coins: 'PATHWISE_ADMOB_REWARDED', crate: 'PATHWISE_ADMOB_REWARDED',
  hint: 'PATHWISE_ADMOB_EXTRA_HINT', refill: 'PATHWISE_ADMOB_EXTRA_HINT',
  wheel: 'PATHWISE_ADMOB_WHEEL', boost: 'PATHWISE_ADMOB_REWARDED',
});

export function publicConfig() {
  return {
    version: configVersion, rules, themePrices, products: Object.keys(products),
    boosts, research: Object.fromEntries(Object.values(research).map((r) => [r.name, {
      limit: r.limit, base: r.base, increment: r.increment, advanced: r.advanced, prerequisite: r.prerequisite,
    }])),
    wheel: wheelPrizes.map(({ id, label, weight, coins }) => ({ id, label, weight, coins })),
  };
}
