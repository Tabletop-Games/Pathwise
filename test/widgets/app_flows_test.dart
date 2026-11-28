import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../lib/logic/attack_clock.dart';
import '../../lib/main.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/journey.dart';
import '../../lib/model/user_preferences.dart';
import '../../lib/ui/game_ui.dart';
import '../../lib/views/components/brand_mark.dart';
import '../../lib/views/components/puzzle_board.dart';
import '../../lib/views/fortune_view.dart';
import '../../lib/views/store_view.dart';
import '../support/fixtures.dart';

Finder _journeyLevel(int level) =>
    find.byKey(ValueKey('journey-level-$level')).hitTestable();

void main() {
  test('contextual coin shortfalls select the smallest covering pack', () {
    expect(recommendedCoinPack(25), 'pathwise_coins_500');
    expect(recommendedCoinPack(501), 'pathwise_coins_1250');
    expect(recommendedCoinPack(1250), 'pathwise_coins_1250');
    expect(recommendedCoinPack(18001), isNull);
    expect(recommendedCoinPack(0), isNull);
  });

  testWidgets('coin balance opens the unified Coins category', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = AppModel(storage: MemoryStorage(), snapshot: {});
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.tap(find.text('50'));
    await tester.pumpAndSettle();
    expect(find.text('Store'), findsOneWidget);
    expect(find.text('Transaction history'), findsNothing);
    expect(
      find.text('Purchases are unavailable on this build.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('launch offers an unspent spin once per session', (tester) async {
    await tester.runAsync(
      () => rootBundle.loadString('assets/data/fortune-prizes.json'),
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
    'home orders play, Store, Wheel and shortcuts and reserves the mark for About',
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
      final streakChip = find.byKey(const ValueKey('streak-chip'));
      final hintChip = find.byKey(const ValueKey('hint-chip'));
      expect(streakChip, findsOneWidget);
      expect(hintChip, findsOneWidget);
      expect(
        tester.getCenter(hintChip).dx,
        greaterThan(tester.getCenter(streakChip).dx),
      );
      expect(
        find.descendant(of: hintChip, matching: find.text('3')),
        findsOneWidget,
      );
      expect(find.byTooltip('Store'), findsNothing);
      expect(find.text('Themes'), findsNothing);

      Offset position(String label) => tester.getCenter(find.text(label));
      final ordered = [
        'Play level 1',
        'Daily challenge',
        'Journey',
        'Time Attack',
        'Store',
        'Fortune Wheel',
      ];
      for (var i = 1; i < 4; i++) {
        await tester.scrollUntilVisible(find.text(ordered[i]), 100);

        expect(
          position(ordered[i]).dy,
          greaterThan(position(ordered[i - 1]).dy),
        );
      }
      for (var i = 4; i < ordered.length; i++) {
        if (i >= 4) {
          await tester.scrollUntilVisible(find.text(ordered[i]), 200);
          await tester.pumpAndSettle();
        }
        expect(find.text(ordered[i]), findsOneWidget);
      }
      await tester.scrollUntilVisible(find.text('Boosts'), 230);
      await tester.pumpAndSettle();
      expect(position('Research').dy, closeTo(position('Boosts').dy, 8));
      expect(
        position('Research').dy,
        greaterThan(position('Fortune Wheel').dy),
      );
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
    await tester.tap(find.text('Journey'));
    await tester.pumpAndSettle();
    await tester.tap(_journeyLevel(1));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
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
        () => rootBundle.loadString('assets/data/fortune-prizes.json'),
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
      expect(find.byKey(const ValueKey('wheel-video')), findsNothing);
      expect(find.text('Prize odds'), findsNothing);
      await tester.tap(find.text('Free spin'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(model.coinBalance, 50);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(model.fortuneWait, greaterThan(0));
      expect(model.hintsRemaining, 3);
      expect(find.text('+${model.coinBalance - 50}'), findsOneWidget);
      expect(find.text('${model.coinBalance}'), findsOneWidget);
      expect(find.text('Free spin'), findsNothing);
      expect(find.textContaining(RegExp(r'^\d+h \d+m$')), findsOneWidget);
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
      expect(find.text('Free spin'), findsNothing);
      expect(find.textContaining(RegExp(r'^\d+h \d+m$')), findsOneWidget);
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
        final reportError = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint(
            'OVERFLOW-FULL: ${details.toDiagnosticsNode().toStringDeep()}',
          );
          reportError?.call(details);
        };
        addTearDown(() => FlutterError.onError = reportError);
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
        expect(find.text('Research'), findsOneWidget);
        final upgrade = find.byType(PricePill);
        expect(upgrade, findsWidgets);
        await tester.tap(upgrade.first);
        await tester.pumpAndSettle();
        expect(find.textContaining('1/'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(find.text('Boosts'), 170);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Boosts'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('boost-inventory-doubleTen')),
          findsOneWidget,
        );
        final activate = find.text('Activate').first;
        await tester.ensureVisible(activate);
        await tester.pumpAndSettle();
        await tester.tap(activate);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('5 min left'), -150);
        await tester.pumpAndSettle();
        expect(find.text('5 min left'), findsOneWidget);
        final problem = tester.takeException();
        if (problem != null) debugPrint('OVERFLOW-DETAIL: $problem');
        expect(problem, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await model.flush();
        model.dispose();
      },
    );
  }

  testWidgets('retired features are absent on home, Stats and Themes', (
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
    await tester.scrollUntilVisible(find.text('Store'), 180);
    await tester.tap(find.text('Store'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('High Pass'),
      220,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('store-themes')),
        matching: find.byType(Scrollable),
      ),
    );
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
      expect(find.text('Get a hint'), findsOneWidget);
      final adButton = find.byKey(const ValueKey('hint-watch'));
      expect(tester.widget<ActionPill>(adButton).onTap, isNull);
      expect(find.text('Unavailable'), findsOneWidget);
      final buy = tester.widget<PricePill>(
        find.byKey(const ValueKey('hint-buy')),
      );
      expect(buy.price, 80);
      expect(buy.affordable, isFalse);
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
    await tester.tap(find.byTooltip('Statistics'));
    await tester.pumpAndSettle();
    expect(find.text('Puzzles solved'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final store = find.byKey(const ValueKey('store-card'));
    await tester.scrollUntilVisible(store.hitTestable(), 180);
    await tester.tap(store.hitTestable());
    await tester.pumpAndSettle();
    final blackwater = find.byKey(const ValueKey('theme-card-blackwater'));
    await tester.ensureVisible(blackwater);
    await tester.tap(
      find.descendant(of: blackwater, matching: find.text('Apply')),
    );
    await tester.pumpAndSettle();
    expect(model.theme.label, 'Blackwater');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });

  testWidgets(
    'Journey supports replay, locked feedback and continuing from results',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'results': {
            'levels/36': {'milliseconds': 1000, 'hints': 0, 'stars': 3},
          },
        },
        loader: (_) async => fixture(),
      )..setHaptics(false);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
      );
      await tester.tap(find.text('Journey'));
      await tester.pumpAndSettle();
      expect(find.text('Journey'), findsOneWidget);
      expect(find.byTooltip('Level grid'), findsNothing);
      expect(_journeyLevel(37), findsOneWidget);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(find.bySemanticsLabel('Level 37, current'), findsOneWidget);
        expect(find.bySemanticsLabel('Level 38, locked'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Level 36, completed, 3 of 3 stars'),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
      await tester.tap(_journeyLevel(36));
      await tester.pumpAndSettle();
      expect(model.activeId?.key, 'levels/36');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_journeyLevel(37), findsOneWidget);

      await tester.tap(_journeyLevel(38));
      await tester.pumpAndSettle();
      expect(model.activeId, isNull);
      expect(
        find.text('Clear Level 37 first to unlock Level 38'),
        findsOneWidget,
      );
      await tester.tap(_journeyLevel(37));
      await tester.pumpAndSettle();
      expect(model.activeId?.key, 'levels/37');
      final route = fixture().solution;
      model.begin(route.first);
      for (final cell in route.skip(1)) {
        model.step(cell);
      }
      model.end();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.ensureVisible(find.text('Next level'));
      await tester.tap(find.text('Next level'));
      await tester.pumpAndSettle();
      expect(model.activeId!.value, 38);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_journeyLevel(38), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    },
  );
  testWidgets('Journey keeps distant jumps usable with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'highestUnlocked': 100000,
        'ownedThemes': ['signal'],
      },
      loader: (_) async => fixture(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.scrollUntilVisible(find.text('Journey').hitTestable(), 140);
    await tester.tap(find.text('Journey'));
    await tester.pumpAndSettle();
    expect(_journeyLevel(100000), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-level-1')), findsNothing);

    await tester.tap(find.byTooltip('Chapters'));
    await tester.pumpAndSettle();
    expect(find.text('Chapters'), findsOneWidget);
    const chapter = 3999;
    final chapterChoice = find.byKey(
      const ValueKey('journey-chapter-choice-$chapter'),
    );
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('journey-chapter-choice-4000')),
          )
          .enabled,
      isFalse,
    );
    await tester.scrollUntilVisible(
      chapterChoice.hitTestable(),
      140,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(chapterChoice.hitTestable());
    await tester.pumpAndSettle();
    expect(_journeyLevel(99976), findsOneWidget);

    await tester.tap(find.byTooltip('Jump to level'));
    await tester.pumpAndSettle();
    final go = find.widgetWithText(FilledButton, 'Go');
    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    expect(tester.widget<FilledButton>(go).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '1000');
    await tester.pump();
    await tester.tap(go);
    await tester.pumpAndSettle();
    expect(_journeyLevel(1000), findsOneWidget);

    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    await tester.pumpAndSettle();
    expect(_journeyLevel(1000), findsOneWidget);
    model.setTheme(PathwiseTheme.signal);
    await tester.pumpAndSettle();
    expect(_journeyLevel(1000), findsOneWidget);
    for (final level in [1, 25, 26, 100, 10000, 1000000]) {
      await tester.tap(find.byTooltip('Jump to level'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '$level');
      await tester.pump();
      await tester.tap(go);
      await tester.pumpAndSettle();
      expect(_journeyLevel(level), findsOneWidget);
    }
    await tester.tap(find.byTooltip('Current level'));
    await tester.pumpAndSettle();
    expect(_journeyLevel(100000), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });

  testWidgets('Journey shows and claims pending chapter treasures', (
    tester,
  ) async {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'journey': {
          'chapterChests': [0, 1],
        },
      },
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.tap(find.text('Journey'));
    await tester.pumpAndSettle();
    expect(find.text('Treasures · 2'), findsOneWidget);
    await tester.tap(find.text('Treasures · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter treasures'), findsOneWidget);
    expect(find.text(chapterName(0)).hitTestable(), findsOneWidget);
    expect(find.text(chapterName(1)).hitTestable(), findsOneWidget);

    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claim treasure'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1 treasure claimed!'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Treasures · 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });

  testWidgets('theme preview is isolated and shortfall is exact', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 870));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = AppModel(storage: MemoryStorage(), snapshot: {});
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.scrollUntilVisible(find.text('Store'), 180);
    await tester.tap(find.text('Store'));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('theme-card-forestMint'));
    await tester.ensureVisible(card);
    await tester.tap(
      find.descendant(of: card, matching: find.byType(LevelOneBoardPreview)),
    );
    await tester.pumpAndSettle();
    expect(model.theme.label, 'Field');
    expect(model.coinBalance, 50);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: card, matching: find.byType(PricePill)),
    );
    await tester.pumpAndSettle();
    final shortfall =
        economy.themePrice(PathwiseTheme.forestMint) - model.coinBalance;
    expect(find.text('$shortfall short'), findsOneWidget);
    await tester.tap(find.text('Get coins'));
    await tester.pumpAndSettle();
    expect(find.byKey(const PageStorageKey('store-coins')), findsOneWidget);
    expect(model.coinBalance, 50);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });
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
      expect(find.byType(SelectableText), findsNothing);
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
      expect(find.byType(SelectableText), findsNothing);
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
