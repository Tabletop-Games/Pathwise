import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';

import { verifyReceipt } from './verify.mjs';

const secret = 'f'.repeat(64);
const credential = `Bearer ${secret}`;
const token = 'valid-token-example';
const product = 'pathwise_coins_120';

function fixture() {
  const ledger = new Map();
  const play = {
    purchaseStateContext: { purchaseState: 'PURCHASED' },
    obfuscatedExternalAccountId: createHash('sha256').update(secret).digest('hex'),
    productLineItem: [{
      productId: product,
      productOfferDetails: { quantity: 1, refundableQuantity: 1, consumptionState: 'YET_TO_BE_CONSUMED' },
    }],
  };
  const deps = {
    getPurchase: async () => play,
    claim: async (id, info, { consumed }) => {
      if (ledger.has(id)) return ledger.get(id).profile === info.profile;
      if (consumed) return false;
      ledger.set(id, info);
      return true;
    },
  };
  return { play, ledger, deps };
}

test('same installation gets the same grant on retries after consumption', async () => {
  const { play, ledger, deps } = fixture();
  const first = await verifyReceipt(credential, { product, token }, deps);
  assert.equal(first.status, 200);
  play.productLineItem[0].productOfferDetails.consumptionState = 'CONSUMED';
  assert.deepEqual(await verifyReceipt(credential, { product, token }, deps), first);
  assert.equal(ledger.size, 1);
});

test('pending and canceled purchase states cannot be fulfilled', async () => {
  const { play, ledger, deps } = fixture();
  play.purchaseStateContext.purchaseState = 'PENDING';
  assert.equal((await verifyReceipt(credential, { product, token }, deps)).status, 409);
  play.purchaseStateContext.purchaseState = 'CANCELLED';
  assert.equal((await verifyReceipt(credential, { product, token }, deps)).status, 403);
  assert.equal(ledger.size, 0);
});

test('rejects a different installation, wrong sku, refunded order, malformed credential and consumed first claim', async () => {
  const { play, ledger, deps } = fixture();
  assert.equal((await verifyReceipt(`Bearer ${'a'.repeat(64)}`, { product, token }, deps)).status, 403);
  assert.equal((await verifyReceipt(credential, { product: 'pathwise_coins_800', token }, deps)).status, 403);
  assert.equal((await verifyReceipt('invalid', { product, token }, deps)).status, 403);
  const offer = play.productLineItem[0].productOfferDetails;
  offer.refundableQuantity = 0;
  assert.equal((await verifyReceipt(credential, { product, token }, deps)).status, 403);
  offer.refundableQuantity = 1;
  offer.consumptionState = 'CONSUMED';
  assert.equal((await verifyReceipt(credential, { product, token }, deps)).status, 403);
  assert.equal(ledger.size, 0);
});

test('returns authoritative amounts for new coin packs and accepts verified permanent Premium', async () => {
  const { play, ledger, deps } = fixture();
  const line = play.productLineItem[0];
  const pack = 'pathwise_coins_3500';
  line.productId = pack;
  const credit = await verifyReceipt(credential, { product: pack, token }, deps);
  assert.equal(credit.body.coins, 3500);
  assert.equal(ledger.get(credit.body.id).coins, 3500);
  const premium = 'pathwise_premium';
  line.productId = premium;
  const pass = await verifyReceipt(credential, { product: premium, token: 'premium-token-example' }, deps);
  assert.equal(pass.status, 200);
  assert.equal(pass.body.product, premium);
  assert.equal(pass.body.coins, 0);
  assert.equal(ledger.size, 2);
});
