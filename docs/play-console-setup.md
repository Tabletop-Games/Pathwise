# Play Console and AdMob setup

This guide covers the configuration that Pathwise needs in Google Play Console, Play Games Services and AdMob. There are two people involved:

- **Developer** (you): owns the code, the AdMob account and the build.
- **Play Console owner** (your friend): owns the Play Console account and the app listing.

The owner does not need to share their password. Everything below is done by inviting or switching to accounts with the permissions listed.

> **Verification note.** Google's documentation site could not be read while this guide was written, so the console menu names below follow the documented concepts and may differ slightly. Check each step against the live console before relying on it. Items marked **Manual** cannot be completed from the repository.

## 1. What the owner must allow (minimum)

Play Console → Users and permissions → invite the developer's Google account (or grant access from the owner's account) with:

| Area | Permission | Needed for |
| --- | --- | --- |
| Play Games Services | Manage the game's configuration and testers (the role that includes Play Games Services management) | Saved Games, sign-in, testers |
| Monetize with Play | View and manage products, and manage license testers | Coin packs, permanent products, purchase testing |
| Release | Create and roll out releases to internal testing | Installing test builds |
| App information and store listing | Only if the developer edits the listing | Optional |

Grant the narrowest role that includes these. Check the current role names in Users and permissions, because Google changes them. Revoke the developer's access after the launch if the owner prefers.

## 2. Identifiers you will need

Collect these first. None of them are invented here; copy them from the console.

