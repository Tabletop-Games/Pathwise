import 'dart:math' as math;

import '../puzzle.dart';
import '../puzzle_profile.dart';
import '../puzzle_random.dart';
import '../puzzle_solver.dart';
import 'deduction.dart';
import 'difficulty.dart';
import 'fingerprint.dart';
import 'spec.dart';
import 'structure.dart';

/// Deterministic counters for one generation call. Nothing here is a clock.
final class GenerationStats {
  int attempts = 0;
  int accepted = 0;
  int solverCalls = 0;
  int solverNodes = 0;
  int deduceCalls = 0;
  int fallback = 0;
  final Map<String, int> rejections = {};

  void reject(String reason) =>
      rejections.update(reason, (n) => n + 1, ifAbsent: () => 1);
}

/// A board that passed every quality gate, with its ranking score.
final class Accepted {
  const Accepted(this.board, this.quality);
  final VerifiedPuzzle board;
  final double quality;
}

/// The mutable working copy of a board during construction.
final class _Board {
  _Board(this.n);

  final int n;
  final List<Formation> formations = [];
  final Set<int> ice = {};
  (int, int)? gate;
  (int, int)? portal;
  List<int> route = [];
  final Set<int> clues = {};
  Map<int, int> index = {};

  Set<Wall> get walls => {for (final f in formations) ...f.edges};

  Set<int> get mechanicCells => {
    ...ice,
    if (gate case (final key, final door)) ...[key, door],
    if (portal case (final a, final b)) ...[a, b],
  };

  void setRoute(List<int> cells) {
    route = cells;
    index = {for (final (i, cell) in cells.indexed) cell: i};
    clues
      ..clear()
      ..add(cells.first)
      ..add(cells.last);
  }

  Puzzle puzzle() => Puzzle(
    n,
    [
      for (final cell in route)
        if (clues.contains(cell)) cell,
    ],
    walls: walls,
    gate: gate,
    portal: portal,
    iceTiles: ice,
  );

  List<int> freeCells() {
    final blocked = mechanicCells;
    return [
      for (final cell in route)
        if (!clues.contains(cell) && !blocked.contains(cell)) cell,
    ];
  }
}

