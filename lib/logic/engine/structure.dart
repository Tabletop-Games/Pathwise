import '../puzzle_profile.dart';
import '../puzzle_random.dart';

typedef Wall = (int, int);

Wall wallBetween(int a, int b) => a < b ? (a, b) : (b, a);

/// A connected group of walls built as one shape.
final class Formation {
  const Formation(this.kind, this.edges);

  /// `bar`, `ell`, `u`, `zigzag`, `tee`, `chamber`, `partition`, `stagger`
  /// or `hook`.
  final String kind;
  final Set<Wall> edges;
}

/// Draws on the lattice of grid corners. Every unit step along an interior
/// grid line becomes the wall between the two cells it separates; steps along
/// the outer border are free because the board already ends there.
class _Pen {
  _Pen(this.n);

  final int n;
  int x = 0;
  int y = 0;
  bool ok = true;
  final Set<Wall> edges = {};

  void at(int px, int py) {
    x = px;
    y = py;
  }

  /// Direction 0 east, 1 south, 2 west, 3 north.
  void go(int direction, int length) {
    for (var step = 0; step < length && ok; step++) {
      final nx = x + (direction == 0 ? 1 : (direction == 2 ? -1 : 0));
      final ny = y + (direction == 1 ? 1 : (direction == 3 ? -1 : 0));
      if (nx < 0 || nx > n || ny < 0 || ny > n) {
        ok = false;
        return;
      }
      if (direction == 0 || direction == 2) {
        final column = direction == 0 ? x : nx;
        if (y >= 1 && y <= n - 1) {
          edges.add(wallBetween((y - 1) * n + column, y * n + column));
        }
      } else {
        final row = direction == 1 ? y : ny;
        if (x >= 1 && x <= n - 1) {
          edges.add(wallBetween(row * n + x - 1, row * n + x));
        }
      }
      x = nx;
      y = ny;
    }
  }
}

Formation? _finish(String kind, _Pen pen) =>
    pen.ok && pen.edges.isNotEmpty ? Formation(kind, pen.edges) : null;

int _turn(int direction, bool left) => (direction + (left ? 3 : 1)) % 4;

/// A straight barrier, anchored to the border or floating.
Formation? _bar(PuzzleRandom rng, int n) {
  final length = 2 + rng.nextInt(n - 2);
  final line = 1 + rng.nextInt(n - 1);
  final horizontal = rng.chance(50);
  final anchored = rng.chance(60) || n - length - 1 < 1;
  final fromStart = rng.chance(50);
  final start = anchored
      ? (fromStart ? 0 : n - length)
      : 1 + rng.nextInt(n - length - 1);
  final pen = _Pen(n);
  if (horizontal) {
    pen.at(start, line);
    pen.go(0, length);
  } else {
    pen.at(line, start);
    pen.go(1, length);
  }
  return _finish('bar', pen);
}

Formation? _ell(PuzzleRandom rng, int n) {
  final pen = _Pen(n);
  pen.at(rng.nextInt(n + 1), rng.nextInt(n + 1));
  final first = rng.nextInt(4);
  pen.go(first, 2 + rng.nextInt(n - 2));
  pen.go(_turn(first, rng.chance(50)), 1 + rng.nextInt(n - 2));
  return _finish('ell', pen);
}

Formation? _u(PuzzleRandom rng, int n) {
  final pen = _Pen(n);
  pen.at(rng.nextInt(n + 1), rng.nextInt(n + 1));
  final first = rng.nextInt(4);
  final left = rng.chance(50);
  final depth = 1 + rng.nextInt(n - 2);
  pen.go(first, depth);
  final second = _turn(first, left);
  pen.go(second, 2 + rng.nextInt(n - 3));
  pen.go(_turn(second, left), depth + (rng.chance(40) ? 1 : 0));
  return _finish('u', pen);
}

