import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/logic/game_controller.dart';
import 'package:pathwise/logic/puzzle.dart';

GameController gameFixture() => GameController(
  VerifiedPuzzle(Puzzle(3, [0, 2, 4, 8]), [0, 1, 2, 5, 4, 3, 6, 7, 8]),
);

void main() {
  late GameController game;
  setUp(() => game = gameFixture());

  test('only contiguous moves in checkpoint order count', () {
    expect(game.begin(8), false);
    expect(game.begin(2), false);
    expect(game.step(1), RouteEdit.none);
    expect(game.begin(0), true);
    expect(game.step(4), RouteEdit.none);
    expect(game.step(3), RouteEdit.advance);
    expect(game.step(4), RouteEdit.none);
    expect(game.path, [0, 3]);
    expect(game.nextCheckpoint, 2);
  });

  test('retraction unwinds checkpoint state and undo restores the preceding stroke', () {
    game.begin(0);
    game.step(1);
    game.step(2);
    game.step(5);
    expect(game.step(8), RouteEdit.none);
    expect(game.nextCheckpoint, 3);
    expect(game.end(), true);

    game.begin(5);
    expect(game.step(2), RouteEdit.retract);
    expect(game.step(1), RouteEdit.retract);
    expect(game.nextCheckpoint, 2);
    expect(game.end(), true);

    expect(game.undo(), true);
    expect(game.path, [0, 1, 2, 5]);
    expect(game.nextCheckpoint, 3);
    expect(game.undo(), true);
    expect(game.path, [0]);
  });

  test(
    'only the direct backward step or a deliberate tap can reuse a cell',
    () {
      game.begin(0);
      for (final cell in [1, 2, 5, 4]) {
        game.step(cell);
      }
      expect(game.step(1), RouteEdit.none);
      game.end();
      game.begin(1);
      game.end();
      expect(game.path, [0, 1]);
      expect(game.clear(), true);
      expect(game.path, [0]);
      expect(game.undo(), true);
      expect(game.path, [0, 1]);
    },
  );

  test(
    'hint removes the first divergent step and reveals exactly one next tile',
    () {
      game.begin(0);
      game.step(3);
      game.step(6);
      game.end();
      expect(game.hint(), true);
      expect(game.path, [0]);
      expect(game.hintCell, 1);
      expect(game.hint(), false);
      expect(game.hintsUsed, 1);
      expect(game.undo(), true);
      expect(game.path, [0, 3, 6]);
      game.hint();
      game.begin(1);
      game.end();
      expect(game.hintCell, isNull);
      expect(game.hint(), true);
      expect(game.hintCell, 2);
      expect(game.nextCheckpoint, 2);
    },
  );

  test('completion requires the final step and locks the solved board', () {
    game.begin(0);
    for (final cell in game.board.solution.skip(1).take(7)) {
      expect(game.step(cell), RouteEdit.advance);
      expect(game.complete, false);
    }
    expect(game.step(8), RouteEdit.advance);
    expect(game.complete, true);
    game.end();
    expect(game.undo(), false);
    expect(game.clear(), false);
    expect(game.hint(), false);
    expect(game.begin(0), false);
  });

  test('final checkpoint preserves an incomplete route for undo', () {
    final game = GameController(
      VerifiedPuzzle(Puzzle(3, [0, 8]), [0, 1, 2, 5, 4, 3, 6, 7, 8]),
    );
    game.begin(0);
    for (final cell in [1, 2, 5]) {
      game.step(cell);
    }
    expect(game.nextCheckpoint, 2);
    expect(game.step(8), RouteEdit.advance);
    expect(game.path, [0, 1, 2, 5, 8]);
    expect(game.complete, false);
  });

  test('invalid saved path and undo entries cannot corrupt legal play', () {
    game.restore([0, 4], [], 3, null);
    expect(game.path, [0]);
    game.restore(
      [0, 1],
      [
        [0, 4],
        [0],
      ],
      2,
      2,
    );
    expect(game.path, [0, 1]);
    expect(game.hintCell, 2);
    expect(game.hintsUsed, 2);
    expect(game.undo(), true);
    expect(game.path, [0]);
    expect(game.undo(), false);
  });
}
