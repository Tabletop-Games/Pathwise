import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../lib/logic/puzzle_generator.dart';
import '../lib/main.dart';
import '../lib/model/app_model.dart';
import '../lib/model/game_state.dart';
import '../lib/model/user_preferences.dart';
import 'app_model_test.dart' show MemoryStorage;

void main() {
  testWidgets('first launch offers the demo once and Settings replays it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final storage = MemoryStorage();
    final level = const PuzzleId.level(1);
    final demo = find.text('Draw one continuous route');

    Future<AppModel> launch() async {
      final model = AppModel(storage: storage, snapshot: await storage.load());
      await tester.pumpWidget(
        PathwiseStartup(
          theme: PathwiseTheme.field,
          initialize: () async => model,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();
      return model;
    }

    await launch();
    expect(demo, findsOneWidget);
    expect((await storage.load())['levelOneDemoSeen'], isTrue);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(demo, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());

    final player = await launch();
    expect(demo, findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    expect(demo, findsOneWidget);

    final board = generatePuzzle(level.generation, level: 1);
    final route = board.solution;
    final grid = tester.getRect(find.byKey(const ValueKey('puzzle-grid')));
    final cellSize = grid.width / board.puzzle.size;
    Offset cell(int tile) =>
        grid.topLeft +
        Offset(
          (tile % board.puzzle.size + 0.5) * cellSize,
          (tile ~/ board.puzzle.size + 0.5) * cellSize,
        );

    final drag = await tester.startGesture(cell(route.first));
    await drag.moveTo(cell(route[1]));
    await drag.moveTo(cell(route.first));
    for (final tile in route.skip(1)) {
      await drag.moveTo(cell(tile));
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text('Level 1 solved!'), findsOneWidget);
    expect(player.activeId, isNull);
    expect(player.result(level), isNotNull);
    expect(player.highestUnlocked, 2);
    expect(player.levelsSolved, 1);
    expect(player.coinBalance, 95);
    expect(player.hintsRemaining, 3);
    final done = find.text('Done');
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Level 1 solved!'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Continue · Level 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('existing saves skip automatic onboarding', () {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {'highestUnlocked': 24},
    );
    addTearDown(model.dispose);
    expect(model.shouldOfferLevelOneDemo, isFalse);
  });
}
