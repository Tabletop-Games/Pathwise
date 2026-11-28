import 'puzzle.dart';

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

/// The solve time, in milliseconds, that maps to the baseline thresholds.
const int _baselineExpectedMs = 16000;

/// A bounded `[1.0, 4.0]` multiplier from the board's expected solve time.
///
/// The expected time is a model estimate built from the deductions and the
/// decisions on the board (see `expectedSolveMs`), so it grows with how much
/// reasoning the board needs rather than with the level number. Boards built
/// by hand, which have no profile, use a size-only estimate.
double difficultyMultiplierForBoard(VerifiedPuzzle board) {
  final expected =
      board.profile?.expectedSolveMs ?? 3000 + board.puzzle.area * 1000;
  return (((expected / _baselineExpectedMs) * 4).round() / 4.0).clamp(1.0, 4.0);
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
