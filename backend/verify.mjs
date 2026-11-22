import { createHash, timingSafeEqual } from 'node:crypto';

export const appPackage = 'games.tabletop.pathwise';
const products = Object.freeze({
  pathwise_coins_120: 120, pathwise_coins_340: 340, pathwise_coins_800: 800,
  pathwise_coins_500: 500, pathwise_coins_1200: 1200, pathwise_coins_3500: 3500,
  pathwise_coins_8000: 8000, pathwise_coins_20000: 20000,
  pathwise_themes_forever: 0, pathwise_remove_ads: 0, pathwise_premium: 0,
});
const digest = (text) => createHash('sha256').update(text).digest('hex');
const denied = { status: 403, body: { error: 'purchase_not_verifiable' } };

/**
 * Verifies the purchase with Google and claims its token exactly once. A retry
 * by the same installation returns the same grant, including after consumption.
 */
export async function verifyReceipt(authorization, payload, { getPurchase, claim }) {
  const credential = /^Bearer ([a-f0-9]{64})$/.exec(authorization ?? '')?.[1];
  if (!credential) return denied;
  const { product, token } = payload ?? {};
  if (!Object.hasOwn(products, product) || typeof token !== 'string' || token.length > 2048 ||
      !/^[\w.~-]{12,}$/.test(token)) {
    return { status: 422, body: { error: 'invalid_purchase' } };
  }

  const profile = digest(credential);
  const purchase = await getPurchase(token);
  if (!purchase) return denied;
  if (purchase.purchaseStateContext?.purchaseState === 'PENDING') {
    return { status: 409, body: { error: 'payment_pending' } };
  }
  const account = purchase.obfuscatedExternalAccountId;
  const lines = purchase.productLineItem;
  const line = lines?.[0];
  if (purchase.purchaseStateContext?.purchaseState !== 'PURCHASED' ||
      typeof account !== 'string' || !/^[a-f0-9]{64}$/.test(account) ||
      !timingSafeEqual(Buffer.from(profile), Buffer.from(account)) ||
      !Array.isArray(lines) || lines.length !== 1 || line.productId !== product ||
      line.productOfferDetails?.quantity !== 1 ||
      (line.productOfferDetails?.refundableQuantity ?? 0) !== 1) {
    return denied;
  }

  const consumed = line.productOfferDetails?.consumptionState === 'CONSUMED';
  const coins = products[product];
  if (consumed && coins === 0) return denied;
  const id = digest(`${appPackage}\0${token}`);
  if (!await claim(id, { product, profile, coins }, { consumed })) return denied;
  return { status: 200, body: { id, product, coins } };
}
