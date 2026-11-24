# Android-only development policy

Pathwise is an Android-only project for the foreseeable future. This is a standing requirement, not a temporary measure.

## What this means

- **No iOS work.** Do not build, compile, sign, test or investigate iOS. Do not add iOS CI jobs, iOS acceptance criteria or iOS-specific features (billing, authentication, cloud saves, advertising).
- **Dormant scaffolding.** The `ios/` directory stays in the repository untouched, as a starting point if iOS support is requested later. It is excluded from analysis (`analysis_options.yaml`) and from CI.
- **Existing iOS code paths** in Dart (for example StoreKit or iOS ad units) remain as they were. They are not built, tested or maintained. Do not extend them.
- **Reintroducing iOS verification** requires an explicit request from the project owner.

## Required verification

Every change must pass these checks on Android:

| Check | Command |
| --- | --- |
| Formatting | `dart format --output=none --set-exit-if-changed .` |
| Static analysis | `flutter analyze --no-pub` |
| Automated tests | `flutter test --no-pub` |
| Economy simulation | `dart run tool/economy_simulation.dart` |
| Android debug APK | `flutter build apk --debug --dart-define-from-file=config/production.example.json` |
| Android minified release APK | `flutter build apk --release --dart-define-from-file=config/production.example.json` (signing variables set) |
| Android minified release AAB | `flutter build appbundle --release --dart-define-from-file=config/production.example.json` |
| R8 verification | Mapping and resource output are checked by the Android job in `.github/workflows/verify.yml` (`build/app/outputs/mapping/release/mapping.txt`, `resources.txt`, `tool/verify_android_artifacts.py`) |

CI runs these in `.github/workflows/verify.yml`.

## Local commands

Install the debug build on an emulator:

```sh
flutter emulators --launch <EMULATOR_ID>
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.shenmareparas.pathwise.debug -c android.intent.category.LAUNCHER 1
```

Release artifacts:

```sh
flutter build apk --release --dart-define-from-file=/secure/pathwise-production.json
flutter build appbundle --release --dart-define-from-file=/secure/pathwise-production.json
```

## Preserved Android behaviour

Application IDs (`com.shenmareparas.pathwise` for production, `com.shenmareparas.pathwise.debug` for debug), signing configuration, Play Billing, AdMob integration, and Play Games Saved Games are unchanged by this policy.
