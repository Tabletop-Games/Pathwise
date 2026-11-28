# Release

The version is in `pubspec.yaml` (`version: 1.0.0+8`: name 1.0.0, build 8). Compare the build number with the private Play Console upload history and raise it before uploading. Publishing to Google Play is a manual publisher action.

## Checks before a release

Run, in order:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
dart run tool/economy_simulation.dart
flutter build apk --debug --dart-define-from-file=config/production.example.json
flutter build apk --release --dart-define-from-file=/secure/pathwise-production.json
flutter build appbundle --release --dart-define-from-file=/secure/pathwise-production.json
python3 tool/prepare_play_bundle.py build/app/outputs/bundle/release/app-release.aab /secure/pathwise-play.aab
```

Use JDK 21, API 36 and NDK 28.2.13676358. Release builds enable R8 optimisation and resource shrinking. Keep these with the matching build and store them privately: `mapping.txt`, the native symbol zip (`build/app/outputs/native-debug-symbols/release/native-debug-symbols.zip`) and SHA-256 digests. Upload the symbol zip separately in Play Console.

`tool/prepare_play_bundle.py` removes duplicate native symbol metadata from the verified bundle and signs the slim upload with the publisher key. `tool/verify_android_artifacts.py` then confirms that every native library in the bundle matches the release APK.

## What CI verifies

`.github/workflows/verify.yml` runs the checks above on every pull request and on `main`, with an ephemeral signing key, and then:

- confirms the debug APK uses the AdMob sample app ID and the release APK uses the production one;
- verifies APK signing (`apksigner`) and 16 KB ZIP alignment (`zipalign -P 16`);
- validates the AAB with Bundletool and checks the base manifest;
- runs `tool/verify_android_artifacts.py`;
- requires the R8 `mapping.txt` and `resources.txt` outputs;
- archives the debug and release APKs.

## Manual device checks

CI cannot cover these; do them on a device or emulator before a Play release:

- the minified release build starts from the native launch screen into the saved-theme home screen;
- play offline (airplane mode): campaign, Daily, Time Attack and coin purchases work, and one offline notice appears;
- a coin pack purchase with a licence tester: credited once, restored after reinstall for permanent products;
- cloud save on two devices with one tester account, including the conflict dialog ([cloud-saves.md](cloud-saves.md));
- gesture tracking and large-font layouts on hardware;
- rewarded ads with AdMob test units, then live units only after review;
- the Settings update check against a Play-distributed build.

## Inspecting an installed build

`aapt dump badging app-release.apk` shows the application ID (`com.shenmareparas.pathwise`), API requirement, version code and ABIs. `apksigner verify --print-certs app-release.apk` shows the signing certificate; an update needs the same package ID and a compatible signature. The debug package (`com.shenmareparas.pathwise.debug`) keeps its own data.
