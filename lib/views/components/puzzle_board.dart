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
  if (cell == puzzle.ice) yield _mark(_TileMark.ice);
}

void _paintTile(
  Canvas canvas,
  Offset center,
  BoardPalette palette,
  List<_Mark> marks, {
  bool visited = false,
}) {
  final base = visited ? palette.covered : palette.tile;
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
      Paint()..color = color.withValues(alpha: .15),
    );
    canvas.save();
    final arrowOffset = visited && mark.kind == _TileMark.arrow
        ? Offset(-mark.direction.dy, mark.direction.dx) * .19
        : Offset.zero;
    final origin = center + offset + arrowOffset;
    canvas.translate(origin.dx, origin.dy);
    if (!single) canvas.scale(.54);
    final ink = Paint()
      ..color = color.withValues(
        alpha: mark.kind == _TileMark.arrow ? .43 : .76,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = .051
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
          ink..strokeWidth = .10,
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
        canvas.drawCircle(Offset.zero, .355, ink);
        canvas.drawCircle(Offset.zero, .235, ink);
        if (mark.kind == _TileMark.portalEntry) {
          final dot = ink..style = PaintingStyle.fill;
          canvas.drawCircle(Offset.zero, .055, dot);
          canvas.drawCircle(const Offset(0, -.355), .056, dot);
        }
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

void _paintWall(Canvas canvas, Offset a, Offset b, BoardPalette palette) {
  final delta = b - a;
  final midpoint = (a + b) / 2;
  final ends = Offset(-delta.dy, delta.dx) * .44;
  canvas.drawLine(
    midpoint - ends,
    midpoint + ends,
    Paint()
      ..color = palette.ink
      ..strokeWidth = .10
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
      if (puzzle.wall != null)
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
          'Enter the dotted ring to jump to its partner.',
          [
            [_mark(_TileMark.portalEntry)],
            [_mark(_TileMark.portalExit)],
          ],
        ),
      if (puzzle.ice != null)
        (
          'Ice',
          'Slide one more tile in the direction you entered.',
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
      _paintTile(
        canvas,
        _center(cell),
        palette,
        _marksAt(puzzle, cell, visited).toList(),
        visited: visited.contains(cell),
      );
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

    if (puzzle.wall case (final from, final to)) {
      _paintWall(canvas, _center(from), _center(to), palette);
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
