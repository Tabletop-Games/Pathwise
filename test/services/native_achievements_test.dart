import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/achievement_sync.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/game_state.dart';
import 'package:pathwise/model/native_achievements.dart';
import 'package:pathwise/model/progression.dart';
import 'package:pathwise/model/time_attack.dart';
import 'package:pathwise/model/user_preferences.dart';
import 'package:pathwise/views/play_games_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

class GamesFake extends PlayAchievementGateway {
  String? player;
  bool fail = false;
  bool withoutConfirmation = false;
  Completer<void>? pending;
  final updates = <AchievementUpdate>[];
  final remote = <String, Map<String, RemoteAchievement>>{};
  int loads = 0;
  int signIns = 0, opened = 0;
  bool allowSignIn = false;

  @override
  Future<bool> authenticated() async => player != null;

  @override
  Future<bool> signIn() async {
    signIns++;
    if (allowSignIn) player = 'native';
    return allowSignIn;
  }

  @override
  Future<bool> openAchievements() async {
    opened++;
    return player != null;
  }

  @override
  Future<RemoteAchievementState?> load() async {
    loads++;
    final selected = player;
    await pending?.future;
    if (selected == null || player != selected) return null;
    return (player: selected, progress: Map.of(remote[selected]!));
  }

  @override
  Future<bool> update(String player, AchievementUpdate update) async {
    if (this.player != player) return false;
    updates.add(update);
    if (fail) return false;
    if (!withoutConfirmation) {
      final existing = remote[player]![update.id]!;
      final steps = update.steps ?? 0;
      remote[player]![update.id] = (
        steps: steps,
        total: existing.total,
        unlocked: steps == existing.total,
      );
    }
    return true;
  }
}

