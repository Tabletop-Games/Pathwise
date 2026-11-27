import 'dart:ui' show Offset;

import 'puzzle.dart';

/// Cardinal axis vectors: 0 right, 1 down, 2 left, 3 up.
const _unit = [Offset(1, 0), Offset(0, 1), Offset(-1, 0), Offset(0, -1)];

/// Transient position of the upright path tip while a finger is down. It is
/// never stored, synced, or given to gameplay: the accepted route stays the
/// only game state.
final class TipVisual {
  const TipVisual({
    required this.cell,
    required this.center,
    required this.tip,
    required this.trim,
    required this.extension,
  });

  /// The last accepted cell and its centre, in board units (one unit per cell).
  final int cell;
  final Offset center;

  /// Where the tip is drawn.
  final Offset tip;

  /// The tip has moved back along the accepted trail, so the last accepted
  /// segment should end at [tip] instead of at [center].
  final bool trim;

  /// Distance between [center] and [tip] in cells.
  final double extension;
}

/// Maps a pointer onto a horizontal or vertical axis through the last
/// accepted cell.
///
/// The tip lies on one axis (horizontal or vertical) through the accepted cell
/// centre, so it is never on a diagonal. The axis changes only when the other
/// axis dominates by a dead zone.
///
/// The tracker owns no gameplay rules. It asks `canEnter` whether a
/// neighbouring cell would be accepted and otherwise stops the tip just short
/// of the obstacle. The existing validator still decides what is accepted.
class TipTracker {
  TipTracker({
    this.tipRadius = .22,
    this.deadZone = .10,
    this.checkpointLead = .42,
    this.rebaseRadius = .2,
  });

  /// Tip radius in cells, used to stop short of walls.
  final double tipRadius;

  /// How far above a checkpoint centre the tip rests so the number stays legible.
  final double checkpointLead;

  /// How much the other axis must dominate before the tip changes axis.
  final double deadZone;

  /// After an automatic move the tip waits until the finger is this close to
  /// the accepted cell's centre.
  final double rebaseRadius;

  double get _blocked => .5 - tipRadius - .02;

  int? _cell;
  int _length = -1;
  int? _before;
  bool _horizontal = true;
  int _leadSign = 1;
  bool _rebase = false;
  final _reach = <double>[.5, .5, .5, .5];
  final _legal = <bool>[false, false, false, false];

  /// Clears gesture state when the finger lifts or the gesture is cancelled.
  void reset() {
    _cell = null;
    _length = -1;
    _before = null;
    _rebase = false;
  }

  static Offset centerOf(Puzzle puzzle, int cell) =>
      Offset(cell % puzzle.size + .5, cell ~/ puzzle.size + .5);

  /// Where the tip rests with no finger down. On a checkpoint it sits just
  /// above the rim so the number stays readable while remaining upright.
  static TipVisual rest(
    Puzzle puzzle,
    List<int> route, {
    double checkpointLead = .42,
  }) {
    final cell = route.last;
    final center = centerOf(puzzle, cell);
    final lead = puzzle.numbers[cell] != 0 ? checkpointLead : 0.0;
    return TipVisual(
      cell: cell,
      center: center,
      tip: lead > 0 ? center + Offset(0, -lead) : center,
      trim: false,
      extension: lead,
    );
  }

