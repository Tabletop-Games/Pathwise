# Pathwise

Pathwise is an offline Android logic puzzle. Draw one continuous route from 1 to the final checkpoint, visiting the numbers in order and covering every tile. The app includes a 36-level campaign, a daily challenge, endless puzzles, three visual themes, optional haptics, and local progress and statistics.

## Play

Press 1, then drag through edge-adjacent tiles. Resume at the route tip after lifting your finger. Drag back along the route or tap an earlier tile to retract. **Undo** restores the route before your last input action. **Clear** returns to the start. **Hint** retracts any wrong turn and highlights the next correct tile. A finished route shows its time and hint count.

The daily puzzle follows the device's local calendar. Levels, daily puzzles, and the endless sequence are deterministic and playable offline. In-progress routes and undo history are stored locally. The app has no accounts, advertising, or purchases.

[Gameplay research and specification](docs/gameplay.md)

## Build and test

Use Flutter 3.50.1 with JDK 21, Android SDK 36, and Android NDK 28.2.13676358. Android 7.0 (API 24) or later is supported.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

For a signed release, provide `PATHWISE_KEYSTORE`, `PATHWISE_STORE_PASSWORD`, `PATHWISE_KEY_ALIAS`, and `PATHWISE_KEY_PASSWORD` in the build environment. Without signing credentials, Gradle builds unsigned artifacts. Keep the production keystore and passwords outside this repository.

## Source and licensing

Pathwise adapts the Flutter Android project, Provider-based MVVM structure, settings, persistence, and haptic service from [shenmareparas/Chess at 5df12d7](https://github.com/shenmareparas/Chess/tree/5df12d74f00f8b9574c9424608dbf56635cd39b1). The Pathwise changes replace the chess engine, views, assets, and commercial services with the route puzzle and offline play modes. Adaptation dated November 22, 2026.

Pathwise is distributed under [GNU GPL v3](LICENSE). The bundled Bricolage Grotesque font retains its [SIL Open Font License](assets/fonts/OFL.txt). The Pathwise icon, board design, and puzzles were created for this project.
