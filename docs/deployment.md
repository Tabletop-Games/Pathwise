# Backend deployment guide

This guide sets up the Pathwise game service on Google Cloud Run and Firestore. Nothing in this repository creates cloud resources by itself. Every command below runs only when you run it, and most create billable resources.

Placeholders in angle brackets, such as `<PROD_PROJECT_ID>`, are values you create or look up. None of them exist yet, and none are invented here.

## What is ready and what you must configure

| Area | State |
| --- | --- |
| Backend code: identity, sessions, wallet, progression, completion validation, Time Attack, Fortune Wheel, crates, AdMob SSV, Play Billing verification, refunds | Complete and covered by `npm --prefix backend test` against an in-memory Firestore double |
| Flutter client: connection service, connection screen and overlay, server-backed economy, server reward sessions, server purchase verification | Complete. Compiled and tested only by CI, because no Dart SDK was available when this was written |
| Google Cloud projects, Firestore databases, Cloud Run services, secrets, IAM | **You create them** (sections 2–6) |
| Play Console API access, RTDN topic, Voided Purchases polling | **You configure them** (section 7) |
| AdMob SSV callback URL | **You configure it** (section 8) |
| Play Games server-side access (account recovery) | **You configure it** (section 9) |
| Play Integrity | Server verification is implemented and off by default. The Android client does not request integrity tokens yet (section 10) |
| A deployed, working production backend | **Does not exist yet** |

## 1. Environments

Use two separate Google Cloud projects, so debug builds can never touch production wallets.

| | Production | Development |
| --- | --- | --- |
| App ID | `com.shenmareparas.pathwise` | `com.shenmareparas.pathwise.debug` |
| Cloud project | `<PROD_PROJECT_ID>` | `<DEV_PROJECT_ID>` |
| Cloud Run service | `pathwise-api-production` | `pathwise-api-development` |
| `PATHWISE_ENV` | `production` | `development` |
| Flutter `PATHWISE_API_BASE` | production service URL | development service URL |

The separation is enforced in three places:

- The server accepts registrations only from the package for its environment.
- Session tokens carry the environment, and the other environment rejects them.
- The app refuses a backend that reports a different environment. The app's environment follows the build mode and cannot be overridden: debug and profile builds are `development`, release builds are `production`.

The `dev.grant` command, which adds test coins, exists only when `PATHWISE_ENV=development`. Release builds contain no authentication bypass.

For local work, run the backend against the in-memory double through the tests (`npm --prefix backend test`). You can also run the Firestore emulator:

```sh
gcloud emulators firestore start --host-port=127.0.0.1:8085
# in another shell
cd backend
FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 GOOGLE_CLOUD_PROJECT=demo-pathwise \
PATHWISE_ENV=development PATHWISE_ONLINE_ENABLED=true \
PATHWISE_SESSION_KEYS="dev:$(openssl rand -hex 32)" npm start
```

To reach the local server from the Android emulator, build the app with `--dart-define=PATHWISE_API_BASE=http://10.0.2.2:8080`. Android blocks cleartext HTTP by default, so prefer the deployed development service over HTTPS.

## 2. Create the projects and enable APIs

Repeat this for each project:

```sh
gcloud projects create <PROJECT_ID>
gcloud billing projects link <PROJECT_ID> --billing-account=<BILLING_ACCOUNT_ID>
gcloud services enable --project <PROJECT_ID> \
  run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  firestore.googleapis.com secretmanager.googleapis.com \
  androidpublisher.googleapis.com playintegrity.googleapis.com \
  pubsub.googleapis.com cloudscheduler.googleapis.com \
  logging.googleapis.com monitoring.googleapis.com
```

## 3. Firestore

Create one Native-mode database per project, in the region you will use for Cloud Run:

```sh
gcloud firestore databases create --project <PROJECT_ID> --location=<REGION> --type=firestore-native
```

Deploy the deny-all client rules. Only the service account reads and writes, and IAM bypasses these rules. Install the Firebase CLI with `npm i -g firebase-tools`, then run:

```sh
cd backend/deploy
firebase deploy --project <PROJECT_ID> --only firestore:rules,firestore:indexes
```

No composite indexes are needed, because every read is a direct document get. `firestore.indexes.json` only disables indexing on large map fields to save write cost.

### Collections

