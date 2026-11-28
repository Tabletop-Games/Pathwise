import 'dart:convert';

import '../lib/logic/game_controller.dart';
import '../lib/logic/mechanic_tutorials.dart';
import '../lib/logic/puzzle.dart';
import '../lib/logic/puzzle_generator.dart';
import '../lib/logic/puzzle_solver.dart';
import '../lib/model/game_state.dart';

String signature(Puzzle p) {
  final variants = <String>[];
  for (var variant = 0; variant < 8; variant++) {
    int map(int cell) {
      var x = cell % p.size, y = cell ~/ p.size;
      if (variant >= 4) x = p.size - 1 - x;
      for (var i = 0; i < variant % 4; i++) {
        final oldX = x;
        x = p.size - 1 - y;
        y = oldX;
      }
      return y * p.size + x;
    }

    final walls =
        [
          for (final (a, b) in p.walls) [map(a), map(b)]..sort(),
        ]..sort(
          (a, b) => a.first == b.first
              ? a.last.compareTo(b.last)
              : a.first.compareTo(b.first),
        );
    final ice = p.iceTiles.map(map).toList()..sort();
    variants.add(
      jsonEncode([
        p.size,
        p.checkpoints.map(map).toList(),
        walls,
        ice,
        if (p.gate case (final a, final b)) [map(a), map(b)] else null,
        if (p.portal case (final a, final b)) [map(a), map(b)] else null,
      ]),
    );
  }
  variants.sort();
  return variants.first;
}

const sampledLevels = 1000;

void main() {
  final watch = Stopwatch()..start();
  final signatures = <String, int>{};
  final first = <String, int>{};
  final sizes = <int, int>{};
  final clues = <int, int>{};
  int? firstCombination;
  var boardsWithProvenInfluence = 0;
  var mechanicBoards = 0;
  final bands = <int, List<int>>{};
  final duplicates = <String>[];
  for (var level = 1; level <= sampledLevels; level++) {
    final id = PuzzleId.level(level);
    final board = generatePuzzle(id.generation, level: level);
    final again = generatePuzzle(id.generation, level: level);
    if (signature(board.puzzle) != signature(again.puzzle) ||
        board.solution.join(',') != again.solution.join(',')) {
      throw StateError('Non-deterministic level $level');
    }
    final proof = solve(board.puzzle);
    if (!proof.unique || proof.first!.join(',') != board.solution.join(',')) {
      throw StateError('Uncertified level $level');
    }
    final game = GameController(board);
    if (!game.begin(board.puzzle.start))
      throw StateError('Start failed $level');
    while (!game.complete) {
      final before = game.length;
      if (game.step(board.solution[before]) != RouteEdit.advance ||
          game.length <= before) {
        throw StateError('Solution or forced move failed at level $level');
      }
    }
    game.end();
    final hintGame = GameController(board);
    while (!hintGame.complete) {
      if (!hintGame.hint() ||
          hintGame.hintCell != board.solution[hintGame.length]) {
        throw StateError('Hint failed at level $level');
      }
      if (!hintGame.begin(hintGame.tip) ||
          hintGame.step(hintGame.hintCell!) != RouteEdit.advance) {
        throw StateError('Hint move failed at level $level');
      }
      hintGame.end();
    }
    final signatureValue = signature(board.puzzle);
    if (signatures.containsKey(signatureValue))
      duplicates.add('${signatures[signatureValue]}/$level');
    signatures[signatureValue] = level;
    final mechanics = mechanicsOnBoard(board.puzzle);
    if (mechanics.length > 1) firstCombination ??= level;
    if (mechanics.isNotEmpty) {
      mechanicBoards++;
      if (mechanicInfluence(board.puzzle) > 0) boardsWithProvenInfluence++;
    }
    clues.update(
      board.puzzle.checkpoints.length,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    for (final item in mechanics) {
      first.putIfAbsent(item.id, () => level);
    }
    sizes.update(board.puzzle.size, (n) => n + 1, ifAbsent: () => 1);
    bands.putIfAbsent((level - 1) ~/ 100, () => []).add(difficultyScore(board));
  }
  print(
    jsonEncode({
      'levels': sampledLevels,
      'firstMechanics': first,
      'firstCombination': firstCombination,
      'mechanicBoards': mechanicBoards,
      'boardsWithProvenInfluence': boardsWithProvenInfluence,
      'checkpointCounts': clues.map((k, v) => MapEntry('$k', v)),
      'sizes': sizes.map((k, v) => MapEntry('$k', v)),
      'bands': {
        for (final entry in bands.entries)
          '${entry.key * 100 + 1}-${entry.key * 100 + 100}': {
            'min': entry.value.reduce((a, b) => a < b ? a : b),
            'max': entry.value.reduce((a, b) => a > b ? a : b),
            'mean': entry.value.reduce((a, b) => a + b) / entry.value.length,
          },
      },
      'symmetryEquivalentDuplicates': duplicates,
      'elapsedMs': watch.elapsedMilliseconds,
    }),
  );
}
