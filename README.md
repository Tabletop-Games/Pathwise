# Pathwise

Pathwise is an Android route puzzle by Tabletop Games. Draw one continuous path from 1 to the final checkpoint, visiting the numbers in order and covering every tile.

## Play

On first launch, follow the highlighted tiles on the real Level 1 board; replay it from **Settings → Demo**. Press 1 and drag through edge-adjacent tiles. Drag backwards or tap an earlier tile to retract. **Undo** reverses the last action, **Clear** returns to checkpoint 1, and **Hint** corrects a wrong turn and reveals more of the certified route.

Play an endless procedural campaign through a Journey of illustrated chapters, a three-board Daily Challenge, and 1-, 3- or 5-minute Time Attack. Faster solves earn up to three stars. Earn coins, buy permanent Research and timed Boosts, collect path tips and themes in the Store, spin the Fortune Wheel and catch supply crates.

Pathwise is local-first. Everything except ads, Google Play Billing and Play Games works offline, and progress syncs through Google Play Games Saved Games when you are signed in and online.

Documentation: [gameplay](docs/gameplay.md) · [economy](docs/economy.md) · [design system](docs/design-system.md) · [architecture](docs/architecture.md) · [cloud saves](docs/cloud-saves.md) · [monetization](docs/monetization.md) · [security](docs/security.md) · [Play Games](docs/play-games.md) · [sharing](docs/social-sharing.md) · [development](docs/development.md) · [release](docs/release.md) · [Play Console setup](docs/play-console-setup.md) · [changelog](CHANGELOG.md)

Agents and contributors: read [AGENTS.md](AGENTS.md).

## Build

Flutter 3.50.1, JDK 21, Android SDK 36 and NDK 28.2.13676358. Android 7.0 (API 24) or later.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
dart run tool/economy_simulation.dart
flutter build apk --release
flutter build appbundle --release
```

Signing variables, build configuration and device workflows are in [docs/development.md](docs/development.md).

## Source and licensing

Pathwise adapts the Flutter Android project, Provider MVVM structure, settings, persistence, haptics, named palette ideas and consent/cache advertising pattern from [shenmareparas/Chess at 5df12d7](https://github.com/shenmareparas/Chess/tree/5df12d74f00f8b9574c9424608dbf56635cd39b1). The adaptation started November 22, 2026. Pathwise generates its own puzzles and uses its own artwork.

Pathwise is distributed under [GNU GPL v3](LICENSE). The bundled Bricolage Grotesque font keeps its [SIL Open Font License](assets/fonts/OFL.txt).