| Collection | Document ID | Contents |
| --- | --- | --- |
| `pathwise-players` | player ID | Authoritative wallet: coins, hints, themes, entitlements, research, boosts, streak, wheel and crate state, reward counters, and the last 60 transactions |
| `pathwise-progress` | player ID | Results, Daily stages, highest unlocked level, tutorials, saved attempts, preferences, Time Attack runs |
| `pathwise-ledger` | `<player>.<operation id>` | One record per applied command: kind, argument hash, result and transaction entries. Provides idempotency and the recoverable ledger |
| `pathwise-devices` | device ID | Hashed rotating refresh token and session epoch |
| `pathwise-games-accounts` | hash of the Play Games player ID | The owning player, for recovery |
| `pathwise-play-purchase-grants` | hash of the package and purchase token | The owning player, product, `finalized` and `voided` |
| `pathwise-ad-sessions` | random 64-hex ID | Reward session: player, ad unit, placement, receipt, `claimed` |
| `pathwise-ad-receipts` | hash of the AdMob transaction ID | Callback deduplication |
| `pathwise-rate` | `<scope>.<key>` | Durable rate-limit windows |
| `pathwise-challenges` | hash of the challenge | Single-use registration challenges |
| `pathwise-system` | `voided-cursor`, `health` | Reconciliation cursor and health probe |

### TTL policies

These collections hold an `expiresAt` timestamp. Enable TTL on each, once per project:

```sh
for c in pathwise-rate pathwise-ad-sessions pathwise-ad-receipts pathwise-devices pathwise-challenges; do
  gcloud firestore fields ttls update expiresAt --collection-group="$c" --enable-ttl --project <PROJECT_ID>
done
```

`pathwise-ledger` and `pathwise-play-purchase-grants` have no TTL, because they are the recoverable record.

### Backups

Turn on point-in-time recovery and daily backups:

```sh
gcloud firestore databases update --project <PROJECT_ID> --database='(default)' --enable-pitr
gcloud firestore backups schedules create --project <PROJECT_ID> --database='(default)' \
  --recurrence=daily --retention=14d
```

To recover, restore a backup into a new database with `gcloud firestore databases restore`, check it, then point the service at it.

## 4. Service accounts and IAM

The service runs as a dedicated identity with only the roles it needs:

```sh
gcloud iam service-accounts create pathwise-api --project <PROJECT_ID> --display-name "Pathwise API"
SA=pathwise-api@<PROJECT_ID>.iam.gserviceaccount.com
gcloud projects add-iam-policy-binding <PROJECT_ID> --member "serviceAccount:$SA" --role roles/datastore.user
gcloud projects add-iam-policy-binding <PROJECT_ID> --member "serviceAccount:$SA" --role roles/logging.logWriter
gcloud projects add-iam-policy-binding <PROJECT_ID> --member "serviceAccount:$SA" --role roles/monitoring.metricWriter
```

Secret access is granted per secret in section 5. Do not create or download a key for this account. Cloud Run supplies its credentials.

For Pub/Sub push and Cloud Scheduler, create one invoker identity:

```sh
gcloud iam service-accounts create pathwise-push --project <PROJECT_ID>
```

`/v1/play/rtdn` and `/v1/play/reconcile` check its Google-signed OIDC token, including the audience and the email address.

## 5. Secrets

```sh
# Session signing keys, as "kid:secret[,kid2:secret2]". The first key signs; every listed key verifies.
printf 'k1:%s' "$(openssl rand -hex 32)" | gcloud secrets create pathwise-session-keys --project <PROJECT_ID> --data-file=-
# Play Games OAuth web client secret (section 9). Use a placeholder until then.
printf '%s' '<PGS_WEB_CLIENT_SECRET>' | gcloud secrets create pathwise-pgs-web-client-secret --project <PROJECT_ID> --data-file=-
for s in pathwise-session-keys pathwise-pgs-web-client-secret; do
  gcloud secrets add-iam-policy-binding "$s" --project <PROJECT_ID> \
    --member "serviceAccount:pathwise-api@<PROJECT_ID>.iam.gserviceaccount.com" --role roles/secretmanager.secretAccessor
done
```

To rotate the signing key, add a new version `k2:<new>,k1:<old>`, deploy, wait at least 15 minutes (the session lifetime), then remove `k1`.

## 6. Deploy Cloud Run

Copy `backend/deploy/env.<environment>.example.yaml` outside the repository and fill it in. Leave `PATHWISE_ONLINE_ENABLED: 'false'` for the first deploy.

