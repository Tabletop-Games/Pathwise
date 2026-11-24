# Backend

The Node 22 service in `backend/` runs on Cloud Run with Firestore, and it is the authority for Pathwise's identity, economy and progression. Setup is described in [deployment](deployment.md). The architecture is described in [online architecture](online-architecture.md).

## Modules

| File | Responsibility |
| --- | --- |
| `server.mjs` | Production entry point. Wires Firestore, Google auth, Play, AdMob and the HTTP server. |
| `app.mjs` | Router, maintenance and update gates, rate limits, error mapping, redacted logs. |
| `auth.mjs`, `tokens.mjs` | Registration, signed 15-minute sessions, rotating 90-day refresh tokens with reuse detection, Play Games linking and recovery, sign-out everywhere. |
| `players.mjs` | Player documents, the `mutate` transaction runner with the idempotency ledger, streaks, achievements, the public wallet view. |
| `economy.mjs` | Hints, themes, research, boosts, freezes, Fortune Wheel, crates, preferences, time zone. |
| `play.mjs` | Puzzle sessions, saved attempts, completion validation, Daily checkpoints, Time Attack runs. |
| `engine/` | JavaScript port of the Dart puzzle model, solver, generator and puzzle IDs. |
| `rewards.mjs` | AdMob SSV callbacks, reward sessions and server-chosen reward grants. |
| `purchases.mjs` | Play purchase verification, grants, consumption and acknowledgement, refund reversal, RTDN, Voided Purchases reconciliation. |
| `integrity.mjs` | Optional Play Integrity verdict checks. |
| `economy-config.mjs` | **The single authoritative table of prices, rewards and limits.** |

## API

All responses are JSON with `Cache-Control: no-store`. Authenticated routes take `Authorization: Bearer <session>`.

| Method and path | Auth | Purpose |
| --- | --- | --- |
| `GET /healthz` | – | Readiness |
| `GET /v1/ping` | – | Cheap reachability check used by the client heartbeat |
| `GET /v1/config` | – | Public economy configuration. Returns 426 below `PATHWISE_MIN_BUILD` |
| `GET /v1/auth/challenge` | – | Single-use challenge for Play Integrity |
| `POST /v1/auth/register` | – | New player and device |
| `POST /v1/auth/refresh` | refresh token | New session and rotated refresh token |
| `POST /v1/auth/link` | session | Link Play Games for recovery |
| `POST /v1/auth/recover` | Play Games code | Sign this device into the linked player |
| `POST /v1/auth/signout-all` | session | Revoke every device |
| `GET /v1/state` | session | Wallet and progression snapshot |
| `POST /v1/command` | session | `{op, type, args}` economy and play commands |
| `POST /v1/play/verify` | session | Verify and grant a Play purchase |
| `POST /v1/rewards/start/<placement>` | session | Reward session for an ad |
| `GET /v1/rewards/status/<id>` | session | Whether Google's callback arrived |
| `GET /v1/rewards/callback` | AdMob signature | SSV callback |
| `POST /v1/play/rtdn` | Pub/Sub OIDC | Real-time Developer Notifications |
| `POST /v1/play/reconcile` | Scheduler OIDC | Voided Purchases backstop |

Commands: `play.start`, `attempt.save`, `play.complete`, `attack.start|clear|finish|stop`, `hint.buy|use`, `theme.buy|equip`, `research.buy`, `boost.buy|activate`, `freeze.buy`, `wheel.free|settle`, `crate.poll|forfeit`, `reward.claim`, `tutorial.ack`, `prefs.set`, `timezone.set`. The development environment adds `dev.grant`.

## Guarantees

- **Idempotency.** Each command carries an operation ID. The first execution stores its result in `pathwise-ledger` inside the same transaction. A retry with the same ID and arguments replays that result. Reusing an ID for different arguments returns 409.
- **Atomicity.** A command reads the wallet, progress and ledger entry in one Firestore transaction and writes them together. Concurrent spends are serialized by Firestore's optimistic concurrency, so they cannot overdraw.
- **Server-defined values.** Prices, rewards, limits and prize odds come from `economy-config.mjs`. Client fields such as `reward`, `coins` or `price` are ignored.
- **Server time.** Cooldowns, daily limits, rolling windows, boost expiry and Time Attack deadlines use the server clock and the player's stored time-zone offset. The offset can change at most once a day.

## Tests

`npm --prefix backend test` runs these suites:

- The engine port against the published catalogue.
- Parity between `economy-config.mjs` and the Dart constants.
- Token signing.
- Authentication and recovery.
- Wallet commands, including concurrency and replay.
- Completion validation and Time Attack.
- Purchases, refunds and reconciliation.
- AdMob SSV.
- HTTP behaviour.

`testing/memory-db.mjs` is a transactional Firestore double. It rejects nested arrays and undefined values like Firestore does. `server.test.mjs` boots the real entry point when dependencies are installed.
