// Identity: server-issued player + device credentials, short-lived signed
// session tokens, rotating refresh tokens, Play Games linking and recovery.
import { createHash } from 'node:crypto';
import { appPackages, rules } from './economy-config.mjs';
import { HttpError, clientAddress, durableLimit, readJson } from './http.mjs';
import { collections, credit, newPlayerState, newProgress } from './players.mjs';
import { randomToken, sha256 } from './tokens.mjs';
import { nonceFor } from './integrity.mjs';

export const SESSION_TTL_MS = 15 * 60 * 1000;
const REFRESH_TTL_MS = 90 * 86400000;
const ROTATION_GRACE_MS = 120000;
const CHALLENGE_TTL_MS = 5 * 60 * 1000;
const hash = (value) => createHash('sha256').update(value).digest('hex');

export function createAuth({ db, signer, env, integrity, verifyGamesCode, now = Date.now }) {
  const packageName = appPackages[env] ?? (() => { throw new Error('PATHWISE_ENV must be production or development'); })();
  const devices = db.collection(collections.devices);

  const issueSession = (playerId, did, epoch) => {
    const token = signer.sign('session', { sub: playerId, did, ep: epoch, env, aud: packageName }, SESSION_TTL_MS);
    return { token, expiresAt: now() + SESSION_TTL_MS };
  };

  /** Verifies the Bearer session token. Pure CPU; epoch is re-checked by each transaction. */
  function authenticate(request) {
    const header = request.headers.authorization ?? '';
    const claims = header.startsWith('Bearer ') ? signer.verify('session', header.slice(7)) : null;
    if (!claims || claims.env !== env || claims.aud !== packageName || typeof claims.sub !== 'string') {
      throw new HttpError(401, 'session_expired');
    }
    return { playerId: claims.sub, did: claims.did, epoch: claims.ep };
  }

  const newDevice = (tx, playerId, epoch) => {
    const did = randomToken(8);
    const secret = randomToken(32);
    tx.create(devices.doc(did), { player: playerId, ep: epoch, refresh: sha256(secret), prev: null, prevUntil: 0,
      created: now(), seen: now(), expiresAt: new Date(now() + REFRESH_TTL_MS) });
    return { did, refresh: `${did}.${secret}` };
  };

  async function checkAttestation(body, scope) {
    if (!integrity.required) return;
    const challenge = body.challenge;
    const valid = signer.verify('challenge', challenge);
    if (!valid || valid.scope !== scope || !await integrity.verify(body.integrityToken, challenge)) {
      throw new HttpError(403, 'attestation_failed');
    }
    // A challenge is single use.
    try {
      await db.collection('pathwise-challenges').doc(hash(challenge)).create({ expiresAt: new Date(now() + 2 * CHALLENGE_TTL_MS) });
    } catch { throw new HttpError(403, 'attestation_failed'); }
  }

  function checkApp(body) {
    if (body.pkg !== packageName) throw new HttpError(403, 'wrong_app');
    const tz = Number.isInteger(body.tz) && Math.abs(body.tz) <= 840 ? body.tz : 0;
    return tz;
  }

  const handlers = {
    challenge(request) {
      const scope = new URL(request.url, 'http://x').searchParams.get('scope') === 'recover' ? 'recover' : 'register';
      const challenge = signer.sign('challenge', { scope, n: randomToken(8) }, CHALLENGE_TTL_MS);
      return [200, { challenge, nonce: nonceFor(challenge), required: integrity.required }];
    },

    async register(request) {
      const body = await readJson(request, 4096 + 8192);
      const tz = checkApp(body);
      const ip = hash(clientAddress(request));
      if (!await durableLimit(db, 'pathwise-rate', `register.${ip}`, { limit: 10, windowMs: 3600000, now })) {
        throw new HttpError(429, 'rate_limit');
      }
      await checkAttestation(body, 'register');
      const playerId = `p_${randomToken(12)}`;
      const time = now();
      const state = newPlayerState(playerId, time, tz);
      state.hints = rules.starterHints;
      credit(state, time, 'starter', 'Welcome coins', rules.starterCoins);
      const device = await db.runTransaction(async (tx) => {
        const created = newDevice(tx, playerId, state.epoch);
        tx.create(db.collection(collections.players).doc(playerId), state);
        tx.create(db.collection(collections.progress).doc(playerId), newProgress());
        return created;
      });
      return [201, { playerId, session: issueSession(playerId, device.did, state.epoch), refresh: device.refresh, serverNow: time }];
    },

    async refresh(request) {
      const body = await readJson(request, 1024);
      const [did, secret] = String(body.refresh ?? '').split('.');
      if (!/^[a-f0-9]{16}$/.test(did ?? '') || !/^[a-f0-9]{64}$/.test(secret ?? '')) throw new HttpError(401, 'session_expired');
      const presented = sha256(secret);
      const deviceRef = devices.doc(did);
      const result = await db.runTransaction(async (tx) => {
        const device = await tx.get(deviceRef);
        if (!device.exists) return { error: 'session_expired' };
        const time = now();
        const player = await tx.get(db.collection(collections.players).doc(device.get('player')));
        if (!player.exists || player.get('epoch') !== device.get('ep') || time - device.get('seen') > REFRESH_TTL_MS) {
          return { error: 'session_expired' };
        }
        const current = device.get('refresh') === presented;
        const previous = device.get('prev') === presented && time < device.get('prevUntil');
        if (!current && !previous) {
          // A rotated-out token outside the grace window signals theft: revoke the device.
          if (device.get('prev') === presented) tx.delete(deviceRef);
          return { error: 'session_expired' };
        }
        const next = randomToken(32);
        tx.set(deviceRef, { ...device.data(), refresh: sha256(next), prev: current ? presented : device.get('prev'),
          prevUntil: current ? time + ROTATION_GRACE_MS : device.get('prevUntil'), seen: time,
          expiresAt: new Date(time + REFRESH_TTL_MS) });
        return { playerId: device.get('player'), epoch: player.get('epoch'), refresh: `${did}.${next}` };
      });
      if (result.error) throw new HttpError(401, result.error);
      return [200, { session: issueSession(result.playerId, did, result.epoch), refresh: result.refresh, serverNow: now() }];
    },

    async link(request) {
      const { playerId } = authenticate(request);
      const body = await readJson(request, 4096);
      if (typeof body.code !== 'string' || body.code.length < 8 || body.code.length > 2048) throw new HttpError(422, 'invalid_code');
      if (!await durableLimit(db, 'pathwise-rate', `link.${playerId}`, { limit: 6, windowMs: 3600000, now })) throw new HttpError(429, 'rate_limit');
      const games = await verifyGamesCode(body.code);
      if (!games) throw new HttpError(403, 'account_unavailable');
      const accountKey = hash(games);
      const account = db.collection(collections.games).doc(accountKey);
      const playerRef = db.collection(collections.players).doc(playerId);
      const outcome = await db.runTransaction(async (tx) => {
        const [a, p] = await tx.getAll(account, playerRef);
        if (!p.exists) return 'player_not_found';
        if (a.exists && a.get('player') !== playerId) return 'account_in_use';
        if (p.get('games') && p.get('games') !== accountKey) return 'already_linked';
        if (!a.exists) tx.create(account, { player: playerId, at: now() });
        tx.set(playerRef, { ...p.data(), games: accountKey });
        return 'linked';
      });
      if (outcome === 'linked') return [200, { linked: true }];
      return [outcome === 'player_not_found' ? 404 : 409, { error: outcome }];
    },

    async recover(request) {
      const body = await readJson(request, 4096 + 8192);
      checkApp(body);
      const ip = hash(clientAddress(request));
      if (!await durableLimit(db, 'pathwise-rate', `recover.${ip}`, { limit: 10, windowMs: 3600000, now })) throw new HttpError(429, 'rate_limit');
      await checkAttestation(body, 'recover');
      if (typeof body.code !== 'string' || body.code.length < 8 || body.code.length > 2048) throw new HttpError(422, 'invalid_code');
      const games = await verifyGamesCode(body.code);
      if (!games) throw new HttpError(403, 'account_unavailable');
      const account = db.collection(collections.games).doc(hash(games));
      const found = await db.runTransaction(async (tx) => {
        const a = await tx.get(account);
        if (!a.exists) return null;
        const p = await tx.get(db.collection(collections.players).doc(a.get('player')));
        if (!p.exists) return null;
        return { playerId: a.get('player'), epoch: p.get('epoch'), ...newDevice(tx, a.get('player'), p.get('epoch')) };
      });
      if (!found) throw new HttpError(404, 'no_linked_account');
      return [200, { playerId: found.playerId, session: issueSession(found.playerId, found.did, found.epoch),
        refresh: found.refresh, serverNow: now() }];
    },

    /** Revokes every device of the player by bumping the session epoch. */
    async signOutEverywhere(request) {
      const { playerId } = authenticate(request);
      const ref = db.collection(collections.players).doc(playerId);
      await db.runTransaction(async (tx) => {
        const p = await tx.get(ref);
        if (p.exists) tx.set(ref, { ...p.data(), epoch: p.get('epoch') + 1 });
      });
      return [200, { revoked: true }];
    },
  };

  return { authenticate, handlers, packageName, issueSession };
}
