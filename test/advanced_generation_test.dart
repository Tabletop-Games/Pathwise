import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/game_controller.dart';
import '../lib/logic/puzzle_generator.dart';
import '../lib/logic/puzzle_solver.dart';
import '../lib/model/game_state.dart';

void main() {
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