Formation? _zigzag(PuzzleRandom rng, int n) {
  final pen = _Pen(n);
  pen.at(rng.nextInt(n + 1), rng.nextInt(n + 1));
  var direction = rng.nextInt(4);
  final stairs = rng.chance(50);
  var left = rng.chance(50);
  final legs = 3 + rng.nextInt(3);
  for (var leg = 0; leg < legs; leg++) {
    pen.go(direction, 1 + rng.nextInt(2));
    direction = _turn(direction, left);
    if (stairs) left = !left;
  }
  return _finish('zigzag', pen);
}

Formation? _tee(PuzzleRandom rng, int n) {
  final pen = _Pen(n);
  pen.at(rng.nextInt(n + 1), rng.nextInt(n + 1));
  final stem = rng.nextInt(4);
  pen.go(stem, 1 + rng.nextInt(n - 2));
  final cx = pen.x;
  final cy = pen.y;
  final arm = 1 + rng.nextInt(2);
  pen.go(_turn(stem, true), arm);
  pen.ok = true;
  pen.at(cx, cy);
  pen.go(_turn(stem, false), arm);
  return pen.edges.isEmpty ? null : Formation('tee', pen.edges);
}

Formation? _hook(PuzzleRandom rng, int n) {
  final pen = _Pen(n);
  pen.at(rng.nextInt(n + 1), rng.nextInt(n + 1));
  var direction = rng.nextInt(4);
  final left = rng.chance(50);
  var length = 2 + rng.nextInt(n - 2);
  for (var leg = 0; leg < 3 && length > 0; leg++) {
    pen.go(direction, length);
    direction = _turn(direction, left);
    length -= 1 + rng.nextInt(2);
  }
  return _finish('hook', pen);
}

/// A partly enclosed room with one doorway.
Formation? _chamber(PuzzleRandom rng, int n) {
  final width = 2 + rng.nextInt(n > 5 ? 3 : 2);
  final height = 2 + rng.nextInt(n > 5 ? 3 : 2);
  if (width >= n || height >= n) return null;
  final x0 = rng.nextInt(n - width + 1);
  final y0 = rng.nextInt(n - height + 1);
  final sides = <List<int>>[];
  for (var i = 0; i < width; i++) {
    sides.add([x0 + i, y0, 0]);
    sides.add([x0 + i, y0 + height, 0]);
  }
  for (var i = 0; i < height; i++) {
    sides.add([x0, y0 + i, 1]);
    sides.add([x0 + width, y0 + i, 1]);
  }
  final door = rng.nextInt(sides.length);
  final edges = <Wall>{};
  for (final (index, side) in sides.indexed) {
    if (index == door) continue;
    final pen = _Pen(n)..at(side[0], side[1]);
    pen.go(side[2] == 0 ? 0 : 1, 1);
    edges.addAll(pen.edges);
  }
  return edges.length < 3 ? null : Formation('chamber', edges);
}

/// A full dividing line with [gaps] openings.
Formation? _partition(PuzzleRandom rng, int n, int gaps) {
  final line = 1 + rng.nextInt(n - 1);
  final horizontal = rng.chance(50);
  final open = <int>{};
  while (open.length < gaps) {
    open.add(rng.nextInt(n));
  }
  final edges = <Wall>{};
  for (var unit = 0; unit < n; unit++) {
    if (open.contains(unit)) continue;
    final pen = _Pen(n);
    if (horizontal) {
      pen.at(unit, line);
      pen.go(0, 1);
    } else {
      pen.at(line, unit);
      pen.go(1, 1);
    }
    edges.addAll(pen.edges);
  }
  return edges.length < 2 ? null : Formation('partition', edges);
}

