import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/ad_frequency.dart';
import '../lib/logic/ad_service.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

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

  test('Time Attack automatically advances, survives opening again, then pays once', () async {
    var time = 1000;
    final store = MemoryStorage();
    final model = app(store, now: () => time);
    expect(await model.openAttack(), isTrue);
    final original = model.attack!.id;
    final deadline = model.attack!.deadline;
    time += 5000;
    complete(model);
    await Future<void>.delayed(Duration.zero);
    expect(model.activeId!.attackIndex, 1);
    time += 7000;
    complete(model);
    await Future<void>.delayed(Duration.zero);
    expect(model.activeId!.attackIndex, 2);
    expect(model.levelsSolved, 0);
    model.setForeground(false);
    await model.flush();
    model.dispose();

    time += 30000;
    final restored = app(store, data: await store.load(), now: () => time);
    expect(await restored.openAttack(), isTrue);
    expect(restored.attack!.id, original);
    expect(restored.attack!.deadline, deadline);
    expect(restored.attackRemaining.value.inMilliseconds, deadline - time);
    time = deadline;
    restored.refreshAttackClock();
    expect(restored.attack!.finished, isTrue);
    expect(restored.attack!.average, 6000);
    expect(restored.attack!.fastest, 5000);
    expect(restored.attackBest, 200);
    expect(restored.attack!.coins, 12);
    expect(restored.coinBalance, 52);
    restored.refreshAttackClock();
    await restored.flush();
    final restarted = app(store, data: await store.load(), now: () => time);
    restarted.refreshAttackClock();
    expect(restarted.attackHistory, hasLength(1));
    expect(restarted.coinBalance, 52);
    restored.dispose();
    restarted.dispose();
  });

  test('three hints persist after clear, reopen and replay; credit is scoped and idempotent', () async {
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
    expect(model.freeHints, 0);
    expect(model.canHint, isFalse);
    model.hint();
    expect(model.hintCell, isNull);
    await model.open(id, replay: true);
    expect(model.freeHints, 0);
    final ads = AdService();
    expect(
      await ads.watchVideo((event) => model.grantRewardedHint(id.key, event)),
      isFalse,
    );
    expect(model.extraHints, 0);
    expect(await model.grantRewardedHint(id.key, 'reward-1'), isTrue);
    expect(await model.grantRewardedHint(id.key, 'reward-1'), isFalse);
    expect(model.extraHints, 1);
    model.hint();
    expect(model.extraHints, 0);
    await model.flush();
    final restored = app(store, data: await store.load());
    await restored.open(id, replay: true);
    expect(restored.freeHints, 0);
    expect(restored.extraHints, 0);
    expect(await restored.grantRewardedHint(id.key, 'reward-1'), isFalse);
    ads.dispose();
    model.dispose();
    restored.dispose();
  });

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
        40 + economy.premiumBonus + Achievement.collector.coins,
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
      expect(restored.buyHint(), isTrue);
      expect(restored.buyHint(), isFalse);
      expect(
        await restored.grantRewardedHint('levels/1', 'reward-ad-free'),
        isFalse,
      );
      expect(restored.coinsSpent, economy.extraHintPrice);
      expect(restored.extraHints, 1);
      model.dispose();
      restored.dispose();
    },
  );

  test('frequency requires completed exits, monotonic spacing and post-reward cooldown', () {
    final caps = AdFrequency();
    for (var i = 0; i < 4; i++) {
      caps.completedExit();
    }
    expect(caps.eligible(Duration.zero), isFalse);
    caps.completedExit();
    expect(caps.eligible(Duration.zero), isTrue);
    caps.attemptedInterstitial(Duration.zero);
    for (var i = 0; i < 5; i++) {
      caps.completedExit();
    }
    expect(caps.eligible(const Duration(seconds: 239)), isFalse);
    caps.rewardedClosed(const Duration(seconds: 235));
    expect(caps.eligible(const Duration(seconds: 294)), isFalse);
    expect(caps.eligible(const Duration(seconds: 295)), isTrue);
  });
  test(
    'v2 retains verified ownership, balance and previous hint use',
    () async {
      final store = MemoryStorage();
      final v2 = app(
        store,
        data: {
          'schemaVersion': 2,
          'themePass': true,
          'ownedThemes': ['warmWalnut'],
          'preferences': {'theme': 'warmWalnut'},
          'ledger': [
            {
              'id': 'existing-coin',
              'label': 'Existing coins',
              'amount': 90,
              'at': '2026-11-22T00:00:00Z',
            },
          ],
          'results': {
            'levels/4': {'milliseconds': 1500, 'hints': 2},
          },
        },
      );
      await v2.open(const PuzzleId.level(4), replay: true);
      expect(v2.freeHints, 1);
      expect(v2.hasThemePass, isTrue);
      expect(v2.adFree, isFalse);
      expect(v2.ownedThemes, 14);
      expect(v2.theme.label, 'Warm Walnut');
      expect(v2.coinBalance, 90);
      await v2.flush();
      expect((await store.load())['schemaVersion'], 3);
      v2.dispose();
    },
  );
  test(
    'persisted ad pacing also protects the first minutes after a reboot',
    () async {
      var clock = 60000;
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'schemaVersion': 3,
          'lastAutomaticAd': {'boot': 4, 'milliseconds': 2000000},
        },
        bootTime: () => (boot: 5, milliseconds: clock),
      );
      expect(await model.reserveAutomaticAd(), isFalse);
      clock = 240000;
      expect(await model.reserveAutomaticAd(), isTrue);
      expect(await model.reserveAutomaticAd(), isFalse);
      model.dispose();
    },
  );
}
