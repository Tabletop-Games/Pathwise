import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/puzzle.dart';
import '../../model/app_model.dart';
import '../../model/app_themes.dart';

class PuzzleBoard extends StatefulWidget {
  const PuzzleBoard({
    required this.model,
    required this.puzzle,
    required this.palette,
    super.key,
  });

  final AppModel model;
  final Puzzle puzzle;
  final BoardPalette palette;

  @override
  State<PuzzleBoard> createState() => _PuzzleBoardState();
}

class _PuzzleBoardState extends State<PuzzleBoard> {
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
    if (cell == null || !widget.model.begin(cell)) return;
    _pointer = event.pointer;
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
        if (prior == widget.model.tip) widget.model.step(y * _size + x);
      }
    }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final path = model.path;
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
                  child: CustomPaint(
                    painter: _BoardPainter(
                      puzzle: widget.puzzle,
                      palette: widget.palette,
                      route: path,
                      hint: model.hintCell,
                      next: model.nextCheckpoint,
                      complete: model.complete,
                    ),
                  ),
                ),
                if (!model.complete)
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _PointerPainter(
                        puzzle: widget.puzzle,
                        color: widget.palette.route,
                        validCells: widget.puzzle.neighbors[path.last]
                            .where(model.canStep)
                            .toSet(),
                        tip: path.last,
                        pointer: _pointerPosition,
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
                          (path.contains(cell) || model.canStep(cell)),
                      onTap:
                          !model.complete &&
                              (path.contains(cell) || model.canStep(cell))
                          ? () => model.tap(cell)
                          : null,
                      label: _label(cell, path),
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

  String _label(int cell, List<int> path) {
    final number = widget.puzzle.numbers[cell];
    final state = switch (cell) {
      _ when cell == widget.model.hintCell => ', hinted',
      _ when cell == path.last => ', route tip',
      _ when path.contains(cell) => ', visited',
      _ => '',
    };
    final label = number == 0 ? '' : ', checkpoint $number';
    return 'Row ${cell ~/ _size + 1}, column ${cell % _size + 1}$label$state';
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.puzzle,
    required this.palette,
    required this.route,
    required this.hint,
    required this.next,
    required this.complete,
  }) : visited = route.toSet();

  final Puzzle puzzle;
  final BoardPalette palette;
  final List<int> route;
  final int? hint;
  final int next;
  final Set<int> visited;
  final bool complete;

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
    for (var cell = 0; cell < puzzle.area; cell++) {
      final tile = RRect.fromRectAndRadius(
        Rect.fromCenter(center: _center(cell), width: .94, height: .94),
        const Radius.circular(.17),
      );
      fill.color = visited.contains(cell) ? palette.covered : palette.tile;
      canvas.drawRRect(tile, fill);
    }

    final first = _center(route.first);
    final tip = _center(route.last);
    final stroke = Path()..moveTo(first.dx, first.dy);
    for (final cell in route.skip(1)) {
      final point = _center(cell);
      stroke.lineTo(point.dx, point.dy);
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
      final distance = point - tip;
      final ring = Paint()
        ..color = palette.route
        ..style = PaintingStyle.stroke
        ..strokeWidth = .036;
      canvas.drawCircle(point, .34, ring);
      for (final fraction in [.28, .43, .58]) {
        canvas.drawCircle(tip + distance * fraction, .038, ink);
      }
    }
    for (final (index, cell) in puzzle.checkpoints.indexed) {
      final number = index + 1;
      final isVisited = visited.contains(cell);
      final position = _center(cell);
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
      !identical(oldDelegate.route, route);
}

/// Pointer motion between accepted cells only repaints this light overlay.
class _PointerPainter extends CustomPainter {
  _PointerPainter({
    required this.puzzle,
    required this.color,
    required this.validCells,
    required this.tip,
    required this.pointer,
  }) : super(repaint: pointer);

  final Puzzle puzzle;
  final Color color;
  final Set<int> validCells;
  final int tip;
  final ValueNotifier<Offset?> pointer;

  @override
  void paint(Canvas canvas, Size size) {
    final position = pointer.value;
    if (position == null) return;
    final center = Offset(tip % puzzle.size + .5, tip ~/ puzzle.size + .5);
    final delta = position - center;
    if (delta.distance > .85) return;
    final extension = delta.dx.abs() > delta.dy.abs()
        ? Offset(delta.dx.clamp(-.49, .49), 0)
        : Offset(0, delta.dy.clamp(-.49, .49));
    final neighbor =
        tip +
        (extension.dx != 0
            ? extension.dx.sign.toInt()
            : extension.dy.sign.toInt() * puzzle.size);
    final radius = puzzle.numbers[tip] == 0 ? .16 : .275;
    if (!validCells.contains(neighbor) || extension.distance <= radius) return;
    final start = center + extension * (radius / extension.distance);
    final side = size.width / puzzle.size;
    canvas.drawLine(
      start * side,
      (center + extension) * side,
      Paint()
        ..color = color.withValues(alpha: .65)
        ..strokeWidth = .17 * side
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) =>
      oldDelegate.puzzle != puzzle ||
      oldDelegate.color != color ||
      oldDelegate.tip != tip ||
      !setEquals(oldDelegate.validCells, validCells);
}
