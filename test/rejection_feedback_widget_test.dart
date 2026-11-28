import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../lib/logic/game_controller.dart';
import '../lib/logic/puzzle.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/user_preferences.dart';
import '../lib/views/components/puzzle_board.dart';

class _Controls implements BoardControls, RejectionControls {
  _Controls(this.game);
  final GameController game;
  int errors = 0;
  VoidCallback? changed;
  @override
  List<int> get path => game.path;
  @override
  int get tip => game.tip;
  @override
  int? get hintCell => game.hintCell;
  @override
  int get nextCheckpoint => game.nextCheckpoint;
  @override
  bool get complete => game.complete;
  @override
  bool begin(int cell) {
    final value = game.begin(cell);
    changed?.call();
    return value;
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
  void rejectHaptic() => errors++;
}

void main() {
  testWidgets(
    'invalid drag paints a temporary path without mutating the route',
    (tester) async {
      final puzzle = Puzzle(3, [0, 2, 1, 8]);
      final controls = _Controls(
        GameController(VerifiedPuzzle(puzzle, [0, 3, 6, 7, 4, 5, 2, 1, 8])),
      );
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
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final grid = find.byKey(const ValueKey('puzzle-grid'));
      final topLeft = tester.getTopLeft(grid);
      final gesture = await tester.startGesture(topLeft + const Offset(50, 50));
      await gesture.moveTo(topLeft + const Offset(150, 50));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(controls.path, [0]);
      expect(controls.errors, 1);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('rejection-layer')),
      );
      await tester.runAsync(() async {
        final picture = await boundary.toImage();
        final bytes = (await picture.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (50 * picture.width + 125) * 4;
        expect(bytes.getUint8(offset + 3), 0);
        picture.dispose();
      });
      await gesture.moveTo(topLeft + const Offset(160, 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(controls.errors, 1);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(bytes.getUint8((50 * image.width + 125) * 4 + 3), 0);
        image.dispose();
      });
      await gesture.moveTo(topLeft + const Offset(50, 50));
      await gesture.moveTo(topLeft + const Offset(50, 150));
      await tester.pump();
      expect(controls.path, [0, 3]);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wall feedback stops at the blocked boundary and rearms on retry',
    (tester) async {
      final puzzle = Puzzle(3, [0, 8], walls: [(0, 1)]);
      final controls = _Controls(
        GameController(VerifiedPuzzle(puzzle, [0, 3, 4, 1, 2, 5, 8, 7, 6])),
      );
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
                      palette: BoardPalette.palettes[PathwiseTheme.blackwater]!,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('puzzle-grid')),
      );
      final gesture = await tester.startGesture(origin + const Offset(50, 50));
      await gesture.moveTo(origin + const Offset(90, 50));
      await tester.pump();
      final pointerLayer = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('pointer-layer')),
      );
      await tester.runAsync(() async {
        final image = await pointerLayer.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        // The classic tip follows the finger but stops short of the wall.
        expect(bytes.getUint8((50 * image.width + 70) * 4 + 3), greaterThan(0));
        expect(bytes.getUint8((50 * image.width + 105) * 4 + 3), 0);
        image.dispose();
      });
      await gesture.moveTo(origin + const Offset(150, 50));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(controls.errors, 1, reason: 'the wall rejection buzzes once');
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('rejection-layer')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(bytes.getUint8((50 * image.width + 125) * 4 + 3), 0);
        image.dispose();
      });
      await gesture.moveTo(origin + const Offset(50, 50));
      await gesture.moveTo(origin + const Offset(150, 50));
      expect(controls.errors, 2, reason: 'retrying the wall rearms it');
      expect(controls.path, [0]);
      await gesture.up();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion suppresses moving path but preserves feedback', (
    tester,
  ) async {
    final puzzle = Puzzle(3, [0, 2, 1, 8]);
    final controls = _Controls(
      GameController(VerifiedPuzzle(puzzle, [0, 3, 6, 7, 4, 5, 2, 1, 8])),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
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
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byKey(const ValueKey('puzzle-grid')));
    final board = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('board-layer')),
    );
    Future<int> sample() async => (await tester.runAsync(() async {
      final image = await board.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final value = bytes.getUint32((80 * image.width + 180) * 4);
      image.dispose();
      return value;
    }))!;
    final original = await sample();
    final gesture = await tester.startGesture(origin + const Offset(50, 50));
    await gesture.moveTo(origin + const Offset(150, 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(controls.errors, 1);
    expect(controls.path, [0]);
    expect(await sample(), isNot(original));
    await tester.pump(const Duration(milliseconds: 500));
    expect(await sample(), original);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('rejection-layer')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(bytes.getUint8((50 * image.width + 125) * 4 + 3), 0);
      image.dispose();
    });
    await gesture.up();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'the classic tip follows the finger continuously and settles on release',
    (tester) async {
      final puzzle = Puzzle(3, [0, 2, 4, 8]);
      final controls = _Controls(
        GameController(VerifiedPuzzle(puzzle, [0, 3, 6, 7, 4, 1, 2, 5, 8])),
      );
      final palette = BoardPalette.palettes[PathwiseTheme.field]!;
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
                      palette: palette,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('puzzle-grid')),
      );
      final drag = await tester.startGesture(origin + const Offset(50, 50));
      await drag.moveTo(origin + const Offset(50, 150));
      await tester.pump();
      expect(controls.path, [0, 3]);
      final layer = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('pointer-layer')),
      );
      Future<List<int>> pixel(int x, int y) async =>
          (await tester.runAsync(() async {
            final image = await layer.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final i = (y * image.width + x) * 4;
            final out = [
              bytes.getUint8(i),
              bytes.getUint8(i + 1),
              bytes.getUint8(i + 2),
              bytes.getUint8(i + 3),
            ];
            image.dispose();
            return out;
          }))!;
      // Move the finger part way toward the next cell. The tip must be there
      // before the cell is accepted, not stuck on the cell centre.
      await drag.moveTo(origin + const Offset(50, 185));
      await tester.pump();
      expect(controls.path, [0, 3], reason: 'the route has not changed');
      final tip = await pixel(50, 185);
      expect(tip[3], greaterThan(0), reason: 'something is painted at the tip');
      expect(tip[0], greaterThan(200));
      await drag.moveTo(origin + const Offset(80, 185));
      await tester.pump();
      final sideways = await pixel(80, 185);
      expect(sideways[3], 0, reason: 'the tip stays on its vertical axis');
      await drag.up();
      await tester.pumpAndSettle();
      expect((await pixel(50, 185))[3], 0, reason: 'transient tip is gone');
      expect(controls.path, [0, 3]);
    },
  );

  testWidgets('rejection moves the tip along the temporary segment', (
    tester,
  ) async {
    final puzzle = Puzzle(3, [0, 2, 4, 8]);
    final game = GameController(
      VerifiedPuzzle(puzzle, [0, 3, 6, 7, 4, 1, 2, 5, 8]),
    );
    game.begin(0);
    game.step(3);
    game.end();
    final controls = _Controls(game);
    final palette = BoardPalette.palettes[PathwiseTheme.field]!;
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
                    palette: palette,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byKey(const ValueKey('puzzle-grid')));
    final drag = await tester.startGesture(origin + const Offset(50, 150));
    await drag.moveTo(origin + const Offset(150, 150));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    final layer = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('rejection-layer')),
    );
    await tester.runAsync(() async {
      final image = await layer.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final tip = (150 * image.width + 122) * 4;
      final original = (150 * image.width + 50) * 4;
      expect(bytes.getUint8(tip), greaterThan(200));
      expect(
        bytes.getUint8(original),
        closeTo((palette.route.r * 255).round(), 1),
      );
      image.dispose();
    });
    expect(controls.path, [0, 3]);
    expect(controls.nextCheckpoint, 2);
    await drag.up();
  });
}
