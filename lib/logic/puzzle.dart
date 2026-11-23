/// Cells are indexed in row-major order. Checkpoint numbers are one-based.
final class Puzzle {
  Puzzle(
    this.size,
    Iterable<int> checkpoints, {
    (int, int)? wall,
    Iterable<(int, int)> walls = const [],
    this.arrow,
    this.gate,
    this.portal,
    int? ice,
    Iterable<int> iceTiles = const [],
  }) : walls = Set.unmodifiable({...walls, if (wall != null) wall}),
       iceTiles = Set.unmodifiable({...iceTiles, if (ice != null) ice}),
       checkpoints = List.unmodifiable(checkpoints) {
    if (size < 2 || size > 7) throw ArgumentError.value(size);
    if (this.checkpoints.length < 2 ||
        this.checkpoints.toSet().length != this.checkpoints.length ||
        this.checkpoints.any((cell) => cell < 0 || cell >= area)) {
      throw ArgumentError.value(checkpoints, 'checkpoints');
    }

    for (final (index, cell) in this.checkpoints.indexed) {
      numbers[cell] = index + 1;
    }
  }

  final (int, int)? arrow, gate, portal;
  final Set<(int, int)> walls;
  final Set<int> iceTiles;

  int? forcedNext(int? previous, int cell) {
    if (portal?.$1 == cell) return portal!.$2;
    if (!iceTiles.contains(cell) || previous == null) return null;
    final nextX = 2 * (cell % size) - previous % size;
    final nextY = 2 * (cell ~/ size) - previous ~/ size;
    if (nextX < 0 || nextX >= size || nextY < 0 || nextY >= size) return -1;
    return nextY * size + nextX;
  }

  final int size;
  final List<int> checkpoints;
  int get area => size * size;
  int get start => checkpoints.first;
  int get finish => checkpoints.last;
  late final List<int> numbers = List.filled(area, 0);
  late final List<List<int>> neighbors = List.generate(area, (cell) {
    final row = cell ~/ size;
    final column = cell % size;
    return [
      if (row > 0) cell - size,
      if (column > 0) cell - 1,
      if (column + 1 < size) cell + 1,
      if (row + 1 < size) cell + size,
    ];
  });

  Iterable<int> movesFrom(int cell) sync* {
    yield* neighbors[cell];
    if (portal?.$1 == cell && !neighbors[cell].contains(portal!.$2))
      yield portal!.$2;
    if (portal?.$2 == cell && !neighbors[cell].contains(portal!.$1))
      yield portal!.$1;
  }

  bool canExtend(
    int cell,
    int next,
    int length,
    int checkpoint, {
    bool allowEarlyFinish = false,
    int? previous,
    bool Function(int)? hasVisited,
  }) {
    if (cell == finish || !movesFrom(cell).contains(next)) return false;
    if (walls.contains((cell, next)) || walls.contains((next, cell)))
      return false;
    if (arrow?.$1 == cell && arrow!.$2 != next) return false;
    if (gate?.$2 == next && hasVisited?.call(gate!.$1) != true) return false;
    if (portal?.$2 == next && portal!.$1 != cell) return false;
    final forced = forcedNext(previous, cell);
    if (forced != null && forced != next) return false;
    final number = numbers[next];
    if (number != 0 && number != checkpoint) return false;
    if (allowEarlyFinish && next == finish) return true;
    return (next == finish) == (length + 1 == area);
  }
}

final class VerifiedPuzzle {
  VerifiedPuzzle(this.puzzle, Iterable<int> solution)
    : solution = List.unmodifiable(solution);

  final Puzzle puzzle;
  final List<int> solution;
}
