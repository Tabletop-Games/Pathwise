# Pathwise publisher setup

Application ID `com.shenmareparas.pathwise`. Public version `1.0.0`, repository code `8`. **Before upload**, inspect Play Console → App bundle explorer and every testing track. If any artifact has used code 8 or greater, pass `--build-number=HIGHEST_PLUS_ONE` to both release build commands. Play Console is the authority for upload history. The repository starts with external integrations disabled.

## 1. Before building

- [ ] Install Flutter 3.50.1 / Dart 3.14, Node.js 22+, JDK 21, Android SDK platform 36 and build tools 36, and NDK 28.2.13676358. Gradle wrapper 9.5 and AGP 9.3.1 are pinned. Accept SDK licenses using `flutter doctor --android-licenses`. Download `bundletool-all-1.18.3.jar` from the [official release](https://github.com/google/bundletool/releases/tag/1.18.3) and save it as `/secure/bundletool.jar` for the commands below.
- [ ] Copy `config/production.example.json` to a private external directory. Keep flags false for the first build. Every build needs `PATHWISE_API_BASE` pointing at a deployed backend of the matching environment ([deployment](docs/deployment.md)); without it the app shows its connection screen. Android project IDs are public configuration, while the upload keystore and passwords belong outside the repository.
- [ ] In Play Console → All apps → Create app, choose Pathwise, the default language, Game, and the intended access model. Uploading the first matching bundle associates `com.shenmareparas.pathwise`. Enable Play App Signing from Test and release → Setup → App integrity. Preserve the production app ID and the upload key.
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

Expected package is `com.shenmareparas.pathwise`. Compare the APK certificate using `apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk`. Verify 16 KB zip alignment with `zipalign -c -P 16 4 build/app/outputs/flutter-apk/app-release.apk`. Run `python3 tool/verify_android_artifacts.py build/app/outputs/flutter-apk/app-release.apk /secure/pathwise-play.aab` to verify native libraries match. Archive the digest, mapping and private symbol zip. In Play Console → Test and release → App bundle explorer, select the version, then Downloads → Assets → Upload native debug symbols. R8 mapping remains embedded in the bundle. The slim bundle omits native symbol metadata and leaves the libraries in the Play-delivered app unchanged. Inspect `build/app/outputs/mapping/release/{mapping,usage,resources}.txt` for minification, removal evidence, and resource analysis. Never upload a locally generated verification key to production.

## 2. Before internal testing

- [ ] Test and release → Testing → Internal testing → Create new release. Accept the signing prompt, upload the signed AAB, add notes, review, and roll out the **internal** release.
- [ ] Internal testing → Testers → create an email list or add a Google Group. Open the opt-in URL while signed in with the tester account, then install from Play. Settings → License testing → add accounts that will exercise billing; installation-track and license-test access are separate.
- [ ] Verify fresh install, the connection screen in airplane mode, connection loss and resumption mid-puzzle, restore on a second device after linking Play Games, Time Attack process restart, level replays, and route and milestone recovery after force-stop, crate collection, hint spending and acquisition, Premium UI, edge-to-edge, large fonts, and theme contrast on a minified build. Review the merged-manifest permissions. If the account is subject to a closed-testing production-access requirement, complete the Play Console checklist shown for that account.

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

### Checkout and restore

- [ ] Google Play Console → Monetize with Play → Monetization setup → Licensing. Copy the Base64 RSA public key into `PATHWISE_PLAY_BILLING_PUBLIC_KEY` in the build JSON. It is a public verification key. Set `PATHWISE_BILLING_ENABLED` after adding license testers and confirming test purchases.
- [ ] For iOS, use macOS with Xcode and the same Flutter SDK. Open `ios/Runner.xcworkspace` and select your signing team. In App Store Connect → Apps → Pathwise → Monetization → In-App Purchases, create the same consumable and non-consumable product IDs. Use the App Store sandbox and validate with `flutter build ios --no-codesign` before producing a signed archive. Confirm sandbox purchases and Restore Purchases on a signed device build.
- [ ] Exercise approval, pending payment, cancellation, app interruption before fulfillment, and restoration. Verify one ledger entry for a consumable and one lifetime premium bonus per save. The app validates a Play purchase signature or a verified StoreKit 2 transaction before persisting a grant and finishing it. Device-side checks offer limited resistance to a modified client. Consumed coins cannot be reconstructed from the store after save loss. Refunds and revocations do not automatically reconcile the wallet.

## 4. Before enabling advertisements

The [build configuration template](config/production.example.json) contains the Android App ID `ca-app-pub-7623640820680894~1301071315` and all five Android ad units. Gradle reads the App ID from the build JSON or the `PATHWISE_ADMOB_APP_ID` environment override. Release uses the configured App ID, and debug/profile use Google's sample App ID.

| Format | Uses | Build key |
| --- | --- | --- |
| Rewarded | Coins, Supply Crates, Boosts | `PATHWISE_ADMOB_REWARDED` |
| Rewarded | Hints | `PATHWISE_ADMOB_EXTRA_HINT` |
| Rewarded | Fortune Wheel | `PATHWISE_ADMOB_WHEEL` |
| Anchored adaptive banner | Level selection and standard puzzles | `PATHWISE_ADMOB_BANNER` |
| Interstitial | Qualifying completed puzzle exits | `PATHWISE_ADMOB_INTERSTITIAL` |

- [ ] In AdMob → Apps → Pathwise, confirm all five Android units belong to this app. For iOS create separate units, populate the `PATHWISE_ADMOB_IOS_*` fields, and create ignored `ios/Flutter/AdMob.local.xcconfig` with `PATHWISE_ADMOB_IOS_APP_ID = YOUR_IOS_APP_ID`.
- [ ] In AdMob → Privacy & messaging, publish the applicable regional consent messages for Pathwise. Verify the app's privacy policy and Play Console disclosures. Link the developer website and confirm the `app-ads.txt` crawler status and AdMob app readiness.
- [ ] Build a local test APK with Google's sample ad units. Complete the five reward flows, and test cancellation, no fill, offline behavior, and repeated callbacks. Remove Ads must suppress automatic ads and leave opt-in videos available.

```sh
flutter build apk --debug --dart-define=PATHWISE_ADS_TEST=true
```

- [ ] With the signed credentials from section 1 and both ad-serving flags still false in the copied JSON, build a consent-only Android APK. On an authorized Android device, open Settings → Ad privacy. Verify the applicable first-run consent form and the privacy choices form in a region where AdMob requires them. Confirm the app remains usable after a refusal and when offline. This build can call UMP using the production App ID and blocks Mobile Ads SDK initialization and ad loads.

```sh
flutter build apk --release --dart-define-from-file=/secure/pathwise-production.json \
  --dart-define=PATHWISE_ADS_VERIFY_CONSENT=true
```

- [ ] After validating the published UMP setup, set `PATHWISE_ADS_CONSENT_CONFIGURED` and `PATHWISE_ADS_ENABLED` to `"true"` in the copied JSON. Omit `PATHWISE_ADS_VERIFY_CONSENT` in the serving build. Register authorized devices under AdMob → Settings → Test devices before loading any ads from a signed release candidate. Use internal distribution and confirm that ads are marked as tests. A release with any missing, duplicate, invalid, or Google sample Android unit stays disabled.
- [ ] Build the signed release artifacts with the approved configuration. Continue to the artifact validation and packaging steps in section 1.

```sh
flutter build apk --release --dart-define-from-file=/secure/pathwise-production.json
flutter build appbundle --release --dart-define-from-file=/secure/pathwise-production.json
```

Reward delivery uses the SDK earned callback and a local deduplicated transaction for its specific placement. Wheel counters use a rolling 24-hour window and survive restarts. Advertising uses no publisher callback URL.

## 5. Before enabling Play Games

- [ ] Play Console → Grow users → Play Games Services → Setup and management → Configuration. Create the game project, associate Android package `com.shenmareparas.pathwise`, and add an Android OAuth credential using the **Play App Signing SHA-1** from App integrity. For a sideloaded build, add a separate credential for its signing certificate. Add tester accounts and publish the Play Games configuration when ready.
- [ ] Set the numeric project ID in environment variable `PATHWISE_GAMES_PROJECT_ID` at build. Set `PATHWISE_GAMES_ENABLED` true in the external JSON for an authorized test.
- [ ] Create or bulk-import the 29 Standard, Incremental and Hidden definitions. Add Google's resource IDs to the external `PATHWISE_GAMES_ACHIEVEMENTS` JSON-string field. Follow the [inventory, import command, signing and verification instructions](docs/google-play-achievements.md) and use the [mapping template](config/play-games-achievements.example.json).
- [ ] On a Play-certified Android device with the authorized tester account, confirm native sign-in, the native achievements activity, standard unlock, incremental steps, hidden state, offline restart, reconnection, account switching, and readback on a second device.
- [ ] Optional leaderboards: create separate Time Attack score boards for 1, 3, and 5 minutes. Map each assigned ID in `PATHWISE_GAMES_LEADERBOARDS` with the exact keys `Time Attack · 1 min`, `Time Attack · 3 min`, and `Time Attack · 5 min`. After an unassisted completed run, submit from the results screen. Existing local personal bests remain independent. This is native, client-side submission without server adjudication.
- [ ] Retire any discontinued mode achievements created for internal testing. Existing native achievement progress and authentication do not require a custom backend.
- [ ] On the same Android build, finish a Daily Challenge and Time Attack. Open each Share action. Check WhatsApp or WhatsApp Business, X, LinkedIn and Telegram, installed and absent where possible. Verify More Apps, Copy Message and Copy Link. LinkedIn requires pasting the prepared caption. The canonical [Play Store link](https://play.google.com/store/apps/details?id=com.shenmareparas.pathwise) may resolve only for testers before launch. [Sharing behavior](docs/social-sharing.md)

## 6. Before publishing

- [ ] Grow users → Store presence → Main store listing. Upload the 512×512 [icon](docs/media/pathwise-play-icon.png), 1024×500 [feature graphic](docs/media/pathwise-feature-graphic.png), and real Play-tested gameplay screenshots. The [Play](docs/media/pathwise-play-preview.png), [puzzle](docs/media/pathwise-puzzle-preview.png), and [Research](docs/media/pathwise-research-preview.png) images are renders from Flutter widget tests. Choose category, listing copy, and support contact. Use native portrait screenshots showing actual puzzle, research, and cosmetics screens. The repository includes design assets, while actual device captures depend on an internal build.
- [ ] Policy and programs → App content. Provide a public HTTPS privacy policy and support contact. Complete Ads, Content rating, Target audience, Data safety, app access, and any account deletion obligations. Disclose SDKs and actual configured data flows. Ads, billing, puzzle activity and Play account linking can change disclosures. Review Google SDK data disclosures before submission. No telemetry export or hosted crash service is currently integrated.
- [ ] Test and release → Production → Create new release after Play grants access. Upload the validated publisher-signed `pathwise-play.aab`, review warnings, choose the release countries and rollout, and submit manually. This repository does not publish to Play.

## 7. Post-launch operations

- [ ] Observe Play Vitals, ANRs, crash clusters, refund trends, and test ongoing restore and consent. Upload/archive mapping and native symbols with each release. Keep an incident kill switch by disabling the corresponding flags for the next build.
- [ ] In Cloud Console → Billing → Budgets & alerts set a small launch budget and alerts at 50%, 80%, and 100%. A budget is an alert, not a spending cap. Monitor Cloud Run requests/CPU, Firestore requests and retained data, egress, and build/artifact storage. At low traffic the design uses zero minimum Cloud Run instances and may fit free quotas. Region, backup retention, and request volume determine actual charges. Example launch planning envelope is US$5–20/month before paid support capacity, not a quote.
- [ ] Keep Play and App Store reporting enabled and review refund and purchase recovery reports. Earlier backend deployments are independent of this client release.

Troubleshooting. A missing product usually points to inactive purchase options, account/track mismatch, a different package, or region availability. Disabled verifier health points to readiness document, runtime IAM, or ADC problems. For rewarded no-fill, verify consent, unit, test-device registration, and matching callback settings. Play Games sign-in failure often points to tester email, unpublished configuration, OAuth project, package or signing SHA-1 mismatch. If a reward never verifies, inspect receipt and session status by non-secret identifiers and verify Cloud Run ingress and Google key availability. Publishing is blocked on your account configuration, internal tests, and any unfinished capability you plan to market.

[Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756) · [Internal testing](https://support.google.com/googleplay/android-developer/answer/9845334) · [AdMob rewarded ads](https://developers.google.com/admob/flutter/rewarded) · [PGS v2 authentication](https://developer.android.com/games/pgs/android/android-signin) · [Cloud Run service identity](https://docs.cloud.google.com/run/docs/securing/service-identity)

## Android identity migration

The Android ID `com.shenmareparas.pathwise` is a new Play application and a separate Android sandbox from `games.tabletop.pathwise`. Android will not transfer local progression, balances, hints, themes, settings, transactions, or entitlements. No supported cross-app export/import is documented here; do not uninstall or clear the old app expecting its data to move. Prior Play purchases cannot be assumed restorable in the new app.

Create the new Play Console app, recreate all eight existing product IDs, configure testing and obtain its own Play licensing public key. Configure Play Games and OAuth credentials for the new package and appropriate signing certificates. Update and deploy the backend's package association and Google Play API permissions separately; do not assume old receipt records or claims migrate. Keep the existing signing key secure.

Review AdMob's current app and ad-unit associations for the new Play app. Create a new AdMob app and corresponding units if required by AdMob's current setup, then use its actual IDs through the existing build flags. The historical IDs are not verified for the new package. Complete UMP consent setup before setting `PATHWISE_ADS_CONSENT_CONFIGURED=true`; validate test ads before enabling production. The new Play Store link may not resolve until the listing is available.

For release builds, launch with `adb -s emulator-5554 shell am start -n com.shenmareparas.pathwise/.MainActivity` and stop with `adb -s emulator-5554 shell am force-stop com.shenmareparas.pathwise`.

### Side-by-side debug installation

Debug builds use `com.shenmareparas.pathwise.debug` and display **Pathwise Debug**. Release builds retain `com.shenmareparas.pathwise` and **Pathwise**. They have separate application data; neither installation replaces the other. The activity class remains `com.shenmareparas.pathwise.MainActivity`. Debug builds are not the Play production application and should not be used to verify production purchases.

```bash
cd ~/dev/Pathwise
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
flutter pub get && \
flutter build apk --debug --dart-define=PATHWISE_ADS_TEST=true && \
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk && \
adb -s emulator-5554 shell am force-stop com.shenmareparas.pathwise.debug && \
adb -s emulator-5554 shell am start -n com.shenmareparas.pathwise.debug/com.shenmareparas.pathwise.MainActivity
```

For hot reload: `flutter run -d emulator-5554 --debug --dart-define=PATHWISE_ADS_TEST=true`. Debug ads use test units; production ads and billing retain their existing release configuration.
