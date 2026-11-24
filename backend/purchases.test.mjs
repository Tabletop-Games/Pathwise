import assert from 'node:assert/strict';
import { test } from 'node:test';
import { start } from './testing/harness.mjs';

const verify = (h, p, product, token) => h.call('POST', '/v1/play/verify', { token: p.token, body: { product, token } });
const T1 = 'token-aaaaaaaaaaaa';

test('a verified coin pack credits once, then is consumed after the grant is durable', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add(T1, 'pathwise_coins_1250', p.id);
  const res = await verify(h, p, 'pathwise_coins_1250', T1);
  assert.equal(res.status, 200);
  assert.equal(res.body.wallet.coins, 50 + 1250);
  assert.deepEqual(h.play.calls, [['consume', 'pathwise_coins_1250', T1]]);
  // Retry after Play marks it consumed: same grant, no double credit.
  h.play.purchases.get(T1).productLineItem[0].productOfferDetails.consumptionState = 'CONSUMED';
  const again = await verify(h, p, 'pathwise_coins_1250', T1);
  assert.equal(again.status, 200);
  assert.equal(again.body.replay, true);
  assert.equal(again.body.wallet.coins, 1300);
});

test('client-asserted products, prices and tokens are never trusted', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  assert.equal((await verify(h, p, 'pathwise_coins_999999', T1)).status, 422);
  assert.equal((await verify(h, p, 'pathwise_coins_500', 'short')).status, 422);
  assert.equal((await verify(h, p, 'pathwise_coins_500', T1)).status, 403, 'unknown purchase token');
  h.play.add(T1, 'pathwise_coins_500', p.id);
  assert.equal((await verify(h, p, 'pathwise_coins_18000', T1)).status, 403, 'product must match the Play record');
  assert.equal((await h.state(p)).body.wallet.coins, 50);
});

test('a purchase belongs to the player it was made for and cannot be claimed by another', async (t) => {
  const h = await start(); t.after(h.close);
  const buyer = (await h.register()).player;
  const thief = (await h.register()).player;
  h.play.add(T1, 'pathwise_coins_500', buyer.id);
  assert.equal((await verify(h, thief, 'pathwise_coins_500', T1)).status, 403);
  assert.equal((await verify(h, buyer, 'pathwise_coins_500', T1)).status, 200);
  assert.equal((await verify(h, thief, 'pathwise_coins_500', T1)).status, 403, 'granted token stays bound to its owner');
  assert.equal((await h.state(thief)).body.wallet.coins, 50);
});

test('pending, cancelled and multi-quantity purchases grant nothing', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add(T1, 'pathwise_coins_500', p.id, { purchaseStateContext: { purchaseState: 'PENDING' } });
  assert.equal((await verify(h, p, 'pathwise_coins_500', T1)).body.error, 'payment_pending');
  h.play.add('token-bbbbbbbbbbbb', 'pathwise_coins_500', p.id, { purchaseStateContext: { purchaseState: 'CANCELLED' } });
  assert.equal((await verify(h, p, 'pathwise_coins_500', 'token-bbbbbbbbbbbb')).status, 403);
  h.play.add('token-cccccccccccc', 'pathwise_coins_500', p.id);
  h.play.purchases.get('token-cccccccccccc').productLineItem[0].productOfferDetails.quantity = 5;
  assert.equal((await verify(h, p, 'pathwise_coins_500', 'token-cccccccccccc')).status, 403);
  assert.equal((await h.state(p)).body.wallet.coins, 50);
});

test('an already-consumed token that was never granted cannot be claimed', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add(T1, 'pathwise_coins_500', p.id);
  h.play.purchases.get(T1).productLineItem[0].productOfferDetails.consumptionState = 'CONSUMED';
  assert.equal((await verify(h, p, 'pathwise_coins_500', T1)).status, 403);
});

test('concurrent verification of one token credits exactly once', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add(T1, 'pathwise_coins_3000', p.id);
  const all = await Promise.all(Array.from({ length: 5 }, () => verify(h, p, 'pathwise_coins_3000', T1)));
  assert.ok(all.every((r) => r.status === 200));
  assert.equal((await h.state(p)).body.wallet.coins, 3050);
});

test('entitlements: Remove Ads does not unlock themes, Premium bundles both plus a one-time bonus', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add('token-ads-000000', 'pathwise_remove_ads', p.id);
  const ads = await verify(h, p, 'pathwise_remove_ads', 'token-ads-000000');
  assert.equal(ads.body.wallet.entitlements.adFree, true);
  assert.equal(ads.body.wallet.entitlements.themePass, false);
  assert.equal(ads.body.wallet.themes.includes('gilded'), false);
  assert.deepEqual(h.play.calls.at(-1), ['acknowledge', 'pathwise_remove_ads', 'token-ads-000000']);
  h.play.add('token-themes-00', 'pathwise_themes_forever', p.id);
  const themes = await verify(h, p, 'pathwise_themes_forever', 'token-themes-00');
  assert.equal(themes.body.wallet.themes.includes('gilded'), true);
  assert.equal(themes.body.wallet.entitlements.adFree, true);
  h.play.add('token-premium-0', 'pathwise_premium', p.id);
  const premium = await verify(h, p, 'pathwise_premium', 'token-premium-0');
  assert.equal(premium.body.wallet.coins, 1050);
});

