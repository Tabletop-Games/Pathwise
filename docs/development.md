# Development

## Requirements

Flutter 3.50.1 (Dart 3.14 or later), JDK 21, Android SDK platform 36 with build tools, and NDK 28.2.13676358. Minimum API 24, target API 36. Accept SDK licences with `flutter doctor --android-licenses`, then:

```sh
flutter pub get --enforce-lockfile
```

## Android only

Pathwise is Android-only until the project owner says otherwise. Do not build, sign, test or investigate iOS, do not add iOS CI jobs or iOS billing, ads, sign-in or cloud-save code, and leave the dormant `ios/` scaffolding untouched (it is excluded from analysis in `analysis_options.yaml`).

## Configuration

Build-time configuration comes from a JSON file passed with `--dart-define-from-file`. Copy the template and fill in only what you have; never commit the copy.

```sh
cp config/production.example.json /secure/pathwise-production.json
```

| Key | Needed for |
| --- | --- |
| `PATHWISE_ADS_ENABLED`, `PATHWISE_ADS_CONSENT_CONFIGURED`, `PATHWISE_ADMOB_*` | Live ads (keep `false` until the AdMob checklist is complete) |
| `PATHWISE_GAMES_ENABLED` | Play Games sign-in and cloud save |
| `PATHWISE_BILLING_ENABLED`, `PATHWISE_PLAY_BILLING_PUBLIC_KEY` | Purchases |

Gradle reads `PATHWISE_GAMES_PROJECT_ID` (the Play Games application ID number; unset means Play Games is off). Release signing reads `PATHWISE_KEYSTORE`, `PATHWISE_KEY_ALIAS`, `PATHWISE_STORE_PASSWORD` and `PATHWISE_KEY_PASSWORD`; without them Gradle builds unsigned artifacts. The debug package (`com.shenmareparas.pathwise.debug`) uses a local fake cloud save and ad test mode, so test progress never reaches a production save. Publisher-side setup is in [play-console-setup.md](play-console-setup.md).

## Build and run

```sh
flutter build apk --debug --dart-define-from-file=config/production.example.json
flutter build apk --release --dart-define-from-file=/secure/pathwise-production.json
flutter build appbundle --release --dart-define-from-file=/secure/pathwise-production.json
python3 tool/prepare_play_bundle.py build/app/outputs/bundle/release/app-release.aab /secure/pathwise-play.aab
```

Emulator workflow:

```sh
flutter emulators --launch <EMULATOR_ID>
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.shenmareparas.pathwise.debug -c android.intent.category.LAUNCHER 1
```

Turn off Wi-Fi and mobile data on the emulator to check that play continues offline and that the offline notice appears once.

## Verification

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
dart run tool/economy_simulation.dart
```

CI (`.github/workflows/verify.yml`) runs these plus the credential-pattern scan, the Android debug build, the minified release APK and AAB, bundle validation and the R8 checks described in [release.md](release.md). Analyzer infos fail the build. The enforced lints are `prefer_relative_imports` and `directives_ordering`.

## Tests

| Area | Files |
| --- | --- |
| Domain: puzzles, solver, generator, stars, tip tracking, economy, progression | `puzzle_test`, `puzzle_generation_test`, `star_rating_test`, `tip_tracker_test`, `economy_test`, and similar pure tests |
| Model and persistence | `app_model_test`, `game_state_storage_test`, `transaction_and_lifecycle_test` |
| Cloud | `cloud_save_format_test`, `cloud_sync_service_test`, `cloud_guard_test` |
| Services | ads, billing, connectivity, sound, haptics, notifications, achievements |
| ViewModels | `mvvm_viewmodels_test` |
| Widgets and flows | `widget_test`, store, Journey, tutorials, crates, fortune, settings |
| Architecture | `architecture_boundaries_test` |
| Visual and assets | `ui_captures_test`, `asset_validation_test` |

Use named, seeded fixtures, fake clocks and fake services. Do not make real network calls, show real ads or make real purchases in tests. Test observable behaviour and domain invariants, not private implementation. Delete a test when its feature is removed.

## Tools

| Tool | Purpose |
| --- | --- |
| `tool/economy_simulation.dart` | Seeded economy scenarios (run in CI) |
| `tool/journey_economy.dart` | Campaign reward estimate |
| `tool/validate_catalogue.dart` | Generates, certifies and plays the first 1,000 levels and checks for duplicate boards |
| `tool/benchmark_puzzles.dart` | Generator timing on the host |
| `tool/export_play_games_achievements.dart` | Writes the Play Games achievement import files |
| `tool/prepare_play_bundle.py` | Builds the slim Play upload bundle and signs it with the upload key |
| `tool/verify_android_artifacts.py` | Checks the slim bundle matches the release APK's native libraries |

Python tools use only the standard library; run them with `python3`, or `uv run` when a dependency is ever needed.

## Working agreements

Instructions for coding agents are in [`AGENTS.md`](../AGENTS.md). The short version: keep the repository in step with the code, delete what a change makes obsolete, commit as Aman Sanoj, and use a pull request.