  /// Projects [pointer] (board units) for the current accepted [route].
  ///
  /// [canEnter] reports whether stepping onto a neighbour would be accepted by
  /// the real validator.
  TipVisual update({
    required Puzzle puzzle,
    required List<int> route,
    required Offset pointer,
    required bool Function(int cell) canEnter,
  }) {
    final cell = route.last;
    final before = route.length > 1 ? route[route.length - 2] : null;
    final center = centerOf(puzzle, cell);
    final d = pointer - center;
    if (_cell != cell || _length != route.length) {
      _computeReach(puzzle, route, cell, before, canEnter);
      _onRouteChanged(puzzle, cell, before, route.length, d);
      _cell = cell;
      _length = route.length;
      _before = before;
    }

    if (_rebase) {
      if (d.dx.abs() <= rebaseRadius && d.dy.abs() <= rebaseRadius) {
        _rebase = false;
      } else {
        return TipVisual(
          cell: cell,
          center: center,
          tip: center,
          trim: false,
          extension: 0,
        );
      }
    }

    final adx = d.dx.abs(), ady = d.dy.abs();
    // Switch axis only when the other axis clearly dominates. A boundary
    // crossing always has |along| = 0.5 >= |perpendicular|, so a cell change
    // can never trigger a switch.
    if (_horizontal && ady > adx + deadZone) {
      _horizontal = false;
      _leadSign = d.dy >= 0 ? 1 : -1;
    } else if (!_horizontal && adx > ady + deadZone) {
      _horizontal = true;
      _leadSign = d.dx >= 0 ? 1 : -1;
    }

    final along = _horizontal ? d.dx : d.dy;
    final positiveDir = _horizontal ? 0 : 1;
    final negativeDir = _horizontal ? 2 : 3;
    // The sideways offset is ignored on purpose: the tip sits on the axis
    // through the accepted cell, and at a cell boundary the extension is
    // exactly +-0.5, so accepting the cell never moves the tip.
    final extension = along
        .clamp(-_reach[negativeDir], _reach[positiveDir])
        .toDouble();

    final extDir = extension >= 0 ? positiveDir : negativeDir;
    if (puzzle.numbers[cell] != 0 && checkpointLead > 0) {
      if (extension != 0 && _legal[extDir]) {
        var position = extension;
        final lead = checkpointLead - extension.abs();
        if (lead > 0) {
          position += _leadSign * lead;
        } else {
          _leadSign = extension >= 0 ? 1 : -1;
        }
        final direction = position >= 0 ? positiveDir : negativeDir;
        final distance = position.abs();
        final tip = center + _unit[direction] * distance;
        final towardBefore =
            before != null &&
            distance > 0 &&
            _directionBetween(puzzle, cell, before) == direction &&
            !_portalHop(puzzle, cell, before);
        return TipVisual(
          cell: cell,
          center: center,
          tip: tip,
          trim: towardBefore,
          extension: distance,
        );
      }
      return TipVisual(
        cell: cell,
        center: center,
        tip: center + Offset(0, -checkpointLead),
        trim: false,
        extension: checkpointLead,
      );
    }

    final direction = extension >= 0 ? positiveDir : negativeDir;
    final distance = extension.abs();
    final tip = center + _unit[direction] * distance;
    final towardBefore =
        before != null &&
        distance > 0 &&
        _directionBetween(puzzle, cell, before) == direction &&
        !_portalHop(puzzle, cell, before);
    return TipVisual(
      cell: cell,
      center: center,
      tip: tip,
      trim: towardBefore,
      extension: distance,
    );
  }

  void _onRouteChanged(
    Puzzle puzzle,
    int cell,
    int? before,
    int length,
    Offset d,
  ) {
    final previous = _cell;
    if (previous == null) {
      _horizontal = d.dx.abs() >= d.dy.abs();
      _leadSign = (_horizontal ? d.dx : d.dy) >= 0 ? 1 : -1;
      _rebase = false;
      return;
    }
    final forward = length == _length + 1 && before == previous;
    final retract = length == _length - 1 && cell == _before;
    final step = (forward || retract)
        ? _directionBetween(puzzle, previous, cell)
        : -1;
    if (step >= 0 && !_portalHop(puzzle, previous, cell)) {
      _horizontal = step % 2 == 0;
      _leadSign = (step == 0 || step == 1) ? 1 : -1;
      _rebase = false;
      return;
    }
    // Slide, portal or several cells at once. If the finger is already inside
    // the new cell carry on from it. Otherwise the tip waits on the accepted
    // cell until the finger arrives.
    _horizontal = d.dx.abs() >= d.dy.abs();
    _leadSign = (_horizontal ? d.dx : d.dy) >= 0 ? 1 : -1;
    _rebase = d.dx.abs() >= .5 || d.dy.abs() >= .5;
  }

  void _computeReach(
    Puzzle puzzle,
    List<int> route,
    int cell,
    int? before,
    bool Function(int cell) canEnter,
  ) {
    final x = cell % puzzle.size, y = cell ~/ puzzle.size;
    for (var dir = 0; dir < 4; dir++) {
      final v = _unit[dir];
      final nx = x + v.dx.toInt(), ny = y + v.dy.toInt();
      if (nx < 0 || ny < 0 || nx >= puzzle.size || ny >= puzzle.size) {
        _reach[dir] = _blocked;
        _legal[dir] = false;
        continue;
      }
      final next = ny * puzzle.size + nx;
      final wall =
          puzzle.walls.contains((cell, next)) ||
          puzzle.walls.contains((next, cell));
      if (wall) {
        _reach[dir] = _blocked;
        _legal[dir] = false;
      } else if (next == before && !_portalHop(puzzle, cell, next)) {
        // Backtracking along the trail is always legal.
        _reach[dir] = .5;
        _legal[dir] = true;
      } else if (route.contains(next)) {
        _reach[dir] = _blocked;
        _legal[dir] = false;
      } else {
        final ok = canEnter(next);
        _reach[dir] = ok ? .5 : _blocked;
        _legal[dir] = ok;
      }
    }
  }

  static int _directionBetween(Puzzle puzzle, int from, int to) {
    final dx = to % puzzle.size - from % puzzle.size;
    final dy = to ~/ puzzle.size - from ~/ puzzle.size;
    if (dx == 1 && dy == 0) return 0;
    if (dx == 0 && dy == 1) return 1;
    if (dx == -1 && dy == 0) return 2;
    if (dx == 0 && dy == -1) return 3;
    return -1;
  }

  static bool _portalHop(Puzzle puzzle, int a, int b) {
    final portal = puzzle.portal;
    if (portal == null) return false;
    return (portal.$1 == a && portal.$2 == b) ||
        (portal.$1 == b && portal.$2 == a);
  }
}