```sh
PROJECT_ID=<PROJECT_ID> REGION=<REGION> ENVIRONMENT=production \
ENV_FILE=/secure/pathwise-backend.production.yaml backend/deploy/deploy.sh
```

The script sets:

- 0 to 10 instances (`MAX_INSTANCES` overrides the maximum).
- Concurrency 40.
- 1 vCPU and 512 MiB.
- A 30-second request timeout.
- Startup CPU boost.

Access is public (`--allow-unauthenticated`), because players authenticate with Pathwise sessions rather than Google IAM. The server also enforces:

- 15-second request and 10-second header timeouts.
- Body limits of 1–16 KB per endpoint.
- Per-address and per-player limits in memory.
- Durable Firestore limits on registration, linking and recovery.

Verify the deployment:

```sh
URL=$(gcloud run services describe pathwise-api-production --project <PROJECT_ID> --region <REGION> --format 'value(status.url)')
curl -fsS "$URL/healthz"        # 503 {"status":"disabled"} while PATHWISE_ONLINE_ENABLED is false
```

Set `PATHWISE_ONLINE_ENABLED: 'true'`, redeploy, then check:

```sh
curl -fsS "$URL/healthz"        # 200 {"status":"ready","env":"production",...}
curl -fsS "$URL/v1/config"      # public economy configuration
```

Build the app against it. The `PATHWISE_BUILD` value must match the version code:

```sh
flutter build appbundle --release --dart-define-from-file=/secure/pathwise-production.json \
  --dart-define=PATHWISE_API_BASE="$URL" --dart-define=PATHWISE_BUILD=<VERSION_CODE>
```

Set `PATHWISE_MIN_BUILD` to the lowest version code you still accept. Older builds then see the Update screen.

## 7. Google Play Billing

1. In Play Console → Setup → API access, link `<PROD_PROJECT_ID>`. Invite `pathwise-api@<PROD_PROJECT_ID>.iam.gserviceaccount.com` under Users and permissions, with **View financial data** and **Manage orders and subscriptions** for Pathwise only.
2. Keep the eight product IDs unchanged. In the app, purchases carry `obfuscatedAccountId` set to the player's billing account. The server rejects a purchase made for a different player.
3. Set up Real-time Developer Notifications:
   ```sh
   gcloud pubsub topics create play-rtdn --project <PROD_PROJECT_ID>
   gcloud pubsub topics add-iam-policy-binding play-rtdn --project <PROD_PROJECT_ID> \
     --member serviceAccount:google-play-developer-notifications@system.gserviceaccount.com --role roles/pubsub.publisher
   gcloud pubsub subscriptions create play-rtdn-push --project <PROD_PROJECT_ID> --topic play-rtdn \
     --push-endpoint "$URL/v1/play/rtdn" \
     --push-auth-service-account pathwise-push@<PROD_PROJECT_ID>.iam.gserviceaccount.com \
     --push-auth-token-audience "$URL/v1/play/rtdn" --ack-deadline 30
   ```
   In Play Console → Monetize with Play → Monetization setup, set the topic to `projects/<PROD_PROJECT_ID>/topics/play-rtdn` and send a test notification. Set `PATHWISE_RTDN_AUDIENCE="$URL/v1/play/rtdn"` and `PATHWISE_RTDN_SERVICE_ACCOUNT=pathwise-push@<PROD_PROJECT_ID>.iam.gserviceaccount.com`.
4. Add the Voided Purchases backstop. It runs hourly and catches refunds whose notification was missed:
   ```sh
   gcloud scheduler jobs create http pathwise-reconcile --project <PROD_PROJECT_ID> --location <REGION> \
     --schedule "17 * * * *" --http-method POST --uri "$URL/v1/play/reconcile" \
     --oidc-service-account-email pathwise-push@<PROD_PROJECT_ID>.iam.gserviceaccount.com \
     --oidc-token-audience "$URL/v1/play/reconcile" --headers Content-Type=application/json --message-body '{}'
   ```
   Set `PATHWISE_RECONCILE_AUDIENCE` and `PATHWISE_RECONCILE_SERVICE_ACCOUNT` to match.
5. In the app config, set `PATHWISE_BILLING_ENABLED=true`. With the server present, iOS purchases stay off until an App Store server verifier exists.

### Purchase flow

1. The client sends the product and token to `/v1/play/verify`.
2. The server confirms with Google: purchased, one unit, matching product and matching account.
3. In one transaction, the server creates the grant and credits coins or sets the entitlement.
4. The server consumes or acknowledges the purchase.

