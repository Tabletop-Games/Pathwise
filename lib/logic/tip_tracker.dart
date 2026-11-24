import 'dart:ui' show Offset;

import 'puzzle.dart';

/// Cardinal facings: 0 right, 1 down, 2 left, 3 up. Matches `tipDirection`.
const _unit = [Offset(1, 0), Offset(0, 1), Offset(-1, 0), Offset(0, -1)];

Offset facingVector(int facing) => _unit[facing % 4];

/// Transient picture of the path tip while a finger is down. It is never
/// stored, synced or given to gameplay: the accepted route stays the only
/// game state.
final class TipVisual {
  const TipVisual({
    required this.cell,
    required this.center,
    required this.tip,
    required this.facing,
    required this.trim,
    required this.extension,
  });

  /// The last accepted cell and its centre, in board units (one unit per cell).
  final int cell;
  final Offset center;

  /// Where the tip is drawn.
  final Offset tip;

  /// 0 right, 1 down, 2 left, 3 up. Always cardinal.
  final int facing;

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
/// Facing is the direction of the finger's motion on the active axis, with
/// hysteresis, and is always one of four cardinals.
///
/// The tracker owns no gameplay rules. It asks `canEnter` whether a
/// neighbouring cell would be accepted and otherwise stops the tip just short
/// of the obstacle. The existing validator still decides what is accepted.
class TipTracker {
  TipTracker({
    this.tipRadius = .22,
    this.deadZone = .10,
    this.hysteresis = .10,
    this.checkpointLead = .31,
    this.rebaseRadius = .2,
  });

  /// Tip radius in cells, used to stop short of walls.
  final double tipRadius;

  /// How far ahead of a checkpoint centre the tip rests.
  final double checkpointLead;

  /// How much the other axis must dominate before the tip changes axis.
  final double deadZone;

  /// Retreat along the axis, in cells, before the facing flips.
  final double hysteresis;

  /// After an automatic move the tip waits until the finger is this close to
  /// the accepted cell's centre.
  final double rebaseRadius;

  double get _blocked => .5 - tipRadius - .02;

  int? _cell;
  int _length = -1;
  int? _before;
  bool _horizontal = true;
  int _sign = 1;
  int _leadSign = 1;
  double _peak = 0;
  bool _rebase = false;
  final _reach = <double>[.5, .5, .5, .5];

  /// Clears gesture state when the finger lifts or the gesture is cancelled.
  void reset() {
    _cell = null;
    _length = -1;
    _before = null;
    _rebase = false;
    _peak = 0;
  }

  static Offset centerOf(Puzzle puzzle, int cell) =>
      Offset(cell % puzzle.size + .5, cell ~/ puzzle.size + .5);

  /// Where the tip rests with no finger down. On a checkpoint it sits on the
  /// leading rim so the number stays readable.
  static TipVisual rest(
    Puzzle puzzle,
    List<int> route,
    int facing, {
    double checkpointLead = .31,
  }) {
    final cell = route.last;
    final center = centerOf(puzzle, cell);
    final lead = puzzle.numbers[cell] != 0 ? checkpointLead : 0.0;
    return TipVisual(
      cell: cell,
      center: center,
      tip: center + facingVector(facing) * lead,
      facing: facing,
      trim: false,
      extension: lead,
    );
  }

