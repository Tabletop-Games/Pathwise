import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/main.dart';
import '../lib/model/app_model.dart';
import 'app_model_test.dart' show MemoryStorage, fixture;

void main() {
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
    await tester.tap(find.text('Expedition'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Start Foothills'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Foothills'));
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
    expect(find.text('Route complete'), findsOneWidget);
    expect(find.text('Next stage'), findsOneWidget);
    expect(model.complete, true);
    expect(model.solved, 1);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Next stage'));
    await tester.tap(find.text('Next stage'));
    await tester.pumpAndSettle();
    expect(find.text('Stage 2/10 · 0/4 field marks'), findsOneWidget);
    expect(model.path, [0]);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });

  testWidgets('Expedition wraps large trail numbers and opens indexed replay', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'expeditionProgress': {
          'next': 9007199254740991,
          'claims': 0,
          'stages': 0,
          'clean': 0,
          'qualifiedClean': 0,
        },
      },
      loader: (_) async => fixture(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.scrollUntilVisible(find.text('Expedition'), 160);
    await tester.tap(find.text('Expedition'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trail 9007199254740991 ·'), findsOneWidget);
    await tester.tap(find.byTooltip('Find a trail'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '100000');
    await tester.pump();
    await tester.tap(find.text('Show trail'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trail 100000 ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('extra hint dialog never offers coin payment to Premium', (
    tester,
  ) async {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'schemaVersion': 4,
        'premium': true,
        'hintUsage': {'daily/2026-11-23': 3},
      },
      today: () => DateTime(2026, 11, 23),
      loader: (_) async => fixture(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.tap(find.text('Play daily'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch ad · 1 hint'));
    await tester.pumpAndSettle();
    expect(find.text('Extra hint'), findsOneWidget);
    expect(find.textContaining('Spend'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch ad · 1 hint'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Watch ad · 1 hint'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Rewarded video unavailable'), findsOneWidget);
    expect(model.hintTank, 3);
    expect(model.extraHints, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });

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
      await tester.tap(find.text('40'));
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
      expect(model.coinBalance, 40);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    },
  );
  testWidgets(
    'Time Attack opens with ten minutes and shows results at expiration',
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
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('0 solved · 0 points'), findsOneWidget);
      now += 600000;
      model.refreshAttackClock();
      await tester.pumpAndSettle();
      expect(find.text('Time’s up'), findsOneWidget);
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