NativeAchievement achievement(String id) =>
    nativeAchievements.singleWhere((item) => item.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog limits, reachable prices and hidden eligibility', () {
    expect(nativeAchievements, hasLength(29));
    expect(
      nativeAchievements.map((item) => item.id).toSet(),
      hasLength(nativeAchievements.length),
    );
    expect(achievement('immortal').hidden, true);
    expect(achievement('immortal').incremental, true);
    expect(
      achievement('masterResearcher').target,
      lessThan(Research.values.fold<int>(0, (sum, item) => sum + item.limit)),
    );
    expect(
      achievement('styleMaster').target,
      lessThan(PathwiseTheme.values.length - 4),
    );
    for (final item in nativeAchievements) {
      expect(item.progress({item.metric: -1}), 0);
      expect(item.earned({item.metric: item.target - 1}), false);
      expect(item.progress({item.metric: item.target + 1}), item.target);
    }
  });

  test(
    'real completion records survive restart and replays do not add precision',
    () async {
      final store = MemoryStorage();
      var boot = (boot: 1, milliseconds: 0);
      Future<AppModel> launch() async => AppModel(
        storage: store,
        snapshot: await store.load(),
        loader: (_) async => fixture(),
        bootTime: () => boot,
      );
      var app = await launch();
      await app.open(const PuzzleId.level(1));
      complete(app);
      expect(
        app.recentAchievements.map((item) => item.id),
        contains('firstSteps'),
      );
      expect(app.achievementCounters[AchievementMetric.precision], 1);
      await app.open(const PuzzleId.level(1), replay: true);
      complete(app);
      expect(app.recentAchievements, isEmpty);
      expect(app.achievementCounters[AchievementMetric.solves], 1);
      await app.open(const PuzzleId.level(2));
      app.tap(1);
      app.clear();
      app.close();
      await app.flush();
      app.dispose();

      app = await launch();
      await app.open(const PuzzleId.level(2));
      complete(app);
      expect(app.achievementCounters[AchievementMetric.precision], 1);
      expect(app.achievementCounters[AchievementMetric.hintFree], 2);

      for (final (day, passed) in [
        ('2026-11-23', 0),
        ('2026-11-24', 10),
        ('2026-11-25', 5 * 3600000),
        ('2026-11-26', 48 * 3600000),
      ]) {
        boot = (boot: 1, milliseconds: passed);
        await app.open(PuzzleId.daily(day));
        complete(app);
      }
      expect(app.achievementCounters[AchievementMetric.daily], 2);
      app.close();
      await app.flush();
      app.dispose();
      app = await launch();
      expect(app.dailySolved, 4);
      expect(
        achievement('dailyDiscovery').earned(app.achievementCounters),
        true,
      );
      expect(app.achievementCounters[AchievementMetric.daily], 2);
      app.dispose();
    },
  );

  test('native Daily progress prevents backward dates and reboot bypasses', () {
    final ledger = AchievementLedger({});
    ledger.daily('2026-11-20', (boot: 2, milliseconds: 1));
    ledger.daily('2026-11-21', (boot: 3, milliseconds: 1000));
    expect(ledger.eligibleDailies, 1);
    final resumed = AchievementLedger(ledger.toJson());
    resumed.daily('2026-11-19', (boot: 3, milliseconds: 80000000));
    resumed.daily('2026-11-21', (boot: 1, milliseconds: 80000000));
    expect(resumed.eligibleDailies, 1);
    resumed.daily('2026-11-22', (boot: 3, milliseconds: 80000000));
    expect(resumed.eligibleDailies, 2);
  });

  test('research and theme purchases count, permanent theme passes grant no progress', () async {
    final app = AppModel(storage: MemoryStorage(), snapshot: {});
    expect(
      await app.applyVerifiedPurchase('pack-1', coins: 500, themes: false),
      true,
    );
    expect(app.research(Research.magnet), true);
    expect(app.unlockTheme(PathwiseTheme.forestMint), true);
    expect(app.achievementCounters[AchievementMetric.research], 1);
    expect(app.achievementCounters[AchievementMetric.themes], 1);
    expect(
      await app.applyVerifiedPurchase('pass-1', coins: 0, themes: true),
      true,
    );
    expect(app.achievementCounters[AchievementMetric.themes], 1);
    app.dispose();
  });

  test(
    'Time Attack thresholds use completed timed sessions and actual scoring',
    () async {
      var time = (boot: 1, milliseconds: 0);
      final app = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        bootTime: () => time,
        loader: (_) async => fixture(),
      );
      expect(await app.openAttack(), true);
      for (var count = 0; count < 10; count++) {
        time = (boot: 1, milliseconds: time.milliseconds + 15000);
        complete(app);
        await Future<void>.delayed(Duration.zero);
      }
      expect(app.achievementCounters[AchievementMetric.attackScore], 0);
      time = (boot: 1, milliseconds: AttackRun.duration.inMilliseconds);
      app.refreshAttackClock();
      expect(app.achievementCounters[AchievementMetric.attackScore], 1000);
      expect(achievement('timeLord').earned(app.achievementCounters), true);
      expect(app.achievementCounters[AchievementMetric.solves], 0);
      await app.flush();
      app.dispose();
    },
  );

  test('offline progress sync uses absolute steps and waits for Google confirmation', () async {
    final store = MemoryStorage();
    final app = AppModel(
      storage: store,
      snapshot: {},
      loader: (_) async => fixture(),
    );
    await app.open(const PuzzleId.level(1));
    complete(app);
    app.close();
    await app.flush();
    app.dispose();

    final saved = AppModel(storage: store, snapshot: await store.load());
    final gateway = GamesFake()
      ..remote['one'] = {
        'STANDARD': (steps: 0, total: 0, unlocked: false),
        'STEPS': (steps: 0, total: 10, unlocked: false),
        'HIDDEN': (steps: 0, total: 10000, unlocked: false),
        'MISMATCH': (steps: 0, total: 10, unlocked: false),
      }
      ..remote['two'] = {'STEPS': (steps: 10, total: 10, unlocked: true)};
    final sync = AchievementSync(
      saved,
      gateway: gateway,
      enabled: true,
      ids: {
        'firstSteps': 'STANDARD',
        'gettingStarted': 'STEPS',
        'immortal': 'HIDDEN',
        'master': 'MISMATCH',
        'apprentice': 'REPLACE_WITH_PLAY_GAMES_RESOURCE_ID',
        'researcher': 'DUPLICATE',
        'styleMaster': 'DUPLICATE',
      },
    );
    final balance = saved.coinBalance;
    sync.foreground(true);
    await sync.refresh();
    expect(sync.status, AchievementSyncStatus.unavailable);
    expect(sync.configuredCount, 4);
    expect(gateway.updates, isEmpty);

    gateway.player = 'one';
    gateway.withoutConfirmation = true;
    await sync.refresh();
    expect(sync.confirmed(achievement('firstSteps')), false);
    gateway.withoutConfirmation = false;
    gateway.fail = true;
    await sync.refresh();
    expect(sync.confirmed(achievement('firstSteps')), false);
    gateway.fail = false;
    gateway.updates.clear();
    await sync.refresh();
    expect(
      gateway.updates,
      unorderedEquals([(id: 'STANDARD', steps: null), (id: 'STEPS', steps: 1)]),
    );
    expect(sync.confirmed(achievement('firstSteps')), true);
    expect(sync.confirmed(achievement('gettingStarted')), false);
    gateway.updates.clear();
    await sync.refresh();
    expect(gateway.updates, isEmpty);
    expect(
      (await store.load())['nativeAchievements']['confirmed'],
      hasLength(1),
    );

    gateway.player = 'two';
    await sync.refresh(accountMayHaveChanged: true);
    expect(sync.confirmed(achievement('firstSteps')), false);
    expect(sync.confirmed(achievement('gettingStarted')), true);
    expect(sync.accountMismatch, true);
    expect(gateway.updates, isEmpty);
    expect(saved.coinBalance, balance);
    expect(
      (await store.load())['nativeAchievements']['confirmed'],
      hasLength(2),
    );
    sync.dispose();
    saved.dispose();
  });

  test(
    'a backgrounded sync cannot report an old account as confirmed',
    () async {
      final app = AppModel(storage: MemoryStorage(), snapshot: {});
      final gateway = GamesFake()
        ..player = 'old'
        ..remote['old'] = {'ID': (steps: 0, total: 0, unlocked: true)}
        ..pending = Completer<void>();
      final sync = AchievementSync(
        app,
        gateway: gateway,
        enabled: true,
        ids: {'firstSteps': 'ID'},
      );
      sync.foreground(true);
      final refresh = sync.refresh();
      sync.foreground(false);
      gateway.pending!.complete();
      await refresh;
      expect(sync.confirmed(achievement('firstSteps')), false);
      expect(gateway.updates, isEmpty);
      sync.dispose();
      app.dispose();
    },
  );

  testWidgets(
    'open native uses existing authentication and explains failed sign-in',
    (tester) async {
      final app = AppModel(storage: MemoryStorage(), snapshot: {});
      final gateway = GamesFake();
      final sync = AchievementSync(app, gateway: gateway, enabled: true);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            ChangeNotifierProvider.value(value: sync),
          ],
          child: const MaterialApp(home: PlayGamesView()),
        ),
      );
      final open = find.text('Open Google Play Achievements');
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.textContaining('sign-in is unavailable'), findsOneWidget);
      expect(gateway.opened, 0);
      gateway.allowSignIn = true;
      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(gateway.signIns, 2);
      expect(gateway.opened, 2);
      expect(find.textContaining('sign-in is unavailable'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      sync.dispose();
      app.dispose();
    },
  );

  testWidgets(
    'disabled Play Games keeps the local catalog and hides secret details',
    (tester) async {
      final app = AppModel(storage: MemoryStorage(), snapshot: {});
      final sync = AchievementSync(app, enabled: false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            ChangeNotifierProvider.value(value: sync),
          ],
          child: const MaterialApp(home: PlayGamesView()),
        ),
      );
      expect(find.text('Google Play Achievements'), findsOneWidget);
      expect(find.text('First Steps'), findsOneWidget);
      expect(find.text('Open Google Play Achievements'), findsNothing);
      expect(find.text('Puzzle Immortal'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      sync.dispose();
      app.dispose();
    },
  );
}
