import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/mechanic_tutorials.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/game_state.dart';
import '../../lib/views/mechanic_tutorial_view.dart';
import '../../lib/views/puzzle_view.dart';
import '../../lib/views/settings_view.dart';
import '../support/fixtures.dart' show MemoryStorage;

void main() {
  testWidgets(
    'actual board triggers practice and acknowledgement survives reload',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = MemoryStorage();
      final board = VerifiedPuzzle(Puzzle(3, [0, 8], walls: [(0, 1)]), [
        0,
        3,
        4,
        1,
        2,
        5,
        8,
        7,
        6,
      ]);
      final model = AppModel(
        storage: storage,
        snapshot: {},
        loader: (_) async => board,
      );
      await model.open(const PuzzleId.level(1));
      expect(model.pendingMechanicTutorials, [MechanicTutorial.walls]);
      expect(model.begin(0), isFalse);
      final balance = model.coinBalance;
      final ads = AdService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            ChangeNotifierProvider.value(value: ads),
          ],
          child: const MaterialApp(home: PuzzleView()),
        ),
      );
      expect(find.byType(MechanicTutorialView), findsOneWidget);
      final grid = tester.getRect(find.byKey(const ValueKey('puzzle-grid')));
      final side = grid.width / 3;
      Offset at(int cell) =>
          grid.topLeft +
          Offset((cell % 3 + .5) * side, (cell ~/ 3 + .5) * side);
      final drag = await tester.startGesture(at(0));
      await drag.moveTo(at(1));
      await tester.pump();
      await drag.moveTo(at(0));
      await drag.moveTo(at(3));
      await drag.moveTo(at(6));
      await drag.moveTo(at(7));
      await drag.moveTo(at(4));
      await drag.moveTo(at(1));
      await drag.moveTo(at(2));
      await drag.moveTo(at(5));
      await drag.moveTo(at(8));
      await drag.up();
      await tester.pump();
      expect(find.text('Well done!'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(model.pendingMechanicTutorials, isEmpty);
      expect(model.coinBalance, balance);
      expect(model.path, [0]);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
      ads.dispose();
      final restored = AppModel(
        storage: storage,
        snapshot: await storage.load(),
        loader: (_) async => board,
      );
      await restored.open(const PuzzleId.level(1));
      expect(restored.pendingMechanicTutorials, isEmpty);
      restored.dispose();
    },
  );
  test(
    'skip persists, interrupted tutorials remain pending, and order is stable',
    () async {
      final storage = MemoryStorage();
      final board = VerifiedPuzzle(
        Puzzle(3, [0, 8], walls: [(0, 1)], iceTiles: [4]),
        [0, 3, 4, 5, 2, 1, 6, 7, 8],
      );
      AppModel make(Map<String, dynamic> snapshot) => AppModel(
        storage: storage,
        snapshot: snapshot,
        loader: (_) async => board,
      );
      final first = make({});
      await first.open(const PuzzleId.level(1));
      expect(first.pendingMechanicTutorials, [
        MechanicTutorial.walls,
        MechanicTutorial.ice,
      ]);
      expect(
        await first.acknowledgeMechanic(MechanicTutorial.walls, skipped: true),
        isTrue,
      );
      expect(first.pendingMechanicTutorials, [MechanicTutorial.ice]);
      first.close();
      await first.flush();
      first.dispose();
      final second = make(await storage.load());
      await second.open(const PuzzleId.level(1));
      expect(second.pendingMechanicTutorials, [MechanicTutorial.ice]);
      expect(
        await second.acknowledgeMechanic(MechanicTutorial.ice, skipped: false),
        isTrue,
      );
      second.close();
      await second.flush();
      second.dispose();
      final data = await storage.load();
      expect(data['mechanicTutorials'], {
        'walls': 'skipped',
        'ice': 'completed',
      });
      final third = make(data);
      await third.open(const PuzzleId.level(1));
      expect(third.pendingMechanicTutorials, isEmpty);
      third.dispose();
    },
  );
  for (final mechanic in MechanicTutorial.values) {
    testWidgets(
      '${mechanic.id} practice uses the real board and completes in isolation',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final model = AppModel(storage: MemoryStorage(), snapshot: {})
          ..setHaptics(false);
        final initialCoins = model.coinBalance;
        bool? outcome;
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: model,
            child: MaterialApp(
              home: MechanicTutorialView(
                mechanic: mechanic,
                onAcknowledge: (skipped) async {
                  outcome = skipped;
                  return true;
                },
              ),
            ),
          ),
        );
        final grid = tester.getRect(find.byKey(const ValueKey('puzzle-grid')));
        final side = grid.width / 3;
        Offset at(int cell) =>
            grid.topLeft +
            Offset((cell % 3 + .5) * side, (cell ~/ 3 + .5) * side);
        final drag = await tester.startGesture(at(0));
        if (mechanic == MechanicTutorial.walls ||
            mechanic == MechanicTutorial.gate) {
          await drag.moveTo(at(1));
          await tester.pump();
          await drag.moveTo(at(0));
        }
        final partialSteps = switch (mechanic) {
          MechanicTutorial.walls => [3, 6, 7, 4],
          MechanicTutorial.ice => [1],
          MechanicTutorial.gate => [3, 6, 7, 4, 1],
          MechanicTutorial.portal => [1],
        };
        for (final cell in partialSteps) {
          await drag.moveTo(at(cell));
          await tester.pump();
        }
        // Mechanic demonstrated, but puzzle is incomplete: Continue must stay disabled.
        expect(find.text('Well done!'), findsNothing);
        expect(find.textContaining('Now complete the puzzle.'), findsOneWidget);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pump();
        expect(outcome, isNull);

        // Complete the remaining legal route on the same board.
        final remainingSteps = switch (mechanic) {
          MechanicTutorial.walls => [1, 2, 5, 8],
          MechanicTutorial.ice => [2, 5, 4, 3, 6, 7, 8],
          MechanicTutorial.gate => [2, 5, 8],
          MechanicTutorial.portal => [8, 7, 6, 3, 4, 5, 2],
        };
        for (final cell in remainingSteps) {
          await drag.moveTo(at(cell));
          await tester.pump();
        }
        await drag.up();
        await tester.pump();
        expect(find.text('Well done!'), findsOneWidget);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pump();
        expect(outcome, false);
        expect(model.coinBalance, initialCoins);
        expect(model.highestUnlocked, 1);
        expect(model.hintsRemaining, 3);
        expect(model.activeId, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
      },
    );
  }

  testWidgets(
    'Restart demo resets mechanic instruction and disables Continue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(storage: MemoryStorage(), snapshot: {})
        ..setHaptics(false);
      bool? outcome;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: model,
          child: MaterialApp(
            home: MechanicTutorialView(
              mechanic: MechanicTutorial.ice,
              onAcknowledge: (skipped) async {
                outcome = skipped;
                return true;
              },
            ),
          ),
        ),
      );
      final grid = tester.getRect(find.byKey(const ValueKey('puzzle-grid')));
      final side = grid.width / 3;
      Offset at(int cell) =>
          grid.topLeft +
          Offset((cell % 3 + .5) * side, (cell ~/ 3 + .5) * side);
      final drag = await tester.startGesture(at(0));
      for (final cell in [1, 2, 5, 4, 3, 6, 7, 8]) {
        await drag.moveTo(at(cell));
        await tester.pump();
      }
      await drag.up();
      await tester.pump();
      expect(find.text('Well done!'), findsOneWidget);

      await tester.ensureVisible(find.text('Restart demo'));
      await tester.tap(find.text('Restart demo'));
      await tester.pump();
      expect(find.text('Well done!'), findsNothing);
      expect(find.text('Enter the ice tile to the right.'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(outcome, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    },
  );

  testWidgets(
    'Restart demo resets mechanic instruction and disables Continue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(storage: MemoryStorage(), snapshot: {})
        ..setHaptics(false);
      bool? outcome;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: model,
          child: MaterialApp(
            home: MechanicTutorialView(
              mechanic: MechanicTutorial.ice,
              onAcknowledge: (skipped) async {
                outcome = skipped;
                return true;
              },
            ),
          ),
        ),
      );
      final grid = tester.getRect(find.byKey(const ValueKey('puzzle-grid')));
      final side = grid.width / 3;
      Offset at(int cell) =>
          grid.topLeft +
          Offset((cell % 3 + .5) * side, (cell ~/ 3 + .5) * side);
      final drag = await tester.startGesture(at(0));
      for (final cell in [1, 2, 5, 4, 3, 6, 7, 8]) {
        await drag.moveTo(at(cell));
        await tester.pump();
      }
      await drag.up();
      await tester.pump();
      expect(find.text('Well done!'), findsOneWidget);

      await tester.ensureVisible(find.text('Restart demo'));
      await tester.tap(find.text('Restart demo'));
      await tester.pump();
      expect(find.text('Well done!'), findsNothing);
      expect(find.text('Enter the ice tile to the right.'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(outcome, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    },
  );

  testWidgets('Next opens tutorial for the actual next board', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final first = VerifiedPuzzle(Puzzle(3, [0, 8]), [
      0,
      1,
      2,
      5,
      4,
      3,
      6,
      7,
      8,
    ]);
    final wall = VerifiedPuzzle(Puzzle(3, [0, 8], walls: [(0, 1)]), [
      0,
      3,
      4,
      1,
      2,
      5,
      8,
      7,
      6,
    ]);
    var calls = 0;
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {},
      loader: (_) async => calls++ == 0 ? first : wall,
    )..setHaptics(false);
    await model.open(const PuzzleId.level(1));
    model.begin(0);
    for (final cell in first.solution.skip(1)) {
      model.step(cell);
    }
    model.end();
    expect(model.complete, isTrue);
    final ads = AdService();
    final billing = BillingService(persist: (_) async => true);
    addTearDown(billing.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: model),
          ChangeNotifierProvider.value(value: ads),
          ChangeNotifierProvider.value(value: billing),
        ],
        child: const MaterialApp(home: PuzzleView()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    final next = find.text('Next level');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(model.activeId?.level, 2);
    expect(find.byType(MechanicTutorialView), findsOneWidget);
    expect(model.pendingMechanicTutorials, [MechanicTutorial.walls]);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    ads.dispose();
  });
  testWidgets(
    'Settings Demo replays acknowledged mechanics without exposing unseen ones',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'mechanicTutorials': {'walls': 'completed'},
        },
      )..setHaptics(false);
      final ads = AdService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            ChangeNotifierProvider.value(value: ads),
          ],
          child: const MaterialApp(home: SettingsView()),
        ),
      );
      await tester.tap(find.text('How to play'));
      await tester.pumpAndSettle();
      expect(find.text('Walls'), findsOneWidget);
      expect(find.text('Portals'), findsNothing);
      final coins = model.coinBalance;
      await tester.tap(find.text('Walls'));
      await tester.pumpAndSettle();
      expect(find.byType(MechanicTutorialView), findsOneWidget);
      await tester.tap(find.text('Skip tutorial'));
      await tester.pumpAndSettle();
      expect(find.text('Practice mechanics'), findsOneWidget);
      expect(model.coinBalance, coins);
      expect(model.acknowledgedMechanics, {'walls'});
      expect(model.activeId, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      ads.dispose();
    },
  );
}
