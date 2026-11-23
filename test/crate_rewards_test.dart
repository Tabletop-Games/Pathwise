import 'package:flutter_test/flutter_test.dart';

import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import '../lib/model/native_achievements.dart';
import '../lib/model/progression.dart';
import '../lib/model/time_attack.dart';
import '../lib/model/user_preferences.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('short clears combine their eligible time and the final move awards a crate', () async {
    final store = MemoryStorage();
    var clock = (boot: 1, milliseconds: 1000);
    Future<AppModel> launch() async => AppModel(
      storage: store,
      snapshot: await store.load(),
      bootTime: () => clock,
      loader: (_) async => fixture(),
    )..setHaptics(false);
    var model = await launch();
    for (var level = 1; level <= 3; level++) {
      await model.open(PuzzleId.level(level));
      model.tap(1);
      clock = (boot: clock.boot, milliseconds: clock.milliseconds + 15000);
      complete(model);
      if (level < 3) expect(model.unopenedCrates, isEmpty);
      model.close();
      await model.flush();
      if (level == 2) {
        model.dispose();
        clock = (boot: 2, milliseconds: 150000);
        model = await launch();
      }
    }
    final crate = model.unopenedCrates.single;
    final before = model.coinBalance;
    expect(model.transactions.where((tx) => tx.id == crate.id), isEmpty);
    model.dispose();

    clock = (boot: 3, milliseconds: 2000000);
    model = await launch();
    expect(model.unopenedCrates.single, crate);
    final results = await Future.wait([
      model.claimCrate(crate.id),
      model.claimCrate(crate.id),
    ]);
    expect(results, [true, false]);
    expect(model.unopenedCrates, isEmpty);
    expect(model.coinBalance, greaterThanOrEqualTo(before + crate.coins));
    expect(
      model.transactions.singleWhere((tx) => tx.id == crate.id).amount,
      crate.coins,
    );
    final earned = model.coinBalance;
    model.dispose();

    model = await launch();
    expect(model.coinBalance, earned);
    expect(model.unopenedCrates, isEmpty);
    expect(await model.claimCrate(crate.id), false);
    model.dispose();
  });

  testWidgets(
    'an open puzzle ticks, pauses in background and waits until a stroke ends',
    (tester) async {
      var milliseconds = 100;
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        bootTime: () => (boot: 1, milliseconds: milliseconds),
        loader: (_) async => fixture(),
      )..setHaptics(false);
      await model.open(const PuzzleId.level(1));
      model.begin(1);
      milliseconds += 45000;
      await tester.pump(const Duration(seconds: 45));
      expect(model.unopenedCrates, isEmpty);
      model.end();
      await tester.pump();
      expect(model.unopenedCrates, hasLength(1));
      final crate = model.unopenedCrates.single;
      expect(await model.claimCrate(crate.id), true);

      model.setForeground(false);
      milliseconds += 300000;
      await tester.pump(const Duration(minutes: 5));
      model.setForeground(true);
      expect(model.unopenedCrates, isEmpty);
      milliseconds += 150000;
      await tester.pump(const Duration(minutes: 2, seconds: 30));
      expect(model.unopenedCrates, hasLength(1));
      await model.flush();
      model.dispose();
    },
  );

  test(
    'opening a legendary crate awards coins and its achievement once',
    () async {
      final store = MemoryStorage();
      var model = AppModel(
        storage: store,
        snapshot: {
          'progression': {
            'serial': 18,
            'crates': [
              {'id': 'crate/17', 'rarity': 'legendary', 'coins': 150},
            ],
          },
        },
      );
      expect(await model.claimCrate('crate/17'), true);
      expect(model.coinBalance, 250);
      expect(model.hasAchievement(Achievement.legendaryCrate), true);
      expect(model.progression.legendary, 1);
      model.dispose();

      model = AppModel(storage: store, snapshot: await store.load());
      expect(await model.claimCrate('crate/17'), false);
      expect(model.coinBalance, 250);
      expect(model.progression.legendary, 1);
      model.dispose();
    },
  );

  test('crate cap uses monotonic time across calendar changes and reboot', () {
    final state = Progression({
      'crateWait': 0,
      'ranks': {'collector': 6},
    });
    const first = 200000;
    for (var drop = 0; drop < 6; drop++) {
      state.accrueCrateTime(150000);
      expect(
        state.considerCrate((
          boot: 1,
          milliseconds: first + drop * 150000,
        ), () => 0),
        true,
      );
    }
    state.accrueCrateTime(150000);
    final restored = Progression(state.toJson());
    expect(restored.crates.length, 6);
    expect(restored.considerCrate((boot: 2, milliseconds: 1), () => 0), false);
    expect(
      restored.considerCrate((boot: 2, milliseconds: 86400000), () => 0),
      true,
    );
    restored.accrueCrateTime(150000);
    expect(
      restored.considerCrate((boot: 2, milliseconds: 86550000), () => 0),
      false,
    );
  });

  test('legacy saves preserve balances, completed puzzles, earned themes and one-time refunds', () async {
    final store = MemoryStorage();
    const BootTime stamp = (boot: 7, milliseconds: 150000);
    Map<String, Object> transaction(String id, String label, int amount) => {
      'id': id,
      'label': label,
      'amount': amount,
      'at': '2026-11-23T12:00:00Z',
    };
    AppModel launch(Map<String, dynamic> snapshot) =>
        AppModel(storage: store, snapshot: snapshot, bootTime: () => stamp);
    var model = launch({
      'schemaVersion': 8,
      'archivedTrailCoins': 1000,
      'ledger': [
        transaction('trail/1/3', 'Old trail', 12),
        transaction('notes/week/12', 'Old objective', 64),
        transaction('research/fieldwork/0', 'Fieldwork', -210),
        transaction('boost/10', '50% more first-qualification base coins', -12),
      ],
      'expeditionProgress': {
        'next': 4,
        'stages': 5,
        'clean': 1,
        'qualifiedClean': 26,
      },
      'expedition': {'obsolete': 'intentionally unreadable'},
      'fieldNotes': {'obsolete': 'ignored'},
      'highestUnlocked': 71,
      'hintTank': 2,
      'ownedThemes': ['basinGold'],
      'preferences': {'theme': 'basinGold'},
      'attempts': {'expedition/10/2/0': {}, 'levels/71': {}},
      'results': {
        'levels/70': {'milliseconds': 500, 'hints': 0},
      },
      'progressionBoot': 6,
      'progression': {
        'serial': 12,
        'ranks': {'expedition': 3, 'fieldwork': 1, 'hunter': 3},
        'inventory': {'trailProvisions': 1, 'doubleTen': 1},
        'crate': {
          'id': 'crate/11',
          'coins': 55,
          'rarity': 'rare',
          'deadline': 100,
        },
      },
    });
    expect(model.coinBalance, 1076);
    expect(model.highestUnlocked, 71);
    expect(model.result(const PuzzleId.level(70))?.milliseconds, 500);
    expect(model.hintTank, 2);
    expect(model.theme, PathwiseTheme.basinGold);
    expect(model.solved, 33);
    expect(model.unassisted, 28);
    expect(model.progression.rank(Research.legendaryCache), 3);
    expect(model.achievementCounters[AchievementMetric.research], 7);
    expect(model.progression.inventory, {'doubleTen': 1});
    expect(model.unopenedCrates.single.id, 'crate/11');
    expect(await model.flush(), true);
    model.dispose();

    final saved = await store.load();
    expect(saved.keys, isNot(contains('expedition')));
    expect(saved.keys, isNot(contains('fieldNotes')));
    expect(saved['attempts'].keys, ['levels/71']);
    model = launch(saved);
    expect(model.coinBalance, 1076);
    expect(model.solved, 33);
    expect(model.unopenedCrates, hasLength(1));
    model.dispose();
  });
}
