# Pathwise Architecture Audit

**Baseline commit:** `98c7727` (`main`)  
**Scope:** Repository-wide MVVM, state ownership, dependency direction, transaction integrity, offline-first persistence & cloud sync, gameplay/Journey rendering, lifecycle, and testability audit.

---

## Executive Summary

Pathwise has strong foundations in several areas:
- Pure puzzle rules (`lib/logic/puzzle.dart`), solver (`lib/logic/puzzle_solver.dart`), and generator (`lib/logic/puzzle_generator.dart`) are pure Dart and deterministically tested.
- Cloud save planning (`lib/cloud/cloud_save_format.dart`) is pure Dart, digest-verified, and separates `economyDigest` from `progressKeys` with explicit conflict resolution.
- `GameStateStorage` uses a write-protection guard (`protect()`), and `PuzzleBoard` already separates pointer tip rendering into its own `RepaintBoundary` layer.

However, rapid feature iteration (Economy 2.0, Journey isometric artwork, Fortune Wheel, Mystery Rewards, offline-first mode, Boosts/Research) has accumulated significant architectural debt:
1. **`AppModel` (`lib/model/app_model.dart`, 2,460 lines)** has grown into a God Object owning persistence, wallet transactions, gameplay session state, Time Attack timers, supply crates, Journey/mystery/chest state, Fortune Wheel, monetization callbacks, tutorials, and settings.
2. **Non-atomic transaction mutations & SDK lifecycle bugs** create real risks of inconsistent in-memory vs. persisted state, dropped rewarded-ad payouts, wedged billing queues, and cloud sync races.
3. **Views directly implement business rules and call platform/SDK APIs** (`AdService`, `BillingService`, `PlayGames`, `InAppUpdateFlutter`, `ShareDestinationService`, `rootBundle`, `BannerAd`).
4. **Broad `context.watch<AppModel>()` and 1-second `setState` timers** trigger unnecessary full-screen rebuilds during gameplay, Store browsing, Boosts, Fortune Wheel, and Home.

---

## Findings by Severity

### Critical

#### C1. Non-atomic in-memory state mutations before `flush()` in `AppModel`
- **Location:** `lib/model/app_model.dart` — `applyVerifiedPurchase` (`L1684-1709`), `grantBoostAd` (`L690-702`), `claimVerifiedCrate` (`L781-811`), `grantHintAd` (`L895-903`), `claimMysteryReward` (`L1232-1263`), `spinRewardedFortune` (`L1525-1547`), `grantAdBonus` (`L1645-1672`), `buyHint` (`L879-893`), `buyTip` (`L992-1014`), `claimChapter` (`L1062-1075`), `buyFreeze` (`L1789-1810`), `unlockTheme` (`L1455-1472`), `research` (`L651-669`), `buyBoost` (`L704-723`).
- **Current implementation:** `applyVerifiedPurchase` lacks a `storageError` guard and mutates `_themePass`, `_removeAds`, `_premium`, and `_wallet` before `flush()`. Similarly, ad-reward and spend methods mutate `_wallet`, `_hintBalance`, `_hintEvents`, `_ownedTips`, `_owned`, and `progression` in memory before `await flush()` succeeds, without rollback on write failure (unlike `acknowledgeMechanic` at `L916-925`). Additionally, `flush()` passes a live mutable `snapshot` map to `onPersisted?.call(snapshot)` after `await storage.save(payload)` (`L2311-2316`).
- **Architectural problem:** Persistence is not transactional with in-memory state, and the cloud sync callback receives mutable references that can change across an `await`.
- **Practical consequences:** On storage write failure, `flush()` returns `false` while in-memory balances/entitlements/dedup keys (`_hintEvents`, `_wallet`) remain mutated—blocking retries in-session while disk never recorded the change.
- **Proposed correction:** Guard `applyVerifiedPurchase` against `storageError` (except when recovering entitlements safely), roll back or stage state mutations on failed `flush()` for async transactions, and pass an immutable/decoded snapshot copy to `onPersisted`.
- **Refactoring risk:** Medium (must preserve exact return values and synchronous `Wallet` behavior for existing callers/tests).
- **Required regression coverage:** Unit tests simulating `GameStateStorage.save()` throwing on `buyTip`, `buyHint`, `grantAdBonus`, `grantHintAd`, `grantBoostAd`, `claimVerifiedCrate`, `claimMysteryReward`, and `applyVerifiedPurchase`.

