import assert from 'node:assert/strict';
import { test } from 'node:test';
import { nonceFor } from './integrity.mjs';
import { start } from './testing/harness.mjs';

test('registration issues a server-side identity, welcome grants and a session', async (t) => {
  const h = await start(); t.after(h.close);
  const r = await h.register();
  assert.equal(r.status, 201);
  assert.match(r.player.id, /^p_[a-f0-9]{24}$/);
  const s = await h.state(r.player);
  assert.equal(s.body.wallet.coins, 50);
  assert.equal(s.body.wallet.hints, 3);
  const other = await h.register();
  assert.notEqual(other.player.id, r.player.id);
});

test('registration rejects the wrong application package and malformed bodies', async (t) => {
  const h = await start(); t.after(h.close);
  assert.equal((await h.call('POST', '/v1/auth/register', { body: { pkg: 'com.example.other' } })).status, 403);
  assert.equal((await h.call('POST', '/v1/auth/register', { raw: 'not json' })).status, 422);
  assert.equal((await h.call('POST', '/v1/auth/register', { raw: '[]' })).status, 422);
  assert.equal((await h.call('POST', '/v1/auth/register', { raw: JSON.stringify({ pad: 'x'.repeat(20000) }) })).status, 413);
});

test('requests without a valid session are refused and tokens cannot select another player', async (t) => {
  const h = await start(); t.after(h.close);
  const a = (await h.register()).player;
  const b = (await h.register()).player;
  for (const [method, path] of [['GET', '/v1/state'], ['POST', '/v1/command'], ['POST', '/v1/play/verify']]) {
    assert.equal((await h.call(method, path, {})).status, 401, path);
    assert.equal((await h.call(method, path, { token: 'pw1.k1.e30.AAAA' })).status, 401, path);
  }
  await h.command(b, 'dev.grant', { coins: 5 }); // unknown in production
  // A request parameter or body field cannot redirect the session to someone else's wallet.
  const sneaky = await h.call('GET', `/v1/state?player=${b.id}&playerId=${b.id}`, { token: a.token });
  assert.equal(sneaky.body.wallet.billingAccount, (await h.state(a)).body.wallet.billingAccount);
  assert.notEqual(sneaky.body.wallet.billingAccount, (await h.state(b)).body.wallet.billingAccount);
  const cmd = await h.call('POST', '/v1/command', { token: a.token, body: { op: 'op-hint-1234', type: 'hint.buy', args: { playerId: b.id } } });
  assert.equal(cmd.status, 402, 'the command acts on the session owner only');
  assert.equal((await h.state(b)).body.wallet.coins, 50);
});

test('access tokens expire and refresh tokens rotate', async (t) => {
  const h = await start(); t.after(h.close);
  const { player } = await h.register();
  assert.equal((await h.state(player)).status, 200);
  h.clock.time += 16 * 60 * 1000;
  assert.equal((await h.state(player)).status, 401, 'session expired');
  const first = await h.call('POST', '/v1/auth/refresh', { body: { refresh: player.refresh } });
  assert.equal(first.status, 200);
  assert.notEqual(first.body.refresh, player.refresh);
  assert.equal((await h.state({ token: first.body.session.token })).status, 200);
});

test('refresh tolerates a lost response inside the grace window but revokes on later reuse', async (t) => {
  const h = await start(); t.after(h.close);
  const { player } = await h.register();
  const first = await h.call('POST', '/v1/auth/refresh', { body: { refresh: player.refresh } });
  // The client never saw `first`; retrying the old token within the grace window still works.
  const retry = await h.call('POST', '/v1/auth/refresh', { body: { refresh: player.refresh } });
  assert.equal(retry.status, 200);
  h.clock.time += 5 * 60 * 1000;
  // Reuse of a rotated-out token after the window indicates theft: device is revoked.
  const stolen = await h.call('POST', '/v1/auth/refresh', { body: { refresh: player.refresh } });
  assert.equal(stolen.status, 401);
  const latest = await h.call('POST', '/v1/auth/refresh', { body: { refresh: retry.body.refresh } });
  assert.equal(latest.status, 401, 'device revoked');
  assert.equal((await h.call('POST', '/v1/auth/refresh', { body: { refresh: 'zz.zz' } })).status, 401);
  void first;
});

test('sign-out everywhere invalidates every device and session', async (t) => {
  const h = await start(); t.after(h.close);
  const { player } = await h.register();
  assert.equal((await h.call('POST', '/v1/auth/signout-all', { token: player.token, body: {} })).status, 200);
  assert.equal((await h.state(player)).status, 401);
  assert.equal((await h.call('POST', '/v1/auth/refresh', { body: { refresh: player.refresh } })).status, 401);
});

