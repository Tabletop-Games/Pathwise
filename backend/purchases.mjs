// Google Play purchase verification, atomic grants, refund reversal and
// reconciliation. Grants are keyed by the hashed purchase token, so a token can
// never credit twice, and every grant records the player that owns it.
import { createHash, timingSafeEqual } from 'node:crypto';
import { appPackages, products, rules } from './economy-config.mjs';
import { HttpError } from './http.mjs';
import { billingAccount, collections, credit, publicWallet } from './players.mjs';

const digest = (text) => createHash('sha256').update(text).digest('hex');
export const grantsCollection = 'pathwise-play-purchase-grants';
const DENIED = () => new HttpError(403, 'purchase_not_verifiable');

const equalText = (a, b) => typeof a === 'string' && typeof b === 'string' &&
  a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));

export function createPurchases({ db, play, env, now = Date.now }) {
  const packageName = appPackages[env];
  const grants = db.collection(grantsCollection);
  const players = db.collection(collections.players);

  async function verify(playerId, body) {
    const { product, token } = body ?? {};
    if (!Object.hasOwn(products, product) || typeof token !== 'string' || token.length > 2048 || !/^[\w.~-]{12,}$/.test(token)) {
      throw new HttpError(422, 'invalid_purchase');
    }
    const purchase = await play.getPurchase(token);
    if (!purchase) throw DENIED();
    if (purchase.purchaseStateContext?.purchaseState === 'PENDING') throw new HttpError(409, 'payment_pending');
    const lines = purchase.productLineItem;
    const line = lines?.[0];
    if (purchase.purchaseStateContext?.purchaseState !== 'PURCHASED' ||
        !equalText(purchase.obfuscatedExternalAccountId, billingAccount(playerId)) ||
        !Array.isArray(lines) || lines.length !== 1 || line.productId !== product ||
        line.productOfferDetails?.quantity !== 1 || (line.productOfferDetails?.refundableQuantity ?? 0) !== 1) {
      throw DENIED();
    }
    const consumed = line.productOfferDetails?.consumptionState === 'CONSUMED';
    const spec = products[product];
    const id = digest(`${packageName}\0${token}`);
    const grantRef = grants.doc(id);
    const playerRef = players.doc(playerId);
    const outcome = await db.runTransaction(async (tx) => {
      const [grant, player] = await tx.getAll(grantRef, playerRef);
      if (!player.exists) throw new HttpError(404, 'player_not_found');
      const state = player.data();
      if (grant.exists) {
        if (grant.get('player') !== playerId || grant.get('product') !== product) throw DENIED();
        if (grant.get('voided')) throw new HttpError(403, 'purchase_refunded');
        return { state, replay: true, finalized: grant.get('finalized') === true };
      }
      if (consumed) throw DENIED();
      const time = now();
      if (spec.coins) credit(state, time, `purchase/${id}`, 'Google Play coin pack', spec.coins);
      if (spec.entitlement) {
        state.entitlements[spec.entitlement] = true;
        if (spec.entitlement === 'premium' && !state.entitlements.premiumBonus) {
          state.entitlements.premiumBonus = true;
          credit(state, time, 'premium/bonus', 'Premium bonus', rules.premiumBonus);
        }
      }
      state.rev++;
      tx.set(playerRef, state);
      tx.create(grantRef, { player: playerId, product, coins: spec.coins ?? 0, at: time, finalized: false, voided: false });
      return { state, replay: false, finalized: false };
    });
    // Consume or acknowledge only after the grant is durable. Safe to repeat.
    if (!outcome.finalized) {
      try {
        if (spec.coins) await play.consume(product, token); else await play.acknowledge(product, token);
        await grantRef.update({ finalized: true });
      } catch { /* The client retry or the reconcile job repeats this step. */ }
    }
    return { id, product, coins: spec.coins ?? 0, replay: outcome.replay, wallet: publicWallet(outcome.state, now()) };
  }

  /** Reverses a refunded or revoked purchase exactly once. Coin balance may go negative. */
  async function reverse(token) {
    const id = digest(`${packageName}\0${token}`);
    const grantRef = grants.doc(id);
    return db.runTransaction(async (tx) => {
      const grant = await tx.get(grantRef);
      if (!grant.exists) return 'unknown';
      if (grant.get('voided')) return 'already_reversed';
      const playerRef = players.doc(grant.get('player'));
      const player = await tx.get(playerRef);
      const state = player.data();
      const time = now();
      const spec = products[grant.get('product')];
      if (spec?.coins) clawBack(state, time, `refund/${id}`, 'Refunded purchase', spec.coins);
      if (spec?.entitlement) {
        state.entitlements[spec.entitlement] = false;
        if (spec.entitlement === 'premium') clawBack(state, time, `refund/${id}/bonus`, 'Refunded Premium bonus', rules.premiumBonus);
      }
      state.rev++;
      tx.set(playerRef, state);
      tx.set(grantRef, { ...grant.data(), voided: true, voidedAt: time });
      return 'reversed';
    });
  }

  function clawBack(state, time, id, label, amount) {
    state.coins -= amount;
    state.spent += amount;
    state.recent.push({ id, label, amount: -amount, at: time });
    if (state.recent.length > 60) state.recent.shift();
  }

  /** Handles a decoded Real-time Developer Notification. */
  async function notification(message) {
    if (message?.packageName !== packageName) return 'ignored';
    const voided = message.voidedPurchaseNotification;
    if (voided?.purchaseToken && voided.productType === 2) return reverse(voided.purchaseToken);
    return 'ignored';
  }

  /** Polls the Voided Purchases API as a backstop for missed notifications. */
  async function reconcile() {
    const cursorRef = db.collection('pathwise-system').doc('voided-cursor');
    // The API rejects a start time older than 30 days.
    const cursor = Math.max((await cursorRef.get()).get('since') ?? now() - 3 * 86400000, now() - 29 * 86400000);
    let latest = cursor;
    let reversed = 0;
    let pageToken;
    do {
      const page = await play.listVoided(cursor, pageToken);
      for (const entry of page.voidedPurchases ?? []) {
        if (await reverse(entry.purchaseToken) === 'reversed') reversed++;
        latest = Math.max(latest, Number(entry.voidedTimeMillis) || 0);
      }
      pageToken = page.tokenPagination?.nextPageToken;
    } while (pageToken);
    // Overlap one minute so a late entry cannot slip between polls; reversal is idempotent.
    await cursorRef.set({ since: Math.max(cursor, latest - 60000), at: now() });
    return { reversed };
  }

  return { verify, reverse, notification, reconcile, packageName };
}