| Item | Value | Where to find it |
| --- | --- | --- |
| Production package name | `com.shenmareparas.pathwise` | App already in Play Console |
| Debug package name | `com.shenmareparas.pathwise.debug` | Used only for local testing |
| Play Games Services application ID (number) | `<GAMES_APP_ID>` | Play Games Services → Configuration (or the game's listing) |
| Upload key SHA-1 | `<UPLOAD_SHA1>` | Your upload keystore, `keytool -list -v` |
| Play App Signing certificate SHA-1 | `<APP_SIGNING_SHA1>` | Play Console → Test and release → Setup → App integrity |
| Debug keystore SHA-1 | `<DEBUG_SHA1>` | `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` (only if the debug package uses Play Games) |
| Monetization licensing public key | `<LICENSE_KEY>` | Play Console → Monetize with Play → Monetization setup |
| AdMob app ID | `ca-app-pub-7623640820680894~1301071315` | Already in `config/production.example.json` |

Do not put any of the values above into a committed file except the public ones already in `config/production.example.json` (the AdMob app ID and ad unit IDs are public identifiers).

## 3. Play Games Services project (Play Console owner)

1. Play Console → Play Games Services → **Set up** (or **Create** a project), and link it to the Pathwise app. Choose the Android platform.
2. Enter the production package name `com.shenmareparas.pathwise`. Google asks for the SHA-1 of the signing key. Add:
   - The **Play App Signing** certificate (`<APP_SIGNING_SHA1>`). This is the one that matters for the Play-distributed build.
   - Your **upload key** (`<UPLOAD_SHA1>`), if you test with it.
3. Note the **application ID** shown after setup. Put it in the build as `PATHWISE_GAMES_PROJECT_ID`. It is a number, not a secret.
4. Enable **Saved Games** for the project. Saved Games is part of the Play Games Services configuration and must be on for cloud saves to work.
5. Add testers: Play Games Services → Testers (or Setup and management → Testers) → add the Google accounts that will test sign-in and saves. An unpublished Play Games project only works for listed testers.
6. Configuration status: leave the project unpublished while testing. Publish it before release. Google's review of the published configuration is required before players outside the testers list can sign in.

**Manual:** Google's console may ask for an icon, description, and achievement definitions. Pathwise's achievements are already defined in `docs/google-play-achievements.md`; import them as described there.

### Debug package (optional)

Debug builds do not need Play Games. By default they use a local fake save, so no test data reaches the production project. To test real Saved Games from the debug package:

1. Add `com.shenmareparas.pathwise.debug` as a second Android client in the same Play Games project, with the debug keystore SHA-1.
2. Build with `PATHWISE_GAMES_ENABLED=true` and the same `PATHWISE_GAMES_PROJECT_ID`.

Debug and production saves stay separate even then, because the app package names differ and the debug build uses its own local key prefix.

## 4. Google Cloud (no billing required)

Play Games Services is configured in Play Console. Pathwise does not need a Google Cloud project, a billing account, Firestore, Cloud Run or a service account for this architecture. Do not create any of them for this release.

The OAuth client that Play Games sign-in uses is created automatically for the Play Games project. If the console asks you to set an OAuth consent screen, you may skip it for Saved Games sign-in. If you later add server-side features, revisit this.

## 5. Billing (Play Console owner, Manual)

1. Play Console → Monetize with Play → Products → In-app products. Create the eight products with these exact IDs:
   `pathwise_coins_500`, `pathwise_coins_1250`, `pathwise_coins_3000`, `pathwise_coins_7500`, `pathwise_coins_18000`, `pathwise_remove_ads`, `pathwise_themes_forever`, `pathwise_premium`.
2. The five coin packs are consumable. The other three are non-consumable (one-time) products.
3. Activate each product and set prices. The app shows the price returned by Play. Do not put prices in the code.
4. Monetization setup → copy the **licensing public key** into `PATHWISE_PLAY_BILLING_PUBLIC_KEY`. The app uses it to verify purchase signatures on the device.
5. License testers: Settings → License testing → add the tester accounts. License testers buy with no real charge, and only they can test purchases before release.

Refunds: Google reports refunds and revocations to the app when it starts (the app asks Google which permanent products are owned). Refunds of coin packs are not reconstructed from Google Play, because consumed purchases disappear from its history. See [cloud saves](cloud-saves.md#guarantees-and-their-limits).

## 6. Internal testing

1. Play Console → Test and release → Testing → Internal testing → create a release.
2. Upload the signed bundle from `docs/release.md`.
3. Testers → add a list with the Google accounts for sign-in and billing, and share the opt-in link.
4. Install from Play on each test device (debug installs are not from Play and cannot use Play Games or Play Billing).

## 7. AdMob (developer)

1. AdMob → Apps → Pathwise → confirm the Android app ID matches `ca-app-pub-7623640820680894~1301071315`.
2. Confirm the five Android ad units exist: banner, interstitial, rewarded (coins), extra hint, Fortune Wheel (see `config/production.example.json`).
3. **No server-side verification URL is needed.** The earlier backend design set one; it is removed. Leave the rewarded units' "Server-side verification" setting off.
4. Consent: keep UMP (Google's consent messages) configured in AdMob → Privacy & messaging. The app shows the consent form only where required.
5. Keep the ad units' existing names and IDs unchanged.

## 8. Build configuration (developer)

Build commands no longer need any backend variables. The following are the only values that matter for Play Games and Billing:

| Variable | Where | Value |
| --- | --- | --- |
| `PATHWISE_GAMES_PROJECT_ID` | Environment variable read by Gradle | The Play Games application ID (number). Default `0` disables Play Games. |
| `PATHWISE_GAMES_ENABLED` | `--dart-define` | `true` to enable Play Games sign-in and Saved Games in the Dart code |
| `PATHWISE_PLAY_BILLING_PUBLIC_KEY` | `--dart-define` | The licensing public key from step 5 |
| `PATHWISE_BILLING_ENABLED` | `--dart-define` | `true` to enable purchases |
| `PATHWISE_ADS_ENABLED`, `PATHWISE_ADS_CONSENT_CONFIGURED` | `--dart-define` | Keep `false` until you are ready to serve real ads |

Example:

```sh
export PATHWISE_GAMES_PROJECT_ID=<GAMES_APP_ID>
flutter build appbundle --release \
  --dart-define-from-file=config/production.example.json \
  --dart-define=PATHWISE_GAMES_ENABLED=true \
  --dart-define=PATHWISE_PLAY_BILLING_PUBLIC_KEY=<LICENSE_KEY>
```

## 9. Verification checklist

Automated tests cover the logic (`flutter test`). These steps need the real console and devices:

- [ ] Sign in from Settings → Cloud save on a Play-installed build. Status shows "Connected to Google Play Games".
- [ ] Complete a level, then check that **Last synced** updates.
- [ ] Install on a second device with the same tester account. Sign in and confirm progress appears, or the conflict dialog appears if both devices changed coins.
- [ ] Sign out, sign in with a second tester account. Confirm the device progress is not replaced without a choice.
- [ ] Airplane mode: the connection overlay appears; the route is kept; Retry resumes play.
- [ ] Buy a coin pack with a license tester: the purchase is blocked until sync succeeds, then credited once.
- [ ] Reinstall the app and sign in: progress and purchases return.
- [ ] Refund a test purchase: the permanent entitlement is removed on the next start.

Record any failure with the Play Console page and the device model; do not paste account identifiers into issue trackers.

## 10. Remaining manual steps (not automatable in this repository)

- Create and configure the Play Games Services project, enable Saved Games, and add testers (section 3).
- Create the eight products and the licensing key (section 5).
- Create the internal testing release and tester lists (section 6).
- Confirm the AdMob settings (section 7).
- Run the verification checklist on real devices (section 9).
