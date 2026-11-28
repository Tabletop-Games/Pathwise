import 'puzzle_profile.dart';

/// The first rule that prevents an attempted extension.
enum MoveRejection {
  finished,
  adjacency,
  wall,
  gate,
  portal,
  ice,
  checkpoint,
  finish,
  revisit,
}

/// Cells are indexed in row-major order. Checkpoint numbers are one-based.
///
/// This class is the single source of movement rules. The gesture controller,
/// the exact solver, the deduction engine and the generator all evaluate
/// moves through [rejectionFor] and [forcedNext], so they cannot disagree.
///
/// Mechanics:
/// - A wall blocks the edge between two adjacent cells.
/// - An ice tile is passed straight through: the route must leave in the
///   direction it entered.
/// - The gate cell may only be entered after the key cell has been visited.
/// - A portal pair joins two cells. Entering either portal cell emerges from
///   the other, so the pair is always traversed as one step in either
///   direction.
final class Puzzle {
  Puzzle(
    this.size,
    Iterable<int> checkpoints, {
    (int, int)? wall,
    Iterable<(int, int)> walls = const [],
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
    for (final (a, b) in this.walls) {
      _blocked.add(a * 64 + b);
      _blocked.add(b * 64 + a);
    }
  }

  /// `(key, gate)`: the gate cell opens once the key cell has been visited.
  final (int, int)? gate;

  /// Two cells joined by a portal.
  final (int, int)? portal;
  final Set<(int, int)> walls;
  final Set<int> iceTiles;
  final int size;
  final List<int> checkpoints;
  final Set<int> _blocked = {};

  int get area => size * size;
  int get start => checkpoints.first;
  int get finish => checkpoints.last;
  late final List<int> numbers = List.filled(area, 0);

  /// Orthogonal neighbours in the grid, ignoring walls and portals.
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

  /// Cells a route may step to from each cell, ignoring walls: the grid
  /// neighbours plus the portal partner.
  late final List<List<int>> _moves = List.generate(area, (cell) {
    final partner = portalPartner(cell);
    return [
      ...neighbors[cell],
      if (partner != null && !neighbors[cell].contains(partner)) partner,
    ];
  });

  /// True when a wall lies between [a] and [b], in either order.
  bool isWalled(int a, int b) => _blocked.contains(a * 64 + b);

  /// The other end of the portal when [cell] is a portal cell.
  int? portalPartner(int cell) {
    final pair = portal;
    if (pair == null) return null;
    if (cell == pair.$1) return pair.$2;
    if (cell == pair.$2) return pair.$1;
    return null;
  }

  /// The next cell the route is forced to take after arriving at [cell] from
  /// [previous], `-1` when that cell lies outside the grid, or null when the
  /// route is free to choose.
  int? forcedNext(int? previous, int cell) {
    final partner = portalPartner(cell);
    if (partner != null) return previous == partner ? null : partner;
    if (!iceTiles.contains(cell) || previous == null) return null;
    final nextX = 2 * (cell % size) - previous % size;
    final nextY = 2 * (cell ~/ size) - previous ~/ size;
    if (nextX < 0 || nextX >= size || nextY < 0 || nextY >= size) return -1;
    return nextY * size + nextX;
  }

  /// Cells reachable in one step when walls are applied, ignoring every other
  /// rule.
  Iterable<int> movesFrom(int cell) => _moves[cell];

  bool canExtend(
    int cell,
    int next,
    int length,
    int checkpoint, {
    bool allowEarlyFinish = false,
    int? previous,
    bool Function(int)? hasVisited,
  }) {
    return rejectionFor(
          cell,
          next,
          length,
          checkpoint,
          allowEarlyFinish: allowEarlyFinish,
          previous: previous,
          hasVisited: hasVisited,
        ) ==
        null;
  }

  MoveRejection? rejectionFor(
    int cell,
    int next,
    int length,
    int checkpoint, {
    bool allowEarlyFinish = false,
    int? previous,
    bool Function(int)? hasVisited,
  }) {
    if (cell == finish) return MoveRejection.finished;
    if (next < 0 || next >= area || !_moves[cell].contains(next)) {
      return MoveRejection.adjacency;
    }
    if (isWalled(cell, next)) return MoveRejection.wall;
    if (gate?.$2 == next && hasVisited?.call(gate!.$1) != true) {
      return MoveRejection.gate;
    }
    final forced = forcedNext(previous, cell);
    if (forced != null && forced != next) {
      return portalPartner(cell) != null
          ? MoveRejection.portal
          : MoveRejection.ice;
    }
    final number = numbers[next];
    if (number != 0 && number != checkpoint) return MoveRejection.checkpoint;
    if (allowEarlyFinish && next == finish) return null;
    return (next == finish) == (length + 1 == area)
        ? null
        : MoveRejection.finish;
  }
}

/// A board whose solution has been certified, with its generation profile.
///
/// Hand-built boards (tutorials, fixtures) have no [profile].
final class VerifiedPuzzle {
  VerifiedPuzzle(this.puzzle, Iterable<int> solution, {this.profile})
    : solution = List.unmodifiable(solution);

  final Puzzle puzzle;
  final List<int> solution;
  final PuzzleProfile? profile;
}
