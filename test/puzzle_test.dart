import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/puzzle.dart';
import '../lib/logic/puzzle_generator.dart';
import '../lib/logic/puzzle_solver.dart';
import '../lib/model/expedition.dart';
import '../lib/model/game_state.dart';

/// Independent reference with coordinates and a Set, no pruning or engine rules.
int referenceCount(Puzzle puzzle) {
  final occupied = {puzzle.start};

  int visit(int cell, int checkpoint) {
    if (occupied.length == puzzle.area) {
      return cell == puzzle.finish && checkpoint == puzzle.checkpoints.length
          ? 1
          : 0;
    }
    if (cell == puzzle.finish) return 0;
    var solutions = 0;
    for (var next = 0; next < puzzle.area; next++) {
      final distance =
          (next ~/ puzzle.size - cell ~/ puzzle.size).abs() +
          (next % puzzle.size - cell % puzzle.size).abs();
      if (distance != 1 || occupied.contains(next)) continue;
      final number = puzzle.checkpoints.indexOf(next);
      if (number != -1 && number != checkpoint) continue;
      occupied.add(next);
      solutions += visit(next, checkpoint + (number == -1 ? 0 : 1));
      occupied.remove(next);
    }
    return solutions;
  }

  return visit(puzzle.start, 1);
}

void expectSolution(VerifiedPuzzle board) {
  final size = board.puzzle.size;
  final route = board.solution;
  expect(route.length, size * size);
  expect(route.toSet(), Set.of(List.generate(size * size, (index) => index)));
  expect(route.first, board.puzzle.start);
  expect(route.last, board.puzzle.finish);
  final checkpoints = board.puzzle.checkpoints;
  expect(route.where(checkpoints.contains), checkpoints);
  for (var index = 1; index < route.length; index++) {
    final a = route[index - 1];
    final b = route[index];
    final distance =
        (a ~/ size - b ~/ size).abs() + (a % size - b % size).abs();
    expect(distance, 1);
  }
  expect(solve(board.puzzle).unique, true);
}

void main() {
  test('DFS agrees with independent enumeration for all 3×3 boards with three or four checkpoints', () {
    final cells = List.generate(9, (index) => index);
    final seen = <int>{};
    void compare(List<int> checkpoints) {
      final puzzle = Puzzle(3, checkpoints);
      final expected = referenceCount(puzzle);
      seen.add(expected.clamp(0, 2));
      final actual = solve(puzzle);
      expect(
        actual.count,
        expected.clamp(0, 2),
        reason: checkpoints.join(' → '),
      );
      expect(actual.unique, expected == 1);
    }

    for (final start in cells) {
      for (final middle in cells.where((cell) => cell != start)) {
        for (final end in cells.where(
          (cell) => cell != start && cell != middle,
        )) {
          compare([start, middle, end]);
          for (final other in cells) {
            if (other != start && other != middle && other != end) {
              compare([start, middle, other, end]);
            }
          }
        }
      }
    }
    expect(seen, {0, 1, 2});
  });

  test('budget exhaustion never certifies a unique board', () {
    final puzzle = Puzzle(3, [0, 8]);
    expect(solve(puzzle, budget: 0).exhausted, false);
    expect(solve(puzzle, budget: 1).unique, false);
  });

  test('rejects invalid puzzle definitions', () {
    expect(() => Puzzle(1, [0, 1]), throwsArgumentError);
    expect(() => Puzzle(4, [1, 1]), throwsArgumentError);
    expect(() => Puzzle(4, [0, 16]), throwsArgumentError);
    expect(() => Puzzle(4, [1]), throwsArgumentError);
  });

  test('all campaign boards are original, distinct and uniquely solved', () {
    final signatures = <String>{};
    for (var level = 1; level <= legacyLevelCount; level++) {
      final id = PuzzleId.level(level);
      final board = generatePuzzle(id.generation);
      expectSolution(board);
      expect(
        signatures.add('${id.size}:${board.puzzle.checkpoints.join(',')}'),
        true,
      );
      expect(board.puzzle.checkpoints.length, lessThan(board.puzzle.area));
    }
  });

  test(
    'daily and expedition generation is deterministic across sizes and dates',
    () {
      for (final id in [
        for (var day = 1; day <= 8; day++)
          PuzzleId.daily(dayKey(DateTime(2026, 11, day))),
        for (final trail in Trail.values)
          for (final serial in [0, 5])
            for (var stage = 0; stage < Trail.stages; stage++)
              PuzzleId.expedition(trail, serial, stage),
      ]) {
        final a = generatePuzzle(id.generation);
        final b = generatePuzzle(id.generation);
        expect(a.puzzle.checkpoints, b.puzzle.checkpoints);
        expect(a.solution, b.solution);
        expectSolution(a);
      }
    },
  );
}
