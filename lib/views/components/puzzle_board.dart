import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/game_controller.dart';
import '../../logic/puzzle.dart';
import '../../logic/puzzle_generator.dart';
import '../../logic/tip_tracker.dart';
import '../../model/app_themes.dart';
import '../../model/game_state.dart';
import '../../model/path_tips.dart';
import 'tip_art.dart';

/// Facing direction is derived only from accepted orthogonal moves. Portal
/// transport is skipped, including when its endpoints happen to be adjacent.
int tipDirection(Puzzle puzzle, List<int> route) {
  for (var i = route.length - 1; i > 0; i--) {
    final from = route[i - 1], to = route[i];
    if (puzzle.portal?.$1 == from && puzzle.portal?.$2 == to) continue;
    final dx = to % puzzle.size - from % puzzle.size;
    final dy = to ~/ puzzle.size - from ~/ puzzle.size;
    if (dx == 1 && dy == 0) return 0;
    if (dx == 0 && dy == 1) return 1;
    if (dx == -1 && dy == 0) return 2;
    if (dx == 0 && dy == -1) return 3;
  }
  return 0;
}

class LevelOneBoardPreview extends StatelessWidget {
  const LevelOneBoardPreview({
    required this.palette,
    this.tip = PathTip.classic,
    this.directionOverride,
    super.key,
  });

  final PathTip tip;
  final int? directionOverride;

  final BoardPalette palette;
  static final _board = generatePuzzle(
    const PuzzleId.level(1).generation,
    level: 1,
  );

  /// One stable prefix of the actual Level 1 solution, shared by all themes.
  static VerifiedPuzzle get board => _board;
  static final List<int> previewRoute = () {
    final solution = _board.solution;
    final middle = (solution.length / 2).round();
    final candidates = [middle, middle - 1, middle + 1];
    final count = candidates.firstWhere(
      (length) =>
          length > 1 &&
          length < solution.length &&
          _board.puzzle.numbers[solution[length - 1]] == 0,
      orElse: () => middle,
    );
    return List<int>.unmodifiable(solution.take(count));
  }();

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Partially solved Level 1 board',
    child: AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _BoardPainter(
          puzzle: _board.puzzle,
          palette: palette,
          tipStyle: tip,
          directionOverride: directionOverride,
          showTip: true,
          route: previewRoute,
          hint: null,
          next:
              1 +
              previewRoute
                  .where((cell) => _board.puzzle.numbers[cell] != 0)
                  .length,
          complete: false,
        ),
      ),
    ),
  );
}

class PuzzleBoard extends StatefulWidget {
  const PuzzleBoard({
    required this.model,
    required this.puzzle,
    required this.palette,
    this.tipStyle = PathTip.classic,
    super.key,
  });

  final PathTip tipStyle;
  final BoardControls model;
  final Puzzle puzzle;
  final BoardPalette palette;

  @override
  State<PuzzleBoard> createState() => _PuzzleBoardState();
}