/// Parallel barriers anchored from alternating sides, leaving a staggered gap
/// at the far end of each. They turn the board into winding lanes.
Formation? _stagger(PuzzleRandom rng, int n) {
  final bars = n <= 4 ? 1 + rng.nextInt(2) : 2 + rng.nextInt(2);
  final horizontal = rng.chance(50);
  final gap = rng.chance(75) ? 1 : 2;
  var line = 1 + rng.nextInt(2);
  var fromStart = rng.chance(50);
  final edges = <Wall>{};
  for (var bar = 0; bar < bars && line <= n - 1; bar++) {
    final length = n - gap;
    final pen = _Pen(n);
    final start = fromStart ? 0 : n - length;
    if (horizontal) {
      pen.at(start, line);
      pen.go(0, length);
    } else {
      pen.at(line, start);
      pen.go(1, length);
    }
    edges.addAll(pen.edges);
    fromStart = !fromStart;
    line += 2 + rng.nextInt(2);
  }
  return edges.length < 2 ? null : Formation('stagger', edges);
}

/// A random formation of any kind, or null when the draw does not fit.
Formation? randomFormation(PuzzleRandom rng, int n, {int maxEdges = 8}) {
  final kind = rng.nextInt(7);
  final formation = switch (kind) {
    0 => _bar(rng, n),
    1 => _ell(rng, n),
    2 => _ell(rng, n),
    3 => _u(rng, n),
    4 => _zigzag(rng, n),
    5 => _tee(rng, n),
    _ => _hook(rng, n),
  };
  if (formation == null || formation.edges.length > maxEdges) return null;
  return formation;
}

/// The largest total number of wall edges a board of [size] may carry and
/// stay readable.
int wallLimit(int size, DifficultyBand band) => switch (size) {
  <= 4 => 6,
  5 => 9,
  6 => 13,
  _ => 17,
};

/// Whether the cells stay connected once [walls] are drawn.
bool staysConnected(int n, Set<Wall> walls) {
  final blocked = {
    for (final (a, b) in walls) ...[a * 64 + b, b * 64 + a],
  };
  final seen = <int>{0};
  final queue = [0];
  for (var head = 0; head < queue.length; head++) {
    final cell = queue[head];
    final row = cell ~/ n;
    final column = cell % n;
    for (final next in [
      if (row > 0) cell - n,
      if (row + 1 < n) cell + n,
      if (column > 0) cell - 1,
      if (column + 1 < n) cell + 1,
    ]) {
      if (blocked.contains(cell * 64 + next) || !seen.add(next)) continue;
      queue.add(next);
    }
  }
  return seen.length == n * n;
}

/// The structural skeleton for an archetype: walls only. Mechanics that need
/// the route (ice, gates) are added later, to remove alternative solutions.
List<Formation> buildSkeleton(
  Archetype archetype,
  int n,
  PuzzleRandom rng,
  DifficultyBand band,
) {
  final limit = wallLimit(n, band);
  final formations = <Formation>[];
  void add(Formation? formation) {
    if (formation == null) return;
    final before = {for (final f in formations) ...f.edges};
    final union = {...before, ...formation.edges};
    if (union.length > limit || union.length == before.length) return;
    if (!staysConnected(n, union)) return;
    formations.add(formation);
  }

  switch (archetype) {
    case Archetype.openOrder:
      break;
    case Archetype.corridors:
      add(_stagger(rng, n));
      if (rng.chance(40)) add(randomFormation(rng, n, maxEdges: 5));
    case Archetype.chambers:
      add(_chamber(rng, n));
      if (rng.chance(45)) add(_chamber(rng, n));
      if (rng.chance(35)) add(randomFormation(rng, n, maxEdges: 5));
    case Archetype.bottleneck:
      add(_partition(rng, n, n >= 6 && rng.chance(40) ? 2 : 1));
      if (rng.chance(45)) add(randomFormation(rng, n, maxEdges: 5));
    case Archetype.interlock:
      for (var i = 0; i < 2 + rng.nextInt(2); i++) {
        add(randomFormation(rng, n, maxEdges: 6));
      }
    case Archetype.directional:
    case Archetype.keyed:
    case Archetype.wormhole:
    case Archetype.mixed:
      for (var i = 0; i < 1 + rng.nextInt(2); i++) {
        add(randomFormation(rng, n, maxEdges: 6));
      }
  }
  return formations;
}
