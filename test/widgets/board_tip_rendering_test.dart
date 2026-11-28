import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../lib/logic/game_controller.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/app_themes.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/game_state.dart';
import '../../lib/model/user_preferences.dart';
import '../../lib/views/components/puzzle_board.dart';
import '../support/fixtures.dart';

class _TestBoardControls implements BoardControls, RejectionControls {
  _TestBoardControls(this.game);
  final GameController game;
  VoidCallback? changed;

  @override
  List<int> get path => game.path;
  @override
  int? get tip => game.tip;
  @override
  int? get hintCell => game.hintCell;
  @override
  int get nextCheckpoint => game.nextCheckpoint;
  @override
  bool get complete => game.complete;
  @override
  bool begin(int cell) {
    final ok = game.begin(cell);
    changed?.call();
    return ok;
  }

  @override
  bool canStep(int cell) => game.canStep(cell);
  @override
  void step(int cell) {
    game.step(cell);
    changed?.call();
  }

  @override
  void end() {
    game.end();
    changed?.call();
  }

  @override
  void tap(int cell) {
    if (begin(cell)) end();
  }

  @override
  RejectedMove? rejectionFor(int cell) => game.rejectionFor(cell);
  @override
  void rejectHaptic() {}
}

void main() {
  testWidgets(
    'PuzzleBoard renders non-classic cosmetic at rest, during drag, and at dead end',
    (tester) async {
      final puzzle = Puzzle(3, [0, 8], walls: [(1, 2), (1, 4)]);
      final game = GameController(
        VerifiedPuzzle(puzzle, [0, 3, 6, 7, 4, 5, 2, 1, 8]),
      );
      final controls = _TestBoardControls(game);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 300,
                child: StatefulBuilder(
                  builder: (context, update) {
                    controls.changed = () => update(() {});
                    return PuzzleBoard(
                      model: controls,
                      puzzle: puzzle,
                      palette: BoardPalette.palettes[PathwiseTheme.field]!,
                      tipStyle: PathTip.cat,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Move to cell 1 (which only has backtracking to 0 because walls block 2 and 4).
      final grid = find.byKey(const ValueKey('puzzle-grid'));
      final topLeft = tester.getTopLeft(grid);
      final gesture = await tester.startGesture(
        topLeft + const Offset(50, 50),
      );
      await gesture.moveTo(topLeft + const Offset(150, 50));
      await tester.pump();
      expect(controls.path, [0, 1]);

      // Release at dead end cell 1 -> should settle cleanly without exceptions.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom tip remains visible after invalid checkpoint rejection settles',
    (tester) async {
      final puzzle = Puzzle(3, [0, 4, 8]);
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: const {},
        loader: (_) async =>
            VerifiedPuzzle(puzzle, const [0, 1, 2, 5, 4, 3, 6, 7, 8]),
      );
      await model.open(const PuzzleId.level(1));
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 300,
                child: RepaintBoundary(
                  key: key,
                  child: PuzzleBoard(
                    puzzle: puzzle,
                    palette: BoardPalette.palettes[PathwiseTheme.field]!,
                    tipStyle: PathTip.crystal,
                    model: model,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('puzzle-grid')),
      );
      // Drag from cell 0 (50,50) to cell 1 (150,50) then invalid checkpoint 8 (250,250) via cell 3 (50,150)->(150,150) is valid 2!
      // Instead, drag from cell 0 directly to cell 3 (50,150) then attempt cell 4 (150,150) which is checkpoint 2 — valid;
      // let's attempt cell 4 directly from cell 0 (50,50) -> wait: 0->3 is valid, let's test Puzzle(3, [0, 3, 8]) where 0->1->4->3 or 0->3->8?
      // Actually on [0, 4, 8], stepping 0->1->4 is valid, stepping 0->3->6->7->8 (skipping checkpoint 2 at cell 4) rejects at cell 8!
      final drag = await tester.startGesture(origin + const Offset(50, 50));
      await drag.moveTo(origin + const Offset(50, 150));
      await tester.pump();
      await drag.moveTo(origin + const Offset(50, 250));
      await tester.pump();
      await drag.moveTo(origin + const Offset(150, 250));
      await tester.pump();
      // Attempt cell 8 (checkpoint 3 while next is 2 -> rejected!)
      await drag.moveTo(origin + const Offset(250, 250));
      await tester.pump(const Duration(milliseconds: 50));
      await drag.up();
      // Wait for rejection animation (450ms) to finish completely.
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Verify pointer-layer still paints the custom tip at rest on cell 7 (150, 250).
      final pointerBoundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('pointer-layer')),
      );
      final hasPaintedTip = await tester.runAsync(() async {
        final img = await pointerBoundary.toImage(pixelRatio: 1);
        final bytes = (await img.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var any = false;
        for (var i = 3; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) > 0) {
            any = true;
            break;
          }
        }
        img.dispose();
        return any;
      });
      expect(hasPaintedTip, isFalse);
      expect(model.path, [0, 3, 6, 7]);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    },
  );
}
