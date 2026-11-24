// HTTP router. Dependencies are injected so the whole service runs against an
// in-memory Firestore double in tests and against Firestore in production.
import { readFileSync } from 'node:fs';
import { publicConfig } from './economy-config.mjs';
import { commands } from './economy.mjs';
import { HttpError, memoryLimiter, readJson, send } from './http.mjs';
import { collections, mutate, newProgress, publicWallet } from './players.mjs';
import { attemptView, playCommands } from './play.mjs';

const minuteLimit = (limit) => memoryLimiter({ limit, windowMs: 60000 });

export function createApp({ db, env, auth, purchases, rewards, verifyPush, health, now = Date.now,
  minBuild = 0, onlineEnabled = true, log = console.log }) {
  const registry = { ...commands, ...playCommands, 'reward.claim': rewards.claim };
  if (env === 'development') {
    // Development backend only. Never exists in the production environment.
    registry['dev.grant'] = (ctx, args) => {
      const coins = Number.isInteger(args.coins) ? Math.min(Math.max(args.coins, 0), 100000) : 0;
      const hints = Number.isInteger(args.hints) ? Math.min(Math.max(args.hints, 0), 100) : 0;
      if (coins) { ctx.state.coins += coins; ctx.state.earned += coins; }
      ctx.state.hints += hints;
      return { coins, hints };
    };
  }
  const perPlayer = minuteLimit(240);
  const perAddress = minuteLimit(120);

  async function snapshot(playerId, epoch) {
    const [wallet, progress] = await Promise.all([
      db.collection(collections.players).doc(playerId).get(),
      db.collection(collections.progress).doc(playerId).get(),
    ]);
    if (!wallet.exists || wallet.get('epoch') !== epoch) throw new HttpError(401, 'session_expired');
    const state = wallet.data();
    const saved = progress.data() ?? newProgress();
    const time = now();
    const run = saved.attack.current;
    return {
      wallet: publicWallet(state, time),
      progress: {
        rev: saved.rev, results: saved.results, stages: saved.stages, highestUnlocked: saved.highestUnlocked,
        tutorials: saved.tutorials,
        attempts: Object.fromEntries(Object.entries(saved.attempts).map(([key, value]) => [key, attemptView(value)])), prefs: saved.prefs, hintUse: saved.hintUse,
        attackHistory: saved.attack.history.slice(-10).map(({ id, minutes, score, coins, record }) => ({ id, minutes, score, coins, record })),
        attack: run ? { id: run.id, minutes: run.minutes, deadline: run.deadline, remainingMs: run.finished ? 0 : Math.max(0, run.deadline - time),
          clears: run.clears, finished: run.finished === true, coins: run.coins, unassisted: run.unassisted, previousBest: run.previousBest } : null,
      },
      serverNow: time,
    };
  }

  async function route(request, response, path) {
    const method = request.method;
    const address = request.headers['x-forwarded-for'] ?? request.socket.remoteAddress ?? 'unknown';
    if (!perAddress(String(address).split(',').pop().trim())) throw new HttpError(429, 'rate_limit');

    if (method === 'GET' && path === '/healthz') {
      const ready = onlineEnabled && await health().catch(() => false);
      return send(response, ready ? 200 : 503, { status: ready ? 'ready' : 'disabled', env, package: auth.packageName });
    }
    if (!onlineEnabled) throw new HttpError(503, 'maintenance');
    if (method === 'GET' && path === '/v1/ping') return send(response, 200, { serverNow: now(), env });

    const build = Number(request.headers['x-pathwise-build'] ?? 0);
    if (minBuild > 0 && build < minBuild) throw new HttpError(426, 'update_required', { minBuild });

    if (method === 'GET' && path === '/v1/config') return send(response, 200, { ...publicConfig(), minBuild, env });
    if (method === 'GET' && path === '/v1/auth/challenge') return send(response, ...auth.handlers.challenge(request));
    const open = { '/v1/auth/register': 'register', '/v1/auth/refresh': 'refresh', '/v1/auth/recover': 'recover' };
    if (method === 'POST' && open[path]) return send(response, ...await auth.handlers[open[path]](request));
    if (method === 'POST' && path === '/v1/auth/link') return send(response, ...await auth.handlers.link(request));
    if (method === 'POST' && path === '/v1/auth/signout-all') return send(response, ...await auth.handlers.signOutEverywhere(request));

    if (method === 'GET' && path === '/v1/rewards/callback') {
      const query = request.url.slice(path.length + 1);
      return send(response, ...await rewards.callback(request, query));
    }
    if (method === 'POST' && path === '/v1/play/rtdn') {
      await verifyPush(request, 'rtdn');
      const body = await readJson(request, 16384);
      let message;
      try { message = JSON.parse(Buffer.from(String(body.message?.data ?? ''), 'base64').toString()); }
      catch { throw new HttpError(422, 'invalid_message'); }
      return send(response, 200, { result: await purchases.notification(message) });
    }
    if (method === 'POST' && path === '/v1/play/reconcile') {
      await verifyPush(request, 'reconcile');
      return send(response, 200, await purchases.reconcile());
    }

    // Everything below needs a valid session.
    const identity = auth.authenticate(request);
    if (!perPlayer(identity.playerId)) throw new HttpError(429, 'rate_limit');

    if (method === 'GET' && path === '/v1/state') return send(response, 200, await snapshot(identity.playerId, identity.epoch));
    if (method === 'POST' && path === '/v1/command') {
      const body = await readJson(request, 12288);
      const handler = typeof body.type === 'string' && Object.hasOwn(registry, body.type) ? registry[body.type] : null;
      if (!handler) throw new HttpError(422, 'unknown_command');
      const args = body.args && typeof body.args === 'object' && !Array.isArray(body.args) ? body.args : {};
      const result = await mutate(db, { playerId: identity.playerId, epoch: identity.epoch, op: body.op,
        kind: body.type, args, now }, (ctx) => handler(ctx, args));
      return send(response, 200, result);
    }
    if (method === 'POST' && path === '/v1/play/verify') {
      const body = await readJson(request, 4096);
      return send(response, 200, await purchases.verify(identity.playerId, body));
    }
    const start = /^\/v1\/rewards\/start\/([a-z]{3,8})$/.exec(path);
    if (method === 'POST' && start) {
      const body = await readJson(request, 1024).catch(() => ({}));
      return send(response, 200, await rewards.start(identity.playerId, start[1], body));
    }
    const status = /^\/v1\/rewards\/status\/([a-f0-9]{64})$/.exec(path);
    if (method === 'GET' && status) return send(response, ...await rewards.status(identity.playerId, status[1]));
    throw new HttpError(404, 'not_found');
  }

  return async function handle(request, response) {
    const started = Date.now();
    const path = request.url.split('?')[0];
    const operation = path.startsWith('/v1/') ? path.replace(/\/[a-f0-9]{16,}$/, '/:id').slice(0, 48) : path;
    try {
      await route(request, response, path);
    } catch (error) {
      if (!response.headersSent) {
        if (error instanceof HttpError) send(response, error.status, { error: error.code, ...error.extra });
        else send(response, 503, { error: 'service_unavailable' });
      }
      if (!(error instanceof HttpError)) log(JSON.stringify({ severity: 'ERROR', operation, error: String(error?.code ?? error?.name ?? 'error') }));
    } finally {
      // Never log bodies, query strings, bearer values or purchase tokens.
      if (path !== '/healthz' || response.statusCode >= 500) {
        log(JSON.stringify({ severity: response.statusCode >= 500 ? 'WARNING' : 'INFO', operation,
          status: response.statusCode, durationMs: Date.now() - started }));
      }
    }
  };
}

export const readVersion = () => JSON.parse(readFileSync(new URL('./package.json', import.meta.url))).version;