class _PuzzleBoardState extends State<PuzzleBoard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rejection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    animationBehavior: AnimationBehavior.preserve,
  );
  RejectedMove? _rejectedMove;
  int? _attemptFrom;
  int? _attemptTarget;
  int? _rejectedCell;

  String? _attemptPath;

  void _showRejection(int cell) {
    final controls = widget.model;
    if (controls is! RejectionControls || controls.tip == null) return;
    final rejectionControls = controls as RejectionControls;
    final issue = rejectionControls.rejectionFor(cell);
    if (issue == null ||
        issue.reason == MoveRejection.adjacency ||
        cell == _rejectedCell)
      return;
    _rejectedCell = cell;
    _rejectedMove = issue;
    _attemptFrom = controls.tip;
    _attemptTarget = cell;
    _attemptPath = controls.path.join(',');
    rejectionControls.rejectHaptic();
    _rejection.forward(from: 0);
  }

  void _attempt(int cell) {
    final controls = widget.model;
    final from = controls.tip;
    _showRejection(cell);
    controls.step(cell);
    if (controls.tip != from) _clearRejection();
  }

  void _clearRejection() {
    _rejection.stop();
    _rejection.value = 0;
    _rejectedMove = null;
    _rejectedCell = null;
    _attemptPath = null;
  }

  /// Transient picture of the tip while a finger is down. Never persisted.
  final _visual = ValueNotifier<TipVisual?>(null);

  /// Set only while the tip retracts along the trail, so the board redraws
  /// the route up to the tip. Forward drags never repaint the board layer.
  final _trim = ValueNotifier<({int cell, Offset tip})?>(null);
  late TipTracker _tracker = _newTracker();

  TipTracker _newTracker() => TipTracker(
    tipRadius: tipRadiusOf(widget.tipStyle),
    checkpointLead: tipLead(widget.tipStyle),
  );
  int? _pointer;
  Offset? _previous;

  void _track(Offset position) {
    final controls = widget.model;
    final route = controls.path;
    final visual = _tracker.update(
      puzzle: widget.puzzle,
      route: route,
      pointer: position,
      acceptedFacing: tipDirection(widget.puzzle, route),
      canEnter: controls.canStep,
    );
    _visual.value = visual;
    final trim = visual.trim ? (cell: visual.cell, tip: visual.tip) : null;
    if (trim?.cell != _trim.value?.cell || trim?.tip != _trim.value?.tip) {
      _trim.value = trim;
    }
  }

  void _settle() {
    _tracker.reset();
    _visual.value = null;
    _trim.value = null;
  }

  int get _size => widget.puzzle.size;

  int? _cell(Offset point) {
    if (point.dx < 0 ||
        point.dy < 0 ||
        point.dx >= _size ||
        point.dy >= _size) {
      return null;
    }
    return point.dy.floor() * _size + point.dx.floor();
  }

  void _down(PointerDownEvent event, double side) {
    if (_pointer != null) return;
    final position = event.localPosition / side;
    final cell = _cell(position);
    if (cell == null) return;
    _rejectedCell = null;
    final controls = widget.model;
    if (!controls.path.contains(cell) &&
        controls is RejectionControls &&
        (controls as RejectionControls).rejectionFor(cell) != null) {
      _showRejection(cell);
      return;
    }
    if (!widget.model.begin(cell)) {
      _showRejection(cell);
      return;
    }
    _pointer = event.pointer;
    _rejectedCell = null;
    _previous = position;
    _track(position);
  }

  void _move(PointerMoveEvent event, double side) {
    if (_pointer != event.pointer) return;
    final target = event.localPosition / side;
    final start = _previous!;
    final delta = target - start;
    // Inspect boundary crossings in geometric order so fast drags can cross
    // multiple cells in one event without skipping cells or fabricating turns.
    if (_cell(start) != null) {
      var x = start.dx.floor();
      var y = start.dy.floor();
      final xDirection = delta.dx.sign.toInt();
      final yDirection = delta.dy.sign.toInt();
      final xStep = delta.dx == 0 ? double.infinity : 1 / delta.dx.abs();
      final yStep = delta.dy == 0 ? double.infinity : 1 / delta.dy.abs();
      var tx = delta.dx == 0
          ? double.infinity
          : ((x + (xDirection > 0 ? 1 : 0)) - start.dx) / delta.dx;
      var ty = delta.dy == 0
          ? double.infinity
          : ((y + (yDirection > 0 ? 1 : 0)) - start.dy) / delta.dy;
      final endCell = _cell(target);
      while (math.min(tx, ty) <= 1 && y * _size + x != endCell) {
        // A corner hit supplies no orthogonal direction.
        if ((tx - ty).abs() < 1e-8) break;
        final prior = y * _size + x;
        if (tx < ty) {
          x += xDirection;
          tx += xStep;
        } else {
          y += yDirection;
          ty += yStep;
        }
        if (x < 0 || y < 0 || x >= _size || y >= _size) break;
        if (prior == widget.model.tip) _attempt(y * _size + x);
      }
    }
    if (_cell(target) != _rejectedCell) _rejectedCell = null;
    _previous = target;
    _track(target);
  }

  void _up(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _previous = null;
    _settle();
    widget.model.end();
  }

  @override
  void dispose() {
    _visual.dispose();
    _trim.dispose();
    _rejection.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PuzzleBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tipStyle != widget.tipStyle) {
      _tracker = _newTracker();
      _settle();
    }
    if (oldWidget.puzzle != widget.puzzle ||
        widget.model.complete ||
        (_rejectedMove != null &&
            widget.model.path.join(',') != _attemptPath)) {
      _clearRejection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final path = model.path;
    final visited = path.toSet();
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth / _size;
        return RawGestureDetector(
          gestures: {
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                  (_) {},
                ),
          },
          child: Listener(
            key: const ValueKey('puzzle-grid'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _down(event, side),
            onPointerMove: (event) => _move(event, side),
            onPointerUp: _up,
            onPointerCancel: _up,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  key: const ValueKey('board-layer'),
                  child: CustomPaint(
                    painter: _BoardPainter(
                      puzzle: widget.puzzle,
                      palette: widget.palette,
                      tipStyle: widget.tipStyle,
                      route: path,
                      hint: model.hintCell,
                      next: model.nextCheckpoint,
                      complete: model.complete,
                      rejection: _rejection,
                      rejectedMove: () => _rejectedMove,
                      trim: _trim,
                      reducedMotion: MediaQuery.disableAnimationsOf(context),
                    ),
                  ),
                ),
                if (!model.complete)
                  RepaintBoundary(
                    key: const ValueKey('pointer-layer'),
                    child: CustomPaint(
                      painter: _TipPainter(
                        puzzle: widget.puzzle,
                        palette: widget.palette,
                        tipStyle: widget.tipStyle,
                        route: path,
                        visual: _visual,
                        rejection: _rejection,
                        reduced: MediaQuery.disableAnimationsOf(context),
                      ),
                    ),
                  ),
                RepaintBoundary(
                  key: const ValueKey('rejection-layer'),
                  child: CustomPaint(
                    painter: _RejectionPainter(
                      puzzle: widget.puzzle,
                      animation: _rejection,
                      issue: () => _rejectedMove,
                      attemptFrom: () => _attemptFrom,
                      attemptTarget: () => _attemptTarget,
                      routeColor: widget.palette.route,
                      tipColor: widget.palette.accent,
                      palette: widget.palette,
                      tipStyle: widget.tipStyle,
                      direction: tipDirection(widget.puzzle, path),
                      reducedMotion: MediaQuery.disableAnimationsOf(context),
                    ),
                  ),
                ),
                for (var cell = 0; cell < widget.puzzle.area; cell++)
                  Positioned(
                    left: (cell % _size) * side,
                    top: (cell ~/ _size) * side,
                    width: side,
                    height: side,
                    child: Semantics(
                      container: true,
                      button: true,
                      enabled:
                          !model.complete &&
                          (path.contains(cell) ||
                              model.canStep(cell) ||
                              (model is RejectionControls &&
                                  widget.puzzle.neighbors[path.last].contains(
                                    cell,
                                  ))),
                      onTap:
                          !model.complete &&
                              (path.contains(cell) ||
                                  model.canStep(cell) ||
                                  (model is RejectionControls &&
                                      widget.puzzle.neighbors[path.last]
                                          .contains(cell)))
                          ? () {
                              final rejection = model is RejectionControls
                                  ? (model as RejectionControls).rejectionFor(
                                      cell,
                                    )
                                  : null;
                              if (!path.contains(cell) && rejection != null) {
                                _rejectedCell = null;
                                _showRejection(cell);
                              } else {
                                model.tap(cell);
                              }
                            }
                          : null,
                      label: _label(cell, path, visited),
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _label(int cell, List<int> path, Set<int> visited) {
    final number = widget.puzzle.numbers[cell];
    final state = switch (cell) {
      _ when cell == widget.model.hintCell => ', hinted',
      _ when cell == path.last => ', route tip',
      _ when path.contains(cell) => ', visited',
      _ => '',
    };
    final label = number == 0 ? '' : ', checkpoint $number';
    final mechanics = _marksAt(widget.puzzle, cell, visited)
        .map(
          (mark) => switch (mark.kind) {
            _TileMark.arrow =>
              mark.direction.dx > 0
                  ? 'exit right'
                  : mark.direction.dx < 0
                  ? 'exit left'
                  : mark.direction.dy > 0
                  ? 'exit down'
                  : 'exit up',
            _TileMark.key => 'key',
            _TileMark.lockedGate => 'locked gate',
            _TileMark.openGate => 'unlocked gate',
            _TileMark.portalEntry => 'portal entry',
            _TileMark.portalExit => 'portal exit',
            _TileMark.ice => 'ice',
          },
        )
        .map((text) => ', $text')
        .join();
    return 'Row ${cell ~/ _size + 1}, column ${cell % _size + 1}$label$mechanics$state';
  }
}

enum _TileMark {
  arrow,
  key,
  lockedGate,
  openGate,
  portalEntry,
  portalExit,
  ice,
}

typedef _Mark = ({_TileMark kind, Offset direction});
_Mark _mark(_TileMark kind) => (kind: kind, direction: Offset.zero);

Offset _cellCenter(int cell, int size) =>
    Offset(cell % size + .5, cell ~/ size + .5);

Iterable<_Mark> _marksAt(Puzzle puzzle, int cell, Set<int> visited) sync* {
  if (puzzle.arrow case (final from, final to) when from == cell) {
    yield (
      kind: _TileMark.arrow,
      direction: _cellCenter(to, puzzle.size) - _cellCenter(from, puzzle.size),
    );
  }
  if (puzzle.gate case (final key, final gate)) {
    if (cell == key && !visited.contains(key)) yield _mark(_TileMark.key);
    if (cell == gate)
      yield _mark(
        visited.contains(key) ? _TileMark.openGate : _TileMark.lockedGate,
      );
  }
  if (puzzle.portal case (final entry, final exit)) {
    if (cell == entry) yield _mark(_TileMark.portalEntry);
    if (cell == exit) yield _mark(_TileMark.portalExit);
  }
  if (puzzle.iceTiles.contains(cell)) yield _mark(_TileMark.ice);
}

void _paintTile(
  Canvas canvas,
  Offset center,
  BoardPalette palette,
  List<_Mark> marks, {
  bool visited = false,
  bool checkpoint = false,
  double rejectionTint = 0,
}) {
  final base = Color.lerp(
    visited ? palette.covered : palette.tile,
    palette.rejection,
    rejectionTint * .48,
  )!;
  final dark = marks.isNotEmpty && base.computeLuminance() < .25;
  Color hue(_TileMark kind) => switch (kind) {
    _TileMark.key || _TileMark.lockedGate || _TileMark.openGate =>
      dark ? const Color(0xffffcb66) : const Color(0xffaa6811),
    _TileMark.portalEntry || _TileMark.portalExit =>
      dark ? const Color(0xff70e3d5) : const Color(0xff087b78),
    _TileMark.ice => dark ? const Color(0xff93d4ff) : const Color(0xff2469a5),
    _TileMark.arrow => palette.ink,
  };
  final tile = RRect.fromRectAndRadius(
    Rect.fromCenter(center: center, width: .94, height: .94),
    const Radius.circular(.17),
  );
  canvas.save();
  canvas.clipRRect(tile);
  canvas.drawRect(tile.outerRect, Paint()..color = base);
  for (final (index, mark) in marks.indexed) {
    final color = hue(mark.kind);
    final single = marks.length == 1;
    final horizontal = marks.length == 2;
    final offset = single
        ? Offset.zero
        : horizontal
        ? Offset(index == 0 ? -.215 : .215, 0)
        : Offset(index.isEven ? -.215 : .215, index < 2 ? -.215 : .215);
    final area = single
        ? tile.outerRect
        : Rect.fromCenter(
            center: center + offset,
            width: horizontal ? .43 : .41,
            height: horizontal ? .90 : .41,
          );
    canvas.drawRRect(
      RRect.fromRectAndRadius(area, const Radius.circular(.12)),
      Paint()..color = color.withValues(alpha: .075),
    );
    canvas.save();
    final direction = mark.direction;
    final motifOffset = switch (mark.kind) {
      _TileMark.arrow when single && checkpoint =>
        Offset(direction.dy, -direction.dx) * .32,
      _TileMark.arrow when visited => Offset(-direction.dy, direction.dx) * .19,
      _TileMark.key when single && checkpoint => const Offset(0, -.32),
      _ => Offset.zero,
    };
    final origin = center + offset + motifOffset;
    canvas.translate(origin.dx, origin.dy);
    if (!single) {
      canvas.scale(.47);
    } else if (checkpoint &&
        (mark.kind == _TileMark.key || mark.kind == _TileMark.arrow)) {
      canvas.scale(.57);
    } else {
      canvas.scale(.82);
    }
    final ink = Paint()
      ..color = color.withValues(
        alpha: mark.kind == _TileMark.arrow ? .28 : .53,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = .037
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (mark.kind) {
      case _TileMark.arrow:
        final d = mark.direction;
        final cross = Offset(-d.dy, d.dx);
        canvas.drawPath(
          Path()
            ..moveTo((-d * .30).dx, (-d * .30).dy)
            ..lineTo((d * .28).dx, (d * .28).dy)
            ..moveTo((d * .08 + cross * .17).dx, (d * .08 + cross * .17).dy)
            ..lineTo((d * .28).dx, (d * .28).dy)
            ..lineTo((d * .08 - cross * .17).dx, (d * .08 - cross * .17).dy),
          ink..strokeWidth = .072,
        );
      case _TileMark.key:
        canvas.rotate(-math.pi / 4);
        canvas.drawCircle(const Offset(-.18, 0), .12, ink);
        canvas.drawLine(const Offset(-.06, 0), const Offset(.30, 0), ink);
        for (final x in [.16, .27]) {
          canvas.drawLine(Offset(x, 0), Offset(x, .105), ink);
        }
      case _TileMark.lockedGate:
      case _TileMark.openGate:
        final open = mark.kind == _TileMark.openGate;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(-.35, -.025, .35, .35),
            const Radius.circular(.06),
          ),
          ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(-.29, -.03)
            ..lineTo(-.29, -.13)
            ..cubicTo(-.29, -.45, .29, -.45, .29, -.13)
            ..lineTo(.29, open ? -.15 : -.03),
          ink,
        );
        canvas.drawCircle(const Offset(0, .115), .026, ink);
      case _TileMark.portalEntry:
      case _TileMark.portalExit:
        final portal = Rect.fromCircle(center: Offset.zero, radius: .34);
        canvas.drawArc(portal, .16, math.pi - .32, false, ink);
        canvas.drawArc(portal, math.pi + .16, math.pi - .32, false, ink);
        final entry = mark.kind == _TileMark.portalEntry;
        final diamond = Path()
          ..moveTo(0, -.14)
          ..lineTo(.14, 0)
          ..lineTo(0, .14)
          ..lineTo(-.14, 0)
          ..close();
        canvas.drawPath(
          diamond,
          ink..style = entry ? PaintingStyle.fill : PaintingStyle.stroke,
        );
      case _TileMark.ice:
        for (var ray = 0; ray < 6; ray++) {
          canvas.save();
          canvas.rotate(ray * math.pi / 3);
          canvas.drawLine(Offset.zero, const Offset(0, -.34), ink);
          canvas.drawLine(const Offset(0, -.21), const Offset(-.09, -.28), ink);
          canvas.drawLine(const Offset(0, -.21), const Offset(.09, -.28), ink);
          canvas.restore();
        }
    }
    canvas.restore();
  }
  canvas.restore();
}

void _paintWall(
  Canvas canvas,
  Offset a,
  Offset b,
  BoardPalette palette, {
  bool continuous = false,
}) {
  final delta = b - a;
  final midpoint = (a + b) / 2;
  final ends = Offset(-delta.dy, delta.dx) * (continuous ? .50 : .44);
  canvas.drawLine(
    midpoint - ends,
    midpoint + ends,
    Paint()
      ..color = palette.ink
      ..strokeWidth = .075
      ..strokeCap = StrokeCap.round,
  );
}

class BoardRulesButton extends StatelessWidget {
  const BoardRulesButton({
    super.key,
    required this.puzzle,
    required this.palette,
  });
  final Puzzle puzzle;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final rules = [
      if (puzzle.walls.isNotEmpty)
        (
          'Walls',
          'A thick line blocks the shared edge.',
          const <List<_Mark>>[],
        ),
      if (puzzle.arrow case (final from, final to))
        (
          'Directional tile',
          'Leave this tile in the direction of the arrow.',
          [
            [
              (
                kind: _TileMark.arrow,
                direction:
                    _cellCenter(to, puzzle.size) -
                    _cellCenter(from, puzzle.size),
              ),
            ],
          ],
        ),
      if (puzzle.gate != null)
        (
          'Keys and gates',
          'Collect the gold key to open the matching lock.',
          [
            [_mark(_TileMark.key)],
            [_mark(_TileMark.lockedGate)],
            [_mark(_TileMark.openGate)],
          ],
        ),
      if (puzzle.portal != null)
        (
          'Portals',
          'Enter the solid diamond to jump to the matching open diamond.',
          [
            [_mark(_TileMark.portalEntry)],
            [_mark(_TileMark.portalExit)],
          ],
        ),
      if (puzzle.iceTiles.isNotEmpty)
        (
          'Ice',
          'Slide straight through the ice until you reach a regular tile.',
          [
            [_mark(_TileMark.ice)],
          ],
        ),
    ];
    if (rules.isEmpty) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Board rules'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (title, description, marks) in rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: (marks.isEmpty ? 2 : marks.length) * 36,
                        height: 36,
                        child: CustomPaint(
                          key: ValueKey('rule-sample-$title'),
                          painter: _RuleSample(palette, marks),
                        ),
                      ),
                      Text(title, style: Theme.of(dialog).textTheme.titleSmall),
                      Text(description),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
      icon: const Icon(Icons.help_outline_rounded, size: 18),
      label: const Text('Board rules'),
    );
  }
}

