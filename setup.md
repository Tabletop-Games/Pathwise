# Pathwise setup

Pathwise is an online-first Android puzzle. The project is Android-only; see [the Android-only policy](docs/android-only.md). It needs an internet connection to play and syncs progress through Google Play Games Services Saved Games. There is no custom backend to deploy. For the Google-side configuration, see [Play Console and AdMob setup](docs/play-console-setup.md). For the design, see [cloud saves](docs/cloud-saves.md) and [connectivity](docs/connectivity.md).

## 1. Prerequisites

- Flutter 3.50.1 with Dart 3.14 or later, JDK 21, Android SDK platform 36 and build tools 36, NDK 28.2.13676358. Accept SDK licences with `flutter doctor --android-licenses`.
- A Google account that is a tester on the Play Games project (for cloud saves) and a license tester (for purchases), when testing those features.

```sh
flutter pub get --enforce-lockfile
```

## 2. Configuration values

Pathwise reads configuration at build time. Copy the template and fill in only what you have:

```sh
cp config/production.example.json /secure/pathwise-production.json
```

| Key | Required for | Notes |
| --- | --- | --- |
| `PATHWISE_ADS_ENABLED`, `PATHWISE_ADS_CONSENT_CONFIGURED` | Live ads | Keep `false` until the AdMob checklist is complete |
| `PATHWISE_ADMOB_*` | Ads | Public IDs in the template |
| `PATHWISE_GAMES_ENABLED` | Cloud saves and Play Games sign-in | `true` only once the Play Games project exists |
| `PATHWISE_BILLING_ENABLED`, `PATHWISE_PLAY_BILLING_PUBLIC_KEY` | Purchases | The licensing public key from Play Console |

Gradle reads one environment variable for Play Games:

```sh
export PATHWISE_GAMES_PROJECT_ID=<GAMES_APP_ID>   # application ID number; unset means Play Games is off
```

Release signing (required for release builds only; never commit these):

```sh
export PATHWISE_KEYSTORE=/secure/pathwise-upload.p12
export PATHWISE_KEY_ALIAS=pathwise-upload
export PATHWISE_STORE_PASSWORD=...   # from secure storage
export PATHWISE_KEY_PASSWORD=...     # from secure storage
```

## 3. Build and run

These are the exact commands. None require a backend or deployment variable.

Debug APK (package `com.shenmareparas.pathwise.debug`, uses the local test save; ads are off unless `PATHWISE_ADS_TEST=true` is passed):

```sh
flutter build apk --debug
```

Release APK (package `com.shenmareparas.pathwise`):

```sh
flutter build apk --release --dart-define-from-file=/secure/pathwise-production.json
```

Release App Bundle, for Play upload:

```sh
flutter build appbundle --release --dart-define-from-file=/secure/pathwise-production.json
python3 tool/prepare_play_bundle.py build/app/outputs/bundle/release/app-release.aab /secure/pathwise-play.aab
```

Emulator (create one in Android Studio's Device Manager first, then list it):

```sh
flutter emulators                       # shows the emulator IDs
flutter emulators --launch <EMULATOR_ID>
adb devices                             # wait until the emulator is listed
```

Install the debug APK on the emulator:

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Launch the installed debug app:

```sh
adb shell monkey -p com.shenmareparas.pathwise.debug -c android.intent.category.LAUNCHER 1
```

Or build, install and run with logs in one step:

```sh
flutter run -d <EMULATOR_ID> --debug
```

On the emulator, turn off Wi-Fi and mobile data to check the connection overlay.

Install a release APK on a device with `adb install -r build/app/outputs/flutter-apk/app-release.apk`. Release APKs are signed with your upload key, so they cannot update a Play build.

## 4. Verify before a release

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart run tool/economy_simulation.dart
```

CI runs these on every pull request, and also builds the minified release APK and AAB and checks the manifest, the R8 mapping and bundle validity. See `.github/workflows/verify.yml`.

## 5. Publisher checklist

- [ ] Play Console and Play Games Services configured as in [the setup guide](docs/play-console-setup.md).
- [ ] Eight products created with their IDs; licence testers added.
- [ ] Internal testing release installed from Play on a test device.
- [ ] Cloud save verified on two devices with the same tester account, including the conflict dialog.
- [ ] Airplane-mode check: the connection overlay appears and Retry resumes the same puzzle.
- [ ] Purchase test with a licence tester: blocked until sync, credited once, restored after reinstall.
- [ ] AdMob: five Android units in place, consent configured, live ads enabled only after review.
- [ ] Budget alerts are not needed for this architecture; no paid cloud service is used.

## 6. Notes

- The debug package uses a local fake save unless `PATHWISE_GAMES_ENABLED` is set. Its test progress never reaches the production Play Games save.
- Android backup is disabled, so reinstalling restores progress from Play Games, not from a local backup.
