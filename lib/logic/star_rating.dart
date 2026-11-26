import '../model/game_state.dart';
import 'puzzle.dart';
import 'puzzle_generator.dart';
import 'puzzle_solver.dart';

/// Baseline Beginner (1.0×) solve-time thresholds in milliseconds.
const int baselineThreeStarMs = 10000;
const int baselineTwoStarMs = 20000;
const int baselineOneStarMs = 30000;

/// Deterministic, replay-stable star thresholds for a puzzle.
final class StarThresholds {
  const StarThresholds({
    required this.threeStarMs,
    required this.twoStarMs,
    required this.oneStarMs,
    required this.multiplier,
  });

  final int threeStarMs;
  final int twoStarMs;
  final int oneStarMs;
  final double multiplier;

  /// Evaluates [milliseconds] against the thresholds:
  /// - `< threeStarMs` -> 3 stars
  /// - `threeStarMs .. twoStarMs` -> 2 stars
  /// - `(twoStarMs, oneStarMs]` -> 1 star
  /// - `> oneStarMs` -> 0 stars
  int rate(int milliseconds) {
    if (milliseconds < 0) return 0;
    if (milliseconds < threeStarMs) return 3;
    if (milliseconds <= twoStarMs) return 2;
    if (milliseconds <= oneStarMs) return 1;
    return 0;
  }
}

/// Computes a bounded `[1.0, 4.0]` difficulty multiplier from deterministic
/// puzzle characteristics without scaling indefinitely by level number.
double difficultyMultiplierForBoard(VerifiedPuzzle board) {
  final p = board.puzzle;
  final score = difficultyScore(board);
  final sizeOffset = switch (p.size) {
    <= 4 => 0.0,
    5 => 0.25,
    6 => 0.60,
    _ => 1.00,
  };
  final raw = 1.0 + sizeOffset + (score / 48.0);
  return ((raw * 4).round() / 4.0).clamp(1.0, 4.0);
}

StarThresholds starThresholdsForBoard(VerifiedPuzzle board) {
  final mult = difficultyMultiplierForBoard(board);
  return StarThresholds(
    threeStarMs: (baselineThreeStarMs * mult).round(),
    twoStarMs: (baselineTwoStarMs * mult).round(),
    oneStarMs: (baselineOneStarMs * mult).round(),
    multiplier: mult,
  );
}

final _levelThresholdCache = <int, StarThresholds>{};

/// Deterministic, bounded-cache lookup for campaign level thresholds when the
/// board is not already loaded in memory (e.g., Journey display or lazy migration).
StarThresholds starThresholdsForLevel(int level) {
  final cached = _levelThresholdCache[level];
  if (cached != null) return cached;
  final board = generatePuzzle(PuzzleId.level(level).generation, level: level);
  final thresholds = starThresholdsForBoard(board);
  if (_levelThresholdCache.length >= 256) {
    _levelThresholdCache.remove(_levelThresholdCache.keys.first);
  }
  _levelThresholdCache[level] = thresholds;
  return thresholds;
}
