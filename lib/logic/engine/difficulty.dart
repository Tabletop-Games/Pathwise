import 'dart:math' as math;

import '../puzzle.dart';
import '../puzzle_profile.dart';
import '../puzzle_solver.dart';
import 'deduction.dart';

/// Difficulty is estimated from how a player has to reason, not from how big
/// the board is or how many mechanics it shows.
///
/// The logic score weighs the deductions needed to solve the board by logic
/// alone: tier-1 propagation is cheap, each lookahead costs far more, and a
/// two-level lookahead more again. Rounds measure how many times the solver had
/// to wait for an earlier deduction before it could continue.
double logicScore(DeductionResult result) {
  final counts = result.techniques;
  var tier1 = 0;
  var tier2 = 0;
  var tier3 = 0;
  for (final entry in counts.entries) {
    switch (techniqueTiers[entry.key] ?? 3) {
      case 1:
        tier1 += entry.value;
      case 2:
        tier2 += entry.value;
      default:
        tier3 += entry.value;
    }
  }
  return tier1 * 0.35 + tier2 * 6 + tier3 * 18 + result.rounds * 0.6;
}

/// Maps the logic score to 0–100 with diminishing returns.
double logicDifficulty(DeductionResult result) {
  final score = logicScore(result);
  return 100 * score / (score + 60);
}

/// Inclusive lower and exclusive upper difficulty bounds for a band.
(double, double) bandRange(DifficultyBand band) => switch (band) {
  DifficultyBand.beginner => (0, 18),
  DifficultyBand.easy => (18, 32),
  DifficultyBand.intermediate => (32, 48),
  DifficultyBand.advanced => (48, 62),
  DifficultyBand.expert => (62, 76),
  DifficultyBand.master => (76, 101),
};

DifficultyBand bandFor(double difficulty) {
  for (final band in DifficultyBand.values) {
    if (difficulty < bandRange(band).$2) return band;
  }
  return DifficultyBand.master;
}

/// The highest deduction tier a band may require.
int tierCap(DifficultyBand band) => switch (band) {
  DifficultyBand.beginner || DifficultyBand.easy => 1,
  DifficultyBand.intermediate || DifficultyBand.advanced => 2,
  DifficultyBand.expert || DifficultyBand.master => 3,
};

/// What a player faces when walking the certified route step by step.
final class WalkAnalysis {
  const WalkAnalysis({
    required this.steps,
    required this.decisions,
    required this.forcedMoveRatio,
    required this.trapCount,
    required this.trapDepth,
    required this.refutationNodes,
  });

  /// Player moves along the route. A slide over ice or a portal jump is one.
  final int steps;

  /// Moves where more than one legal option existed.
  final int decisions;

  /// Share of moves where exactly one option was legal.
  final double forcedMoveRatio;

  /// Locally legal moves that are nevertheless wrong.
  final int trapCount;

  /// How many further moves the deepest trap lets a player make before the
  /// route can no longer be completed.
  final int trapDepth;
  final int refutationNodes;
}

/// The legal player move that starts with [first]: the step itself plus every
/// forced slide or portal jump, or null when the chain breaks a rule.
List<int>? _chain(Puzzle puzzle, List<int> prefix, int first) {
  final route = List<int>.of(prefix);
  var next = first;
  var number = 1 + route.where((cell) => puzzle.numbers[cell] != 0).length;
  final added = <int>[];
  while (true) {
    if (route.contains(next)) return null;
    final from = route.last;
    final reason = puzzle.rejectionFor(
      from,
      next,
      route.length,
      number,
      previous: route.length > 1 ? route[route.length - 2] : null,
      hasVisited: route.contains,
    );
    if (reason != null) return null;
    route.add(next);
    added.add(next);
    if (puzzle.numbers[next] != 0) number++;
    final forced = puzzle.forcedNext(from, next);
    if (forced == null) return added;
    next = forced;
  }
}

/// Walks the certified [solution] and measures every wrong option a player
/// could have taken, and how far each one can be followed.
WalkAnalysis analyzeWalk(
  Puzzle puzzle,
  List<int> solution, {
  int budget = 4000,
  int unresolvedDepth = 12,
}) {
  var steps = 0;
  var decisions = 0;
  var forced = 0;
  var traps = 0;
  var depth = 0;
  var nodes = 0;
  var length = 1;
  while (length < solution.length) {
    final prefix = solution.sublist(0, length);
    final options = <List<int>>[];
    for (final next in puzzle.movesFrom(prefix.last)) {
      final chain = _chain(puzzle, prefix, next);
      if (chain != null) options.add(chain);
    }
    final correct = _chain(puzzle, prefix, solution[length]);
    final size = correct?.length ?? 1;
    steps++;
    if (options.length > 1) {
      decisions++;
    } else {
      forced++;
    }
    for (final option in options) {
      if (option.first == solution[length]) continue;
      final result = solve(
        puzzle,
        budget: budget,
        prefix: [...prefix, ...option],
      );
      nodes += result.nodes;
      traps++;
      final reached = result.status == SolveStatus.inconclusive
          ? unresolvedDepth
          : result.deepest - (length + option.length);
      depth = math.max(depth, math.max(0, reached));
    }
    length += size;
  }
  return WalkAnalysis(
    steps: steps,
    decisions: decisions,
    forcedMoveRatio: steps == 0 ? 1 : forced / steps,
    trapCount: traps,
    trapDepth: depth,
    refutationNodes: nodes,
  );
}

/// Extra difficulty from the walk: deceptive options and few forced moves.
double walkBonus(WalkAnalysis walk) {
  final deception = math.min(walk.trapDepth, 8) * 1.1;
  final traps = math.min(walk.trapCount, 14) * 0.35;
  final freedom = (1 - walk.forcedMoveRatio) * 6;
  return math.min(12, deception + traps + freedom);
}

/// A model of how long a competent player takes. It is an estimate built from
/// the deductions and decisions on the board, not a measurement.
int expectedSolveMs(Puzzle puzzle, DeductionResult result, WalkAnalysis walk) {
  var tier2 = 0;
  var tier3 = 0;
  for (final entry in result.techniques.entries) {
    final tier = techniqueTiers[entry.key] ?? 3;
    if (tier == 2) tier2 += entry.value;
    if (tier == 3) tier3 += entry.value;
  }
  return 3000 +
      puzzle.area * 600 +
      walk.decisions * 700 +
      tier2 * 2200 +
      tier3 * 6500;
}