#### C2. `AppSession.replaceModel` ignores `flush()` failure
- **Location:** `lib/main.dart:143-153` (`AppSession.replaceModel`), `lib/cloud/cloud_sync_service.dart:345-357, 430-437`.
- **Current implementation:** `replaceModel` awaits `next.flush()` and discards the `bool` result. `CloudSyncService` proceeds to call `_markSynced()`.
- **Architectural problem:** Sync state transitions assume local persistence succeeded without checking the write result.
- **Practical consequences:** If `storage.protect()` is active from a startup load failure, `next.flush()` fails (`storageError = true`), yet `CloudSyncService` records that local matches cloud.
- **Proposed correction:** Return `Future<bool>` from `ApplySnapshot` / `replaceModel` and abort `_markSynced()` if local persistence fails.
- **Refactoring risk:** Low.
- **Required regression coverage:** `CloudSyncService` test where `apply` returns `false` verifying `_base` is not updated and status reflects error.

#### C3. `AdService.watchVideo` drops earned rewards and misreports `true` on show failure
- **Location:** `lib/logic/ad_service.dart:367-448` (`watchVideo`), `lib/views/puzzle_view.dart:985-986` (`showHintShop`).
- **Current implementation:** `watchVideo` returns `true` unconditionally once `ad.show()` is invoked—even if `onAdFailedToShowFullScreenContent` fires, `ad.show()` throws, or the user closes without earning. `onUserEarnedReward` checks `if (granted || closed || _disposed) return;` (`L421`), dropping legitimate rewards if `onAdDismissedFullScreenContent` or the 3-minute `expiry` timer fires first, or if `PathwiseApp` rebuilds. `dispose()` does not cancel active `expiry` timers.
- **Architectural problem:** Ad SDK completion, reward delivery, and widget/service disposal lifecycles are conflated.
- **Practical consequences:** Players can lose earned rewards on slow SDK callbacks or have dialogs dismiss (`showHintShop`) even when the ad failed to show.
- **Proposed correction:** Track active `expiry` timers and cancel on `dispose()`; only return `true` when `granted && rewardApplied`; do not discard `onUserEarnedReward` solely because `closed` fired before the reward callback.
- **Refactoring risk:** Medium (must preserve AdMob callback ordering tests).
- **Required regression coverage:** `AdService` tests for `onAdFailedToShowFullScreenContent`, dismissal without reward, reward arriving after dismissal, and `dispose()` cancelling `expiry` timer.

#### C4. `BillingService` queue, verification, and `_buying` lock bugs
- **Location:** `lib/logic/billing_service.dart:116-135` (`reconcileEntitlements`), `L167-176` (`buy`), `L212-247` (`_receive` / `_handle`).
- **Current implementation:** `buy()` awaits `readyForConsumable!()` before setting `_buying = true` and without re-checking `_disposed`. `_receive()` chains `_queue = _queue.then((_) => _handle(purchase))` without error handling. Unknown `productID` exits `_handle` early before resetting `_buying = false`. `reconcileEntitlements()` trusts `queryPastPurchases()` without `_verify()`.
- **Architectural problem:** Asynchronous purchase queue lacks error isolation and state-guard discipline.
- **Practical consequences:** Concurrent `buy()` calls can race; an uncaught exception in `_handle` permanently breaks `_queue`; `_buying` can wedge `true` indefinitely.
- **Proposed correction:** Guard `buy()` with `_buying` before `await` (or a lock flag), re-check `_disposed` after `await`, catch/recover errors in `_queue` and reset `_buying` in `finally`, and verify past purchases consistently where platform details are available.
- **Refactoring risk:** Medium.
- **Required regression coverage:** Unit tests for `BillingService.buy()`, `_receive()` queue error recovery, `_buying` reset on unknown product, and `restore()`/`reconcileEntitlements()`.

#### C5. `CloudSyncService` concurrency, conflict, and persistence races
- **Location:** `lib/cloud/cloud_sync_service.dart:131-152, 156-174, 183-220, 223-255, 476-482`; `lib/cloud/cloud_save_format.dart:259-268` (`combine`).
- **Current implementation:** `start()`, `signIn()`, `signOut()` bypass `_lock`. `localChanged()` and `syncNow()` do not guard against `_choice != null` or `status == CloudSyncStatus.damaged`. `restoreFromCloud()` ignores `fetch.conflict`, lacks `try/catch`, and skips `_finish()`. `resolveChoice(keepDevice: true)` unconditionally sets `CloudSyncStatus.idle` even when `_writeCloud()` fails. `_markSynced()` fires `unawaited(_store.setString(...))`. `combine()` takes `schemaVersion` from `progressFrom` instead of `economyFrom`.
- **Architectural problem:** State machine transitions in `CloudSyncService` are not uniformly serialized or guarded.
- **Practical consequences:** Backgrounding or route edits while a conflict dialog is open can clobber `conflict`/`damaged` state; failed conflict resolution hides errors; `signOut()` can be overwritten by an in-flight `_run()`.
- **Proposed correction:** Serialize `start`/`signIn`/`signOut` through `_lock`, guard `localChanged`/`syncNow` when `_choice != null` or `damaged`, handle `fetch.conflict` and exceptions in `restoreFromCloud` and `resolveChoice`, `await` `_store.setString` in `_markSynced`, and take `schemaVersion` from `economyFrom` in `combine()`.
- **Refactoring risk:** Medium.
- **Required regression coverage:** `CloudSyncService` tests for `signOut` during sync, `localChanged` during conflict/damaged state, `restoreFromCloud` on conflict/error, and `resolveChoice` on write failure.

