import 'engine/construct.dart';
import 'engine/spec.dart';
import 'puzzle.dart';
import 'puzzle_profile.dart';
import 'puzzle_random.dart';
import 'puzzle_solver.dart';

export 'engine/construct.dart' show GenerationStats;
export 'engine/spec.dart';
export 'puzzle_random.dart' show puzzleSeed;

/// Builds the certified board for [spec].
///
/// Generation is deterministic: it depends only on [spec], never on the
/// clock, the device or the order in which boards are requested. Every
/// budget is a count of attempts or search nodes. A board is returned only
/// after the exact solver has proved its solution unique and logic alone has
/// solved it. When the spec's own attempts are used up, the spec is relaxed
/// step by step and the board's profile records the [PuzzleProfile.fallback]
/// level.
VerifiedPuzzle generatePuzzle(PuzzleSpec spec, {GenerationStats? stats}) {
  final tally = stats ?? GenerationStats();
  try {
    return _generate(spec, tally);
  } finally {
    tally.phase('done');
  }
}

VerifiedPuzzle _generate(PuzzleSpec spec, GenerationStats tally) {
  final budget = switch (spec.kind) {
    GenerationKind.attack => 14,
    _ => 36,
  };
  final wanted = spec.kind == GenerationKind.attack ? 1 : 2;
  for (var level = 0; level <= 3; level++) {
    final relaxed = _relax(spec, level);
    final board = _search(relaxed, level == 0 ? budget : 12, wanted, tally);
    if (board == null) continue;
    if (level == 0) return board;
    tally.fallback = level;
    return VerifiedPuzzle(
      board.puzzle,
      board.solution,
      profile: board.profile?.withFallback(level),
    );
  }
  tally.fallback = 4;
  return _lastResort(spec);
}

VerifiedPuzzle? _search(
  PuzzleSpec spec,
  int attempts,
  int wanted,
  GenerationStats stats,
) {
  Accepted? best;
  var found = 0;
  for (var index = 0; index < attempts; index++) {
    stats.attempts++;
    final rng = PuzzleRandom(puzzleSeed('${spec.key}#$index'));
    final candidate = attempt(spec, rng, stats);
    if (candidate == null) continue;
    stats.accepted++;
    found++;
    if (best == null || candidate.quality > best.quality) best = candidate;
    if (found >= wanted) break;
  }
  return best?.board;
}

DifficultyBand _lower(DifficultyBand band, int steps) {
  final index = band.index - steps;
  return DifficultyBand.values[index < 0 ? 0 : index];
}

PuzzleSpec _relax(PuzzleSpec spec, int level) => switch (level) {
  0 => spec,
  1 => PuzzleSpec(
    id: spec.id,
    kind: spec.kind,
    size: spec.size,
    band: _lower(spec.band, 1),
    archetype: spec.archetype,
    walls: spec.walls,
    ice: spec.ice,
    gate: spec.gate,
    portal: spec.portal,
    style: CheckpointStyle.guided,
  ),
  2 => PuzzleSpec(
    id: spec.id,
    kind: spec.kind,
    size: spec.size,
    band: _lower(spec.band, 2),
    archetype: spec.archetype,
    walls: spec.walls,
    ice: spec.ice,
    gate: spec.gate,
    portal: spec.portal,
    style: CheckpointStyle.guided,
  ),
  _ => PuzzleSpec(
    id: spec.id,
    kind: spec.kind,
    size: spec.size,
    band: DifficultyBand.easy,
    archetype: Archetype.openOrder,
    style: CheckpointStyle.guided,
  ),
};

/// A board certified by construction: every cell is a checkpoint, so only
/// one route exists. It is never meant to be seen and is counted when it is.
VerifiedPuzzle _lastResort(PuzzleSpec spec) {
  final n = spec.size;
  final route = [
    for (var row = 0; row < n; row++)
      for (var column = 0; column < n; column++)
        row * n + (row.isEven ? column : n - column - 1),
  ];
  final puzzle = Puzzle(n, route);
  final proof = solve(puzzle);
  if (!proof.unique) throw StateError('Could not certify this puzzle');
  return VerifiedPuzzle(puzzle, route);
}
