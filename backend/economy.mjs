// Economy commands. Every handler is a pure function of (ctx, args): it mutates
// the cloned state inside `mutate`'s transaction and returns a small JSON result.
import { randomInt } from 'node:crypto';
import {
  boosts, crateCoins, pickWheelPrize, research, researchPrice, rules, themePrices, wheelPrizeById,
} from './economy-config.mjs';
import { HttpError } from './http.mjs';
import {
  awardAchievements, boostDiscount, boostRemaining, credit, effect, localDay, ownsTheme, rank, reconcileStreak,
  rollDay, spend,
} from './players.mjs';
import { parsePuzzleKey } from './engine/ids.mjs';

const fail = (status, code) => { throw new HttpError(status, code); };
const text = (value, pattern) => (typeof value === 'string' && pattern.test(value) ? value : fail(422, 'invalid_argument'));
const NAME = /^[A-Za-z][A-Za-z0-9]{0,31}$/;

export const roll = { percent: () => randomInt(100) };

export const commands = {
  'hint.buy': (ctx) => {
    spend(ctx.state, ctx.now, `hint/${ctx.state.serial++}`, 'Hint', rules.hintPrice);
    ctx.state.hints++;
    return { hints: ctx.state.hints };
  },

  'hint.use': (ctx, args) => {
    const parsed = parsePuzzleKey(args.attempt) ?? fail(422, 'invalid_argument');
    if (ctx.state.hints < 1) fail(402, 'no_hints');
    ctx.state.hints--;
    ctx.progress.hintUse[parsed.key] = (ctx.progress.hintUse[parsed.key] ?? 0) + 1;
    const run = ctx.progress.attack.current;
    if (parsed.mode === 'attack' && run?.id === parsed.run) run.unassisted = false;
    ctx.touchProgress();
    return { hints: ctx.state.hints, used: ctx.progress.hintUse[parsed.key] };
  },

  'theme.buy': (ctx, args) => {
    const theme = text(args.theme, NAME);
    if (!Object.hasOwn(themePrices, theme)) fail(422, 'invalid_argument');
    if (ownsTheme(ctx.state, theme)) fail(409, 'already_owned');
    spend(ctx.state, ctx.now, `theme/${theme}`, `Unlocked ${theme}`, themePrices[theme]);
    ctx.state.themes.push(theme);
    ctx.state.equipped = theme;
    return { achievements: awardAchievements(ctx.state, ctx.now) };
  },

  'theme.equip': (ctx, args) => {
    const theme = text(args.theme, NAME);
    if (!Object.hasOwn(themePrices, theme) || !ownsTheme(ctx.state, theme)) fail(403, 'not_owned');
    ctx.state.equipped = theme;
    return {};
  },

  'research.buy': (ctx, args) => {
    const name = text(args.item, NAME);
    const item = Object.hasOwn(research, name) ? research[name] : fail(422, 'invalid_argument');
    const current = rank(ctx.state, name);
    if (current >= item.limit) fail(409, 'max_rank');
    if (item.prerequisite && rank(ctx.state, item.prerequisite) < 3) fail(403, 'locked');
    spend(ctx.state, ctx.now, `research/${name}/${current}`, name, researchPrice(item, current));
    ctx.state.research[name] = current + 1;
    return { rank: current + 1, achievements: awardAchievements(ctx.state, ctx.now) };
  },

  'boost.buy': (ctx, args) => {
    const name = text(args.boost, NAME);
    const boost = Object.hasOwn(boosts, name) ? boosts[name] : fail(422, 'invalid_argument');
    if (!boost.buyable) fail(403, 'not_for_sale');
    spend(ctx.state, ctx.now, `boost/${ctx.state.serial++}`, name, boostDiscount(ctx.state, boost.price));
    ctx.state.inventory[name] = (ctx.state.inventory[name] ?? 0) + 1;
    return {};
  },

  'boost.activate': (ctx, args) => {
    const name = text(args.boost, NAME);
    const boost = Object.hasOwn(boosts, name) ? boosts[name] : fail(422, 'invalid_argument');
    if ((ctx.state.inventory[name] ?? 0) < 1) fail(409, 'none_owned');
    const busy = Object.values(boosts).some((other) => other.slot === boost.slot && boostRemaining(ctx.state, other.name, ctx.now) > 0);
    if (busy) fail(409, 'boost_active');
    ctx.state.inventory[name]--;
    const duration = effect(ctx.state, 'efficiency') + effect(ctx.state, 'tuning');
    ctx.state.active[name] = ctx.now + boost.minutes * 600 * (100 + duration);
    return {};
  },

  'freeze.buy': (ctx) => {
    reconcileStreak(ctx.state.streak, localDay(ctx.now, ctx.state.tz));
    if (ctx.state.streak.freezes >= rules.maxFreezes) fail(409, 'max_freezes');
    spend(ctx.state, ctx.now, `freeze/${ctx.state.serial++}`, 'Streak Freeze', rules.freezePrice);
    ctx.state.streak.freezes++;
    return {};
  },

  'wheel.free': (ctx) => {
    const { wheel } = ctx.state;
    if (wheel.pending) fail(409, 'spin_pending');
    if (ctx.now < wheel.lastFree + rules.freeWheelCooldownMs) fail(429, 'wheel_cooldown');
    const prize = pickWheelPrize(roll.percent());
    wheel.lastFree = ctx.now;
    wheel.pending = { id: `wheel/free/${ctx.now}`, prize: prize.id, kind: 'free' };
    return { pending: wheel.pending };
  },

  // Coins become spendable only now, after the client reports the animation settled.
  'wheel.settle': (ctx, args) => {
    const pending = ctx.state.wheel.pending;
    if (!pending || pending.id !== text(args.id, /^wheel\/[A-Za-z0-9/_.-]{1,80}$/)) fail(409, 'nothing_pending');
    const prize = wheelPrizeById(pending.prize) ?? fail(409, 'unknown_prize');
    credit(ctx.state, ctx.now, pending.id, `Fortune Wheel · ${prize.label}`, prize.coins);
    ctx.state.wheel.counts[prize.id] = (ctx.state.wheel.counts[prize.id] ?? 0) + 1;
    ctx.state.wheel.pending = null;
    return { coins: prize.coins, prize: prize.id };
  },

  'crate.poll': (ctx) => {
    const { crates } = ctx.state;
    crates.drops = crates.drops.filter((stamp) => stamp > ctx.now - rules.crateWindowMs);
    const wait = Math.max(0, crates.nextAt - ctx.now);
    if (wait > 0 || crates.drops.length >= rules.cratesPerWindow || Object.keys(crates.pending).length >= 3) {
      return { crate: null, retryInMs: wait > 0 ? wait : 30000 };
    }
    const coins = crateCoins(roll.percent());
    const id = `crate/${ctx.state.serial++}`;
    crates.pending[id] = coins;
    crates.drops.push(ctx.now);
    const interval = rules.crateBaseWaitSeconds - effect(ctx.state, 'hunter') - effect(ctx.state, 'scout');
    const boosted = boostRemaining(ctx.state, 'crateFrequency', ctx.now) > 0;
    crates.nextAt = ctx.now + Math.max(15, interval) * (boosted ? 500 : 1000);
    return { crate: { id, coins }, flightMs: (8 + effect(ctx.state, 'collector')) * 1000 };
  },

  'crate.forfeit': (ctx, args) => {
    delete ctx.state.crates.pending[text(args.id, /^crate\/\d{1,9}$/)];
    return {};
  },

  'tutorial.ack': (ctx, args) => {
    const id = text(args.id, /^[A-Za-z0-9_.-]{1,40}$/);
    ctx.progress.tutorials[id] = args.skipped === true ? 'skipped' : 'completed';
    ctx.touchProgress();
    return {};
  },

  'prefs.set': (ctx, args) => {
    if (typeof args.haptics === 'boolean') ctx.progress.prefs.haptics = args.haptics;
    if (typeof args.suggestSharing === 'boolean') ctx.progress.prefs.suggestSharing = args.suggestSharing;
    ctx.touchProgress();
    return {};
  },

  'timezone.set': (ctx, args) => {
    const tz = args.tz;
    if (!Number.isInteger(tz) || tz < -840 || tz > 840) fail(422, 'invalid_argument');
    // A moving offset would let a player gain extra reward "days"; allow one change per day.
    if (tz !== ctx.state.tz && ctx.now - ctx.state.tzChanged >= 86400000) {
      ctx.state.tz = tz;
      ctx.state.tzChanged = ctx.now;
      rollDay(ctx.state, ctx.now);
    }
    return { tz: ctx.state.tz };
  },
};