class _RuleSample extends CustomPainter {
  const _RuleSample(this.palette, this.marks);
  final BoardPalette palette;
  final List<List<_Mark>> marks;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.height);
    if (marks.isEmpty) {
      const a = Offset(.5, .5);
      const b = Offset(1.5, .5);
      _paintTile(canvas, a, palette, const []);
      _paintTile(canvas, b, palette, const []);
      _paintWall(canvas, a, b, palette);
    } else {
      for (final (index, tile) in marks.indexed) {
        _paintTile(canvas, Offset(index + .5, .5), palette, tile);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RuleSample oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.marks != marks;
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.puzzle,
    required this.palette,
    required this.route,
    required this.hint,
    required this.next,
    required this.complete,
    this.tipStyle = PathTip.classic,
    this.directionOverride,
    this.rejection,
    this.rejectedMove,
    this.trim,
    this.showTip = false,
    this.reducedMotion = false,
  }) : visited = route.toSet(),
       super(
         repaint: Listenable.merge([
           if (rejection != null) rejection,
           if (trim != null) trim,
         ]),
       );

  /// Present only while the tip retracts along the trail.
  final ValueNotifier<({int cell, Offset tip})?>? trim;

  /// The static preview paints its own tip. Live boards use the tip layer.
  final bool showTip;

  final Puzzle puzzle;
  final BoardPalette palette;
  final PathTip tipStyle;
  final int? directionOverride;
  final List<int> route;
  final int? hint;
  final int next;
  final Set<int> visited;
  final bool complete;
  final AnimationController? rejection;
  final RejectedMove? Function()? rejectedMove;
  final bool reducedMotion;

  Offset _center(int cell) =>
      Offset(cell % puzzle.size + .5, cell ~/ puzzle.size + .5);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width / puzzle.size;
    canvas.save();
    canvas.scale(side);
    final fill = Paint();
    final move = rejection?.isAnimating == true ? rejectedMove?.call() : null;
    final progress = rejection?.value ?? 0;
    final pulse = (1 - progress).clamp(0.0, 1.0);
    final target = move == null || move.reason == MoveRejection.wall
        ? null
        : (move.reason == MoveRejection.arrow ||
                  move.reason == MoveRejection.ice ||
                  (move.reason == MoveRejection.portal &&
                      puzzle.portal?.$1 == move.from)
              ? move.from
              : move.target);
    final shake = reducedMotion
        ? 0.0
        : math.sin(progress * math.pi * 6) * (1 - progress) * 4 / side;
    for (var cell = 0; cell < puzzle.area; cell++) {
      final tile = RRect.fromRectAndRadius(
        Rect.fromCenter(center: _center(cell), width: .94, height: .94),
        const Radius.circular(.17),
      );
      canvas.save();
      if (cell == target) canvas.translate(shake, 0);
      _paintTile(
        canvas,
        _center(cell),
        palette,
        _marksAt(puzzle, cell, visited).toList(),
        visited: visited.contains(cell),
        checkpoint: puzzle.numbers[cell] != 0,
        rejectionTint: cell == target ? pulse : 0,
      );
      if (cell == target) {
        canvas.drawRRect(
          tile.deflate(.025),
          Paint()
            ..color = palette.ink.withValues(alpha: pulse)
            ..strokeWidth = .045
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.restore();
      if (!complete && route.last == puzzle.finish && !visited.contains(cell)) {
        canvas.drawRRect(
          tile.deflate(.045),
          Paint()
            ..color = palette.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = .065,
        );
      }
    }

    for (final (from, to) in puzzle.walls) {
      _paintWall(
        canvas,
        _center(from),
        _center(to),
        palette,
        continuous: puzzle.walls.length > 1,
      );
      if (move != null &&
          move.reason == MoveRejection.wall &&
          ((move.from == from && move.target == to) ||
              (move.from == to && move.target == from))) {
        final a = _center(from), b = _center(to);
        final delta = b - a, midpoint = (a + b) / 2;
        final ends = Offset(-delta.dy, delta.dx) * .44;
        canvas.drawLine(
          midpoint - ends,
          midpoint + ends,
          Paint()
            ..color = palette.rejection.withValues(alpha: pulse)
            ..strokeWidth = .095
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    final first = _center(route.first);
    final trimmed = trim?.value;
    final stroke = Path()..moveTo(first.dx, first.dy);
    for (final cell in route.skip(1)) {
      final point =
          trimmed != null && cell == route.last && trimmed.cell == cell
          ? trimmed.tip
          : _center(cell);
      if (puzzle.portal?.$2 == cell) {
        stroke.moveTo(point.dx, point.dy);
      } else {
        stroke.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      stroke,
      Paint()
        ..color = palette.route
        ..strokeWidth = .25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    if (hint case final cell?) {
      final point = _center(cell);
      final ring = Paint()
        ..color = palette.route
        ..style = PaintingStyle.stroke
        ..strokeWidth = .036;
      canvas.drawCircle(point, .34, ring);
    }
    for (final (index, cell) in puzzle.checkpoints.indexed) {
      final number = index + 1;
      final isVisited = visited.contains(cell);
      final position = _center(cell) + Offset(cell == target ? shake : 0, 0);
      final highlighted = cell == hint || (!complete && cell == route.last);
      final pending = number == next && !highlighted;
      fill.color = highlighted
          ? palette.accent
          : (isVisited ? palette.route : palette.surface);
      canvas.drawCircle(position, .275, fill);
      if (pending) {
        canvas.drawCircle(
          position,
          .274,
          Paint()
            ..color = palette.route
            ..strokeWidth = .034
            ..style = PaintingStyle.stroke,
        );
      }
      final text = TextPainter(
        text: TextSpan(
          text: '$number',
          style: TextStyle(
            fontFamily: 'Bricolage',
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: highlighted
                ? palette.onAccent
                : (isVisited ? palette.onRoute : palette.ink),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.scale(.01);
      text.paint(canvas, -Offset(text.width / 2, text.height / 2));
      canvas.restore();
      text.dispose();
    }
    if (showTip && !complete) {
      paintTip(
        canvas,
        puzzle,
        palette,
        tipStyle,
        TipTracker.rest(
          puzzle,
          route,
          directionOverride ?? tipDirection(puzzle, route),
          checkpointLead: tipLead(tipStyle),
        ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.puzzle != puzzle ||
      oldDelegate.palette != palette ||
      oldDelegate.tipStyle != tipStyle ||
      oldDelegate.directionOverride != directionOverride ||
      oldDelegate.showTip != showTip ||
      oldDelegate.trim != trim ||
      oldDelegate.next != next ||
      oldDelegate.hint != hint ||
      oldDelegate.complete != complete ||
      oldDelegate.reducedMotion != reducedMotion ||
      oldDelegate.rejection != rejection ||
      !identical(oldDelegate.route, route);
}

/// How far ahead of a checkpoint centre a cosmetic tip rests. Classic keeps
/// its highlighted-disc treatment and needs no lead.
double tipLead(PathTip style) => style == PathTip.classic ? 0 : .42;

/// Tip radius in cells. One size on every cell; checkpoints do not shrink it.
double tipRadiusOf(PathTip style) => style == PathTip.classic ? .1685 : .22;

/// Paints the leading segment and the tip in board units. The canvas is
/// already scaled so one unit is one cell.
void paintTip(
  Canvas canvas,
  Puzzle puzzle,
  BoardPalette palette,
  PathTip style,
  TipVisual v,
) {
  final checkpoint = puzzle.numbers[v.cell] != 0;
  final classic = style == PathTip.classic;
  // Classic on a checkpoint is the highlighted disc itself.
  if (classic && checkpoint && v.extension <= .275) return;
  if (v.extension > 0 && !v.trim) {
    final dir = v.tip - v.center;
    final unit = dir / dir.distance;
    // On a checkpoint start at the rim so the number is never covered.
    final start = checkpoint ? v.center + unit * .275 : v.center;
    canvas.drawLine(
      start,
      v.tip,
      Paint()
        ..color = palette.route
        ..strokeWidth = .25
        ..strokeCap = checkpoint ? StrokeCap.butt : StrokeCap.round,
    );
  }
  paintPathTip(
    canvas,
    v.tip,
    tipRadiusOf(style),
    style,
    palette,
    quarterTurns: v.facing,
  );
}

/// The tip and its leading segment. Pointer motion repaints only this layer.
class _TipPainter extends CustomPainter {
  _TipPainter({
    required this.puzzle,
    required this.palette,
    required this.tipStyle,
    required this.route,
    required this.visual,
    required this.rejection,
    required this.reduced,
  }) : super(repaint: Listenable.merge([visual, rejection]));

  final Puzzle puzzle;
  final BoardPalette palette;
  final PathTip tipStyle;
  final List<int> route;
  final ValueNotifier<TipVisual?> visual;
  final AnimationController rejection;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    // The rejection layer draws the tip while its temporary segment plays.
    if (rejection.isAnimating && !reduced) return;
    final v =
        visual.value ??
        TipTracker.rest(
          puzzle,
          route,
          tipDirection(puzzle, route),
          checkpointLead: tipLead(tipStyle),
        );
    canvas.save();
    canvas.scale(size.width / puzzle.size);
    paintTip(canvas, puzzle, palette, tipStyle, v);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TipPainter old) =>
      old.puzzle != puzzle ||
      old.palette != palette ||
      old.tipStyle != tipStyle ||
      old.reduced != reduced ||
      !listEquals(old.route, route);
}

/// Paints transient feedback above the board without changing hit testing or
/// the authoritative route. The notifier repaints only this overlay.
class _RejectionPainter extends CustomPainter {
  _RejectionPainter({
    required this.puzzle,
    required this.animation,
    required this.issue,
    required this.attemptFrom,
    required this.attemptTarget,
    required this.routeColor,
    required this.tipColor,
    required this.palette,
    required this.tipStyle,
    required this.direction,
    required this.reducedMotion,
  }) : super(repaint: animation);
  final Puzzle puzzle;
  final AnimationController animation;
  final RejectedMove? Function() issue;
  final int? Function() attemptFrom, attemptTarget;
  final Color routeColor, tipColor;
  final BoardPalette palette;
  final PathTip tipStyle;
  final int direction;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final move = issue();
    final origin = attemptFrom(), destination = attemptTarget();
    if (move == null ||
        origin == null ||
        destination == null ||
        !animation.isAnimating ||
        reducedMotion)
      return;
    final side = size.width / puzzle.size;
    Offset center(int cell) => Offset(
      (cell % puzzle.size + .5) * side,
      (cell ~/ puzzle.size + .5) * side,
    );
    final from = center(origin), to = center(destination);
    final t = animation.value;
    final segment = t < .16
        ? Curves.easeOut.transform(t / .16)
        : t < .42
        ? 1 - Curves.easeIn.transform((t - .16) / .26)
        : 0.0;
    // Stop the round cap at a wall; leave checkpoint numbers unobscured.
    final distance = move.reason == MoveRejection.wall && move.from == origin
        ? .34
        : puzzle.numbers[destination] != 0
        ? .72
        : 1.0;
    final checkpoint = puzzle.numbers[origin] != 0;
    final end = segment * distance;
    final classic = tipStyle == PathTip.classic;
    final lead = tipLead(tipStyle);
    // Face the attempted neighbour, not the accepted heading.
    final stepX = destination % puzzle.size - origin % puzzle.size;
    final stepY = destination ~/ puzzle.size - origin ~/ puzzle.size;
    final attempted = stepX == 1 && stepY == 0
        ? 0
        : stepX == 0 && stepY == 1
        ? 1
        : stepX == -1 && stepY == 0
        ? 2
        : stepX == 0 && stepY == -1
        ? 3
        : direction;
    final travel = checkpoint ? math.max(end, lead) : end;
    final endPoint = Offset.lerp(from, to, travel)!;
    final rim = checkpoint ? .275 : 0.0;
    if (travel > rim && !(classic && checkpoint && end <= .275)) {
      canvas.drawLine(
        Offset.lerp(from, to, rim)!,
        endPoint,
        Paint()
          ..color = routeColor
          ..strokeWidth = side * .25
          ..strokeCap = checkpoint ? StrokeCap.butt : StrokeCap.round,
      );
    }
    if (classic && checkpoint && end <= .275) return;
    canvas.save();
    canvas.scale(side);
    paintPathTip(
      canvas,
      endPoint / side,
      tipRadiusOf(tipStyle),
      tipStyle,
      palette,
      quarterTurns: attempted,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RejectionPainter oldDelegate) =>
      oldDelegate.puzzle != puzzle ||
      oldDelegate.routeColor != routeColor ||
      oldDelegate.tipColor != tipColor ||
      oldDelegate.tipStyle != tipStyle ||
      oldDelegate.direction != direction ||
      oldDelegate.palette != palette ||
      oldDelegate.reducedMotion != reducedMotion;
}