#### C6. Lifecycle and UI-wedging bugs in Views
- **Location:**
  - `lib/views/mechanic_tutorial_view.dart:108-110` + `lib/views/components/puzzle_board.dart:582`: `rejectionFor()` calls `setState(() => rejected = true)` during `PuzzleBoard.build()`.
  - `lib/views/falling_crate.dart:136-157, 168`: `_CrateRewardState._claim` can return early when `!_current()` without resetting `_busy = false`, leaving `PopScope(canPop: false)` wedged.
  - `lib/views/connection_view.dart:59-77`: `_ConnectionGateState` never resets `_shownForOfflinePeriod = false` on `ConnectivityState.online`.
  - `lib/views/play_games_view.dart:25-34`: `_PlayGamesViewState._run` lacks `try/finally` around `await action()`.
  - `lib/views/journey_rewards.dart:797-819, 991-995`: Missing `mounted` checks between `await`s in `_DiscoveryRowState` and `_ChapterRewardDialogState._claim`.
- **Proposed correction:** Defer `rejected` update via post-frame callback or ViewModel state outside `build()`; reset `_busy` in `finally`; reset `_shownForOfflinePeriod` when online; add `mounted` checks after every `await`.
- **Refactoring risk:** Low.
- **Required regression coverage:** Widget tests for second offline transition in `ConnectionGate`, crate claim interruption, and tutorial rejection without `setState` during `build`.

---

### High

#### H1. `AppModel` God Object (`lib/model/app_model.dart`, 2,460 lines)
- **Current implementation:** Single `ChangeNotifier` owning 9+ unrelated feature domains (gameplay session, Time Attack, supply crates, Journey/chests/mysteries, Fortune Wheel, ads/billing coordination, tutorials, achievements, settings, and snapshot persistence).
- **Architectural problem:** Violates Single Responsibility; forces every screen to depend on one massive mutable surface; makes isolated testing of feature ViewModels impossible without constructing the entire `AppModel`.
- **Proposed correction:** Keep `AppModel` as the coherent shared player-state & persistence coordinator (or delegate internal domains to focused coordinators), and extract dedicated, widget-free feature ViewModels (`GameplayViewModel`, `StoreViewModel`, `ProgressionViewModel`, `FortuneViewModel`, `JourneyViewModel`, `HomeViewModel`, `StreakViewModel`, `CrateViewModel`, `SettingsViewModel`, `PlayGamesViewModel`, `TutorialViewModel`).
- **Refactoring risk:** High if done as a big-bang rewrite; Low-Medium if done incrementally while preserving `AppModel` public contracts for shared state.

#### H2. Business rules, economy calculations, and SDK orchestration inside Views
- **Location:** `store_view.dart`, `progression_view.dart`, `puzzle_view.dart`, `main_menu_view.dart`, `streak_view.dart`, `journey_rewards.dart`, `fortune_view.dart`, `falling_crate.dart`, `play_games_view.dart`, `settings_view.dart`, `share_view.dart`, `level_one_demo.dart`, `mechanic_tutorial_view.dart`, `components/ad_banner.dart`.
- **Architectural problem:** Views compute shortfalls, ad reward amounts, boost durations, ad limits, share eligibility, and directly invoke `AdService`, `BillingService`, `PlayGames`, `InAppUpdateFlutter`, `ShareDestinationService`, `BannerAd`, and `rootBundle`.
- **Proposed correction:** Move all presentation-state derivation, shortfall routing, and service orchestration into feature ViewModels and properly scoped services (`AdService` for banners, `UpdateService` for `InAppUpdateFlutter`, `PlayGamesService` wrapper for `PlayGames`).

#### H3. Broad `context.watch<AppModel>()` rebuilds and 1-second full-screen `setState` timers
- **Location:** `puzzle_view.dart:39`, `store_view.dart:68-70`, `progression_view.dart:162-167, 231`, `fortune_view.dart:38-42, 152-153`, `main_menu_view.dart:117-119`, `campaign_journey_view.dart:139`, `journey_rewards.dart:654-656, 854`.
- **Architectural problem:** Coarse `watch` subscriptions and top-level 1s timers rebuild entire screens (including `PuzzleBoard`, `Semantics`, 22 theme previews, and 42 collection cards) on unrelated state changes or countdown ticks.
- **Proposed correction:** Scope timers to leaf countdown widgets (`_WheelCooldownBadge`, `_ActiveBoostCountdown`) and replace broad `watch<AppModel>()` with targeted `context.select` / ViewModel `ListenableBuilder`s.