test('Play Games linking enables recovery on a new device without exposing others', async (t) => {
  const h = await start(); t.after(h.close);
  const { player } = await h.register();
  await h.command(player, 'tutorial.ack', { id: 'walls' });
  assert.equal((await h.call('POST', '/v1/auth/link', { token: player.token, body: { code: 'games-account-A' } })).status, 200);
  assert.equal((await h.call('POST', '/v1/auth/link', { token: player.token, body: { code: 'games-account-A' } })).status, 200, 'idempotent');
  assert.equal((await h.call('POST', '/v1/auth/link', { token: player.token, body: { code: 'games-account-B' } })).status, 409, 'one account per player');
  const intruder = (await h.register()).player;
  const taken = await h.call('POST', '/v1/auth/link', { token: intruder.token, body: { code: 'games-account-A' } });
  assert.equal(taken.status, 409);
  assert.equal(taken.body.error, 'account_in_use');
  const recovered = await h.call('POST', '/v1/auth/recover', { body: { pkg: h.packageName, code: 'games-account-A' } });
  assert.equal(recovered.status, 200);
  assert.equal(recovered.body.playerId, player.id);
  const restored = await h.state({ token: recovered.body.session.token });
  assert.equal(restored.body.progress.tutorials.walls, 'completed');
  assert.equal((await h.call('POST', '/v1/auth/recover', { body: { pkg: h.packageName, code: 'games-nobody' } })).status, 404);
  assert.equal((await h.call('POST', '/v1/auth/recover', { body: { pkg: h.packageName, code: 'rejected-code' } })).status, 403);
});

test('Play Integrity is enforced when required: challenge, nonce, verdicts and single use', async (t) => {
  const verdict = (challenge, overrides = {}) => ({ tokenPayloadExternal: {
    requestDetails: { requestPackageName: 'com.shenmareparas.pathwise', nonce: nonceFor(challenge), timestampMillis: String(h.clock.time) },
    appIntegrity: { appRecognitionVerdict: 'PLAY_RECOGNIZED' }, deviceIntegrity: { deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'] },
    ...overrides } });
  let next = null;
  const h = await start({ integrityRequired: true, decode: async (token) => next(token) }); t.after(h.close);
  assert.equal((await h.register()).status, 403, 'missing attestation');
  const attempt = async (shape, challengeOverride) => {
    const { body: { challenge } } = await h.call('GET', '/v1/auth/challenge');
    next = () => shape(challenge);
    return h.register({ challenge: challengeOverride ?? challenge, integrityToken: 'x'.repeat(40) });
  };
  assert.equal((await attempt((c) => verdict(c))).status, 201);
  assert.equal((await attempt((c) => verdict(c, { appIntegrity: { appRecognitionVerdict: 'UNRECOGNIZED_VERSION' } }))).status, 403);
  assert.equal((await attempt((c) => verdict(c, { deviceIntegrity: { deviceRecognitionVerdict: [] } }))).status, 403);
  assert.equal((await attempt((c) => verdict('another'))).status, 403, 'nonce bound to the challenge');
  const { body: { challenge } } = await h.call('GET', '/v1/auth/challenge');
  next = () => verdict(challenge);
  assert.equal((await h.register({ challenge, integrityToken: 'x'.repeat(40) })).status, 201);
  assert.equal((await h.register({ challenge, integrityToken: 'x'.repeat(40) })).status, 403, 'challenge replay');
});

test('development and production sessions are not interchangeable', async (t) => {
  const prod = await start({ env: 'production' }); t.after(prod.close);
  const dev = await start({ env: 'development' }); t.after(dev.close);
  const devPlayer = (await dev.register()).player;
  assert.equal((await dev.call('POST', '/v1/auth/register', { body: { pkg: 'com.shenmareparas.pathwise' } })).status, 403);
  assert.equal((await prod.call('POST', '/v1/auth/register', { body: { pkg: 'com.shenmareparas.pathwise.debug' } })).status, 403);
  assert.equal((await prod.state(devPlayer)).status, 401, 'debug session rejected by production');
});

test('the registration endpoint is throttled per address', async (t) => {
  const h = await start(); t.after(h.close);
  let limited = 0;
  for (let i = 0; i < 12; i++) if ((await h.register()).status === 429) limited++;
  assert.ok(limited >= 2);
});

test('clients below the minimum build must update and maintenance mode blocks the API', async (t) => {
  const h = await start({ minBuild: 9 }); t.after(h.close);
  const old = await h.call('GET', '/v1/config', { headers: { 'x-pathwise-build': '8' } });
  assert.equal(old.status, 426);
  assert.equal(old.body.error, 'update_required');
  assert.equal((await h.call('GET', '/v1/config', { headers: { 'x-pathwise-build': '9' } })).status, 200);
  const off = await start({ onlineEnabled: false }); t.after(off.close);
  assert.equal((await off.call('GET', '/v1/ping')).status, 503);
  assert.equal((await off.call('GET', '/healthz')).body.status, 'disabled');
});
