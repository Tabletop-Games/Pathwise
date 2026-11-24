import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/game_controller.dart';
import '../../logic/puzzle.dart';
import '../../logic/puzzle_generator.dart';
import '../../model/app_themes.dart';
import '../../model/game_state.dart';

class LevelOneBoardPreview extends StatelessWidget {
  const LevelOneBoardPreview({required this.palette, super.key});

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
    super.key,
  });

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

  final _pointerPosition = ValueNotifier<Offset?>(null);
  int? _pointer;
  Offset? _previous;

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
    _pointerPosition.value = position;
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
    _pointerPosition.value = target;
  }

  void _up(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _previous = null;
    _pointerPosition.value = null;
    widget.model.end();
  }

  @override
  void dispose() {
    _pointerPosition.dispose();
    _rejection.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PuzzleBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
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
                      route: path,
                      hint: model.hintCell,
                      next: model.nextCheckpoint,
                      complete: model.complete,
                      rejection: _rejection,
                      rejectedMove: () => _rejectedMove,
                      reducedMotion: MediaQuery.disableAnimationsOf(context),
                    ),
                  ),
                ),
                if (!model.complete)
                  RepaintBoundary(
                    key: const ValueKey('pointer-layer'),
                    child: CustomPaint(
                      painter: _PointerPainter(
                        puzzle: widget.puzzle,
                        color: widget.palette.route,
                        tipColor: widget.palette.accent,
                        rejection: _rejection,
                        validCells: widget.puzzle.neighbors[path.last]
                            .where(model.canStep)
                            .toSet(),
                        tip: path.last,
                        pointer: _pointerPosition,
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
    this.rejection,
    this.rejectedMove,
    this.reducedMotion = false,
  }) : visited = route.toSet(),
       super(repaint: rejection);

  final Puzzle puzzle;
  final BoardPalette palette;
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
    final ink = Paint()..color = palette.route;
    final accent = Paint()..color = palette.accent;
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
    final tip = _center(route.last);
    final stroke = Path()..moveTo(first.dx, first.dy);
    for (final cell in route.skip(1)) {
      final point = _center(cell);
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
    if (puzzle.numbers[route.last] == 0) {
      canvas.drawCircle(tip, .16, ink);
      canvas.drawCircle(tip, .095, accent);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.puzzle != puzzle ||
      oldDelegate.palette != palette ||
      oldDelegate.next != next ||
      oldDelegate.hint != hint ||
      oldDelegate.complete != complete ||
      oldDelegate.reducedMotion != reducedMotion ||
      oldDelegate.rejection != rejection ||
      !identical(oldDelegate.route, route);
}

/// Pointer motion between accepted cells only repaints this light overlay.
class _PointerPainter extends CustomPainter {
  _PointerPainter({
    required this.puzzle,
    required this.color,
    required this.tipColor,
    required this.validCells,
    required this.tip,
    required this.pointer,
    required this.rejection,
  }) : super(repaint: Listenable.merge([pointer, rejection]));

  final Puzzle puzzle;
  final Color color, tipColor;
  final Set<int> validCells;
  final int tip;
  final ValueNotifier<Offset?> pointer;
  final AnimationController rejection;

  @override
  void paint(Canvas canvas, Size size) {
    final position = pointer.value;
    if (position == null || rejection.isAnimating) return;
    final center = Offset(tip % puzzle.size + .5, tip ~/ puzzle.size + .5);
    final delta = position - center;
    if (delta.distance > .85) return;
    final sameCell =
        position.dx.floor() == tip % puzzle.size &&
        position.dy.floor() == tip ~/ puzzle.size;
    Offset extension;
    if (sameCell) {
      extension = Offset(delta.dx.clamp(-.49, .49), delta.dy.clamp(-.49, .49));
      bool wallBetween(int neighbor) =>
          puzzle.neighbors[tip].contains(neighbor) &&
          (puzzle.walls.contains((tip, neighbor)) ||
              puzzle.walls.contains((neighbor, tip)));
      // The marker can approach a wall, but its radius must not cross it.
      if (extension.dx > 0 && wallBetween(tip + 1)) {
        extension = Offset(extension.dx.clamp(0.0, .34), extension.dy);
      } else if (extension.dx < 0 && wallBetween(tip - 1)) {
        extension = Offset(extension.dx.clamp(-.34, 0.0), extension.dy);
      }
      if (extension.dy > 0 && wallBetween(tip + puzzle.size)) {
        extension = Offset(extension.dx, extension.dy.clamp(0.0, .34));
      } else if (extension.dy < 0 && wallBetween(tip - puzzle.size)) {
        extension = Offset(extension.dx, extension.dy.clamp(-.34, 0.0));
      }
    } else {
      extension = delta.dx.abs() > delta.dy.abs()
          ? Offset(delta.dx.clamp(-.49, .49), 0)
          : Offset(0, delta.dy.clamp(-.49, .49));
      final neighbor =
          tip +
          (extension.dx != 0
              ? extension.dx.sign.toInt()
              : extension.dy.sign.toInt() * puzzle.size);
      if (!validCells.contains(neighbor)) return;
    }
    final checkpoint = puzzle.numbers[tip] != 0;
    if (checkpoint && extension.distance <= .275) return;
    final side = size.width / puzzle.size;
    final start = center * side;
    final end = (center + extension) * side;
    if (!checkpoint) {
      // Cover the stationary marker without changing the stored route.
      canvas.drawCircle(start, .16 * side, Paint()..color = color);
    }
    final lineStart = checkpoint
        ? (center + extension * (.275 / extension.distance)) * side
        : start;
    canvas.drawLine(
      lineStart,
      end,
      Paint()
        ..color = color
        ..strokeWidth = .25 * side
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(end, .16 * side, Paint()..color = color);
    canvas.drawCircle(end, .095 * side, Paint()..color = tipColor);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) =>
      oldDelegate.puzzle != puzzle ||
      oldDelegate.color != color ||
      oldDelegate.tipColor != tipColor ||
      oldDelegate.rejection != rejection ||
      oldDelegate.tip != tip ||
      !setEquals(oldDelegate.validCells, validCells);
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
    required this.reducedMotion,
  }) : super(repaint: animation);
  final Puzzle puzzle;
  final AnimationController animation;
  final RejectedMove? Function() issue;
  final int? Function() attemptFrom, attemptTarget;
  final Color routeColor, tipColor;
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
    if (checkpoint && end <= .275) return;
    if (!checkpoint) {
      canvas.drawCircle(from, side * .16, Paint()..color = routeColor);
    }
    final endPoint = Offset.lerp(from, to, end)!;
    canvas.drawLine(
      checkpoint ? Offset.lerp(from, to, .275)! : from,
      endPoint,
      Paint()
        ..color = routeColor
        ..strokeWidth = side * .25
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(endPoint, side * .16, Paint()..color = routeColor);
    canvas.drawCircle(endPoint, side * .095, Paint()..color = tipColor);
  }

  @override
  bool shouldRepaint(_RejectionPainter oldDelegate) =>
      oldDelegate.puzzle != puzzle ||
      oldDelegate.routeColor != routeColor ||
      oldDelegate.tipColor != tipColor ||
      oldDelegate.reducedMotion != reducedMotion;
}
