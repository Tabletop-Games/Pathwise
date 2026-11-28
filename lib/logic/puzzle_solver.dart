import 'puzzle.dart';
import 'puzzle_random.dart';

/// What an exact search established. Only [SolveStatus.unique] certifies a
/// board; a search that ran out of budget is [SolveStatus.inconclusive] and
/// never counts as proof of anything.
enum SolveStatus { none, unique, multiple, inconclusive }

final class SearchResult {
  const SearchResult(
    this.status,
    this.count,
    this.first,
    this.nodes, {
    this.second,
    this.deepest = 0,
  });

  final SolveStatus status;

  /// Solutions found. Searches stop at the requested limit, so this is exact
  /// only when it is below that limit and the search was conclusive.
  final int count;
  final List<int>? first;
  final List<int>? second;
  final int nodes;

  /// The longest partial route the search reached, in cells.
  final int deepest;

  bool get unique => status == SolveStatus.unique;
  bool get exhausted => status != SolveStatus.inconclusive;
}

int _popCount(int value) {
  var count = 0;
  var bits = value;
  while (bits != 0) {
    bits &= bits - 1;
    count++;
  }
  return count;
}

int _lowIndex(int bit) => bit.bitLength - 1;

/// Exact depth-first search with sound pruning.
///
/// Counts solutions up to [limit] (two by default, which is enough to decide
/// uniqueness) from the start cell, or from a valid partial route [prefix].
/// The pruning only removes states that provably cannot be completed:
/// - every unvisited cell must keep enough unvisited neighbours (two, or one
///   for the finish; two opposite ones for an ice tile),
/// - all unvisited cells must stay connected to the tip,
/// - the remaining steps must cover the shortest distances between the
///   remaining checkpoints,
/// - on boards without a portal, the colours of the remaining cells must
///   alternate as a route does.
/// Distances and connectivity ignore gates, ice and checkpoint order, so they
/// are relaxations and cannot discard a legal route.
SearchResult solve(
  Puzzle puzzle, {
  int budget = 120000,
  int limit = 2,
  List<int>? prefix,
}) {
  assert(limit >= 2, 'a limit below two cannot decide uniqueness');
  return _Search(puzzle, budget, limit).run(prefix);
}

/// Finds one complete route in a random order, or null when the search finds
/// none within [budget] nodes. The same [random] state gives the same route.
List<int>? findRoute(Puzzle puzzle, PuzzleRandom random, {int budget = 20000}) {
  final search = _Search(puzzle, budget, 1).._random = random;
  return search.run(null).first;
}

final class _Search {
  _Search(this.p, this.budget, this.limit)
    : area = p.area,
      adj = List.filled(p.area, 0),
      moves = List.generate(p.area, (_) => <int>[]) {
    for (var cell = 0; cell < area; cell++) {
      for (final next in p.movesFrom(cell)) {
        if (p.isWalled(cell, next)) continue;
        adj[cell] |= 1 << next;
        moves[cell].add(next);
      }
    }
    _computeDistances();
    for (var cell = 0; cell < area; cell++) {
      final color = (cell % p.size + cell ~/ p.size) & 1;
      if (color == 0) {
        evenMask |= 1 << cell;
      }
    }
    needsPrevious = List.generate(
      area,
      (cell) => p.iceTiles.contains(cell) || p.portalPartner(cell) != null,
    );
    visited = (cell) => remaining & (1 << cell) == 0;
  }

  final Puzzle p;
  final int budget;
  final int limit;
  final int area;
  final List<int> adj;
  final List<List<int>> moves;
  late final List<int> dist;
  late final List<int> chainSuffix;
  late final List<bool> needsPrevious;
  late final bool Function(int) visited;
  int evenMask = 0;
  final dead = <int>{};
  final path = <int>[];
  int remaining = 0;
  int count = 0;
  int nodes = 0;
  int deepest = 0;
  bool aborted = false;
  PuzzleRandom? _random;
  List<int>? first;
  List<int>? second;

  void _computeDistances() {
    dist = List.filled(area * area, 1 << 20);
    for (var source = 0; source < area; source++) {
      final base = source * area;
      dist[base + source] = 0;
      final queue = [source];
      for (var head = 0; head < queue.length; head++) {
        final cell = queue[head];
        for (final next in moves[cell]) {
          if (dist[base + next] != 1 << 20) continue;
          dist[base + next] = dist[base + cell] + 1;
          queue.add(next);
        }
      }
    }
    final checkpoints = p.checkpoints;
    chainSuffix = List.filled(checkpoints.length + 1, 0);
    for (var index = checkpoints.length - 2; index >= 0; index--) {
      chainSuffix[index] =
          chainSuffix[index + 1] +
          dist[checkpoints[index] * area + checkpoints[index + 1]];
    }
  }