#### H4. Gameplay & Journey rendering boundary leaks
- **Location:**
  - `lib/views/components/puzzle_board.dart:582, 1101, 1324-1343, 1496`: `_BoardPainter` and `_TipPainter` attach `_rejection` (repainting all 3 `RepaintBoundary` layers on rejection); `_PuzzleBoardState.build` mutates `_preferredRest` and calls `rejectionFor` during `build()`; `_BoardPainter` allocates `TextPainter` per checkpoint on every repaint.
  - `lib/views/journey_landscape.dart:234, 356-389`: `canvas.saveLayer` on chapter boundaries and `repaint: GameAssetCache.instance` on every mounted Journey row.
  - `lib/views/campaign_journey_view.dart:506-509`: `Image.asset` without `cacheWidth`/`cacheHeight`.
- **Proposed correction:** Decouple `_rejection` from `_BoardPainter`/`_TipPainter`, cache checkpoint `TextPainter`s, move `_restingDirection` out of `build()`, scope `GameAssetCache` repaints, and add `cacheWidth`/`cacheHeight` to Journey node images.

#### H5. Upward and cross-layer dependency violations
- **Location:**
  - `lib/logic/achievement_sync.dart:7`: `lib/logic` imports and mutates `AppModel`.
  - `lib/cloud/cloud_save_provider.dart:7`: `lib/cloud` imports `../logic/play_games.dart`.
  - `lib/model/app_themes.dart:1`: `lib/model` imports `package:material_ui/material_ui.dart`.
  - `lib/logic/social_sharing.dart:1`: mixes pure sharing formatting with `MethodChannel` / `Clipboard`.
  - `lib/logic/star_rating.dart:64`: module-level mutable `_levelThresholdCache`.
  - `lib/views/puzzle_view.dart:973`: calls `ads.isOnline()` bypassing `ConnectivityService`.
- **Proposed correction:** Invert `AchievementSync` to use callbacks/state interface; inject `enabled` into `PlayGamesCloudSaves`; move `BoardPalette` / `ThemeData` to `lib/ui/`; split pure sharing formatter from platform `ShareDestinationService`; encapsulate threshold cache or make it injectable/clearable; route online checks through `ConnectivityService`.

#### H6. Dormant iOS / StoreKit code in an Android-only codebase
- **Location:** `lib/logic/ad_service.dart` (`_ios`, iOS AdMob IDs, `adsConfigured`), `lib/logic/billing_service.dart` (`_storeName`, `verifyStoreKitPurchase`).
- **Proposed correction:** Remove dormant iOS branches from `AdService` and `BillingService` per `AGENTS.md`.

---

### Medium

- **M1.** Wheel daily video limit mismatch: `economy.wheelAdsPerDay` is `6` (`lib/model/economy.dart:59`) while `FortuneStatus` (`lib/model/fortune.dart:68, 81`) hardcodes `4`.
- **M2.** Duplicated boost duration formula in `progression.dart:184` and `progression_view.dart:472, 823`.
- **M3.** Duplicated `AdFrequency` constants between `economy.dart:47-49` and `ad_frequency.dart:5-7`.
- **M4.** Duplicated `nextCheckpoint` / `portalHop` / `tipDirection` logic across `GameController`, `TipTracker`, and `puzzle_board.dart`.
- **M5.** Unbounded `_hintEvents`, `_hintAdDays`, `_coinAdDays`, `_boostAdDays` in `AppModel` save payload (`L2364-2367`).
- **M6.** `AchievementSync._reconcile` (`L244-248`) calls `bindAchievementProgress` even when `needsBinding == false`, triggering redundant `flush()` + cloud sync.
- **M7.** `ConnectivityService.retry()` (`L82, 99`) is silently ignored if `_checking == true`.
- **M8.** `GameAssetCache` in-flight loads can repopulate `_images` after `evictJourneyAssets()`.
- **M9.** Hardcoded colors in `_JourneyNode` (`campaign_journey_view.dart:416-420`) instead of `BoardPalette`.
- **M10.** Inconsistent `showDialog` / `AlertDialog` usage vs `showGameDialog` / `GameDialog`.

---

### Low

- **L1.** Dead branch in `PuzzleId.generation` (`lib/model/game_state.dart:88`).
- **L2.** `AttackRun.fromJson` fallback `minutes = 10` vs constructor default `3` (`lib/model/time_attack.dart:15, 28`).
- **L3.** Outdated claims in `docs/architecture.md` (offline behavior, schema 13) and `docs/cloud-saves.md` (envelope v4).
- **L4.** `GameStateStorage` lacks direct unit tests; no automated architectural import boundary tests exist.
