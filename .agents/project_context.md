# Project context

Pathwise is a wall-free Android route puzzle based on the Flutter Provider MVVM structure of [shenmareparas/Chess](https://github.com/shenmareparas/Chess). `GameController` owns edits and Undo, `Puzzle` defines the orthogonal graph, `puzzle_solver.dart` counts solutions, and `AppModel` coordinates the clock, progression, wallet, and SharedPreferences DataStore.

## Gameplay and progression

The head starts at checkpoint 1. Each legal forward edit is orthogonal, unvisited, and in checkpoint order. The last checkpoint is reachable only when the move covers the last open cell. Retraction removes an existing suffix. Hint follows the uniquely certified solution. There are no walls. See [gameplay research](../docs/gameplay.md).

The level browser lays out twelve tiles per horizontal page. Completing the highest unlocked level unlocks its successor. Earlier and completed levels remain playable so migrated saves with gaps retain access. Level 1–36, daily, and endless preserve v1 generation. Levels 37 onward use the pathwise-v2 seed name and seven target bands with decreasing checkpoint density. The bounded solver certifies every accepted clue removal. The last certified layout is the fallback, so a budget timeout cannot be mistaken for uniqueness. Generation runs in an isolate.

## State and services

`pathwise.save.v1` remains the storage key with schema version 3 in the JSON payload. Versionless v1 snapshots retain routes, best times, streak records, and equipped starter themes. An append-only coin ledger tracks balance, spending, earned rewards and achievement IDs. All mutations share the same queued snapshot writer. See [economy balancing](../docs/economy.md).

The theme catalog comprises three existing starter themes and eleven paid-with-coins or bundle themes, with original Pathwise palettes adapted from named Chess themes. Store previews apply a local theme without equipping. Accessibility tests check text contrast and app widgets expose labeled controls and board semantics.

The billing service observes Google Play purchase states. A HTTPS verifier uses Play Developer API and a Firestore token claim before the app writes a grant. Only then does the client consume or acknowledge. The ad service follows Chess's UMP consent and lazy cache pattern with optional videos and post-game interstitials. Both services are disabled unless configured. See [deployment](../docs/monetization.md).

## Android

The app targets API 36, supports API 24+, and uses AGP 9.3.1 and Gradle 9.5 with JDK 21. Release R8 and resource shrinking are explicit, using the standard optimize configuration and SDK consumer rules. Preserve the mapping and native symbol tables off-repo. Flutter engine outputs cover arm64-v8a, armeabi-v7a, and x86_64. Production signing and store publishing are external.

## Known limits and next work

Offline data is installation-local. Restoration of paid themes requires the same billing profile, such as from Android's app-data restore. Consumed packs cannot be queried from Play's owned inventory. v1 total play time is estimated from best times. Very large saved catalogs still use a single JSON snapshot, so audit write latency before moving to a database. Measure cold start, memory and frame pacing on representative Android devices. Add authenticated cross-device entitlement recovery and a refund reconciliation policy before wide commerce rollout.

Time Attack uses its own board IDs, attempt, score history and capped wallet events. The Android monotonic deadline survives process recreation within the same boot. A different boot ends a resumed run. Permanent store entitlements are granted only after Play verification. Ad-free owners can spend six coins on one additional hint after exhausting the free allowance. [Release behavior and tests](../docs/release-1.2.0.md)
