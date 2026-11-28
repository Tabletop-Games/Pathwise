import 'puzzle.dart';
import 'puzzle_solver.dart';

/// Fixed integer PRNG so saved puzzle IDs remain stable across SDK upgrades.
final class _SeededRandom {
  _SeededRandom(int seed) : _state = seed & 0x7fffffff;

  int _state;

  int nextInt(int bound) {
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return (_state >> 12) % bound;
  }

  void shuffle<T>(List<T> items) {
    for (var index = items.length - 1; index > 0; index--) {
      final other = nextInt(index + 1);
      final item = items[index];
      items[index] = items[other];
      items[other] = item;
    }
  }
}

int puzzleSeed(String id) {
  var hash = 0x011c9dc5;
  for (final code in id.codeUnits) {
    hash = ((hash ^ code) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

VerifiedPuzzle generatePuzzle(
  ({int size, int seed, int clues}) request, {
  int level = 0,
}) {
  VerifiedPuzzle? best;
  var distance = 1 << 30;
  var certified = 0;
  final target = 30 + (level / 10).round();
  for (var attempt = 0; attempt < 24; attempt++) {
    final seed = attempt == 0
        ? request.seed
        : puzzleSeed('${request.seed}/$attempt');
    final board = _tryGenerate((
      size: request.size,
      seed: seed,
      clues: request.clues,
    ), level);
    if (board == null) continue;
    if (level == 0) return board;
    final candidateDistance =
        (difficultyScore(board) - target).abs() -
        8 * mechanicInfluence(board.puzzle);
    if (candidateDistance < distance) {
      best = board;
      distance = candidateDistance;
    }
    if (++certified == 2) return best!;
  }
  if (best != null) return best;
  throw StateError('Could not certify this puzzle');
}

VerifiedPuzzle? _tryGenerate(
  ({int size, int seed, int clues}) request,
  int level,
) {
  final (:size, :seed, :clues) = request;
  final random = _SeededRandom(seed);
  final area = size * size;
  final route = [
    for (var row = 0; row < size; row++)
      for (var column = 0; column < size; column++)
        row * size + (row.isEven ? column : size - column - 1),
  ];
  final neighbors = Puzzle(size, [route.first, route.last]).neighbors;

  // A backbite adds a new edge from an endpoint, then reverses the portion
  // between that endpoint and the new edge to keep one full open route.
  for (var turn = 0; turn < area * 12; turn++) {
    if (random.nextInt(2) == 0) {
      final reversed = route.reversed.toList();
      route.setAll(0, reversed);
    }
    final choices = neighbors[route.first]
        .where((cell) => cell != route[1])
        .toList();
    if (choices.isEmpty) continue;
    final join = route.indexOf(choices[random.nextInt(choices.length)]);
    final prefix = route.take(join).toList().reversed.toList();
    route.setAll(0, prefix);
  }

  // Each mechanic is introduced alone, practiced, then revisited in combinations.
  final pattern = level > 300 ? (level - 301) % 6 : -1;
  final wallEnabled =
      (level >= 31 && level <= 70) ||
      (level >= 101 && level <= 120) ||
      (level >= 151 && level <= 180) ||
      (level >= 231 && level <= 260) ||
      pattern == 0 ||
      pattern == 3 ||
      pattern == 5;
  final iceEnabled =
      (level >= 71 && level <= 120) ||
      (level >= 181 && level <= 200) ||
      (level >= 261 && level <= 300) ||
      pattern == 1 ||
      pattern == 3 ||
      pattern == 4 ||
      pattern == 5;
  final gateEnabled =
      (level >= 121 && level <= 200) ||
      pattern == 0 ||
      pattern == 2 ||
      pattern == 4 ||
      pattern == 5;
  final portalEnabled =
      (level >= 201 && level <= 300) ||
      pattern == 1 ||
      pattern == 2 ||
      pattern == 4 ||
      pattern == 5;
  (int, int)? portal;
  if (portalEnabled) {
    final splices = <(int, int)>[
      for (var i = 1; i < route.length - 4; i++)
        for (var j = i + 2; j < route.length - 2; j++)
          if (neighbors[route[i]].contains(route[j]) &&
              !neighbors[route[i + 1]].contains(route[j + 1]))
            (i, j),
    ];
    if (splices.isEmpty) return null;
    final (i, j) = splices[random.nextInt(splices.length)];
    final reversed = route.sublist(i + 1, j + 1).reversed.toList();
    route.setAll(i + 1, reversed);
    portal = (route[j], route[j + 1]);
  }
  final wallOptions = <(int, int)>[
    for (var i = 0; i < area; i++)
      for (final neighbor in neighbors[route[i]])
        if (route[i] < neighbor && (route.indexOf(neighbor) - i).abs() != 1)
          (route[i], neighbor),
  ];
  final walls = <(int, int)>{};
  if (wallEnabled) {
    final allowed = wallOptions.toSet();
    final runs = <List<(int, int)>>[];
    for (final (a, b) in wallOptions) {
      final stride = b - a == 1 ? size : 1;
      final run = [(a, b)];
      for (var step = 1; step <= 2; step++) {
        final next = (a + stride * step, b + stride * step);
        if ((stride == 1 && a ~/ size != next.$1 ~/ size) ||
            !allowed.contains(next))
          break;
        run.add(next);
      }
      if (run.length >= 2) runs.add(run);
    }
    if (runs.isEmpty) return null;
    walls.addAll(runs[random.nextInt(runs.length)]);
  }
  final gate = gateEnabled
      ? (
          route[2],
          route.reversed
              .skip(2)
              .firstWhere((cell) => cell != portal?.$1 && cell != portal?.$2),
        )
      : null;
  final ice = <int>{};
  final reserved = <int>{
    if (portal != null) ...[portal.$1, portal.$2],
    if (gate != null) ...[gate.$1, gate.$2],
  };
  if (iceEnabled) {
    final straight = <int>[
      for (var i = 1; i < area - 1; i++)
        if (neighbors[route[i - 1]].contains(route[i]) &&
            neighbors[route[i]].contains(route[i + 1]) &&
            route[i] - route[i - 1] == route[i + 1] - route[i] &&
            !reserved.contains(route[i]))
          route[i],
    ];
    if (straight.length < 2) return null;
    final pairs = [
      for (var i = 0; i < straight.length - 1; i++)
        if (route.indexOf(straight[i + 1]) == route.indexOf(straight[i]) + 1)
          [straight[i], straight[i + 1]],
    ];
    if (pairs.isNotEmpty) {
      ice.addAll(pairs[random.nextInt(pairs.length)]);
    } else {
      random.shuffle(straight);
      ice.addAll(straight.take(2));
    }
  }
  reserved.addAll(ice);
  Puzzle build(Iterable<int> checkpoints) => Puzzle(
    size,
    checkpoints,
    walls: walls,
    gate: gate,
    portal: portal,
    iceTiles: ice,
  );

  var certified = build(route.where((cell) => !reserved.contains(cell)));
  var proof = solve(certified);
  if (!proof.unique) return null;
  final removable = route.sublist(1, area - 1);
  random.shuffle(removable);
  for (final cell in removable) {
    if (certified.checkpoints.length <= clues.clamp(2, area)) break;
    if (!certified.checkpoints.contains(cell)) continue;
    final candidate = build(
      certified.checkpoints.where((value) => value != cell),
    );
    final result = solve(candidate, budget: 18000);
    if (result.unique) {
      certified = candidate;
      proof = result;
    }
  }
  return VerifiedPuzzle(certified, proof.first!);
}
