# Android-only (persistent project requirement)

Pathwise is an Android-only project for the foreseeable future. Apply this in every session until the project owner explicitly requests iOS support.

- Do not build, compile, sign, test or investigate iOS. Do not spend implementation time on iOS issues.
- Do not add iOS CI jobs or iOS checks to any workflow. Do not add iOS-specific billing, authentication, cloud saves or advertising.
- Keep the `ios/` directory untouched as dormant scaffolding. It is excluded from analysis.
- Required verification for every change: `dart format --output=none --set-exit-if-changed .`, `flutter analyze --no-pub`, `flutter test --no-pub`, `dart run tool/economy_simulation.dart`, the Android debug APK build, the minified release APK and AAB builds, and the R8 checks. Details are in `docs/android-only.md`.
- Preserve application IDs, signing configuration, Play Billing, AdMob and Play Games Saved Games.
