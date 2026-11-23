# Release verification

The public version line is 1.0.0. Build 8 adds social results and native achievement progress after Fortune Wheel build 7. The publisher must compare it against the private Play Console upload history and increase it if needed before uploading. Follow [setup.md](../setup.md) for production configuration and signing.

Use Flutter 3.50.1, Java 21, API 36 and NDK 28.2.13676358. Release Gradle enables R8 code optimization and resource shrinking. Archive the native symbol table zip from the release build. After Flutter verifies its standard bundle, use `tool/prepare_play_bundle.py` to remove duplicate native symbol metadata and sign the slim Play upload with the same publisher key. Verify library hashes match, and upload the symbols separately in Play Console. Keep SHA-256 digests and R8 mappings in private release storage. CI uses an ephemeral key to verify build artifacts.

Run formatting, static analysis, Flutter and backend tests, the economy simulation, then release APK and AAB builds. Validate the AAB with Bundletool and APK alignment and signing with current Android build tools. Review [measured verification results](performance.md). Google Play publishing remains a manual publisher action.


## Sideload verification

Use `flutter build apk --debug` for developer features, and `flutter build apk --release` without ABI splitting for a universal signed verification build. CI archives both APKs from its verification workflow. Its temporary release certificate is valid for checking the build and differs from the debug and Play App Signing certificates.

Use `aapt dump badging app-release.apk` to inspect the application ID (`games.tabletop.pathwise`), Android API requirement, version code, and bundled ABIs. Run `apksigner verify --print-certs app-release.apk` and compare the SHA-256 certificate digest with the prior installation or Play App Signing certificate. An update requires an identical package ID and compatible signature, and Android can reject version downgrades independently of ABI. Device compatibility remains device-specific until a failed reinstall can be reproduced with its Android install error. Debug data uses its own preference key.
