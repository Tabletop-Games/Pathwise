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

VerifiedPuzzle generatePuzzle(({int size, int seed, int clues}) request) {
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

  var certified = Puzzle(size, route);
  var proof = solve(certified);
  if (!proof.unique) throw StateError('Could not verify the initial route');
  final removable = route.sublist(1, area - 1);
  random.shuffle(removable);
  for (final cell in removable) {
    if (certified.checkpoints.length <= clues.clamp(2, area)) break;
    final candidate = Puzzle(
      size,
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