  /// Projects [pointer] (board units) for the current accepted [route].
  ///
  /// [acceptedFacing] is the cardinal facing derived from accepted edges with
  /// portal transport skipped. [canEnter] reports whether stepping onto a
  /// neighbour would be accepted by the real validator.
  TipVisual update({
    required Puzzle puzzle,
    required List<int> route,
    required Offset pointer,
    required int acceptedFacing,
    required bool Function(int cell) canEnter,
  }) {
    final cell = route.last;
    final before = route.length > 1 ? route[route.length - 2] : null;
    final center = centerOf(puzzle, cell);
    final d = pointer - center;
    if (_cell != cell || _length != route.length) {
      _onRouteChanged(puzzle, cell, before, route.length, acceptedFacing, d);
      _computeReach(puzzle, route, cell, before, canEnter);
      _cell = cell;
      _length = route.length;
      _before = before;
    }

    if (_rebase) {
      if (d.dx.abs() <= rebaseRadius && d.dy.abs() <= rebaseRadius) {
        _rebase = false;
        _setFacing(acceptedFacing);
        _peak = _sign * _along(d);
      } else {
        return TipVisual(
          cell: cell,
          center: center,
          tip: center,
          facing: acceptedFacing,
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
      _sign = d.dy >= 0 ? 1 : -1;
      _peak = _sign * d.dy;
    } else if (!_horizontal && adx > ady + deadZone) {
      _horizontal = true;
      _sign = d.dx >= 0 ? 1 : -1;
      _peak = _sign * d.dx;
    }

    final along = _along(d);
    // Facing follows the direction of motion, with hysteresis.
    final signed = _sign * along;
    if (signed > _peak) {
      _peak = signed;
    } else if (signed < _peak - hysteresis) {
      _sign = -_sign;
      _peak = _sign * along;
    }

    final positiveDir = _horizontal ? 0 : 1;
    final negativeDir = _horizontal ? 2 : 3;
    // The sideways offset is ignored on purpose: the tip sits on the axis
    // through the accepted cell, and at a cell boundary the extension is
    // exactly +-0.5, so accepting the cell never moves the tip.
    final extension = along
        .clamp(-_reach[negativeDir], _reach[positiveDir])
        .toDouble();
    var facing = _sign > 0 ? positiveDir : negativeDir;
    var position = extension;
    if (puzzle.numbers[cell] != 0) {
      // A lead that fades out as the finger moves away from the centre. It is
      // continuous in the finger position, equals the plain extension once the
      // finger is past the lead, and equals -0.5 on the boundary behind the
      // cell, so entering a checkpoint never makes the tip jump. Its side only
      // changes where it contributes nothing, so the tip never jumps either.
      final lead = checkpointLead - extension.abs();
      if (lead > 0) {
        position += _leadSign * lead;
        facing = _leadSign > 0 ? positiveDir : negativeDir;
      } else {
        _leadSign = extension >= 0 ? 1 : -1;
      }
    }
    final direction = position >= 0 ? positiveDir : negativeDir;
    final distance = position.abs();
    final tip = center + _unit[direction] * distance;
    final towardBefore = before != null &&
        distance > 0 &&
        _directionBetween(puzzle, cell, before) == direction &&
        !_portalHop(puzzle, cell, before);
    return TipVisual(
      cell: cell,
      center: center,
      tip: tip,
      facing: facing,
      trim: towardBefore,
      extension: distance,
    );
  }

  double _along(Offset d) => _horizontal ? d.dx : d.dy;

  void _setFacing(int facing) {
    _horizontal = facing % 2 == 0;
    _sign = facing == 0 || facing == 1 ? 1 : -1;
    _leadSign = _sign;
  }

  void _onRouteChanged(
    Puzzle puzzle,
    int cell,
    int? before,
    int length,
    int acceptedFacing,
    Offset d,
  ) {
    final previous = _cell;
    if (previous == null) {
      // First sight of this gesture: start from the accepted facing.
      _setFacing(acceptedFacing);
      _peak = _sign * _along(d);
      _rebase = false;
      return;
    }
    final forward = length == _length + 1 && before == previous;
    final retract = length == _length - 1 && cell == _before;
    final step = (forward || retract)
        ? _directionBetween(puzzle, previous, cell)
        : -1;
    if (step >= 0 && !_portalHop(puzzle, previous, cell)) {
      // One orthogonal step: carry on in the same direction of motion.
      _setFacing(step);
      _peak = _sign * _along(d);
      _rebase = false;
      return;
    }
    // Slide, portal or several cells at once. If the finger is already inside
    // the new cell carry on from it. Otherwise the tip waits on the accepted
    // cell until the finger arrives.
    _setFacing(acceptedFacing);
    _peak = _sign * _along(d);
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
        continue;
      }
      final next = ny * puzzle.size + nx;
      final wall =
          puzzle.walls.contains((cell, next)) ||
          puzzle.walls.contains((next, cell));
      if (wall) {
        _reach[dir] = _blocked;
      } else if (next == before && !_portalHop(puzzle, cell, next)) {
        // Backtracking along the trail is always legal.
        _reach[dir] = .5;
      } else if (route.contains(next)) {
        _reach[dir] = _blocked;
      } else {
        _reach[dir] = canEnter(next) ? .5 : _blocked;
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
