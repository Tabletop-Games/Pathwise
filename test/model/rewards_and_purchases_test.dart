import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:material_ui/material_ui.dart';

import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/game_state_storage.dart';
import '../../lib/logic/puzzle_generator.dart';
import '../../lib/logic/puzzle_solver.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/app_themes.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/game_state.dart';
import '../../lib/model/user_preferences.dart';
import '../support/fixtures.dart' show MemoryStorage, complete, fixture;
import '../../lib/logic/ad_frequency.dart';

final day = DateTime(2026, 11, 22);

AppModel create(
  MemoryStorage store, [
  Map<String, dynamic> saved = const {},
]) => AppModel(
  storage: store,
  snapshot: saved,
  today: () => day,
  loader: (_) async => fixture(),
)..setHaptics(false);

AppModel app(
  MemoryStorage store, {
  Map<String, dynamic> data = const {},
  int Function()? now,
}) => AppModel(
  storage: store,
  snapshot: data,
  loader: (_) async => fixture(),
  bootTime: () => (boot: 5, milliseconds: now?.call() ?? 0),
)..setHaptics(false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('level unlock, achievement and reward are durably idempotent including replay', () async {
    final store = MemoryStorage();
    final model = create(store);
    await model.open(const PuzzleId.level(2));
    expect(model.activeId, isNull);
    await model.open(const PuzzleId.level(1));
    complete(model);
    expect(model.highestUnlocked, 2);
    expect(model.lastReward, 48);
    expect(model.coinBalance, 98);
    expect(model.hasAchievement(Achievement.trailhead), isTrue);
    await model.open(const PuzzleId.level(1), replay: true);
    complete(model);
    expect(model.lastReward, 0);
    expect(model.coinBalance, 98);
    expect(model.levelsSolved, 1);
    await model.flush();
    final restored = create(store, await store.load());
    expect(restored.highestUnlocked, 2);
    expect(restored.coinBalance, 98);
    expect(
      restored.transactions.where((tx) => tx.id == 'achievement/trailhead'),
      hasLength(1),
    );
    model.dispose();
    restored.dispose();
  });

  test('a saved game restores results, the unfinished route, preferences and play time', () async {
    final store = MemoryStorage();
    final model = create(store, {
      'results': {
        'levels/36': {'milliseconds': 60000, 'hints': 1},
        'daily/2026-11-20': {'milliseconds': 50000, 'hints': 0},
        'daily/2026-11-21': {'milliseconds': 49000, 'hints': 0},
      },
      'preferences': {'theme': 'terracotta', 'haptics': false},
      'attempts': {
        'levels/14': {
          'milliseconds': 3000,
          'hints': 0,
          'path': [0, 1, 2],
          'history': [
            [0],
          ],
          'started': true,
        },
      },
    });
    expect(model.highestUnlocked, 37);
    expect(model.levelsSolved, 1);
    expect(model.theme, PathwiseTheme.terracotta);
    expect(model.ownedThemes, 4);
    expect(model.result(const PuzzleId.level(36))!.milliseconds, 60000);
    expect(model.solved, 3);
    expect(model.playTime.inMilliseconds, 159000);
    await model.open(const PuzzleId.level(14));
    expect(model.path, [0, 1, 2]);
    model.close();
    await model.flush();
    final snapshot = await store.load();
    expect(snapshot['schemaVersion'], GameStateStorage.schemaVersion);
    final restored = create(store, snapshot);
    expect(restored.coinBalance, 0);
    expect(restored.highestUnlocked, 37);
    expect(restored.hasAttempt(const PuzzleId.level(14)), isTrue);
    model.dispose();
    restored.dispose();
  });

  test(
    'verified grant and theme purchase cannot double credit or debit',
    () async {
      final store = MemoryStorage();
      final model = create(store);
      final price = economy.themePrice(PathwiseTheme.forestMint);
      final balance = economy.starterCoins + 220 - price;
      expect(model.unlockTheme(PathwiseTheme.forestMint), isFalse);
      expect(
        await model.applyVerifiedPurchase('grant-a', coins: 220, themes: false),
        isTrue,
      );
      expect(
        await model.applyVerifiedPurchase('grant-a', coins: 220, themes: false),
        isTrue,
      );
      expect(model.coinsEarned, economy.starterCoins + 220);
      expect(model.unlockTheme(PathwiseTheme.forestMint), isTrue);
      expect(model.unlockTheme(PathwiseTheme.forestMint), isFalse);
      expect(model.coinBalance, balance);
      expect(model.coinsSpent, price);
      await model.flush();
      final restored = create(store, await store.load());
      expect(restored.ownsTheme(PathwiseTheme.forestMint), isTrue);
      expect(restored.theme, PathwiseTheme.forestMint);
      expect(restored.coinBalance, balance);
      expect(
        await restored.applyVerifiedPurchase(
          'grant-a',
          coins: 120,
          themes: false,
        ),
        isTrue,
      );
      expect(restored.coinBalance, balance);
      expect(
        await restored.applyVerifiedPurchase(
          'grant-pass',
          coins: 0,
          themes: true,
        ),
        isTrue,
      );
      expect(restored.ownedThemes, PathwiseTheme.values.length);
      expect(restored.hasAchievement(Achievement.collector), isTrue);
      model.dispose();
      restored.dispose();
    },
  );

  test('reward days survive restart and reject rollback', () async {
    var now = DateTime(2026, 11, 23, 23, 59);
    final store = MemoryStorage();
    AppModel launch(Map<String, dynamic> snapshot) =>
        AppModel(storage: store, snapshot: snapshot, today: () => now);
    var model = launch({});
    expect(await model.grantAdBonus('before-midnight'), true);
    await model.flush();
    model.dispose();
    model = launch(await store.load());
    expect(model.adsToday, 1);
    now = DateTime(2026, 11, 24);
    expect(model.adsToday, 0);
    expect(await model.grantAdBonus('after-midnight'), true);
    now = DateTime(2026, 11, 23);
    expect(await model.grantAdBonus('rollback'), false);
    expect(await model.grantHintAd('rollback-hint'), false);
    model.dispose();
  });

  test(
    'daily streak bonuses and milestones persist once across a seven-day run',
    () async {
      var now = DateTime(2026, 11, 16);
      final store = MemoryStorage();
      final model = AppModel(
        storage: store,
        snapshot: {},
        today: () => now,
        loader: (_) async => fixture(),
      )..setHaptics(false);
      for (var index = 0; index < 7; index++) {
        now = DateTime(2026, 11, 16 + index);
        await model.open(model.daily);
        complete(model);
      }
      expect(model.dailyStreak, 7);
      expect(model.longestStreak, 7);
      expect(model.lastReward, 10 + 100 + 25 + 45);
      final balance = model.coinBalance;
      await model.open(model.daily, replay: true);
      complete(model);
      expect(model.lastReward, 0);
      expect(model.coinBalance, balance);
      await model.flush();
      final restored = create(store, await store.load());
      expect(restored.longestStreak, 7);
      expect(restored.hasAchievement(Achievement.weeklyRitual), isTrue);
      expect(
        restored.transactions.where(
          (item) => item.id.startsWith('play-streak-week/'),
        ),
        hasLength(1),
      );
      model.dispose();
      restored.dispose();
    },
  );

  test(
    'resume and replay preserve the global wallet and ad deduplication',
    () async {
      final store = MemoryStorage();
      final model = app(store);
      const id = PuzzleId.level(1);
      await model.open(id);
      model.tap(3);
      model.hint();
      expect(model.correctedByHint, isTrue);
      expect(model.path, [0]);
      model.clear();
      model.hint();
      expect(model.path.length, 3);
      model.clear();
      model.hint();
      expect(model.path.length, 5);
      model.clear();
      expect(model.hintsRemaining, 0);
      expect(model.canHint, isFalse);
      model.hint();
      expect(model.hintCell, isNull);
      await model.open(id);
      expect(model.hintsRemaining, 0);
      final ads = AdService();
      expect(await ads.watchVideo(model.grantHintAd), isFalse);
      expect(model.hintsRemaining, 0);
      expect(await model.grantHintAd('reward-1'), isTrue);
      expect(await model.grantHintAd('reward-1'), isFalse);
      expect(model.hintsRemaining, 1);
      model.hint();
      expect(model.hintsRemaining, 0);
      await model.flush();
      final restored = app(store, data: await store.load());
      await restored.open(id);
      expect(restored.hintsRemaining, 0);
      await restored.open(id, replay: true);
      expect(restored.hintsRemaining, 0);
      expect(await restored.grantHintAd('reward-1'), isFalse);
      ads.dispose();
      model.dispose();
      restored.dispose();
    },
  );

  test(
    'verified Premium grants both permanent entitlements and one bonus',
    () async {
      final store = MemoryStorage();
      final model = app(store);
      await model.applyVerifiedPurchase(
        'one',
        coins: 0,
        themes: false,
        bundle: true,
      );
      await model.applyVerifiedPurchase(
        'retry',
        coins: 0,
        themes: false,
        bundle: true,
      );
      expect(model.hasThemePass && model.adFree && model.premium, isTrue);
      expect(
        model.coinBalance,
        50 + economy.premiumBonus + Achievement.collector.coins,
      );
      await model.flush();
      final restored = app(store, data: await store.load());
      expect(
        restored.hasThemePass && restored.adFree && restored.premium,
        isTrue,
      );
      expect(
        restored.transactions.where((tx) => tx.id == 'premium/bonus'),
        hasLength(1),
      );
      await restored.open(const PuzzleId.level(1));
      for (var i = 0; i < 3; i++) {
        restored.hint();
        restored.clear();
      }
      expect(await restored.buyHint(), isTrue);
      expect(await restored.grantHintAd('reward-ad-free'), isTrue);
      expect(restored.coinsSpent, economy.hintPrice);
      expect(restored.hintsRemaining, 2);
      model.dispose();
      restored.dispose();
    },
  );
}