  SearchResult run(List<int>? prefix) {
    final route = prefix ?? [p.start];
    if (route.isEmpty || route.first != p.start) return _result();
    var left = ((1 << area) - 1) ^ (1 << p.start);
    var checkpoint = 2;
    path.add(route.first);
    for (var index = 1; index < route.length; index++) {
      final next = route[index];
      final bit = 1 << next;
      remaining = left;
      if (next < 0 ||
          next >= area ||
          left & bit == 0 ||
          p.rejectionFor(
                route[index - 1],
                next,
                index,
                checkpoint,
                previous: index > 1 ? route[index - 2] : null,
                hasVisited: visited,
              ) !=
              null) {
        return _result();
      }
      left ^= bit;
      if (p.numbers[next] != 0) checkpoint++;
      path.add(next);
    }
    remaining = left;
    _search(route.last, checkpoint);
    return _result();
  }

  SearchResult _result() {
    final status = aborted
        ? SolveStatus.inconclusive
        : count == 0
        ? SolveStatus.none
        : count >= 2 || count >= limit
        ? SolveStatus.multiple
        : SolveStatus.unique;
    return SearchResult(
      status,
      count,
      first,
      nodes,
      second: second,
      deepest: deepest,
    );
  }

  bool _feasible(int cell, int checkpoint) {
    final left = remaining;
    final tipBit = 1 << cell;
    final pool = left | tipBit;
    final cellsLeft = _popCount(left);

    // Every remaining cell needs enough unvisited neighbours.
    var cells = left;
    while (cells != 0) {
      final bit = cells & -cells;
      cells ^= bit;
      final index = _lowIndex(bit);
      final edges = adj[index] & pool;
      if (edges == 0) return false;
      if (index != p.finish && edges & (edges - 1) == 0) return false;
      if (p.iceTiles.contains(index)) {
        final size = p.size;
        final column = index % size;
        final across =
            column > 0 &&
            column + 1 < size &&
            edges & (1 << (index - 1)) != 0 &&
            edges & (1 << (index + 1)) != 0;
        final row = index ~/ size;
        final vertical =
            row > 0 &&
            row + 1 < size &&
            edges & (1 << (index - size)) != 0 &&
            edges & (1 << (index + size)) != 0;
        if (!across && !vertical) return false;
      }
    }

    // Everything unvisited must stay reachable from the tip.
    var connected = tipBit;
    var frontier = tipBit;
    while (frontier != 0) {
      final bit = frontier & -frontier;
      frontier ^= bit;
      final added = adj[_lowIndex(bit)] & left & ~connected;
      connected |= added;
      frontier |= added;
    }
    if (connected & left != left) return false;

    // The remaining steps must reach every remaining checkpoint in order.
    if (checkpoint <= p.checkpoints.length) {
      final target = p.checkpoints[checkpoint - 1];
      final needed =
          dist[cell * area + target] +
          (checkpoint <= p.checkpoints.length - 1
              ? chainSuffix[checkpoint - 1]
              : 0);
      if (needed > cellsLeft) return false;
    }

    if (p.portal == null) {
      final tipColor = (cell % p.size + cell ~/ p.size) & 1;
      final other = tipColor ^ 1;
      final others = _popCount(left & (other == 0 ? evenMask : ~evenMask));
      if (others != (cellsLeft + 1) ~/ 2) return false;
      final finishColor = (p.finish % p.size + p.finish ~/ p.size) & 1;
      if (finishColor != (tipColor ^ (cellsLeft & 1))) return false;
    }
    return true;
  }

  void _search(int cell, int checkpoint) {
    if (path.length > deepest) deepest = path.length;
    if (++nodes > budget) {
      aborted = true;
      return;
    }
    if (remaining == 0) {
      count++;
      if (first == null) {
        first = List.of(path);
      } else {
        second ??= List.of(path);
      }
      return;
    }
    final previous = path.length > 1 ? path[path.length - 2] : null;
    final key =
        remaining |
        (cell << 49) |
        ((needsPrevious[cell] && previous != null ? previous + 1 : 0) << 55);
    if (dead.contains(key)) return;
    if (!_feasible(cell, checkpoint)) {
      dead.add(key);
      return;
    }
    final before = count;
    var candidates = moves[cell];
    if (_random != null) {
      candidates = List.of(candidates);
      _random!.shuffle(candidates);
    }
    for (final next in candidates) {
      final bit = 1 << next;
      if (remaining & bit == 0) continue;
      if (p.rejectionFor(
            cell,
            next,
            path.length,
            checkpoint,
            previous: previous,
            hasVisited: visited,
          ) !=
          null) {
        continue;
      }
      path.add(next);
      remaining ^= bit;
      _search(next, checkpoint + (p.numbers[next] == 0 ? 0 : 1));
      remaining |= bit;
      path.removeLast();
      if (aborted || count >= limit) return;
    }
    if (count == before) dead.add(key);
  }
}
