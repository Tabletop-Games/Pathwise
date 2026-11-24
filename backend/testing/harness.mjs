import { createServer } from 'node:http';
import { generateKeyPairSync, sign } from 'node:crypto';
import { createApp } from '../app.mjs';
import { createAuth } from '../auth.mjs';
import { appPackages } from '../economy-config.mjs';
import { HttpError } from '../http.mjs';
import { createIntegrity } from '../integrity.mjs';
import { billingAccount } from '../players.mjs';
import { createPurchases } from '../purchases.mjs';
import { createRewards } from '../rewards.mjs';
import { createSigner } from '../tokens.mjs';
import { MemoryFirestore } from './memory-db.mjs';

export const KEYS = 'k1:' + 'a'.repeat(40);
export const adKeys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });

/** Fake Google Play Developer API with a mutable purchase table. */
export function fakePlay() {
  const purchases = new Map();
  const calls = [];
  return {
    purchases, calls, voided: [],
    getPurchase: async (token) => purchases.get(token) ?? null,
    consume: async (product, token) => { calls.push(['consume', product, token]); },
    acknowledge: async (product, token) => { calls.push(['acknowledge', product, token]); },
    add(token, product, playerId, extra = {}) {
      purchases.set(token, {
        purchaseStateContext: { purchaseState: 'PURCHASED' }, obfuscatedExternalAccountId: billingAccount(playerId),
        productLineItem: [{ productId: product, productOfferDetails: { quantity: 1, refundableQuantity: 1, consumptionState: 'YET_TO_BE_CONSUMED' } }],
        ...extra,
      });
    },
  };
}

export async function start({ env = 'production', integrityRequired = false, decode, minBuild = 0, onlineEnabled = true,
  rewardEnv = {}, verifyGamesCode } = {}) {
  const db = new MemoryFirestore();
  const clock = { time: 1_800_000_000_000 };
  const now = () => clock.time;
  const signer = createSigner(KEYS, { now });
  const integrity = createIntegrity({ required: integrityRequired, packageName: appPackages[env], decode, now });
  const auth = createAuth({ db, signer, env, integrity, now, verifyGamesCode: verifyGamesCode ?? (async (code) => (code.startsWith('games-') ? code : null)) });
  const play = fakePlay();
  play.listVoided = async () => ({ voidedPurchases: play.voided });
  const purchases = createPurchases({ db, play, env, now });
  const rewards = createRewards({ db, now, keySet: async () => new Map([['100', adKeys.publicKey]]), env: {
    PATHWISE_REWARDS_ENABLED: 'true', PATHWISE_ADMOB_REWARDED: 'ca-app-pub-1111111111111111/1000000001',
    PATHWISE_ADMOB_EXTRA_HINT: 'ca-app-pub-1111111111111111/1000000002', PATHWISE_ADMOB_WHEEL: 'ca-app-pub-1111111111111111/1000000003',
    ...rewardEnv } });
  const logs = [];
  const verifyPush = async (request, kind) => {
    if (request.headers.authorization !== `Bearer push-${kind}`) throw new HttpError(403, 'forbidden');
  };
  const handler = createApp({ db, env, auth, purchases, rewards, now, minBuild, onlineEnabled, log: (line) => logs.push(line),
    health: async () => true, verifyPush });
  const server = createServer((request, response) => { void handler(request, response); });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const packageName = appPackages[env];
  let opCounter = 0;

  async function call(method, path, { token, body, headers = {}, raw } = {}) {
    const response = await fetch(origin + path, {
      method, headers: { ...(body !== undefined || raw ? { 'content-type': 'application/json' } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
      body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
    });
    let json = null;
    try { json = await response.json(); } catch { /* empty */ }
    return { status: response.status, body: json };
  }

  async function register(extra = {}) {
    const response = await call('POST', '/v1/auth/register', { body: { pkg: packageName, tz: 0, ...extra } });
    if (response.status !== 201) return response;
    const { playerId, session, refresh } = response.body;
    return { ...response, player: { id: playerId, token: session.token, refresh } };
  }
  const command = (player, type, args = {}, op = `op-${type}-${++opCounter}-${Math.random().toString(36).slice(2, 8)}`) =>
    call('POST', '/v1/command', { token: player.token, body: { op, type, args } });
  /** Exchanges the refresh token for a new session, as the app does after expiry. */
  const renew = async (player) => {
    const response = await call('POST', '/v1/auth/refresh', { body: { refresh: player.refresh } });
    if (response.status === 200) { player.token = response.body.session.token; player.refresh = response.body.refresh; }
    return response;
  };
  const state = (player) => call('GET', '/v1/state', { token: player.token });

  /** Signs an AdMob SSV callback exactly as Google does. */
  function ssv(token, { unit = '1000000001', transaction = `tx-${Math.random()}`, time = now(), keyId = '100', key = adKeys.privateKey } = {}) {
    const message = `ad_unit=${unit}&custom_data=${token}&timestamp=${time}&transaction_id=${transaction}`;
    return `${message}&signature=${sign('sha256', Buffer.from(message), key).toString('base64url')}&key_id=${keyId}`;
  }

  return { db, clock, call, register, command, state, renew, play, logs, packageName, ssv, origin, env,
    close: () => new Promise((resolve) => { server.closeAllConnections?.(); server.close(resolve); }) };
}
