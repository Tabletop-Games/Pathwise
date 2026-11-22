# Pathwise 1.2.0

Tabletop Games · Android package `games.tabletop.pathwise` · Version code 3. The merged baseline reports version 1.1.0/code 2, with no higher GitHub release or tag at audit. Check the Play Console's authoritative version history before publishing.

## Gameplay and migration

Time Attack runs for ten minutes including background time. Each solve awards 100 points and advances to a newly generated board, growing from 4×4 to 7×7. App restarts resume the saved Android elapsed-time deadline on the same boot. Changing wall time has no effect. A device reboot ends the run because one monotonic timeline cannot span reboots. The game shows solve count, score, previous best, fastest and average times, and rewards at expiration.

The first hint marks the next correct tile. The second and third reveal a short or longer correct route and highlight the next tile. A divergent tail is retracted. Hints follow a certified solution, and the final move remains the player's. The free budget belongs to the saved board ID and survives a replay. Persisted usage, credits, and reward identities prevent resetting or double-crediting allowances. [Economy](economy.md) · [Advertising placements and billing catalog](monetization.md)

Schema 3 uses the existing storage key and keeps v1 and v2 progress and route seeds. Recorded prior hint use counts toward allowances. Existing theme-pass purchasers retain future themes. Automatic ad timestamps, Time Attack, and new purchase entitlements are recorded alongside the coin ledger in the same queued snapshot.

## Android and release checks

Use Flutter 3.50.1, Dart 3.14.0, JDK 21, Gradle 9.5.0, Kotlin 2.4.20, AGP 9.3.1, SDK 35/36, and NDK 28.2.13676358. Minimum API 24 and target API 36 are unchanged. Release uses explicit optimized R8 and resource shrinking with SDK consumer rules. Preserve the exact release map and native symbols securely. No new Android libraries were added.

The launcher has standard and adaptive artwork plus a dedicated route-only monochrome layer for Android 13+. [Play listing icon](media/pathwise-play-icon.png) · [Android adaptive-icon guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)

Run the commands in the [README](../README.md), inspect APK signing and native alignment, validate the AAB, and inspect the shrinker outputs. Install the minified release build on a real Android device or emulator when available. Live Play and AdMob checks require an internal track, credentials, and test accounts. Until then, keep monetization disabled in published builds.

## Verified results

The v1.1 baseline passed 29 Flutter tests, static analysis, and both release builds. The v1.2 build passed formatting and static analysis, 36 Flutter tests, and four backend verifier tests. Tests cover timed progression and expiration, foreground/background handling, v1/v2 migration, hint exhaustion and replay, reward deduplication, and Premium fulfillment.

| Artifact | v1.1 bytes | v1.2 bytes | v1.2 verification SHA-256 |
| --- | ---: | ---: | --- |
| APK | 51,775,888 | 52,499,876 | `93bf05d4deb50e4e430f30d9d12fdd2d9a9fbfe45fa71c3fe0e3d4541f74100b` |
| App Bundle | 54,362,224 | 55,026,426 | `2211af588eaa2eeb814d09267e48dda964cc12059661ef2fc216800bf8f3c7ca` |

The locally signed APK passed signature and 16 KB native alignment checks. The App Bundle passed bundletool validation and contains the mapping and Arm64, Arm32, and x86-64 native symbol tables. R8 9.3.16 produced an obfuscation map and a removal report. Its resource analysis marked 1,209 entries unreachable. Flutter's generated plugin registrant and both Google plugins are in the map. The APK resource table includes standard and adaptive launcher variants and the monochrome layer.

Warm host generator p95 was 0.98–14.03 ms over 25 samples at each of levels 1, 12, 36, 37, 100, 150, 500, 1,000, and 1,000,000. This excludes isolate startup and Android UI work. No Android device or emulator was available, so on-device startup, memory, rendering, launcher appearance, and minified runtime were unmeasured.
