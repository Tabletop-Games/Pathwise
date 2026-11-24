# Pathwise

Pathwise is an Android and iOS route puzzle by Tabletop Games. Draw one continuous path from 1 to the final checkpoint, visiting the numbers in order and covering every tile.

## Play

On your first launch, follow the highlighted tiles on the actual Level 1 board. Practice is separate from scored play. Replay it anytime from **Settings → Demo**.

Press 1 and drag through edge-adjacent tiles. Resume at the route tip, drag backward, or tap an earlier tile to retract. **Undo** restores the last input action, **Clear** returns to checkpoint 1, and **Hint** corrects a wrong turn and reveals progressively longer sections of the certified route. New players start with three hints in a persistent wallet. Buy more for 60 coins or earn up to five a day through optional videos. Results appear over the solved board with a prominent next action.

Play 1,000 Levels, the three-board Daily Challenge, and 1-, 3-, or 5-minute Time Attack offline. Earn coins, develop permanent Research, activate timed Boosts, and customize your board. Catch flying supply crates during play to unlock an optional video reward. The Fortune Wheel offers a free coin spin every 24 hours. [Game modes](docs/game-modes.md) · [Economy](docs/economy.md)

Share text results for Daily Challenge, Time Attack and progression milestones. Earn 29 Play Games achievements offline and synchronize them when Play Games is available. [Social sharing](docs/social-sharing.md) · [Google Play achievements](docs/google-play-achievements.md)

Google Play Billing, Apple StoreKit, AdMob and Play Games require publisher configuration. Start with the [publisher setup guide](setup.md). See [gameplay](docs/gameplay.md), [economy](docs/economy.md), [release verification](docs/release.md) and the [changelog](CHANGELOG.md).

## Build and verify

Use Flutter 3.50.1, JDK 21, Android SDK 35/36, and NDK 28.2.13676358. Android 7.0 (API 24) or later is supported.

```sh
flutter clean
flutter pub get
dart format .
flutter analyze
flutter test
npm --prefix backend ci
npm --prefix backend test
dart run tool/economy_simulation.dart
flutter build apk --release
flutter build appbundle --release
```

For signing, provide `PATHWISE_KEYSTORE`, `PATHWISE_STORE_PASSWORD`, `PATHWISE_KEY_ALIAS`, and `PATHWISE_KEY_PASSWORD` in the build environment. Without them Gradle builds unsigned artifacts. [Release verification and measurements](docs/performance.md)

## Source and licensing

Pathwise adapts the Flutter Android project, Provider MVVM structure, settings, persistence, haptics, named palette ideas, and consent/cache advertising pattern from [shenmareparas/Chess at 5df12d7](https://github.com/shenmareparas/Chess/tree/5df12d74f00f8b9574c9424608dbf56635cd39b1). The adaptation started November 22, 2026. Pathwise uses original artwork and generated puzzles. [Gameplay research](docs/gameplay.md)

Pathwise is distributed under [GNU GPL v3](LICENSE). The bundled Bricolage Grotesque font retains its [SIL Open Font License](assets/fonts/OFL.txt).