test('permanent entitlements restore on a new device, and re-verification never repeats the Premium bonus', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add('token-premium-0', 'pathwise_premium', p.id);
  await verify(h, p, 'pathwise_premium', 'token-premium-0');
  await h.call('POST', '/v1/auth/link', { token: p.token, body: { code: 'games-restore-1' } });
  const device2 = await h.call('POST', '/v1/auth/recover', { body: { pkg: h.packageName, code: 'games-restore-1' } });
  const view = await h.state({ token: device2.body.session.token });
  assert.equal(view.body.wallet.entitlements.premium, true);
  assert.equal(view.body.wallet.coins, 1050);
  // Play "restore purchases" on the new device re-submits the token: idempotent.
  const again = await h.call('POST', '/v1/play/verify', { token: device2.body.session.token, body: { product: 'pathwise_premium', token: 'token-premium-0' } });
  assert.equal(again.status, 200);
  assert.equal(again.body.wallet.coins, 1050);
});

test('refunds reverse coins and entitlements exactly once via RTDN, and the voided poll is a backstop', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add(T1, 'pathwise_coins_500', p.id);
  await verify(h, p, 'pathwise_coins_500', T1);
  h.play.add('token-premium-0', 'pathwise_premium', p.id);
  await verify(h, p, 'pathwise_premium', 'token-premium-0');
  const rtdn = (token, headers = { authorization: 'Bearer push-rtdn' }) => h.call('POST', '/v1/play/rtdn', { headers, body: {
    message: { data: Buffer.from(JSON.stringify({ packageName: h.packageName, voidedPurchaseNotification: { purchaseToken: token, productType: 2 } })).toString('base64') } } });
  assert.equal((await rtdn(T1, {})).status, 403, 'unauthenticated push is refused');
  assert.equal((await rtdn(T1)).body.result, 'reversed');
  assert.equal((await rtdn(T1)).body.result, 'already_reversed');
  let wallet = (await h.state(p)).body.wallet;
  assert.equal(wallet.coins, 50 + 500 + 1000 - 500);
  assert.equal(wallet.entitlements.premium, true);
  h.play.voided = [{ purchaseToken: 'token-premium-0', voidedTimeMillis: String(h.clock.time) }, { purchaseToken: 'never-seen-token', voidedTimeMillis: '1' }];
  const reconcile = await h.call('POST', '/v1/play/reconcile', { headers: { authorization: 'Bearer push-reconcile' }, body: {} });
  assert.equal(reconcile.body.reversed, 1);
  wallet = (await h.state(p)).body.wallet;
  assert.equal(wallet.entitlements.premium, false);
  assert.equal(wallet.entitlements.adFree, false);
  assert.equal(wallet.coins, 50, 'premium bonus is reversed with the refund');
  const retry = await verify(h, p, 'pathwise_premium', 'token-premium-0');
  assert.ok([403].includes(retry.status));
  const foreign = await h.call('POST', '/v1/play/rtdn', { headers: { authorization: 'Bearer push-rtdn' }, body: {
    message: { data: Buffer.from(JSON.stringify({ packageName: 'com.other.app', voidedPurchaseNotification: { purchaseToken: T1, productType: 2 } })).toString('base64') } } });
  assert.equal(foreign.body.result, 'ignored');
});

test('a refunded balance can go negative and blocks spending until it is earned back', async (t) => {
  const h = await start(); t.after(h.close);
  const p = (await h.register()).player;
  h.play.add(T1, 'pathwise_coins_500', p.id);
  await verify(h, p, 'pathwise_coins_500', T1);
  for (let i = 0; i < 9; i++) assert.equal((await h.command(p, 'hint.buy')).status, 200); // 550 -> 10 coins
  await h.call('POST', '/v1/play/rtdn', { headers: { authorization: 'Bearer push-rtdn' }, body: {
    message: { data: Buffer.from(JSON.stringify({ packageName: h.packageName, voidedPurchaseNotification: { purchaseToken: T1, productType: 2 } })).toString('base64') } } });
  const wallet = (await h.state(p)).body.wallet;
  assert.equal(wallet.coins, -490);
  assert.equal((await h.command(p, 'hint.buy')).body.error, 'insufficient_coins');
});
