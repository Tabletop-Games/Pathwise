import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/attack_clock.dart';
import '../lib/main.dart';
import '../lib/model/app_model.dart';
import '../lib/views/components/brand_mark.dart';
import '../lib/views/fortune_view.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

void main() {
  testWidgets('launch offers an unspent spin once per session', (tester) async {
    await tester.runAsync(
      () => rootBundle.loadString('backend/fortune-prizes.json'),
    );
    final store = MemoryStorage();
    AppModel model(Map<String, dynamic> snapshot) => AppModel(
      storage: store,
      snapshot: snapshot,
      bootTime: () => (boot: 1, milliseconds: 500),
    );
    Future<void> launch(AppModel player) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: player,
          child: PathwiseApp(clock: AttackClock()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final player = model({});
    await launch(player);
    expect(find.byType(FortuneView), findsOneWidget);
    expect(player.coinBalance, 50);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    player.setHaptics(false);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(FortuneView), findsNothing);
    await tester.pumpWidget(const SizedBox());
    player.dispose();

    final restarted = model({});
    await launch(restarted);
    expect(find.byType(FortuneView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    restarted.dispose();

    final coolingDown = model({
      'fortune': {'boot': 1, 'at': 500},
    });
    await launch(coolingDown);
    expect(find.byType(FortuneView), findsNothing);
    await tester.pumpWidget(const SizedBox());
    coolingDown.dispose();
  });

  testWidgets(
    'home orders play and shortcuts and reserves the mark for About',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'playStreak': {'count': 1},
          'hintBalance': 3,
        },
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pathwise'), findsOneWidget);
      expect(find.byType(BrandMark), findsNothing);
      expect(find.text('One route through every tile.'), findsNothing);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
      Offset position(String label) => tester.getCenter(find.text(label));
      expect(position('3 hints').dx, greaterThan(position('1-day streak').dx));
      expect(
        find.ancestor(
          of: find.text('3 hints'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );

      final ordered = [
        'Daily challenge',
        'Play level 1',
        'Levels',
        'Time Attack',
      ];
      for (var i = 1; i < ordered.length; i++) {
        expect(
          position(ordered[i]).dy,
          greaterThan(position(ordered[i - 1]).dy),
        );
      }
      await tester.scrollUntilVisible(find.text('Boosts'), 230);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Fortune Wheel')).dy,
        tester.getTopLeft(find.text('Themes')).dy,
      );
      expect(position('Research').dy, position('Boosts').dy);
      expect(
        position('Research').dy,
        greaterThan(position('Fortune Wheel').dy),
      );
      expect(position('Fortune Wheel').dx, lessThan(position('Themes').dx));
      expect(position('Research').dx, lessThan(position('Boosts').dx));

      await tester.scrollUntilVisible(find.byTooltip('Settings'), -250);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final about = find.byType(AboutListTile);
      await tester.scrollUntilVisible(about, 270);
      await tester.pumpAndSettle();
      await tester.tap(about);
      await tester.pumpAndSettle();
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.textContaining('by Tabletop Games'), findsOneWidget);
      expect(find.text('View licenses'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    },
  );

  testWidgets('fast drag, reverse drag, Undo, Clear, Hint and completion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryStorage();
    final model = AppModel(
      storage: store,
      snapshot: {},
      loader: (_) async => fixture(),
    )..setHaptics(false);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.tap(find.text('Levels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').hitTestable());
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('puzzle-grid'));
    final board = tester.getRect(grid);
    const size = 3;
    Offset center(int cell) =>
        board.topLeft +
        Offset(cell % size + .5, cell ~/ size + .5) * (board.width / size);

    final drag = await tester.startGesture(center(0));
    await drag.moveTo(center(2));
    await tester.pump();
    expect(model.path, [0, 1, 2]);

    await drag.moveTo(center(1));
    await tester.pump();
    expect(model.path, [0, 1]);
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(model.path, [0]);

    await tester.tap(find.text('Hint · 3 left'));
    await tester.pumpAndSettle();
    expect(model.hintCell, 1);
    await tester.tapAt(center(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(model.path, [0]);

    final diagonal = await tester.startGesture(center(0));
    await diagonal.moveTo(center(4));
    await diagonal.up();
    await tester.pumpAndSettle();
    expect(model.path, [0]);

    final solution = await tester.startGesture(center(0));
    for (final cell in fixture().solution.skip(1)) {
      await solution.moveTo(center(cell));
      await tester.pump();
    }
    await solution.up();
    await tester.pumpAndSettle();
    expect(find.text('Level complete!'), findsOneWidget);
    expect(find.text('Next level'), findsOneWidget);
    expect(model.complete, true);
    expect(model.solved, 1);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Next level'));
    await tester.tap(find.text('Next level'));
    await tester.pumpAndSettle();
    expect(model.activeId?.level, 2);
    expect(model.path, [0]);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });

  testWidgets(
    'Fortune Wheel shows an offline free spin without video or odds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => rootBundle.loadString('backend/fortune-prizes.json'),
      );
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        bootTime: () => (boot: 1, milliseconds: 500),
      )..setHaptics(false);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
      );
      await tester.scrollUntilVisible(find.text('Fortune Wheel'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fortune Wheel'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Watch for a spin'), findsNothing);
      expect(find.text('Prize odds'), findsNothing);
      await tester.tap(find.text('Free spin'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(model.coinBalance, 50);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(model.fortuneWait, greaterThan(0));
      expect(model.hintsRemaining, 3);
      expect(find.text('+${model.coinBalance - 50} coins'), findsOneWidget);
      expect(find.text('${model.coinBalance} coins'), findsOneWidget);
      expect(find.textContaining('Next free spin in'), findsOneWidget);
      final balance = model.coinBalance;
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Fortune Wheel'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fortune Wheel'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Next free spin in'), findsOneWidget);
      expect(model.coinBalance, balance);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    },
  );

  for (final (screen, scale) in [
    (const Size(320, 640), 1.5),
    (const Size(390, 820), 1.0),
    (const Size(600, 960), 1.25),
  ]) {
    testWidgets(
      'progression and crate UI stay usable at ${screen.width}dp and ${scale}× text',
      (tester) async {
        await tester.binding.setSurfaceSize(screen);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final model = AppModel(
          storage: MemoryStorage(),
          snapshot: {
            'progressionBoot': 1,
            'ledger': [
              {
                'id': 'fixture',
                'label': 'Fixture',
                'amount': 95,
                'at': '2026-11-23T00:00:00Z',
              },
            ],
            'progression': {
              'serial': 2,
              'crates': [
                {'id': 'crate/1', 'rarity': 'rare', 'coins': 55},
              ],
              'inventory': {'doubleTen': 1},
            },
          },
          bootTime: () => (boot: 1, milliseconds: 100),
        )..setHaptics(false);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: model,
            child: const PathwiseApp(),
          ),
        );
        expect(find.text('Supply crate ready'), findsNothing);

        await tester.scrollUntilVisible(find.text('Research'), 170);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Research'));
        await tester.pumpAndSettle();
        expect(find.text('Research lab'), findsOneWidget);
        final upgrade = find.text('Upgrade · 55 coins');
        await tester.scrollUntilVisible(upgrade, 170);
        await tester.pumpAndSettle();
        await tester.tap(upgrade);
        await tester.pumpAndSettle();
        expect(find.text('Rank 1 / 10'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(find.text('Boosts'), 170);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Boosts'));
        await tester.pumpAndSettle();
        expect(find.text('Boost reserve'), findsOneWidget);
        final activate = find.text('Activate').first;
        await tester.ensureVisible(activate);
        await tester.pumpAndSettle();
        await tester.tap(activate);
        await tester.pumpAndSettle();
        expect(find.text('10 min remaining'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await model.flush();
        model.dispose();
      },
    );
  }

  testWidgets('retired features are absent on home, Stats and Vault', (
    tester,
  ) async {
    final model = AppModel(storage: MemoryStorage(), snapshot: {});
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    void check() {
      expect(
        find.textContaining(RegExp(r'Expedition|Field Notes|Qualify on Trail')),
        findsNothing,
      );
    }

    await tester.scrollUntilVisible(find.text('Fortune Wheel'), 130);
    await tester.pumpAndSettle();
    check();
    await tester.scrollUntilVisible(find.byTooltip('Statistics'), -200);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Statistics'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pathwise Achievements'), 200);
    check();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('50'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('High Pass'), 220);
    expect(find.text('High Pass'), findsOneWidget);
    check();
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('the only hint indicator counts from three to zero', (
    tester,
  ) async {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {},
      loader: (_) async => fixture(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.tap(find.text('Play daily'));
    await tester.pumpAndSettle();
    for (var remaining = 3; remaining > 0; remaining--) {
      final button = find.text('Hint · $remaining left');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Hint · ${remaining - 1} left'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^[0-3]/3$')), findsNothing);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });

  testWidgets(
    'empty hint wallet offers a coin purchase and disables unconfigured ads',
    (tester) async {
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'schemaVersion': 4,
          'premium': true,
          'attempts': {
            'daily-checkpoint/2026-11-23/1': {
              'path': [0],
              'history': <Object>[],
              'hints': 3,
              'milliseconds': 0,
              'started': true,
            },
          },
        },
        today: () => DateTime(2026, 11, 23),
        loader: (_) async => fixture(),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
      );
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hint · 0 left'));
      await tester.pumpAndSettle();
      expect(find.text('Need a hint?'), findsOneWidget);
      expect(find.text('No ads available right now'), findsOneWidget);
      expect(find.text('Need 60 more coins'), findsOneWidget);
      expect(find.text('Get coins'), findsOneWidget);
      expect(model.hintsRemaining, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    },
  );

  testWidgets('themes and statistics are reachable on a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 610));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {},
      loader: (_) async => fixture(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blackwater'));
    await tester.pumpAndSettle();
    expect(model.theme.label, 'Blackwater');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Statistics'));
    await tester.pumpAndSettle();
    expect(find.text('Puzzles solved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });

  testWidgets('paged levels show legacy unlock and continue from results', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'results': {
          'levels/36': {'milliseconds': 1000, 'hints': 0},
        },
      },
      loader: (_) async => fixture(),
    )..setHaptics(false);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.tap(find.text('Levels'));
    await tester.pumpAndSettle();
    expect(find.text('Levels 37–48'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Levels 49–60'), findsOneWidget);
    await tester.tap(find.text('Current level'));
    await tester.pumpAndSettle();
    expect(find.text('Levels 37–48'), findsOneWidget);
    await tester.tap(find.text('38').hitTestable());
    await tester.pumpAndSettle();
    expect(model.activeId, isNull);
    await tester.tap(find.text('37').hitTestable());
    await tester.pumpAndSettle();
    expect(model.activeId!.value, 37);
    final route = fixture().solution;
    model.begin(route.first);
    for (final cell in route.skip(1)) {
      model.step(cell);
    }
    model.end();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next level'));
    await tester.tap(find.text('Next level'));
    await tester.pumpAndSettle();
    expect(model.activeId!.value, 38);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Levels 37–48'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });
  testWidgets(
    'cosmetic previews are free and default monetization controls are hidden',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 870));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        loader: (_) async => fixture(),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
      );
      await tester.tap(find.text('50'));
      await tester.pumpAndSettle();
      expect(find.text('Vault'), findsOneWidget);
      expect(find.text('Equipped'), findsOneWidget);
      expect(find.text('Restore purchases'), findsNothing);
      expect(find.textContaining('Optional video'), findsNothing);
      final forest = find.text('Forest Mint');
      await tester.ensureVisible(forest);
      await tester.tap(forest);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(model.theme.label, 'Field');
      expect(model.coinBalance, 50);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    },
  );
  testWidgets(
    'Daily result shares the finished challenge date and real hints',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var date = DateTime(2026, 11, 23);
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        today: () => date,
        loader: (_) async => fixture(),
      )..setHaptics(false);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
      );
      final daily = find.text('Play daily');
      await tester.ensureVisible(daily);
      await tester.tap(daily);
      await tester.pumpAndSettle();
      model.hint();
      complete(model);
      for (var i = 0; i < 2; i++) {
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next checkpoint'));
        await tester.pumpAndSettle();
        expect(model.hintsRemaining, 2);
        complete(model);
      }
      final balance = model.coinBalance;
      date = DateTime(2026, 11, 24);
      model.refreshDate();
      await tester.pumpAndSettle();
      final share = find.text('Share Today’s Result');
      await tester.ensureVisible(share);
      await tester.pumpAndSettle();
      await tester.tap(share);
      await tester.pumpAndSettle();
      final preview = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(preview.data, contains('23 Nov 2026'));
      expect(preview.data, contains('Hints used: 1.'));
      expect(preview.data, contains('games.tabletop.pathwise'));
      expect(model.coinBalance, balance);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    },
  );

  testWidgets(
    'Time Attack opens with the selected duration and shows results at expiration',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var now = 100;
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        loader: (_) async => fixture(),
        bootTime: () => (boot: 4, milliseconds: now),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
      );
      await tester.ensureVisible(find.text('Time Attack'));
      await tester.tap(find.text('Time Attack'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 min'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('0 solved · 0 points'), findsOneWidget);
      now += 60000;
      model.refreshAttackClock();
      await tester.pumpAndSettle();
      expect(find.text('Time’s up'), findsOneWidget);
      await tester.tap(find.text('Share Your Score'));
      await tester.pumpAndSettle();
      final preview = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(preview.data, contains('0 points. 0 puzzles solved.'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Return to home'), findsOneWidget);
      await tester.tap(find.text('Return to home'));
      await tester.pumpAndSettle();
      expect(model.activeId, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    },
  );
}
