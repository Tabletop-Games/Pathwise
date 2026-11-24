import 'puzzle.dart';

final class SearchResult {
  const SearchResult(this.count, this.exhausted, this.first, this.nodes);
  final int count;
  final bool exhausted;
  final List<int>? first;
  final int nodes;
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
  return SearchResult(count, exhausted && count < 2, first, visitedNodes);
}

/// Heuristic for catalogue selection; it is a proxy, not human playtesting.
/// Counts decision points and misleading choices along the verified route,
/// solver search effort, route turns and interacting constraints.
int difficultyScore(VerifiedPuzzle board) {
  final p = board.puzzle;
  final route = board.solution;
  var choices = 0;
  var decisions = 0;
  var turns = 0;
  var checkpoint = 2;
  for (var i = 0; i < route.length - 1; i++) {
    final seen = route.take(i + 1).toSet();
    final options = p
        .movesFrom(route[i])
        .where(
          (next) =>
              !seen.contains(next) &&
              p.canExtend(
                route[i],
                next,
                i + 1,
                checkpoint,
                allowEarlyFinish: true,
                previous: i > 0 ? route[i - 1] : null,
                hasVisited: seen.contains,
              ),
        )
        .length;
    if (options > 1) {
      decisions++;
      choices += options - 1;
    }
    if (i > 0 && route[i] - route[i - 1] != route[i + 1] - route[i]) turns++;
    if (p.numbers[route[i + 1]] != 0) checkpoint++;
  }
  final proof = solve(p);
  var effort = 0;
  for (var nodes = proof.nodes; nodes > 1; nodes ~/= 2) {
    effort++;
  }
  final kinds = [
    p.walls.isNotEmpty,
    p.iceTiles.isNotEmpty,
    p.gate != null,
    p.portal != null,
    p.arrow != null,
  ].where((v) => v).length;
  return decisions * 3 + choices * 2 + turns ~/ 3 + effort + kinds * kinds;
}

/// Counts mechanics proven to rule out alternate solutions. A zero does not
/// prove that a mechanic is irrelevant: bounded searches may be inconclusive,
/// and portals can change the shape of the solution space in other ways.
int mechanicInfluence(Puzzle p) {
  Puzzle without({
    bool walls = false,
    bool ice = false,
    bool gate = false,
    bool portal = false,
  }) => Puzzle(
    p.size,
    p.checkpoints,
    walls: walls ? const [] : p.walls,
    iceTiles: ice ? const [] : p.iceTiles,
    gate: gate ? null : p.gate,
    portal: portal ? null : p.portal,
    arrow: p.arrow,
  );
  var count = 0;
  for (final candidate in [
    if (p.walls.isNotEmpty) without(walls: true),
    if (p.iceTiles.isNotEmpty) without(ice: true),
    if (p.gate != null) without(gate: true),
    if (p.portal != null) without(portal: true),
  ]) {
    if (solve(candidate, budget: 12000).count >= 2) count++;
  }
  return count;
}
