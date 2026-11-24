# Security

Pathwise is online-first. The backend is the trust boundary for identity, balances, prices, rewards, limits, progression and purchases. The client is treated as untrusted. See [online architecture](online-architecture.md), [backend](backend.md) and [deployment](deployment.md).

## Identity and sessions

- The server creates player IDs. The client holds a device refresh token, which is a server-issued random secret stored only as a hash. The token rotates on every use. Reusing a rotated-out token after a 2-minute grace window revokes that device.
- Sessions are HMAC-signed, expire after 15 minutes, and are bound to the environment and app package. Signing keys live in Secret Manager and can be rotated.
- The player ID always comes from the verified session. No request parameter or body field can select another player.
- Account recovery uses a one-time Play Games server code that the server exchanges with Google for the verified player ID. Each Play Games account maps to one player.
- Sign-out everywhere increments a session epoch, which every transaction checks.
- Android backup is disabled so refresh tokens are not cloned to other devices.

## Economy

- Commands run in Firestore transactions that read and write the wallet, progress and idempotency ledger together. Concurrent spends cannot overdraw, and a replayed operation ID returns the stored result.
- Prices, rewards, odds and limits come from `backend/economy-config.mjs`. Client-supplied amounts are ignored.
- Cooldowns and daily limits use server time. The stored time-zone offset can change once a day, so the device clock and time-zone tricks gain nothing.
- Completion submissions are replayed against the regenerated board and must be legal, unlocked, started and plausibly timed. The solver ships in the client, so this proves a valid solution, not that a person solved it. Leaderboards should be treated with that in mind.

## Purchases and ads

- Play purchases are checked with the Play Developer API for state, quantity, product and the obfuscated account ID, which ties each purchase to one player. Grants are keyed by the hashed purchase token, so a token credits once. The purchase is consumed or acknowledged only after the grant commits.
- Refunds arrive by RTDN, with hourly Voided Purchases polling as a backstop. Each reversal is applied once and can leave a negative balance.
- An AdMob reward needs a server-issued session ID in SSV custom data, a valid Google signature over the exact callback bytes, the matching ad unit, a fresh timestamp and an unused transaction ID. It is then claimed by its owner inside the same daily limits.

## Infrastructure

- Firestore rules deny all client access. Only the Cloud Run service account, with `roles/datastore.user`, reads or writes.
- No service-account key is created. Cloud Run supplies credentials. Secrets are kept in Secret Manager.
- Push endpoints accept only Google-signed OIDC tokens for the configured audience and account.
- Request bodies are capped at 1–16 KB. Rate limits apply per address and per player, with durable limits on registration, linking and recovery.
- Logs omit bearer values, refresh tokens, purchase tokens, OAuth codes and callback query strings.

## Limits

These measures make cheating harder; they do not make Pathwise impossible to hack. A modified client can still solve puzzles automatically within the timing bounds. Play Integrity verification is implemented on the server but not yet wired into the client (see [deployment](deployment.md#10-play-integrity-evaluation)). Pathwise does not detect or block VPNs, DNS filters or privacy tools.
