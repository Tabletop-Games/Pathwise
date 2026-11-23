import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/game_controller.dart';
import '../lib/logic/puzzle.dart';
import '../lib/logic/puzzle_generator.dart';
import '../lib/logic/puzzle_solver.dart';
import '../lib/model/game_state.dart';

void main() {
  test('advanced rules reject blocked or unqualified moves', () {
    expect(Puzzle(3, [0, 8], wall: (0, 1)).canExtend(0, 1, 1, 2), isFalse);
    expect(Puzzle(3, [0, 8], arrow: (1, 2)).canExtend(1, 4, 2, 2), isFalse);
    final gated = Puzzle(3, [0, 8], gate: (2, 4));
    expect(gated.canExtend(1, 4, 2, 2), isFalse);
    expect(
      gated.canExtend(1, 4, 4, 2, hasVisited: (cell) => cell == 2),
      isTrue,
    );
    final portal = Puzzle(3, [0, 8], portal: (1, 5));
    expect(portal.canExtend(1, 5, 2, 2), isTrue);
    expect(portal.canExtend(4, 5, 2, 2), isFalse);
    final ice = Puzzle(3, [0, 8], ice: 1);
    expect(ice.canExtend(1, 2, 2, 2, previous: 0), isTrue);
    expect(ice.canExtend(1, 4, 2, 2, previous: 0), isFalse);
  });

  test('advancement bands generate and play certified routes', () {
    for (final level in [
      20,
      21,
      40,
      41,
      70,
      71,
      100,
      101,
      150,
      151,
      200,
      201,
      500,
      1000,
    ]) {
      final id = PuzzleId.level(level);
      for (var variant = 0; variant < 8; variant++) {
        final source = id.generation;
        final board = generatePuzzle((
          size: source.size,
          seed: source.seed + variant,
          clues: source.clues,
        ), level: level);
        final puzzle = board.puzzle;
        expect(puzzle.wall != null, level >= 21 && level <= 40 || level >= 201);
        expect(
          puzzle.arrow != null,
          level >= 41 && level <= 70 || level >= 201,
        );
        expect(
          puzzle.gate != null,
          level >= 71 && level <= 100 || level >= 201,
        );
        expect(
          puzzle.portal != null,
          level >= 101 && level <= 150 || level >= 201,
        );
        expect(puzzle.ice != null, level >= 151);
        expect(
          solve(puzzle).unique,
          isTrue,
          reason: 'Level $level seed offset $variant',
        );
        final game = GameController(board);
        while (!game.complete) {
          expect(game.begin(game.tip), isTrue);
          expect(
            game.step(board.solution[game.length]),
            RouteEdit.advance,
            reason: 'Level $level seed offset $variant',
          );
          game.end();
        }
        expect(game.path, board.solution);
      }
    }
  });
}
