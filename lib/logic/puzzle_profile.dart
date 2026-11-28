/// Internal difficulty classifications used by generation and scheduling.
/// They are not shown to players.
enum DifficultyBand { beginner, easy, intermediate, advanced, expert, master }

/// Construction objectives. An archetype describes what a puzzle should make
/// the player reason about; it is not a fixed layout.
enum Archetype {
  /// Checkpoint order and parity on an open board.
  openOrder,

  /// Long barriers leaving staggered gaps, forming lanes.
  corridors,

  /// Partly enclosed rooms with restricted entrances.
  chambers,

  /// Regions joined through single-cell gaps.
  bottleneck,

  /// Independent formations that constrain each other.
  interlock,

  /// Ice cells whose approach direction decides the route.
  directional,

  /// A key whose position shapes access to a region behind a gate.
  keyed,

  /// A portal pair that rearranges region order.
  wormhole,

  /// Several mechanics interacting in the same region.
  mixed,
}

/// How much a part of a puzzle contributes to its logic.
enum Relevance {
  /// Removing it allows more than one solution.
  essential,

  /// Removing it keeps the solution unique but makes the logic easier.
  supporting,

  /// Removing it changes nothing about how the puzzle is solved.
  redundant,
}

/// A connected group of walls, an ice run or another mechanic part.
final class FormationReport {
  const FormationReport({
    required this.kind,
    required this.cells,
    required this.relevance,
    this.shape,
  });

  /// `wall`, `ice`, `gate` or `portal`.
  final String kind;

  /// For walls, the formation shape: `bar`, `ell`, `u`, `zigzag`, `tee`,
  /// `hook`, `chamber`, `partition` or `stagger`.
  final String? shape;

  /// Number of wall edges, ice tiles, or 2 for pairs.
  final int cells;
  final Relevance relevance;
}

/// Deterministic quality measurements for an accepted board. Nothing here
/// depends on wall-clock time or device speed.
final class PuzzleProfile {
  const PuzzleProfile({
    required this.band,
    required this.archetype,
    required this.difficulty,
    required this.hardestTier,
    required this.techniques,
    required this.deductionSteps,
    required this.chainDepth,
    required this.forcedMoveRatio,
    required this.trapCount,
    required this.trapDepth,
    required this.solverNodes,
    required this.formations,
    required this.fingerprint,
    required this.expectedSolveMs,
    this.fallback = 0,
  });

  final DifficultyBand band;
  final Archetype archetype;

  /// 0–100 estimate of logical difficulty. An estimate of human difficulty,
  /// not a measurement.
  final double difficulty;

  /// The hardest deduction tier needed (1 foundational, 2 intermediate,
  /// 3 advanced).
  final int hardestTier;

  /// Technique id → times applied while solving by logic alone.
  final Map<String, int> techniques;
  final int deductionSteps;

  /// The longest chain of deductions that each needed the one before it.
  final int chainDepth;

  /// Share of route steps where only one move is legal.
  final double forcedMoveRatio;

  /// Locally legal but wrong moves along the solution, and the deepest
  /// lookahead any of them needs before it fails.
  final int trapCount;
  final int trapDepth;

  /// Exact solver nodes spent certifying uniqueness (secondary metric).
  final int solverNodes;
  final List<FormationReport> formations;

  /// Symmetry-canonical identity of the board.
  final String fingerprint;

  /// A model estimate of a competent player's solve time. Not measured.
  final int expectedSolveMs;

  /// 0 for a board that met every gate of its own spec. Higher values mean
  /// the generator relaxed the spec after its attempts were used up.
  final int fallback;

  PuzzleProfile withFallback(int level) => PuzzleProfile(
    band: band,
    archetype: archetype,
    difficulty: difficulty,
    hardestTier: hardestTier,
    techniques: techniques,
    deductionSteps: deductionSteps,
    chainDepth: chainDepth,
    forcedMoveRatio: forcedMoveRatio,
    trapCount: trapCount,
    trapDepth: trapDepth,
    solverNodes: solverNodes,
    formations: formations,
    fingerprint: fingerprint,
    expectedSolveMs: expectedSolveMs,
    fallback: level,
  );
}
