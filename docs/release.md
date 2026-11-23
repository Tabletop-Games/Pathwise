# Release verification

The public version line is 1.0.0. Build 7 follows Infinite Expedition build 6. The publisher must compare it against the private Play Console upload history and increase it if needed before uploading. Follow [setup.md](../setup.md) for production configuration and signing.

Use Flutter 3.50.1, Java 21, API 36 and NDK 28.2.13676358. Release Gradle enables R8 code optimization and resource shrinking. Archive the native symbol table zip from the release build. After Flutter verifies its standard bundle, use `tool/prepare_play_bundle.py` to remove duplicate native symbol metadata and sign the slim Play upload with the same publisher key. Verify library hashes match, and upload the symbols separately in Play Console. Keep SHA-256 digests and R8 mappings in private release storage. CI uses an ephemeral key to verify build artifacts.

Run formatting, static analysis, Flutter and backend tests, the economy simulation, then release APK and AAB builds. Validate the AAB with Bundletool and APK alignment and signing with current Android build tools. Review [measured verification results](performance.md). Google Play publishing remains a manual publisher action.
