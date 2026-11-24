// AdMob server-side verification (SSV) and server-granted ad rewards.
//
// Flow: the signed-in client asks `start` for a short-lived session whose id is
// sent to AdMob as custom data. Google calls `callback` with a signed message;
// only a valid signature marks the session "receipted". `claim` then grants the
// reward inside the player's transaction, enforcing limits with the server clock.
import { createHash, randomBytes, verify } from 'node:crypto';
import { pickWheelPrize, placements, rules } from './economy-config.mjs';
import { HttpError } from './http.mjs';
import { credit, localDay, rollDay, awardAchievements } from './players.mjs';
import { roll } from './economy.mjs';

export const consoleProbe = 'pathwise-console-check';
const unitId = (value) => /^(?:ca-app-pub-\d{16}\/)?(\d{10})$/.exec(value ?? '')?.[1];
const digest = (value) => createHash('sha256').update(value).digest('hex');
export const sessionsCollection = 'pathwise-ad-sessions';
export const receiptsCollection = 'pathwise-ad-receipts';
const fail = (status, code) => { throw new HttpError(status, code); };

export function decodeReward(query, keyFor, now = Date.now(), allowProbe = false) {
  const match = /^(.*)&signature=([A-Za-z0-9_%=-]+)&key_id=(\d+)$/.exec(query);
  if (!match) return null;
  const [, message, encoded, keyId] = match;
  const data = new URLSearchParams(message);
  const fields = ['transaction_id', 'custom_data', 'ad_unit', 'timestamp'];
  if (fields.some((field) => data.getAll(field).length !== 1)) return null;
  const token = data.get('custom_data');
  const transaction = data.get('transaction_id');
  const time = Number(data.get('timestamp'));
  const unit = unitId(data.get('ad_unit'));
  const isProbe = allowProbe && token === consoleProbe;
  if ((!isProbe && !/^[a-f0-9]{64}$/.test(token)) || !transaction || transaction.length > 256 ||
      !unit || !Number.isSafeInteger(time) || Math.abs(now - time) > 3600000) return null;
  const key = keyFor(keyId);
  if (!key || !verify('sha256', Buffer.from(message), key, Buffer.from(decodeURIComponent(encoded), 'base64url'))) return null;
  return { token, id: digest(transaction), unit, time };
}