A repeated token returns the same grant, and Premium's 1,000-coin bonus is recorded once per player. A refund reverses coins, entitlements and the Premium bonus once. The balance can go negative, and the player cannot spend until it is positive again.

## 8. AdMob server-side verification

1. In AdMob → Apps → Pathwise → Ad units, open each rewarded unit (coins, extra hint, wheel). Under Server-side verification, set the callback URL to `$URL/v1/rewards/callback`. Click **Verify URL**: the server answers the signed console probe with `{"verified":true,"probe":true}`.
2. Copy the unit IDs into `PATHWISE_ADMOB_REWARDED`, `PATHWISE_ADMOB_EXTRA_HINT` and `PATHWISE_ADMOB_WHEEL`, then set `PATHWISE_REWARDS_ENABLED=true`. The three units must be different.
3. For the development project, use Google's test units. Their callbacks are not delivered to your server, so verified development rewards need real units in test mode.

### Reward flow

1. The app asks `/v1/rewards/start/<placement>` for a session. The server checks the daily limits with its own clock.
2. The app attaches the session ID to the ad as SSV custom data.
3. After the video, Google calls the callback. The signature, ad unit and time window are checked, and the transaction ID is deduplicated.
4. The app polls the status, then sends `reward.claim`. The server re-checks the limits and grants the fixed reward.

Wheel and crate prizes are chosen on the server.

## 9. Play Games account recovery

1. In Google Cloud → APIs & Services → Credentials (production project), create an OAuth client of type **Web application** for Play Games server-side access.
2. In Play Console → Play Games Services → Configuration → Credentials, add that web client as a **Game server** credential.
3. Put its client ID in `PATHWISE_PGS_WEB_CLIENT_ID` (backend env and app `--dart-define`). Store its secret in `pathwise-pgs-web-client-secret`.

Players link from Settings → Back up with Google Play Games. On a new device, or after a revoked session, the connection screen offers **Restore with Google Play Games**. Unlinked players keep a device-bound profile: reinstalling without a link starts a new profile. Android backup is disabled (`allowBackup="false"`), so refresh tokens are not copied to other devices.

## 10. Play Integrity (evaluation)

The server verifies classic Play Integrity tokens at registration and recovery when `PATHWISE_INTEGRITY_REQUIRED=true`. It checks:

- The package name.
- A single-use nonce derived from a server challenge.
- A timestamp within 5 minutes.
- `PLAY_RECOGNIZED`.
- `MEETS_DEVICE_INTEGRITY`.
- Optionally, the signing-certificate digest.

The Android client does not yet request integrity tokens, so leave this off. Enabling it now would make the app show "Couldn't verify this device". To adopt it:

1. Link the Cloud project under Play Console → App integrity.
2. Add a native integrity request using the challenge's `nonce`.
3. Enable it on the development backend first, and measure false rejections before production.

Integrity raises the cost of scripted abuse. It does not make the game impossible to cheat.

## 11. Logging, monitoring and cost

- Request logs are structured JSON (`operation`, `status`, `durationMs`) and never include tokens, bodies or callback query strings.
- Create log-based alerts in Cloud Monitoring:
  - 5xx rate above 2% over 5 minutes.
  - Any `severity=ERROR`.
  - `/v1/play/reconcile` not seen for 3 hours.
- Create a budget with alerts at 50%, 90% and 100% in Billing → Budgets & alerts, scoped to each project.
- Typical cost per active player-session, from the access patterns in the code:
  - Startup is a session refresh (2 reads, 1 write), a state load (2 reads) and one time-zone command. The config request does not touch Firestore.
  - Each puzzle is 2 commands of 3 reads and 2–3 writes each.
  - A saved route is debounced to at most one write every 5 seconds of play, and only between strokes.
  - The 15-second reachability ping does not touch Firestore.

## 12. Launch checklist

- [ ] Both projects created; Firestore rules, TTL, PITR and backups configured.
- [ ] Secrets created and bound; the service deploys and `/healthz` reports `ready`.
- [ ] Debug build against development: register, play, resume on a second device after linking Play Games, disconnect mid-puzzle, reconnect.
- [ ] Billing test purchases with license testers: pending, cancel, coin pack, each permanent product, reinstall and restore, refund in Play Console followed by RTDN and reconcile.
- [ ] AdMob SSV on internal-test builds: each placement grants once, daily limits hold, a dismissed video grants nothing.
- [ ] Alerts and budget active.