/** Google Play Developer API client using the Cloud Run service identity. */
export function createPlayApi(google, packageName) {
  const base = 'https://androidpublisher.googleapis.com/androidpublisher/v3';
  const app = encodeURIComponent(packageName);
  const request = async (options) => (await (await google.getClient()).request({ timeout: 8000, retry: false, ...options })).data;
  return {
    async getPurchase(token) {
      try { return await request({ url: `${base}/applications/${app}/purchases/productsv2/tokens/${encodeURIComponent(token)}` }); }
      catch (error) {
        if ([400, 404, 410].includes(error.response?.status)) return null;
        throw error;
      }
    },
    consume: (product, token) => request({ method: 'POST',
      url: `${base}/applications/${app}/purchases/products/${encodeURIComponent(product)}/tokens/${encodeURIComponent(token)}:consume` }),
    acknowledge: (product, token) => request({ method: 'POST', data: {},
      url: `${base}/applications/${app}/purchases/products/${encodeURIComponent(product)}/tokens/${encodeURIComponent(token)}:acknowledge` }),
    listVoided: (sinceMs, pageToken) => request({
      url: `${base}/applications/${app}/purchases/voidedpurchases`,
      params: { startTime: String(sinceMs), type: 0, maxResults: 100, ...(pageToken ? { token: pageToken } : {}) } }),
  };
}
