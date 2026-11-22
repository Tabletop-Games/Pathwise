# Pathwise

Pathwise is a wall-free Android route puzzle by Tabletop Games. Draw one continuous path from 1 to the final checkpoint, visiting the numbers in order and covering every tile.

## Play

Press 1 and drag through edge-adjacent tiles. Resume at the route tip, drag backward, or tap an earlier tile to retract. **Undo** restores the last input action, **Clear** returns to checkpoint 1, and **Hint** corrects a wrong turn and reveals progressively longer sections of the certified route. Three free hints are available per puzzle. Extra hints require an earned video reward or coins with an ad-free entitlement. A finished route shows its time, personal best, and earned coins.

Version 1.2.0 adds offline Time Attack, three progressive free hints per puzzle, an expanded store, and adaptive launcher icons. It retains the unlimited level campaign, daily and endless modes, coin shop, and achievements. Earn coins by playing and unlock cosmetics offline. The daily puzzle uses the device's local calendar. Progress, previous boards, and equipped themes from 1.0 are preserved.

Optional Google Play purchases and AdMob placements are disabled by default. They require production setup and testing. [Changelog](CHANGELOG.md) · [Economy](docs/economy.md) · [Monetization setup](docs/monetization.md)

## Build and verify

Use Flutter 3.50.1, JDK 21, Android SDK 35/36, and NDK 28.2.13676358. Android 7.0 (API 24) or later is supported.

```sh
flutter clean
flutter pub get
dart format .
flutter analyze
flutter test
npm --prefix backend test
flutter build apk --release
flutter build appbundle --release
```

For signing, provide `PATHWISE_KEYSTORE`, `PATHWISE_STORE_PASSWORD`, `PATHWISE_KEY_ALIAS`, and `PATHWISE_KEY_PASSWORD` in the build environment. Without them Gradle builds unsigned artifacts. [Release verification and measurements](docs/release-1.2.0.md)

## Source and licensing

Pathwise adapts the Flutter Android project, Provider MVVM structure, settings, persistence, haptics, named palette ideas, and consent/cache advertising pattern from [shenmareparas/Chess at 5df12d7](https://github.com/shenmareparas/Chess/tree/5df12d74f00f8b9574c9424608dbf56635cd39b1). The adaptation started November 22, 2026. Pathwise uses original artwork and generated puzzles. [Gameplay research](docs/gameplay.md)

Pathwise is distributed under [GNU GPL v3](LICENSE). The bundled Bricolage Grotesque font retains its [SIL Open Font License](assets/fonts/OFL.txt).
