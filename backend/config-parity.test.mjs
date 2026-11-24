// The Flutter app still shows prices and rewards from lib/model. The server is the
// authority, so these tests fail whenever the two drift apart.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  achievementRewards, attackReward, boosts, clearReward, crateCoins, milestones, products, research, researchPrice, rules,
  themePrices,
} from './economy-config.mjs';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const economy = read('lib/model/economy.dart');
const progression = read('lib/model/progression.dart');

test('rules mirror EconomyRules getters', () => {
  const getters = Object.fromEntries([...economy.matchAll(/int get (\w+) => (\d+);/g)].map((m) => [m[1], Number(m[2])]));
  for (const name of ['starterCoins', 'streakBonus', 'streakInterval', 'premiumBonus', 'rewardedAdCoins', 'rewardedAdsPerDay',
    'starterHints', 'hintPrice', 'hintAdsPerDay', 'coinAdMilestone', 'coinAdMilestoneBonus', 'doubleBoostAdsPerDay',
    'wheelAdsPerDay', 'cratesPerWindow', 'freezePrice', 'maxFreezes', 'exitsPerInterstitial']) {
    assert.equal(rules[name], getters[name], name);
  }
  assert.equal(rules.automaticAdGapMs, Number(/automaticAdGap = Duration\(minutes: (\d+)\)/.exec(economy)[1]) * 60000);
  assert.equal(clearReward.levels, 5);
  assert.equal(clearReward.daily, 10);
  assert.equal(attackReward(1), 0);
  assert.equal(attackReward(2), 6);
  assert.equal(attackReward(20), 24);
});

test('theme prices match', () => {
  const body = economy.slice(economy.indexOf('int themePrice'), economy.indexOf('enum Achievement'));
  const parsed = {};
  for (const m of body.matchAll(/((?:PathwiseTheme\.\w+\s*\|\|\s*)*PathwiseTheme\.\w+)\s*=>\s*(\d+)/g)) {
    for (const theme of m[1].match(/PathwiseTheme\.(\w+)/g)) parsed[theme.split('.')[1]] = Number(m[2]);
  }
  assert.deepEqual(parsed, themePrices);
});

test('daily milestones and achievements match', () => {
  const rows = [...economy.matchAll(/(\d+): \(coins: (\d+), hints: (\d+)\)/g)];
  assert.equal(rows.length, Object.keys(milestones).length);
  for (const [, days, coins, hints] of rows) assert.deepEqual(milestones[days], { coins: Number(coins), hints: Number(hints) });
  const dart = [...economy.matchAll(/(\w+)\('[^']+', '[^']+', (\d+)\)/g)].map((m) => [m[1], Number(m[2])]);
  assert.deepEqual(achievementRewards.map((a) => [a.id, a.coins]), dart);
});

test('research and boosts match', () => {
  const body = progression.slice(progression.indexOf('enum Research'), progression.indexOf('enum Boost'));
  const rows = [...body.matchAll(/^\s{2}(\w+)\(\s*'[^']*',\s*'[^']*',\s*(\d+),\s*(\d+),\s*(\d+)(,\s*true)?,?\s*\)[,;]/gms)];
  assert.equal(rows.length, Object.keys(research).length);
  for (const [, name, base, limit, increment, advanced] of rows) {
    assert.deepEqual([research[name].base, research[name].limit, research[name].increment, research[name].advanced],
      [Number(base), Number(limit), Number(increment), Boolean(advanced)], name);
  }
  assert.deepEqual(['tuning', 'procurement', 'scout'].map((n) => research[n].prerequisite), ['efficiency', 'savings', 'hunter']);
  assert.equal(researchPrice(research.magnet, 0), Math.trunc(55 * 2 * 3 / 6));
  assert.equal(researchPrice(research.tuning, 7), 190 * 260);
  const boostBody = progression.slice(progression.indexOf('enum Boost'), progression.indexOf('typedef Crate'));
  const boostRows = [...boostBody.matchAll(/^\s{2}(\w+)\('[^']*', (\d+), (\d+), (\d+)\)[,;]/gm)];
  assert.equal(boostRows.length, Object.keys(boosts).length);
  for (const [, name, minutes, price, multiplier] of boostRows) {
    assert.deepEqual([boosts[name].minutes, boosts[name].price, boosts[name].multiplier], [Number(minutes), Number(price), Number(multiplier)], name);
  }
  assert.deepEqual(Object.values(boosts).filter((b) => b.buyable).map((b) => b.name), ['doubleTen', 'doubleSixty', 'tripleFifteen', 'quadrupleTen']);
});

test('crate prizes and products match', () => {
  const body = progression.slice(progression.indexOf('int crateCoins'), progression.indexOf('final class Progression'));
  const bands = [...body.matchAll(/< (\d+) => (\d+)/g)].map((m) => [Number(m[1]), Number(m[2])]);
  for (const [limit, coins] of bands) assert.equal(crateCoins(limit - 1), coins);
  assert.equal(crateCoins(99), rules.crateTopPrize);
  assert.equal(rules.crateTopPrize, Number(/crateTopPrize = (\d+)/.exec(progression)[1]));
  const catalogue = read('lib/model/product_catalog.dart');
  for (const [id, spec] of Object.entries(products)) {
    assert.ok(catalogue.includes(`'${id}'`) || catalogue.includes(id === 'pathwise_themes_forever' ? 'themePassProduct' : id === 'pathwise_remove_ads' ? 'removeAdsProduct' : 'premiumProduct'), id);
    if (spec.coins) assert.ok(new RegExp(`'${id}': \\([^)]*coins: ${spec.coins}`, 's').test(catalogue), id);
  }
  assert.equal(Object.keys(products).length, 8);
});