let cached;
let loadedAt = 0;
export async function googleKeys(force = false, fetcher = fetch) {
  if (!force && cached && Date.now() - loadedAt < 3600000) return cached;
  const response = await fetcher('https://www.gstatic.com/admob/reward/verifier-keys.json', { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error('Verifier keys unavailable');
  const { keys } = await response.json();
  cached = new Map(keys.map((key) => [String(key.keyId), key.pem]));
  loadedAt = Date.now();
  return cached;
}

export const rewardKinds = Object.freeze(['coins', 'hint', 'refill', 'wheel', 'crate', 'boost']);

export function createRewards({ db, env = process.env, now = Date.now, keySet = googleKeys }) {
  const sessions = db.collection(sessionsCollection);
  const receipts = db.collection(receiptsCollection);
  const enabled = () => env.PATHWISE_REWARDS_ENABLED === 'true';
  const unitFor = (issue) => unitId(env[placements[issue]]);
  const configuredUnits = () => new Set(['coins', 'hint', 'wheel'].map(unitFor).filter(Boolean));

  /** Throws unless the player may still earn this reward today. Used at start and again at claim. */
  function assertEligible(state, issue, kind, time) {
    rollDay(state, time);
    const ads = state.ads;
    if (issue === 'coins' && ads.coins >= rules.rewardedAdsPerDay) fail(429, 'daily_limit');
    if ((issue === 'hint' || issue === 'refill') && ads.hint >= rules.hintAdsPerDay) fail(429, 'daily_limit');
    if (issue === 'boost') {
      if (kind === 'doubleTen') { if (ads.boostDouble >= rules.doubleBoostAdsPerDay) fail(429, 'daily_limit'); }
      else if (kind === 'tripleFifteen') { if (ads.coins < rules.coinAdMilestone || ads.triple > 0) fail(429, 'daily_limit'); }
      else fail(422, 'invalid_argument');
    }
    if (issue === 'wheel') {
      if (state.wheel.pending) fail(409, 'spin_pending');
      if (state.wheel.stamps.filter((stamp) => stamp > time - rules.wheelWindowMs).length >= rules.wheelAdsPerDay) fail(429, 'daily_limit');
    }
    if (issue === 'crate' && !Object.hasOwn(state.crates.pending, kind ?? '')) fail(409, 'crate_unavailable');
  }

  async function callback(request, queryText) {
    if (!enabled()) return [503, { error: 'disabled' }];
    if (queryText.length > 4800) return [422, { error: 'invalid_callback' }];
    const time = now();
    let keys = await keySet();
    const keyId = /&key_id=(\d+)$/.exec(queryText)?.[1];
    if (keyId && !keys.has(keyId)) keys = await keySet(true);
    const reward = decodeReward(queryText, (id) => keys.get(id), time, true);
    if (!reward || !configuredUnits().has(reward.unit)) return [403, { error: 'invalid_signature' }];
    if (reward.token === consoleProbe) return [200, { verified: true, probe: true }];
    const session = sessions.doc(reward.token);
    const receipt = receipts.doc(reward.id);
    const applied = await db.runTransaction(async (tx) => {
      const [saved, existing] = await tx.getAll(session, receipt);
      if (existing.exists) return existing.get('session') === reward.token;
      if (!saved.exists || saved.get('unit') !== reward.unit || saved.get('receipt') ||
          reward.time < saved.get('created') - 10000 || reward.time > saved.get('created') + 900000) return false;
      tx.create(receipt, { session: reward.token, expiresAt: new Date(time + 7 * 86400000) });
      tx.set(session, { ...saved.data(), receipt: reward.id });
      return true;
    });
    return applied ? [200, { verified: true }] : [403, { error: 'invalid_session' }];
  }

  async function start(playerId, issue, body) {
    if (!enabled()) throw new HttpError(503, 'disabled');
    if (!rewardKinds.includes(issue)) throw new HttpError(404, 'not_found');
    const unit = unitFor(issue);
    const base = ['coins', 'hint', 'wheel'].map(unitFor);
    if (!unit || base.some((value) => !value) || new Set(base).size !== base.length) throw new HttpError(503, 'placement_unavailable');
    const kind = typeof body?.kind === 'string' ? body.kind.slice(0, 40) : null;
    const time = now();
    const token = randomBytes(32).toString('hex');
    await db.runTransaction(async (tx) => {
      const player = await tx.get(db.collection('pathwise-players').doc(playerId));
      if (!player.exists) throw new HttpError(404, 'player_not_found');
      assertEligible(player.data(), issue, kind, time);
      tx.create(sessions.doc(token), { player: playerId, unit, issue, kind, created: time, receipt: null, claimed: false,
        expiresAt: new Date(time + 86400000) });
    });
    return { token };
  }

  async function status(playerId, token) {
    const saved = await sessions.doc(token).get();
    if (!saved.exists || saved.get('player') !== playerId) throw new HttpError(404, 'not_found');
    if (saved.get('claimed')) return [200, { claimed: true }];
    return saved.get('receipt') ? [200, { verified: true }] : [202, { pending: true }];
  }

  /** Command handler: `reward.claim` runs inside `mutate`. */
  async function claim(ctx, args) {
    const token = typeof args.token === 'string' && /^[a-f0-9]{64}$/.test(args.token) ? args.token : fail(422, 'invalid_argument');
    const ref = sessions.doc(token);
    const session = await ctx.tx.get(ref);
    if (!session.exists || session.get('player') !== ctx.state.id) fail(404, 'not_found');
    if (session.get('claimed')) fail(409, 'already_claimed');
    if (!session.get('receipt')) fail(409, 'not_verified');
    if (ctx.now - session.get('created') > rules.adSessionTtlMs * 4) fail(410, 'session_expired');
    const issue = session.get('issue');
    const kind = session.get('kind');
    const { state } = ctx;
    assertEligible(state, issue, kind, ctx.now);
    const result = grant(state, issue, kind, ctx.now, token);
    ctx.tx.set(ref, { ...session.data(), claimed: true });
    return result;
  }

  function grant(state, issue, kind, time, token) {
    const ads = state.ads;
    const tag = token.slice(0, 16);
    if (issue === 'coins') {
      credit(state, time, `ad/${tag}`, 'Optional video bonus', rules.rewardedAdCoins);
      ads.coins++;
      if (ads.coins === rules.coinAdMilestone) credit(state, time, `ad-milestone/${localDay(time, state.tz)}`, 'Fourth video bonus', rules.coinAdMilestoneBonus);
      return { coins: rules.rewardedAdCoins };
    }
    if (issue === 'hint' || issue === 'refill') { state.hints++; ads.hint++; return { hints: 1 }; }
    if (issue === 'boost') {
      state.inventory[kind] = (state.inventory[kind] ?? 0) + 1;
      if (kind === 'doubleTen') ads.boostDouble++; else ads.triple++;
      return { boost: kind };
    }
    if (issue === 'wheel') {
      const prize = pickWheelPrize(roll.percent());
      state.wheel.stamps = state.wheel.stamps.filter((stamp) => stamp > time - rules.wheelWindowMs);
      state.wheel.stamps.push(time);
      state.wheel.pending = { id: `wheel/video/${tag}`, prize: prize.id, kind: 'video' };
      return { pending: state.wheel.pending };
    }
    // Supply crate: the prize was fixed by the server when the crate dropped.
    const coins = state.crates.pending[kind];
    delete state.crates.pending[kind];
    credit(state, time, `crate-ad/${tag}`, 'Supply crate', coins);
    if (coins === rules.crateTopPrize) { state.crates.legendary++; state.counters.legendary = state.crates.legendary; }
    return { coins, achievements: awardAchievements(state, time) };
  }

  return { callback, start, status, claim, assertEligible };
}
