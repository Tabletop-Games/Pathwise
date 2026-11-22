# Optional monetization

The default build exposes neither payment nor advertising actions. The app stays playable and the coin shop works offline. The SDKs are included and linked in release builds. A disabled AdMob build uses Google's sample manifest ID with delayed measurement initialization and does not issue requests through Pathwise. Never publish a flag-enabled build until service configuration is tested.

## Google Play

Create one-time products in Play Console for `games.tabletop.pathwise`. Localized prices are supplied by Play. Proposed US prices are starting points for equivalent prices in each market.

| Product ID | Fulfillment | Proposed US price |
| --- | --- | ---: |
| `pathwise_coins_120` | 120 coins, consumable | $0.99 |
| `pathwise_coins_340` | 340 coins, consumable | $2.49 |
| `pathwise_coins_800` | 800 coins, consumable | $4.99 |
| `pathwise_themes_forever` | Permanent all-theme pass | $3.99 |

The pass is about 43% less than the least proposed pack spend ($6.97) needed to buy all six premium themes with paid coins alone. Disable multi-quantity and out-of-app purchases for these products.

Deploy `backend/` with Node 22+ using `npm ci --omit=dev` and `npm start`. The HTTPS endpoint must end in `/v1/play/verify`. Enable the Android Publisher API and provision a Firestore Native database. Use a workload identity with access to the Pathwise Play app's purchase lookup and scoped Firestore transaction permissions. Use the default application credential provider and keep keys outside the app and repository. Put the service behind HTTPS and rate limiting, restrict invoker ingress to your gateway where possible, and exclude bearer headers and token payloads from logs. Set `PATHWISE_PLAY_VERIFIER_ENABLED=true` on the backend and create the Firestore document `pathwise-play-purchase-grants/readiness` with boolean field `enabled: true` only after configuring Play access. The app checks `/healthz` before offering or starting a purchase. Firestore grant records are durable deduplication state and must be backed up and retained.

The client sends a random installation credential and presents its SHA-256 digest to Play as the obfuscated account ID. The verifier calls Play's ProductPurchaseV2 endpoint and checks the package, state, product, quantity, remaining refundable quantity, and account binding. Firestore atomically claims the purchase token and returns the same grant on retries for its owner. The client records the verified grant and progress durably before consuming a pack or acknowledging an entitlement. Play handles payment UI and pending or canceled payments. The app does not grant funds from a callback alone.

Activate with `--dart-define=PATHWISE_BILLING_ENABLED=true` and `--dart-define=PATHWISE_BILLING_VERIFY_URL=https://your-host/v1/play/verify`. Use Play license testers to exercise pending, cancellation, retry after a network failure, consumption, and restoration on a minified internal build. Restoration supports owned items with the same billing profile, including a profile recovered with Android app-data backup. Paid coins that have already been consumed remain in the original local save. A new installation without that profile cannot recover prior purchases through this verifier. Before wide production rollout, provide support-assisted profile recovery and decide how to reconcile refunds for previously granted items while supporting offline play.

[Play purchase verification API](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2) · [Flutter billing plugin](https://pub.dev/packages/in_app_purchase)

## AdMob

For local test ads use a debug or profile build with `--dart-define=PATHWISE_ADS_TEST=true`. The flag is ignored in release builds. For production, create AdMob app and unit IDs, publish consent messages in Privacy & Messaging, and use the following values at build time.

- Environment variable `PATHWISE_ADMOB_APP_ID` for the Android SDK app ID.
- Dart defines `PATHWISE_ADS_ENABLED=true` and `PATHWISE_ADS_CONSENT_CONFIGURED=true`.
- Dart defines `PATHWISE_ADMOB_INTERSTITIAL` and `PATHWISE_ADMOB_REWARDED` with your two production unit IDs.

The Gradle configuration rejects missing, test, or malformed native IDs when the production flag is enabled. The Dart service additionally requires valid non-test unit IDs and the consent flag. In a safe screen, UMP updates consent, shows any required form, and gates SDK loads through `canRequestAds`. Check/Watch in Cosmetics is optional and starts this flow. Privacy choices are accessible when required. A cached ad expires after 45 minutes. Interstitials are eligible only after leaving a completed session, at most once per five such exits and with a four-minute minimum in-process interval. No full-screen placements run between a puzzle and Next Level or while the player is drawing.

Before enabling production, test GDPR and other applicable consent geographies, privacy choices, disabled and offline flows, no-fill, and reward-once behavior. Update Play data safety declarations based on the enabled integrations. [AdMob UMP for Flutter](https://developers.google.com/admob/flutter/privacy) · [AdMob rewarded ads](https://developers.google.com/admob/flutter/rewarded)
