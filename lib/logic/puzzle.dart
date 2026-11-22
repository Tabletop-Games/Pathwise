/// Cells are indexed in row-major order. Checkpoint numbers are one-based.
final class Puzzle {
  Puzzle(this.size, Iterable<int> checkpoints)
    : checkpoints = List.unmodifiable(checkpoints) {
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

  bool canExtend(int cell, int next, int length, int checkpoint) {
    if (!neighbors[cell].contains(next)) return false;
    final number = numbers[next];
    if (number != 0 && number != checkpoint) return false;
    return (next == finish) == (length + 1 == area);
  }
}

final class VerifiedPuzzle {
  VerifiedPuzzle(this.puzzle, Iterable<int> solution)
    : solution = List.unmodifiable(solution);

  final Puzzle puzzle;
  final List<int> solution;
}
