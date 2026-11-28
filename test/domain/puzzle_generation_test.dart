import 'package:flutter_test/flutter_test.dart';

import '../../lib/logic/game_controller.dart';
import '../../lib/logic/mechanic_tutorials.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/logic/puzzle_generator.dart';
import '../../lib/logic/puzzle_solver.dart';
import '../../lib/model/game_state.dart';

void main() {
  test('consecutive ice slides and retracts in one stroke', () {
    final board = VerifiedPuzzle(
      Puzzle(4, [0, 12], iceTiles: [1, 2], walls: [(0, 4), (1, 5)]),
      [0, 1, 2, 3, 7, 6, 5, 4, 8, 9, 10, 11, 15, 14, 13, 12],
    );
    final game = GameController(board);
    expect(game.canStep(4), isFalse);
    expect(game.begin(0), isTrue);
    expect(game.step(1), RouteEdit.advance);
    expect(game.path, [0, 1, 2, 3]);
    expect(game.step(2), RouteEdit.retract);
    expect(game.path, [0]);
  });

  test('advanced rules reject blocked or unqualified moves', () {
    expect(Puzzle(3, [0, 8], wall: (0, 1)).canExtend(0, 1, 1, 2), isFalse);
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
    final examples = <int, Set<MechanicTutorial>>{
      30: {},
      31: {MechanicTutorial.walls},
      70: {MechanicTutorial.walls},
      71: {MechanicTutorial.ice},
      100: {MechanicTutorial.ice},
      101: {MechanicTutorial.walls, MechanicTutorial.ice},
      121: {MechanicTutorial.gate},
      151: {MechanicTutorial.walls, MechanicTutorial.gate},
      181: {MechanicTutorial.ice, MechanicTutorial.gate},
      201: {MechanicTutorial.portal},
      231: {MechanicTutorial.walls, MechanicTutorial.portal},
      261: {MechanicTutorial.ice, MechanicTutorial.portal},
      301: {MechanicTutorial.walls, MechanicTutorial.gate},
      302: {MechanicTutorial.ice, MechanicTutorial.portal},
      306: {
        MechanicTutorial.walls,
        MechanicTutorial.ice,
        MechanicTutorial.gate,
        MechanicTutorial.portal,
      },
    };
    for (final level in examples.keys) {
      final id = PuzzleId.level(level);
      for (var variant = 0; variant < 8; variant++) {
        final source = id.generation;
        final board = generatePuzzle((
          size: source.size,
          seed: source.seed + variant,
          clues: source.clues,
        ), level: level);
        final puzzle = board.puzzle;
        expect(mechanicsOnBoard(puzzle).toSet(), examples[level]);
        if (puzzle.walls.isNotEmpty)
          expect(puzzle.walls.length, greaterThanOrEqualTo(2));
        if (puzzle.iceTiles.isNotEmpty)
          expect(puzzle.iceTiles.length, greaterThanOrEqualTo(2));
        final specialTiles = [
          if (puzzle.gate case (final key, final gate)) ...[key, gate],
          if (puzzle.portal case (final entry, final exit)) ...[entry, exit],
          ...puzzle.iceTiles,
        ];
        expect(specialTiles.toSet(), hasLength(specialTiles.length));
        expect(specialTiles.any(puzzle.checkpoints.contains), isFalse);
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

  test('early, boundary and very high levels are deterministic and unique', () {
    for (final number in [
      1,
      12,
      36,
      37,
      100,
      150,
      500,
      1000,
      10000,
      100000,
      1000000,
    ]) {
      final id = PuzzleId.level(number);
      final board = generatePuzzle(id.generation);
      expect(solve(board.puzzle).unique, isTrue, reason: 'level $number');
      expect(board.solution.toSet().length, board.puzzle.area);
      expect(board.solution.first, board.puzzle.start);
      expect(board.solution.last, board.puzzle.finish);
      expect(
        generatePuzzle(id.generation).puzzle.checkpoints,
        board.puzzle.checkpoints,
      );
    }
  });

  test('later difficulty bands target higher measured complexity', () {
    double averageScore(int start) =>
        List.generate(12, (i) {
          final id = PuzzleId.level(start + i);
          return difficultyScore(
            generatePuzzle(id.generation, level: id.level),
          );
        }).reduce((a, b) => a + b) /
        12;
    expect(averageScore(901), greaterThan(averageScore(301)));
    expect(const PuzzleId.level(301).size, 7);
    expect(const PuzzleId.level(1000).size, 7);
  });
}
