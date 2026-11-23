# Pathwise publisher setup

Application ID `games.tabletop.pathwise`. Public version `1.0.0`, repository code `4`. **Before upload**, inspect Play Console → App bundle explorer and every testing track. If any artifact has used code 4 or greater, pass `--build-number=HIGHEST_PLUS_ONE` to both release build commands. Play Console is the authority for upload history. The repository starts with external integrations disabled.

## 1. Before building

- [ ] Install Flutter 3.50.1 / Dart 3.14, Node.js 22+, JDK 21, Android SDK platform 36 and build tools 36, and NDK 28.2.13676358. Gradle wrapper 9.5 and AGP 9.3.1 are pinned. Accept SDK licenses using `flutter doctor --android-licenses`. Download `bundletool-all-1.18.3.jar` from the [official release](https://github.com/google/bundletool/releases/tag/1.18.3) and save it as `/secure/bundletool.jar` for the commands below.
- [ ] Copy `config/production.example.json` to a private external directory. Keep flags false for the first offline build. Android project IDs are public configuration, while the upload keystore, passwords, and server OAuth client secret belong outside the repository.
- [ ] In Play Console → All apps → Create app, choose Pathwise, the default language, Game, and the intended access model. Uploading the first matching bundle associates `games.tabletop.pathwise`. Enable Play App Signing from Test and release → Setup → App integrity. Preserve the production app ID and the upload key.
- [ ] Generate an independent upload key. Back it up with its password in separate protected storage.

```sh
keytool -genkeypair -v -keystore /secure/pathwise-upload.p12 -storetype PKCS12 \
  -alias pathwise-upload -keyalg RSA -keysize 2048 -validity 10000
export PATHWISE_KEYSTORE=/secure/pathwise-upload.p12
export PATHWISE_KEY_ALIAS=pathwise-upload
# Supply PATHWISE_STORE_PASSWORD and PATHWISE_KEY_PASSWORD from secure storage.
flutter clean
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
npm --prefix backend ci
npm --prefix backend test
flutter build apk --release --dart-define-from-file=/secure/pathwise-production.json
cp build/app/outputs/native-debug-symbols/release/native-debug-symbols.zip /secure/pathwise-symbols.zip
flutter build appbundle --release --dart-define-from-file=/secure/pathwise-production.json
python3 tool/prepare_play_bundle.py build/app/outputs/bundle/release/app-release.aab /secure/pathwise-play.aab
java -jar /secure/bundletool.jar validate --bundle=/secure/pathwise-play.aab
jarsigner -verify /secure/pathwise-play.aab
```

Expected package is `games.tabletop.pathwise`. Compare the APK certificate using `apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk`. Verify 16 KB zip alignment with `zipalign -c -P 16 4 build/app/outputs/flutter-apk/app-release.apk`. Run `python3 tool/verify_android_artifacts.py build/app/outputs/flutter-apk/app-release.apk /secure/pathwise-play.aab` to verify native libraries match. Archive the digest, mapping and private symbol zip. In Play Console → Test and release → App bundle explorer, select the version, then Downloads → Assets → Upload native debug symbols. R8 mapping remains embedded in the bundle. The slim bundle omits native symbol metadata and leaves the libraries in the Play-delivered app unchanged. Inspect `build/app/outputs/mapping/release/{mapping,usage,resources}.txt` for minification, removal evidence, and resource analysis. Never upload a locally generated verification key to production.

## 2. Before internal testing

- [ ] Test and release → Testing → Internal testing → Create new release. Accept the signing prompt, upload the signed AAB, add notes, review, and roll out the **internal** release.
- [ ] Internal testing → Testers → create an email list or add a Google Group. Open the opt-in URL while signed in with the tester account, then install from Play. Settings → License testing → add accounts that will exercise billing; installation-track and license-test access are separate.
- [ ] Verify fresh install, local save restart, airplane-mode gameplay, Time Attack process restart, crate collection, hint exhaustion, refill, Premium UI, edge-to-edge, large fonts, and theme contrast on a minified build. Review the merged-manifest permissions. If the account is subject to a closed-testing production-access requirement, complete the Play Console checklist shown for that account.

## 3. Before enabling purchases

Play Console → Monetize with Play → Products → One-time products. Create one purchase option per ID, set availability and localized prices, and activate the product and option. Disable multi-quantity and out-of-app purchases for this catalog. The UI displays the price returned by Play.

| ID | Type | Quantity or benefit | Proposed USD |
| --- | --- | --- | ---: |
| `pathwise_coins_500` | Consumable | 500 | 0.99 |
| `pathwise_coins_1250` | Consumable | 1,250 | 1.99 |
| `pathwise_coins_3000` | Consumable | 3,000 | 3.99 |
| `pathwise_coins_7500` | Consumable | 7,500 | 7.99 |
| `pathwise_coins_18000` | Consumable | 18,000 | 15.99 |
| `pathwise_remove_ads` | Non-consumable | Automatic ads removed | 3.99 |
| `pathwise_themes_forever` | Non-consumable | Current and future themes | 4.99 |
| `pathwise_premium` | Non-consumable | Both entitlements and 1,000 coins once | 6.99 |

### Cloud setup

- [ ] Use a billing-enabled Cloud project in an approved region. Console → APIs & Services → Library → enable Android Publisher API, Cloud Run, Firestore, Cloud Build, Artifact Registry and Secret Manager. Create a Firestore **Native** default database in the approved location.
- [ ] Create a runtime service account with `roles/datastore.user`. In Play Console → Users and permissions → Invite new users, add that account and grant **View financial data, orders, and cancellation survey responses** and **Manage orders and subscriptions** for Pathwise. Do not grant account-wide admin or publishing access. Avoid downloading service-account JSON. Cloud Run supplies application default credentials. Grant the deployer Cloud Run Developer and Service Account User on the runtime identity. Cloud Build needs permission to build source and write its Artifact Registry image.
- [ ] Create `pathwise-play-purchase-grants/readiness` in Firestore with boolean `enabled: true` only after configuration. Leave the document disabled during development.

```sh
gcloud config set project YOUR_PROJECT
gcloud services enable androidpublisher.googleapis.com firestore.googleapis.com run.googleapis.com \
  cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com
gcloud iam service-accounts create pathwise-runtime
gcloud projects add-iam-policy-binding YOUR_PROJECT \
  --member=serviceAccount:pathwise-runtime@YOUR_PROJECT.iam.gserviceaccount.com --role=roles/datastore.user
gcloud run deploy pathwise --source backend --region YOUR_REGION --allow-unauthenticated \
  --service-account pathwise-runtime@YOUR_PROJECT.iam.gserviceaccount.com \
  --max-instances=3 --set-env-vars=PATHWISE_PLAY_VERIFIER_ENABLED=true
curl -fsS https://YOUR_SERVICE/healthz
```

The backend requires Node 22+. Public ingress is required for Android and AdMob callbacks. Put production ingress behind a HTTPS load balancer with request-rate limits where abuse warrants it. Restrict direct ingress when using that setup. The service authenticates purchase and reward association with the installation credential. Play verifies purchase state and account binding before Firestore commits a receipt. Enable App Integrity only after deploying an integration that enforces it. The current client has no Play Integrity attestation.

- [ ] Expect health status `ready`, catalog protocol `2`, and the expected package. Set `PATHWISE_BILLING_VERIFY_URL` to `https://YOUR_SERVICE/v1/play/verify` and `PATHWISE_BILLING_ENABLED` to true in the external JSON. Until this passes, the app keeps purchase actions unavailable.
- [ ] In the license-test build verify approval, slow test card/pending, cancellation, offline return, force-stop after approval, retry, and Restore purchases. Expect no coins until verified, then one ledger entry and consumable availability again. Verify permanent entitlements remain after reload and Premium applies the bonus once. Refund a **test** order through Play Console → Order management and verify a fresh receipt check rejects the voided transaction. Previously redeemed balances are not automatically clawed back.
- [ ] Current recovery is limited to the original installation credential or Android backup. Full paid-balance synchronization, automatic reconciliation of refunds/voided orders, and recovery onto a new profile are unimplemented. Keep commercial billing disabled if these are required by your support policy.

Use a private copy of [the Cloud Run example](config/cloud-run.env.example.yaml) where production services share one deployment. Deploy it using `gcloud run deploy pathwise --source backend --region YOUR_REGION --env-vars-file=/secure/pathwise-cloud.yaml` with the same runtime account and ingress settings. Enable the `expiresAt` TTL field on `pathwise-play-rate` in Firestore → Time to live.

## 4. Before enabling advertisements

- [ ] AdMob → Apps → Add app → Android and associate Pathwise. Create distinct Banner, Interstitial, Rewarded Coins, Rewarded Hint Refill, and Rewarded Extra Hint units. Place the AdMob app ID in environment variable `PATHWISE_ADMOB_APP_ID` when building. Set the five corresponding `PATHWISE_ADMOB_*` fields in the JSON.
- [ ] For each rewarded unit, AdMob → Ad units → Advanced settings → Server-side verification. Set callback URL `https://YOUR_SERVICE/v1/rewards/callback`. In the Verify URL test, enter `pathwise-console-check` as custom data where available. A valid signed probe confirms connectivity without crediting a reward. Complete the full SDK and Firestore checks on an internal-track device. Deploy with `PATHWISE_REWARDS_ENABLED=true` and the exact same values for `PATHWISE_ADMOB_REWARDED`, `PATHWISE_ADMOB_HINT_REFILL`, and `PATHWISE_ADMOB_EXTRA_HINT` on Cloud Run. Set `PATHWISE_REWARD_URL` to the HTTPS service origin in the Android JSON. Enable Firestore TTL on `expiresAt` for `pathwise-ad-sessions`, `pathwise-ad-receipts`, and `pathwise-ad-rate`.
- [ ] AdMob → Privacy & messaging → publish applicable regional consent messages. Link the store listing's developer website to the root `https://YOUR_DOMAIN/app-ads.txt` with the publisher-specific line from AdMob → Apps → app-ads.txt. Confirm crawler status and app readiness.
- [ ] For debug/profile only, use `--dart-define=PATHWISE_ADS_TEST=true` for sample units and callback-only **test** credit. For internal release integration use configured production units with the device registered in AdMob → Settings → Test devices. Verify production IDs are distinct and that signed callbacks match their placement. Requests that fail verification earn no production reward. Confirm dismissal without reward earns nothing, restart after inactivity, and test all three reward flows. Confirm Remove Ads disables banners and automatic interstitials while preserving optional videos.
- [ ] Set `PATHWISE_ADS_ENABLED` and `PATHWISE_ADS_CONSENT_CONFIGURED` true only after accepting the consent and test checklist. Tighten ingress rate limits if unauthorized challenge creation appears. A missing callback, invalid signature, unavailable inventory, or offline network leaves the reward unavailable.

## 5. Before enabling Play Games

- [ ] Play Console → Grow users → Play Games Services → Setup and management → Configuration. Create the game project, associate Android package `games.tabletop.pathwise`, and add an Android OAuth credential using the **Play App Signing SHA-1** from App integrity. For a sideloaded build, add a separate credential for its signing certificate. Add tester accounts and publish the Play Games configuration when ready.
- [ ] Set the numeric project ID in environment variable `PATHWISE_GAMES_PROJECT_ID` at build. Set `PATHWISE_GAMES_ENABLED` true in the external JSON for an authorized test. To link the verified Play identity, add a server/Web OAuth credential to the PGS project. Set the client ID in Android `PATHWISE_GAMES_WEB_CLIENT_ID` and backend `PATHWISE_PGS_WEB_CLIENT_ID`. Store its client secret in Secret Manager and bind it to Cloud Run as `PATHWISE_PGS_WEB_CLIENT_SECRET` using `--set-secrets`. Give only the runtime identity `roles/secretmanager.secretAccessor` on that secret. Enable `games.googleapis.com`.
- [ ] Create one-time achievement definitions in Play Games Services → Achievements. Copy generated IDs into the JSON string map `PATHWISE_GAMES_ACHIEVEMENTS`. Keys are `trailhead`, `trailblazer`, `pathfinder`, `dailyHabit`, `weeklyRitual`, `unaided`, `collector`, `timeTrial`, `twentyFive`, `hundred`, `fiveHundred`, `thousand`, `researcher`, `legendaryCrate`. IDs are created by Google and are unavailable in this repository.
- [ ] Leaderboards → Create leaderboard. Use larger-is-better for Time Attack score and most puzzles solved, and smaller-is-better for a dedicated verified elapsed-time board. The JSON string map `PATHWISE_GAMES_LEADERBOARDS` maps display names to Google-generated IDs. The app opens native leaderboard screens **read-only**. Ranked submission, daily online seasons, move proofs, Play Integrity verification, and server-authoritative rankings are unimplemented. Do not advertise online competition until those services exist. Local Time Attack remains available offline.

## 6. Before publishing

- [ ] Grow users → Store presence → Main store listing. Upload the 512×512 [icon](docs/media/pathwise-play-icon.png), 1024×500 [feature graphic](docs/media/pathwise-feature-graphic.png), and real Play-tested gameplay screenshots. The [Play](docs/media/pathwise-play-preview.png), [puzzle](docs/media/pathwise-puzzle-preview.png), and [Research](docs/media/pathwise-research-preview.png) images are renders from Flutter widget tests. Choose category, listing copy, and support contact. Use native portrait screenshots showing actual puzzle, research, and cosmetics screens. The repository includes design assets, while actual device captures depend on an internal build.
- [ ] Policy and programs → App content. Provide a public HTTPS privacy policy and support contact. Complete Ads, Content rating, Target audience, Data safety, app access, and any account deletion obligations. Disclose SDKs and actual configured data flows. Ads, billing, puzzle activity and Play account linking can change disclosures. Review Google SDK data disclosures before submission. No telemetry export or hosted crash service is currently integrated.
- [ ] Test and release → Production → Create new release after Play grants access. Upload the validated publisher-signed `pathwise-play.aab`, review warnings, choose the release countries and rollout, and submit manually. This repository does not publish to Play.

## 7. Post-launch operations

- [ ] Observe Play Vitals, ANRs, crash clusters, refund trends, and test ongoing restore and consent. Upload/archive mapping and native symbols with each release. Keep an incident kill switch by disabling backend readiness or the corresponding flags for the next build.
- [ ] In Cloud Console → Billing → Budgets & alerts set a small launch budget and alerts at 50%, 80%, and 100%. A budget is an alert, not a spending cap. Monitor Cloud Run requests/CPU, Firestore requests and retained data, egress, and build/artifact storage. At low traffic the design uses zero minimum Cloud Run instances and may fit free quotas. Region, backup retention, and request volume determine actual charges. Example launch planning envelope is US$5–20/month before paid support capacity, not a quote.
- [ ] Configure Firestore scheduled backups and test restore in a separate project. Preserve purchase receipt records and deduplication keys. Set log redaction and short retention for diagnostic request data. Never log bearer headers, raw purchase tokens, OAuth codes, or signed callback query strings. Rotate server credentials and review workload IAM regularly.

Troubleshooting. A missing product usually points to inactive purchase options, account/track mismatch, a different package, or region availability. Disabled verifier health points to readiness document, runtime IAM, or ADC problems. For rewarded no-fill, verify consent, unit, test-device registration, and matching callback settings. Play Games sign-in failure often points to tester email, unpublished configuration, OAuth project, package or signing SHA-1 mismatch. If a reward never verifies, inspect receipt and session status by non-secret identifiers and verify Cloud Run ingress and Google key availability. Publishing is blocked on your account configuration, internal tests, and any unfinished capability you plan to market.

[Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756) · [Internal testing](https://support.google.com/googleplay/android-developer/answer/9845334) · [AdMob SSV](https://developers.google.com/admob/flutter/ssv) · [PGS v2 authentication](https://developer.android.com/games/pgs/android/android-signin) · [Cloud Run service identity](https://docs.cloud.google.com/run/docs/securing/service-identity)
