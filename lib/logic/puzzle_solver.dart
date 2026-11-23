import 'puzzle.dart';

final class SearchResult {
  const SearchResult(this.count, this.exhausted, this.first);
  final int count;
  final bool exhausted;
  final List<int>? first;
  bool get unique => exhausted && count == 1;
}

/// Exhaustively counts solutions, stopping when uniqueness has been disproved
/// or the node budget is exhausted. Neither early exit can certify uniqueness.
SearchResult solve(Puzzle puzzle, {int budget = 120000}) {
  final full = (1 << puzzle.area) - 1;
  final masks = [
    for (var cell = 0; cell < puzzle.area; cell++)
      puzzle.movesFrom(cell).fold(0, (mask, cell) => mask | (1 << cell)),
  ];
  final byBit = {
    for (var cell = 0; cell < puzzle.area; cell++) 1 << cell: cell,
  };
  final path = [puzzle.start];
  final dead = <(int, int, int?)>{};
  var count = 0;
  var visitedNodes = 0;
  var exhausted = true;
  List<int>? first;

  bool canCover(int cell, int remaining) {
    var cells = remaining;
    while (cells != 0) {
      final bit = cells & -cells;
      cells ^= bit;
      final index = byBit[bit]!;
      final edges = masks[index] & (remaining | (1 << cell));
      if (edges == 0 || (index != puzzle.finish && edges & (edges - 1) == 0)) {
        return false;
      }
    }
    var connected = 1 << cell;
    var frontier = connected;
    while (frontier != 0) {
      final bit = frontier & -frontier;
      frontier ^= bit;
      final added = masks[byBit[bit]!] & remaining & ~connected;
      connected |= added;
      frontier |= added;
    }
    return connected & remaining == remaining;
  }

  void search(int cell, int remaining, int checkpoint) {
    if (++visitedNodes > budget || count >= 2) {
      exhausted = false;
      return;
    }
    if (remaining == 0) {
      count++;
      first ??= List.of(path);
      return;
    }
    final previous = path.length > 1 ? path[path.length - 2] : null;
    final state = (
      cell,
      remaining,
      puzzle.iceTiles.contains(cell) ? previous : null,
    );
    // The remaining mask also determines which checkpoints have been visited.
    if (dead.contains(state)) return;
    if (!canCover(cell, remaining)) {
      dead.add(state);
      return;
    }
    final before = count;
    for (final next in puzzle.movesFrom(cell)) {
      final bit = 1 << next;
      if (remaining & bit == 0 ||
          !puzzle.canExtend(
            cell,
            next,
            path.length,
            checkpoint,
            previous: previous,
            hasVisited: (index) => remaining & (1 << index) == 0,
          )) {
        continue;
      }
      path.add(next);
      search(
        next,
        remaining ^ bit,
        checkpoint + (puzzle.numbers[next] == 0 ? 0 : 1),
      );
      path.removeLast();
      if (!exhausted || count >= 2) return;
    }
    if (before == count) dead.add(state);
  }

  search(puzzle.start, full ^ (1 << puzzle.start), 2);
  return SearchResult(count, exhausted && count < 2, first);
}
