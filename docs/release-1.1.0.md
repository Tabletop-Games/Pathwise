# Pathwise 1.1.0 release

Publisher Tabletop Games. Android application ID `games.tabletop.pathwise`. Version name `1.1.0` and version code `2`, increased from the repository's prior code 1. The GitHub repository had no release tags or releases at audit. Confirm Play Console has not already used code 2 before a store upload.

## Audit and migration

The 1.0 baseline passed 18 tests with zero analysis issues. It used Provider MVVM, a bounded orthogonal solver, SharedPreferences DataStore, and a 36-level linear list. Chess supplied useful named palette references, haptic patterns, and AdMob UMP, caching, and exit-placement patterns. The billing callback alone cannot establish payment, so Pathwise uses a Play-backed verifier.

Existing board IDs are unchanged. Migration reads the existing key and writes schema version 2 to that same key on subsequent persistence. Level 1–36 and the daily/endless seeds are preserved exactly. Advancement derives from the highest historical completed or in-progress level. The existing best-time records, settings, and current attempts remain. Pre-upgrade play time uses a lower-bound estimate from historical best times because 1.0 never recorded aggregate play time.

## Build checklist

1. Run the clean, dependency, formatting, analysis, test, and two release build commands in the [README](../README.md).
2. Inspect `build/app/outputs/mapping/release/mapping.txt`, `usage.txt`, and `resources.txt`. Keep `mapping.txt` with the matching build. Inspect the AAB native symbol table metadata for crash symbolication. If building with optional Dart obfuscation, archive the split debug info separately.
3. Verify the APK with Android SDK `apksigner` and the AAB with Google's `bundletool validate`. Check package, version, supported ABIs, and permissions.
4. Install a signed minified APK on API 24+ or use Play's internal track. Exercise cold start, an existing v1 save upgrade, all gameplay controls, clear, replay, Next Level, persistence after process death, store purchases with coins, and default disabled monetization. Exercise Billing and UMP once credentials are configured. See [monetization deployment](monetization.md).
5. Publish manually if desired. The repository delivers source only. Sign store builds with the publisher's key.

## Build design

AGP 9.3.1 and Gradle 9.5 explicitly run optimized R8 and Android resource shrinking for release. Standard optimized ProGuard rules and SDK consumer rules preserve required plugin entry points. The project adds no broad keep rules. APK and AAB contain Flutter's Arm64, Arm32, and x86-64 release libraries. An AAB lets Play split downloads by ABI. The full variable text font is retained for localized text, while Flutter tree-shakes the icon font. AGP packages native symbol tables in the AAB.

The only new Android integrations are the official Flutter Play Billing and Mobile Ads plugins. The ad plugin brings its webview adapter; Flutter resolves iOS transitives in the lockfile without linking them into Android. The Dart crypto package supports obfuscated Play profile IDs. The existing DataStore native counter and Dart JNI bridge are used by persistence. Chess, Stockfish, and chess-specific assets are absent.

The timer updates its own value, and pointer-only rendering uses a separate lightweight repaint layer. Levels are built per page and puzzle generation runs off the UI isolate. A host latency benchmark can be repeated with `dart run tool/benchmark_puzzles.dart`. Device cold startup, memory and frame timing require an Android device or emulator.

## Generation benchmark

Twenty-five warmed samples per level on the verification host using the Dart 3.14 VM. This samples generator work without isolate startup or UI.

| Level | Grid | Checkpoints | p50 (ms) | p95 (ms) |
| ---: | --- | ---: | ---: | ---: |
| 1 | 4×4 | 9 | 0.94 | 2.45 |
| 12 | 5×5 | 12 | 0.82 | 2.31 |
| 36 | 7×7 | 16 | 2.15 | 3.54 |
| 37 | 7×7 | 16 | 3.09 | 3.17 |
| 100 | 7×7 | 15 | 3.63 | 3.73 |
| 150 | 7×7 | 14 | 5.57 | 5.81 |
| 500 | 7×7 | 12 | 9.12 | 9.21 |
| 1,000 | 7×7 | 11 | 3.83 | 3.87 |
| 1,000,000 | 7×7 | 11 | 11.64 | 11.92 |

These are representative host samples. A candidate gets an 18,000-node solver budget and the largest board tries at most 47 removals. If removing a clue cannot be certified, the previous certified layout is retained.

## Verified release

A clean dependency resolution, formatting, and static analysis passed. The Flutter suite passed 29 tests and the verifier suite passed three. A running verifier without deployment configuration returned HTTP 503 from readiness. The Flutter UI tests exercised fast drag, retraction, level paging, completion navigation, previews, and disabled monetization. No emulator or Android device was available. Cold startup, memory, frame pacing, and a minified Android runtime launch were unmeasured.

Both build artifacts were signed with a local verification key. APK signature and 16 KB native alignment passed. Google's bundletool validated the AAB. The package reported version 1.1.0/code 2, minimum API 24 and target API 36.

| Release artifact | v1.0 bytes | v1.1 bytes | Change |
| --- | ---: | ---: | ---: |
| Universal APK | 48,367,164 | 51,775,888 | +7.0% |
| AAB with symbol metadata | 48,617,824 | 54,362,224 | +11.8% |

The comparison is between release builds of different feature sets. It is not a same-version shrinking A/B test. The release dependency tree resolved Google Mobile Ads 25.5.0 and Play Billing 9.1.0. Flutter reduced the icon font from 1,645,184 to 4,568 bytes.

The mapping header identified R8 9.3.16. R8 produced an obfuscation map and a nonempty removal report. Its resource report marked 1,209 entries unreachable. The shrunk resource intermediates were produced and an unused share-resource XML was absent from the APK. The mapping retained Flutter's `GeneratedPluginRegistrant`, Play Billing and Mobile Ads plugins. The App Bundle contains three native ABI symbol tables and the ProGuard map. The APK contains no Chess assets or Stockfish.

| Verification artifact | SHA-256 |
| --- | --- |
| APK | `ecd16cd7c92543a8192c61678efd63d4dab85d9811e17ffc71443f5a4a65c81d` |
| AAB | `2f867772b9e9600659f3bf2a4dbe1f968a22a646b99b94ad8d7206eb242ff2b5` |

Live Play purchase, unbacked cross-device recovery, and AdMob consent and delivery require production or license-test configuration. Production signing used by Tabletop Games and any Play upload remain publisher actions.
