# Optional monetization

The default build exposes neither payment nor advertising actions. The app stays playable and the coin shop works offline. The SDKs are included and linked in release builds. A disabled AdMob build uses Google's sample manifest ID with delayed measurement initialization and does not issue requests through Pathwise. Never publish a flag-enabled build until service configuration is tested.

## Google Play

Create one-time products in Play Console for `games.tabletop.pathwise`. Localized prices are supplied by Play. Proposed US prices are starting points for equivalent prices in each market.

| Product ID | Fulfillment | Proposed US price |
| --- | --- | ---: |
| `pathwise_coins_500` | Starter, 500 coins | $0.99 |
| `pathwise_coins_1200` | Small, 1,200 coins | $1.99 |
| `pathwise_coins_3500` | Medium, 3,500 coins | $4.99 |
| `pathwise_coins_8000` | Large, 8,000 coins | $9.99 |
| `pathwise_coins_20000` | Mega, 20,000 coins | $19.99 |
| `pathwise_remove_ads` | Permanent removal of automatic ads | $3.99 |
| `pathwise_themes_forever` | All current and future themes | $4.99 |
| `pathwise_premium` | Both permanent entitlements and a one-time 1,000-coin bonus | $6.99 |

Coin packs are consumable. The last three products are non-consumable. The UI displays Play's localized prices. It explains overlap for existing owners without promising refunds or a prorated discount. Keep the three v1.1 coin IDs in the verifier to recover interrupted purchases. They are excluded from the new purchase catalog. Disable multi-quantity and out-of-app purchases.

Deploy `backend/` with Node 22+ using `npm ci --omit=dev` and `npm start`. The HTTPS endpoint must end in `/v1/play/verify`. Enable the Android Publisher API and provision a Firestore Native database. Use a workload identity with access to the Pathwise Play app's purchase lookup and scoped Firestore transaction permissions. Use the default application credential provider and keep keys outside the app and repository. Put the service behind HTTPS and rate limiting, restrict invoker ingress to your gateway where possible, and exclude bearer headers and token payloads from logs. Set `PATHWISE_PLAY_VERIFIER_ENABLED=true` on the backend and create the Firestore document `pathwise-play-purchase-grants/readiness` with boolean field `enabled: true` only after configuring Play access. Deploy the v1.2 verifier with catalog protocol 2. The app checks `/healthz` before offering or starting a purchase. Firestore grant records are durable deduplication state and must be backed up and retained.

The client sends a random installation credential and presents its SHA-256 digest to Play as the obfuscated account ID. The verifier calls Play's ProductPurchaseV2 endpoint and checks the package, state, product, quantity, remaining refundable quantity, and account binding. Firestore atomically claims the purchase token and returns the same grant on retries for its owner. The client records the verified grant and progress durably before consuming a pack or acknowledging an entitlement. Play handles payment UI and pending or canceled payments. The app does not grant funds from a callback alone.

Activate with `--dart-define=PATHWISE_BILLING_ENABLED=true` and `--dart-define=PATHWISE_BILLING_VERIFY_URL=https://your-host/v1/play/verify`. Use Play license testers to exercise pending, cancellation, retry after a network failure, consumption, and restoration on a minified internal build. Restoration supports owned items with the same billing profile, including a profile recovered with Android app-data backup. Paid coins that have already been consumed remain in the original local save. A new installation without that profile cannot recover prior purchases through this verifier. Before wide production rollout, provide support-assisted profile recovery and decide how to reconcile refunds for previously granted items while supporting offline play.

[Play purchase verification API](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2) · [Flutter billing plugin](https://pub.dev/packages/in_app_purchase)

## AdMob

For local test ads use a debug or profile build with `--dart-define=PATHWISE_ADS_TEST=true`. The flag is ignored in release builds. For production, create AdMob app and unit IDs, publish consent messages in Privacy & Messaging, and use the following values at build time.

- Environment variable `PATHWISE_ADMOB_APP_ID` for the Android SDK app ID.
- Dart defines `PATHWISE_ADS_ENABLED=true` and `PATHWISE_ADS_CONSENT_CONFIGURED=true`.
- Dart defines `PATHWISE_ADMOB_INTERSTITIAL` and `PATHWISE_ADMOB_REWARDED` with your production full-screen unit IDs, and `PATHWISE_ADMOB_BANNER` for anchored banners.

The Gradle configuration requires a production manifest app ID when ads are enabled. The Dart service checks the production full-screen units, the consent configuration flag, and regional UMP permission before loading. Banner inventory has its own unit. The SDK uses sample units only in opted-in debug/profile builds. The default release requests no ads.

| Placement | Policy |
| --- | --- |
| Adaptive bottom banner | Levels and standard/Time Attack puzzles with enough usable height. Anchored above system navigation. Unavailable units collapse. Remove Ads and Premium hide this placement. |
| Interstitial | After returning from a completed ordinary puzzle, when the return route is visible and the app is resumed. Five qualifying exits, a four-minute minimum interval, a one-minute in-process post-reward cooldown, and a persistent four-minute reservation/cooldown stamp. After a reboot, wait through the first four minutes of uptime if a prior stamp exists. No interstitial while drawing, during Time Attack, or on Next Level. |
| Rewarded hint | The player requests a hint after the three free hints. A completed reward callback and validated internet connection grant one extra hint to that board. Unavailable, incomplete, or offline videos grant nothing. Ad-free players use a six-coin alternative. |
| Rewarded coins | Optional in Cosmetics, including for ad-free owners. Eight coins per completed reward, up to three credited rewards per local day. |

Consent is initialized from a safe post-game exit, Settings, or an explicit video request. Privacy options invalidate the cache. Full-screen cached ads expire after 45 minutes. Test live consent geographies, interrupted ads, no-fill, banner layout across launchers and devices, and purchase recovery on a release-signed Play internal build before enabling commercial services. [AdMob UMP for Flutter](https://developers.google.com/admob/flutter/privacy) · [AdMob adaptive banners](https://developers.google.com/admob/flutter/banner)