bool _same(List<int>? a, List<int>? b) {
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Set<int> _edgeKeys(List<int> route) => {
  for (var i = 0; i + 1 < route.length; i++)
    route[i] < route[i + 1]
        ? route[i] * 64 + route[i + 1]
        : route[i + 1] * 64 + route[i],
};

bool _adjacent(int n, int a, int b) =>
    (a - b).abs() == n || ((a - b).abs() == 1 && a ~/ n == b ~/ n);

int _color(int n, int cell) => (cell % n + cell ~/ n) & 1;

/// Start and finish cells whose colours allow a route through every cell.
(int, int)? _chooseEnds(int n, PuzzleRandom rng, bool portal) {
  final area = n * n;
  final start = rng.nextInt(area);
  final options = <int>[];
  for (var cell = 0; cell < area; cell++) {
    if (cell == start) continue;
    if (portal) {
      options.add(cell);
    } else if (area.isEven) {
      if (_color(n, cell) != _color(n, start)) options.add(cell);
    } else if (_color(n, cell) == 0 && _color(n, start) == 0) {
      options.add(cell);
    }
  }
  if (options.isEmpty) return null;
  return (start, rng.pick(options));
}

/// Two cells far enough apart that jumping between them changes the order in
/// which regions are visited.
(int, int)? _choosePortal(int n, Set<Wall> walls, PuzzleRandom rng) {
  final probe = Puzzle(n, [0, n * n - 1], walls: walls);
  final distances = <int, List<int>>{};
  List<int> distanceFrom(int source) => distances.putIfAbsent(source, () {
    final dist = List<int>.filled(n * n, -1);
    dist[source] = 0;
    final queue = [source];
    for (var head = 0; head < queue.length; head++) {
      final cell = queue[head];
      for (final next in probe.neighbors[cell]) {
        if (probe.isWalled(cell, next) || dist[next] != -1) continue;
        dist[next] = dist[cell] + 1;
        queue.add(next);
      }
    }
    return dist;
  });
  final options = <(int, int)>[];
  final wanted = math.max(3, n - 2);
  for (var a = 0; a < n * n; a++) {
    final dist = distanceFrom(a);
    for (var b = a + 1; b < n * n; b++) {
      if (dist[b] >= wanted) options.add((a, b));
    }
  }
  if (options.isEmpty) return null;
  return rng.pick(options);
}

/// Adds the checkpoint on the route where the alternative route disagrees
/// most with it.
bool _clueFromAlternative(_Board b, List<int> alt, PuzzleRandom rng) {
  final altIndex = {for (final (i, cell) in alt.indexed) cell: i};
  final scored = <(int, int)>[
    for (final cell in b.freeCells())
      ((b.index[cell]! - (altIndex[cell] ?? 0)).abs(), cell),
  ]..sort((x, y) => y.$1.compareTo(x.$1));
  if (scored.isEmpty) return false;
  final top = math.min(3, scored.length);
  b.clues.add(scored[rng.nextInt(top)].$2);
  return true;
}

/// Adds a checkpoint in the middle of the longest stretch of route without
/// one, so clues spread along the whole route.
bool _clueSpread(_Board b, PuzzleRandom rng) {
  final indexes = [for (final cell in b.clues) b.index[cell]!]..sort();
  var from = 0;
  var widest = 0;
  for (var i = 0; i + 1 < indexes.length; i++) {
    final gap = indexes[i + 1] - indexes[i];
    if (gap > widest) {
      widest = gap;
      from = indexes[i];
    }
  }
  if (widest < 2) return false;
  final blocked = b.mechanicCells;
  final options = [
    for (var i = from + 1; i < from + widest; i++)
      if (!blocked.contains(b.route[i]) &&
          (i - from) * 3 >= widest &&
          (from + widest - i) * 3 >= widest)
        b.route[i],
  ];
  if (options.isEmpty) return false;
  b.clues.add(rng.pick(options));
  return true;
}

/// The fewest checkpoints a board of this kind should keep. Open boards teach
/// checkpoint order, so they keep enough numbers for order to matter.
int _clueFloor(PuzzleSpec spec) {
  if (spec.archetype != Archetype.openOrder) return 3;
  return switch (spec.band) {
    DifficultyBand.beginner => spec.size + 2,
    DifficultyBand.easy => spec.size + 1,
    _ => spec.size,
  };
}

/// Adds the checkpoint next to the most undecided edges.
bool _clueFromUnknowns(_Board b, List<(int, int)> unknown, PuzzleRandom rng) {
  final counts = <int, int>{};
  for (final (u, v) in unknown) {
    counts.update(u, (n) => n + 1, ifAbsent: () => 1);
    counts.update(v, (n) => n + 1, ifAbsent: () => 1);
  }
  final scored = <(int, int)>[
    for (final cell in b.freeCells()) (counts[cell] ?? 0, cell),
  ]..sort((x, y) => y.$1.compareTo(x.$1));
  if (scored.isEmpty) return false;
  final best = scored.first.$1;
  final ties = [
    for (final entry in scored)
      if (entry.$1 == best) entry.$2,
  ];
  b.clues.add(rng.pick(ties));
  return true;
}

/// Makes a cell icy where the alternative route turns but the route goes
/// straight.
bool _iceFromAlternative(_Board b, List<int> alt, PuzzleRandom rng) {
  final n = b.n;
  final altIndex = {for (final (i, cell) in alt.indexed) cell: i};
  final options = <int>[];
  for (final cell in b.freeCells()) {
    final i = b.index[cell]!;
    final j = altIndex[cell];
    if (i < 1 || i + 1 >= b.route.length || j == null) continue;
    if (j < 1 || j + 1 >= alt.length) continue;
    final before = b.route[i - 1];
    final after = b.route[i + 1];
    if (!_adjacent(n, before, cell) ||
        !_adjacent(n, cell, after) ||
        cell - before != after - cell) {
      continue;
    }
    final straightInAlt =
        _adjacent(n, alt[j - 1], cell) &&
        _adjacent(n, cell, alt[j + 1]) &&
        cell - alt[j - 1] == alt[j + 1] - cell;
    if (!straightInAlt) options.add(cell);
  }
  if (options.isEmpty) return false;
  b.ice.add(rng.pick(options));
  return true;
}

/// Adds a key and gate whose order the alternative route would break.
bool _gateFromAlternative(_Board b, List<int> alt, PuzzleRandom rng) {
  if (b.gate != null) return false;
  final altIndex = {for (final (i, cell) in alt.indexed) cell: i};
  final free = b.freeCells();
  final options = <(int, int)>[];
  final minimum = math.max(3, b.route.length ~/ 6);
  for (final key in free) {
    for (final door in free) {
      final i = b.index[key]!;
      final j = b.index[door]!;
      if (j - i < minimum) continue;
      final ai = altIndex[key];
      final aj = altIndex[door];
      if (ai == null || aj == null || ai < aj) continue;
      options.add((key, door));
    }
  }
  if (options.isEmpty) return false;
  b.gate = rng.pick(options);
  return true;
}

/// Adds a wall formation that blocks the alternative route and leaves the
/// certified route alone.
bool _wallsFromAlternative(
  _Board b,
  List<int> alt,
  PuzzleRandom rng,
  DifficultyBand band,
) {
  final limit = wallLimit(b.n, band);
  final current = b.walls;
  if (current.length >= limit) return false;
  final routeEdges = _edgeKeys(b.route);
  final altEdges = _edgeKeys(alt);
  Formation? best;
  var bestScore = 0;
  for (var draw = 0; draw < 48; draw++) {
    final formation = draw % 6 == 0
        ? _stripFormation(rng, b.n)
        : randomFormation(rng, b.n, maxEdges: 7);
    if (formation == null) continue;
    final keys = [for (final (a, c) in formation.edges) a * 64 + c];
    if (keys.any(routeEdges.contains)) continue;
    final kills = keys.where(altEdges.contains).length;
    if (kills == 0) continue;
    final union = {...current, ...formation.edges};
    if (union.length > limit || union.length == current.length) continue;
    if (!staysConnected(b.n, union)) continue;
    final score = kills * 4 + formation.edges.length + rng.nextInt(3);
    if (score > bestScore) {
      best = formation;
      bestScore = score;
    }
  }
  if (best == null) return false;
  b.formations.add(best);
  return true;
}

Formation? _stripFormation(PuzzleRandom rng, int n) =>
    buildSkeleton(Archetype.corridors, n, rng, DifficultyBand.easy).firstOrNull;

/// Relative weights for how to remove alternative solutions, by archetype.
({int clue, int wall, int ice, int gate}) _weights(PuzzleSpec spec) {
  var clue = 40;
  var wall = spec.walls ? 40 : 0;
  var ice = spec.ice ? 30 : 0;
  var gate = spec.gate ? 30 : 0;
  switch (spec.archetype) {
    case Archetype.openOrder:
      clue = 100;
    case Archetype.corridors:
    case Archetype.chambers:
    case Archetype.bottleneck:
    case Archetype.interlock:
      wall += 20;
    case Archetype.directional:
      ice += 35;
    case Archetype.keyed:
      gate += 35;
    case Archetype.wormhole:
      clue += 15;
    case Archetype.mixed:
      break;
  }
  return (clue: clue, wall: wall, ice: ice, gate: gate);
}

/// The next kind of constraint to add: a missing required mechanic first,
/// then a weighted draw.
String _chooseKiller(PuzzleSpec spec, _Board b, int round, PuzzleRandom rng) {
  final missing = <String>[
    if (spec.ice && b.ice.isEmpty) 'ice',
    if (spec.gate && b.gate == null) 'gate',
    if (spec.walls && b.formations.isEmpty) 'wall',
  ];
  if (missing.isNotEmpty && round >= 1 && rng.chance(75)) {
    return rng.pick(missing);
  }
  final w = _weights(spec);
  final total = w.clue + w.wall + w.ice + w.gate;
  var roll = rng.nextInt(total);
  if ((roll -= w.wall) < 0) return 'wall';
  if ((roll -= w.ice) < 0) return 'ice';
  if ((roll -= w.gate) < 0) return 'gate';
  return 'clue';
}

/// How much a mechanic part matters to the finished board.
Relevance _relevance(
  Puzzle without,
  List<int> route,
  DeductionResult baseline,
  int cap,
  GenerationStats stats,
) {
  stats.solverCalls++;
  final proof = solve(without, budget: 80000);
  stats.solverNodes += proof.nodes;
  if (!proof.unique || !_same(proof.first, route)) return Relevance.essential;
  stats.deduceCalls++;
  final logic = deduce(without, maxTier: cap, trace: false);
  if (!logic.solved) return Relevance.supporting;
  if (logic.hardestTier > baseline.hardestTier ||
      logicDifficulty(logic) >= logicDifficulty(baseline) + 4) {
    return Relevance.supporting;
  }
  return Relevance.redundant;
}

/// Builds one candidate board. Returns null, after recording why, when any
/// gate fails.
Accepted? attempt(PuzzleSpec spec, PuzzleRandom rng, GenerationStats stats) {
  final n = spec.size;
  final cap = tierCap(spec.band);
  final b = _Board(n);
  if (spec.walls) {
    b.formations.addAll(buildSkeleton(spec.archetype, n, rng, spec.band));
  }
  if (spec.portal) {
    b.portal = _choosePortal(n, b.walls, rng);
    if (b.portal == null) {
      stats.reject('no_portal_site');
      return null;
    }
  }

  List<int>? route;
  for (var tries = 0; tries < 6 && route == null; tries++) {
    final ends = _chooseEnds(n, rng, spec.portal);
    if (ends == null) break;
    if (b.portal case (final p, final q)) {
      if (ends.$1 == p || ends.$1 == q || ends.$2 == p || ends.$2 == q) {
        continue;
      }
    }
    final base = Puzzle(
      n,
      [ends.$1, ends.$2],
      walls: b.walls,
      portal: b.portal,
    );
    route = findRoute(base, rng, budget: 12000);
  }
  if (route == null) {
    stats.reject('no_route');
    return null;
  }
  b.setRoute(route);

  var unique = false;
  for (var round = 0; round < 70 && !unique; round++) {
    final puzzle = b.puzzle();
    stats.solverCalls++;
    final result = solve(puzzle, budget: 60000);
    stats.solverNodes += result.nodes;
    if (result.status == SolveStatus.none) {
      stats.reject('route_lost');
      return null;
    }
    if (result.unique) {
      unique = true;
      break;
    }
    if (result.status == SolveStatus.inconclusive) {
      if (!_clueFromUnknowns(b, const [], rng)) break;
      continue;
    }
    final alt = _same(result.first, route) ? result.second : result.first;
    if (alt == null) break;
    var applied = false;
    switch (_chooseKiller(spec, b, round, rng)) {
      case 'wall':
        applied = _wallsFromAlternative(b, alt, rng, spec.band);
      case 'ice':
        applied = _iceFromAlternative(b, alt, rng);
      case 'gate':
        applied = _gateFromAlternative(b, alt, rng);
    }
    if (!applied && !_clueFromAlternative(b, alt, rng)) break;
  }
  if (!unique) {
    stats.reject('not_unique');
    return null;
  }

  final floor = _clueFloor(spec);
  while (b.clues.length < floor && _clueSpread(b, rng)) {}

  // Add checkpoints until logic alone can solve the board.
  var solved = false;
  for (var round = 0; round < 40; round++) {
    stats.deduceCalls++;
    final logic = deduce(b.puzzle(), maxTier: math.min(cap, 2), trace: false);
    if (logic.inconsistent) {
      stats.reject('inconsistent');
      return null;
    }
    if (logic.solved) {
      solved = true;
      break;
    }
    if (!_clueFromUnknowns(b, logic.unknownEdges, rng)) break;
  }
  if (!solved) {
    stats.reject('not_logic_solvable');
    return null;
  }

  // Remove checkpoints while the board stays logic-solvable and below the
  // difficulty target for its style.
  final (low, high) = bandRange(spec.band);
  final fraction = switch (spec.style) {
    CheckpointStyle.guided => 0.15,
    CheckpointStyle.standard => 0.55,
    CheckpointStyle.sparse => 0.9,
  };
  final ceiling = low + (math.min(high, 100) - low) * fraction;
  final removable = [
    for (final cell in b.route)
      if (b.clues.contains(cell) &&
          cell != b.route.first &&
          cell != b.route.last)
        cell,
  ];
  rng.shuffle(removable);
  for (final cell in removable) {
    if (b.clues.length <= floor) break;
    b.clues.remove(cell);
    final puzzle = b.puzzle();
    stats.solverCalls++;
    final proof = solve(puzzle, budget: 40000);
    stats.solverNodes += proof.nodes;
    var keep = !proof.unique;
    if (!keep) {
      stats.deduceCalls++;
      final logic = deduce(puzzle, maxTier: cap, trace: false);
      keep = !logic.solved || logicDifficulty(logic) > ceiling;
    }
    if (keep) b.clues.add(cell);
  }

  // Drop mechanic parts that do not change how the board is solved.
  stats.deduceCalls++;
  final full = deduce(b.puzzle(), maxTier: cap, trace: false);
  if (!full.solved) {
    stats.reject('lost_logic');
    return null;
  }
  final reports = <FormationReport>[];
  for (final formation in List.of(b.formations)) {
    b.formations.remove(formation);
    final relevance = _relevance(b.puzzle(), route, full, cap, stats);
    if (relevance == Relevance.redundant) continue;
    b.formations.add(formation);
    reports.add(
      FormationReport(
        kind: 'wall',
        cells: formation.edges.length,
        relevance: relevance,
      ),
    );
  }
  for (final cell in b.ice.toList()) {
    b.ice.remove(cell);
    final relevance = _relevance(b.puzzle(), route, full, cap, stats);
    if (relevance == Relevance.redundant) continue;
    b.ice.add(cell);
    reports.add(FormationReport(kind: 'ice', cells: 1, relevance: relevance));
  }
  final gate = b.gate;
  if (gate != null) {
    b.gate = null;
    final relevance = _relevance(b.puzzle(), route, full, cap, stats);
    if (relevance == Relevance.redundant) {
      // Leave the gate off.
    } else {
      b.gate = gate;
      reports.add(
        FormationReport(kind: 'gate', cells: 2, relevance: relevance),
      );
    }
  }
  if (b.portal != null) {
    reports.add(
      const FormationReport(
        kind: 'portal',
        cells: 2,
        relevance: Relevance.essential,
      ),
    );
  }
  if ((spec.walls && b.formations.isEmpty) ||
      (spec.ice && b.ice.isEmpty) ||
      (spec.gate && b.gate == null)) {
    stats.reject('mechanic_irrelevant');
    return null;
  }

  return _finish(spec, b, stats, reports);
}

Accepted? _finish(
  PuzzleSpec spec,
  _Board b,
  GenerationStats stats,
  List<FormationReport> reports,
) {
  final puzzle = b.puzzle();
  stats.solverCalls++;
  final proof = solve(puzzle, budget: 600000);
  stats.solverNodes += proof.nodes;
  if (!proof.unique || !_same(proof.first, b.route)) {
    stats.reject('final_not_unique');
    return null;
  }
  stats.deduceCalls++;
  final logic = deduce(puzzle, trace: false);
  if (!logic.solved || logic.hardestTier > tierCap(spec.band)) {
    stats.reject('final_not_logic');
    return null;
  }
  final walk = analyzeWalk(puzzle, b.route);
  final difficulty = math.min(100.0, logicDifficulty(logic) + walkBonus(walk));
  final (low, high) = bandRange(spec.band);
  if (difficulty < low - 3 || difficulty >= high + 3) {
    stats.reject('band_${difficulty < low ? 'low' : 'high'}');
    return null;
  }
  final redundant = reports.where((r) => r.relevance == Relevance.redundant);
  if (redundant.isNotEmpty) {
    stats.reject('redundant');
    return null;
  }
  final maxForced = switch (spec.band) {
    DifficultyBand.beginner => 0.95,
    DifficultyBand.easy => 0.9,
    DifficultyBand.intermediate => 0.82,
    _ => 0.74,
  };
  if (walk.forcedMoveRatio > maxForced) {
    stats.reject('trivial_walk');
    return null;
  }
  final profile = PuzzleProfile(
    band: bandFor(difficulty),
    archetype: spec.archetype,
    difficulty: difficulty,
    hardestTier: logic.hardestTier,
    techniques: logic.techniques,
    deductionSteps: logic.deductionCount,
    chainDepth: logic.depth,
    forcedMoveRatio: walk.forcedMoveRatio,
    trapCount: walk.trapCount,
    trapDepth: walk.trapDepth,
    solverNodes: proof.nodes,
    formations: reports,
    fingerprint: canonicalBoard(puzzle),
    expectedSolveMs: expectedSolveMs(puzzle, logic, walk),
  );
  final centre = (low + math.min(high, 100)) / 2;
  final richness =
      reports.where((r) => r.relevance == Relevance.essential).length * 2.0 +
      reports.length +
      walk.trapDepth * 0.5;
  final quality = richness - (difficulty - centre).abs() * 0.15;
  return Accepted(VerifiedPuzzle(puzzle, b.route, profile: profile), quality);
}
