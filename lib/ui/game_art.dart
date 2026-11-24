import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../model/app_themes.dart';

/// Colour helpers shared by all original artwork. Every colour is derived from
/// the equipped palette so illustrations belong to the active theme.
extension ArtColors on BoardPalette {
  /// Warm metal used for coins, derived from the theme accent.
  Color get metal => accent;
  Color get metalDark => Color.lerp(accent, ink, dark ? .20 : .42)!;
  Color get metalLight => Color.lerp(accent, dark ? ink : onRoute, .55)!;

  /// Outline that is always legible against [fill].
  Color outlineFor(Color fill) {
    final hsl = HSLColor.fromColor(fill);
    final target = hsl.lightness > .5
        ? hsl.withLightness((hsl.lightness - .42).clamp(.08, 1)).toColor()
        : hsl.withLightness((hsl.lightness + .42).clamp(0, .92)).toColor();
    return Color.lerp(fill, target, .88)!;
  }
}

/// The kinds of artwork [GameArt] can paint.
enum ArtKind {
  coin,
  coinStack1,
  coinStack2,
  coinStack3,
  coinStack4,
  coinStack5,
  gift,
  crate,
  store,
  noAds,
  brush,
  crown,
  bolt,
  hint,
  flame,
  freeze,
  trophy,
  lock,
  check,
  video,
  research,
  wheel,
  timer,
  levels,
  calendar,
}

/// A square illustration. Painted in a unit box so it scales cleanly.
class GameArt extends StatelessWidget {
  const GameArt(
    this.kind, {
    required this.palette,
    this.size = 40,
    this.semanticLabel,
    super.key,
  });

  final ArtKind kind;
  final BoardPalette palette;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final art = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ArtPainter(kind, palette)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: art);
    return Semantics(image: true, label: semanticLabel, child: art);
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.kind, this.palette);
  final ArtKind kind;
  final BoardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide / 2);
    paintArt(canvas, kind, palette);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.kind != kind || old.palette != palette;
}

/// Paints [kind] in a [-1, 1] box centred on the origin.
void paintArt(Canvas canvas, ArtKind kind, BoardPalette p) {
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .09
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  switch (kind) {
    case ArtKind.coin:
      _coin(canvas, p, Offset.zero, .82);
    case ArtKind.coinStack1:
      _stack(canvas, p, 1);
    case ArtKind.coinStack2:
      _stack(canvas, p, 2);
    case ArtKind.coinStack3:
      _stack(canvas, p, 3);
    case ArtKind.coinStack4:
      _stack(canvas, p, 4);
    case ArtKind.coinStack5:
      _stack(canvas, p, 5);
    case ArtKind.gift:
      _gift(canvas, p, line);
    case ArtKind.crate:
      _crate(canvas, p, line);
    case ArtKind.store:
      _store(canvas, p, line);
    case ArtKind.noAds:
      _shield(canvas, p, line);
    case ArtKind.brush:
      _brush(canvas, p, line);
    case ArtKind.crown:
      _crown(canvas, p, line);
    case ArtKind.bolt:
      _bolt(canvas, p, line);
    case ArtKind.hint:
      _hint(canvas, p, line);
    case ArtKind.flame:
      _flame(canvas, p, line);
    case ArtKind.freeze:
      _freeze(canvas, p, line);
    case ArtKind.trophy:
      _trophy(canvas, p, line);
    case ArtKind.lock:
      _lock(canvas, p, line);
    case ArtKind.check:
      _check(canvas, p, line);
    case ArtKind.video:
      _video(canvas, p, line);
    case ArtKind.research:
      _research(canvas, p, line);
    case ArtKind.wheel:
      _wheel(canvas, p, line);
    case ArtKind.timer:
      _timer(canvas, p, line);
    case ArtKind.levels:
      _levels(canvas, p, line);
    case ArtKind.calendar:
      _calendar(canvas, p, line);
  }
}

void _fillStroke(Canvas c, Path path, Color fill, Color stroke, double w) {
  c.drawPath(path, Paint()..color = fill);
  c.drawPath(
    path,
    Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round,
  );
}

void _coin(Canvas c, BoardPalette p, Offset at, double r) {
  c.save();
  c.translate(at.dx, at.dy);
  c.drawCircle(Offset.zero, r, Paint()..color = p.metalDark);
  c.drawCircle(Offset.zero, r * .88, Paint()..color = p.metal);
  c.drawCircle(
    Offset.zero,
    r * .62,
    Paint()
      ..color = p.metalDark.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .09,
  );
  c.drawArc(
    Rect.fromCircle(center: Offset.zero, radius: r * .72),
    math.pi * 1.05,
    math.pi * .5,
    false,
    Paint()
      ..color = p.metalLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .12
      ..strokeCap = StrokeCap.round,
  );
  c.restore();
}

void _stack(Canvas c, BoardPalette p, int level) {
  // 1: single coin. 2: one stack. 3: two stacks. 4: three stacks. 5: four
  // stacks. Larger levels read as larger amounts at a glance.
  void disc(Offset at, double r) {
    final shadow = Paint()..color = p.metalDark;
    c.drawOval(
      Rect.fromCenter(center: at.translate(0, r * .22), width: r * 2, height: r * 1.05),
      shadow,
    );
    c.drawOval(
      Rect.fromCenter(center: at, width: r * 2, height: r * 1.05),
      Paint()..color = p.metal,
    );
    c.drawOval(
      Rect.fromCenter(center: at, width: r * 1.3, height: r * .62),
      Paint()
        ..color = p.metalDark.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .09,
    );
  }

  void column(double x, int count, double r) {
    for (var i = 0; i < count; i++) {
      disc(Offset(x, .72 - i * r * .46), r);
    }
  }

  switch (level) {
    case 1:
      _coin(c, p, Offset.zero, .62);
    case 2:
      column(0, 3, .5);
    case 3:
      column(-.28, 3, .42);
      column(.34, 5, .42);
    case 4:
      column(-.5, 3, .36);
      column(.02, 6, .36);
      column(.54, 4, .36);
    default:
      column(-.62, 3, .32);
      column(-.2, 5, .32);
      column(.22, 8, .32);
      column(.62, 4, .32);
  }
}

void _gift(Canvas c, BoardPalette p, Paint line) {
  final box = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-.7, -.15, .7, .8),
    const Radius.circular(.12),
  );
  final lid = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-.8, -.48, .8, -.1),
    const Radius.circular(.1),
  );
  final body = Color.lerp(p.route, p.accent, .25)!;
  c.drawRRect(box, Paint()..color = body);
  c.drawRRect(lid, Paint()..color = Color.lerp(body, p.onRoute, .14)!);
  c.drawRect(
    const Rect.fromLTRB(-.12, -.48, .12, .8),
    Paint()..color = p.accent,
  );
  final bow = Path()
    ..moveTo(0, -.48)
    ..cubicTo(-.5, -.95, -.78, -.35, 0, -.48)
    ..cubicTo(.5, -.95, .78, -.35, 0, -.48);
  c.drawPath(bow, Paint()..color = p.accent);
  c.drawPath(bow, line..color = p.outlineFor(p.accent)..strokeWidth = .06);
}

void _crate(Canvas c, BoardPalette p, Paint line) {
  final wood = Color.lerp(p.route, p.accent, .3)!;
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-.82, -.5, .82, .78),
    const Radius.circular(.12),
  );
  c.drawRRect(body, Paint()..color = wood);
  c.drawRRect(
    body,
    line
      ..color = p.outlineFor(wood)
      ..strokeWidth = .07,
  );
  for (final x in [-.4, 0.0, .4]) {
    c.drawLine(Offset(x, -.5), Offset(x, .78), line..strokeWidth = .05);
  }
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.9, -.82, .9, -.46),
      const Radius.circular(.1),
    ),
    Paint()..color = Color.lerp(wood, p.onRoute, .2)!,
  );
  c.drawCircle(const Offset(0, .1), .17, Paint()..color = p.accent);
  c.drawCircle(const Offset(0, .1), .17, line..strokeWidth = .05);
}

void _store(Canvas c, BoardPalette p, Paint line) {
  final awning = Path()
    ..moveTo(-.9, -.35)
    ..lineTo(-.7, -.82)
    ..lineTo(.7, -.82)
    ..lineTo(.9, -.35)
    ..close();
  _fillStroke(c, awning, p.accent, p.outlineFor(p.accent), .07);
  for (final x in [-.45, 0.0, .45]) {
    c.drawLine(
      Offset(x, -.82),
      Offset(x * 1.12, -.35),
      line
        ..color = p.metalDark.withValues(alpha: .5)
        ..strokeWidth = .06,
    );
  }
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-.78, -.3, .78, .82),
    const Radius.circular(.1),
  );
  c.drawRRect(body, Paint()..color = Color.lerp(p.route, p.surface, .15)!);
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.18, .12, .5, .82),
      const Radius.circular(.08),
    ),
    Paint()..color = p.surface,
  );
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.6, .05, -.3, .4),
      const Radius.circular(.06),
    ),
    Paint()..color = p.onRoute.withValues(alpha: .55),
  );
}

void _shield(Canvas c, BoardPalette p, Paint line) {
  final shield = Path()
    ..moveTo(0, -.88)
    ..cubicTo(.4, -.7, .62, -.62, .8, -.6)
    ..cubicTo(.82, .15, .5, .62, 0, .9)
    ..cubicTo(-.5, .62, -.82, .15, -.8, -.6)
    ..cubicTo(-.62, -.62, -.4, -.7, 0, -.88)
    ..close();
  _fillStroke(c, shield, p.route, p.outlineFor(p.route), .07);
  // A screen crossed by a slash, drawn as shapes so no font is needed.
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.42, -.28, .42, .3),
      const Radius.circular(.1),
    ),
    Paint()
      ..color = p.onRoute
      ..style = PaintingStyle.stroke
      ..strokeWidth = .09,
  );
  c.drawLine(const Offset(-.5, .42), const Offset(.5, -.4), line
    ..color = p.accent
    ..strokeWidth = .13);
}

void _brush(Canvas c, BoardPalette p, Paint line) {
  final handle = Path()
    ..moveTo(.62, -.78)
    ..lineTo(.82, -.58)
    ..lineTo(-.1, .34)
    ..lineTo(-.3, .14)
    ..close();
  _fillStroke(c, handle, Color.lerp(p.route, p.ink, .25)!, p.ink, .06);
  final tip = Path()
    ..moveTo(-.3, .14)
    ..lineTo(-.1, .34)
    ..cubicTo(-.18, .78, -.62, .86, -.85, .8)
    ..cubicTo(-.7, .6, -.7, .3, -.3, .14)
    ..close();
  _fillStroke(c, tip, p.accent, p.outlineFor(p.accent), .06);
  for (final (dx, dy, color) in [
    (.62, .52, p.route),
    (.22, .72, p.accent),
    (.78, .12, p.metalDark),
  ]) {
    c.drawCircle(Offset(dx, dy), .12, Paint()..color = color);
  }
}

void _crown(Canvas c, BoardPalette p, Paint line) {
  final crown = Path()
    ..moveTo(-.82, .5)
    ..lineTo(-.9, -.4)
    ..lineTo(-.4, .05)
    ..lineTo(0, -.7)
    ..lineTo(.4, .05)
    ..lineTo(.9, -.4)
    ..lineTo(.82, .5)
    ..close();
  _fillStroke(c, crown, p.accent, p.outlineFor(p.accent), .07);
  c.drawRect(
    const Rect.fromLTRB(-.82, .5, .82, .76),
    Paint()..color = p.metalDark,
  );
  for (final x in [-.4, 0.0, .4]) {
    c.drawCircle(Offset(x, .24), .09, Paint()..color = p.metalLight);
  }
}

void _bolt(Canvas c, BoardPalette p, Paint line) {
  final bolt = Path()
    ..moveTo(.2, -.9)
    ..lineTo(-.58, .12)
    ..lineTo(-.04, .12)
    ..lineTo(-.2, .9)
    ..lineTo(.62, -.18)
    ..lineTo(.06, -.18)
    ..close();
  _fillStroke(c, bolt, p.accent, p.outlineFor(p.accent), .07);
}

void _hint(Canvas c, BoardPalette p, Paint line) {
  final bulb = Path()
    ..moveTo(0, -.85)
    ..cubicTo(.7, -.85, .85, -.05, .4, .32)
    ..lineTo(.4, .52)
    ..lineTo(-.4, .52)
    ..lineTo(-.4, .32)
    ..cubicTo(-.85, -.05, -.7, -.85, 0, -.85)
    ..close();
  _fillStroke(c, bulb, p.accent, p.outlineFor(p.accent), .07);
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.32, .62, .32, .84),
      const Radius.circular(.08),
    ),
    Paint()..color = p.metalDark,
  );
  c.drawArc(
    Rect.fromCircle(center: const Offset(-.1, -.35), radius: .3),
    math.pi,
    math.pi * .5,
    false,
    line
      ..color = p.metalLight
      ..strokeWidth = .09,
  );
}

void _flame(Canvas c, BoardPalette p, Paint line) {
  final outer = Path()
    ..moveTo(0, -.92)
    ..cubicTo(.18, -.5, .75, -.28, .62, .3)
    ..cubicTo(.55, .78, -.55, .78, -.62, .3)
    ..cubicTo(-.68, -.05, -.3, -.12, -.3, -.5)
    ..cubicTo(-.12, -.42, -.05, -.65, 0, -.92)
    ..close();
  _fillStroke(c, outer, p.accent, p.outlineFor(p.accent), .07);
  final inner = Path()
    ..moveTo(0, -.1)
    ..cubicTo(.32, .15, .4, .35, .22, .55)
    ..cubicTo(.1, .66, -.2, .66, -.3, .5)
    ..cubicTo(-.4, .3, -.1, .2, 0, -.1)
    ..close();
  c.drawPath(inner, Paint()..color = p.metalLight);
}

void _freeze(Canvas c, BoardPalette p, Paint line) {
  final ink = line
    ..color = p.route
    ..strokeWidth = .12;
  for (var i = 0; i < 3; i++) {
    c.save();
    c.rotate(i * math.pi / 3);
    c.drawLine(const Offset(0, -.82), const Offset(0, .82), ink);
    c.drawLine(const Offset(0, -.55), const Offset(-.2, -.75), ink..strokeWidth = .09);
    c.drawLine(const Offset(0, -.55), const Offset(.2, -.75), ink);
    c.drawLine(const Offset(0, .55), const Offset(-.2, .75), ink);
    c.drawLine(const Offset(0, .55), const Offset(.2, .75), ink);
    c.restore();
  }
}

void _trophy(Canvas c, BoardPalette p, Paint line) {
  final cup = Path()
    ..moveTo(-.55, -.7)
    ..lineTo(.55, -.7)
    ..cubicTo(.55, .1, .35, .35, 0, .38)
    ..cubicTo(-.35, .35, -.55, .1, -.55, -.7)
    ..close();
  _fillStroke(c, cup, p.accent, p.outlineFor(p.accent), .07);
  for (final s in [-1.0, 1.0]) {
    c.drawArc(
      Rect.fromCenter(center: Offset(.62 * s, -.4), width: .5, height: .5),
      s > 0 ? -math.pi / 2 : math.pi / 2,
      math.pi,
      false,
      line
        ..color = p.metalDark
        ..strokeWidth = .09,
    );
  }
  c.drawRect(const Rect.fromLTRB(-.1, .38, .1, .62), Paint()..color = p.metalDark);
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.42, .62, .42, .84),
      const Radius.circular(.07),
    ),
    Paint()..color = p.metalDark,
  );
}

void _lock(Canvas c, BoardPalette p, Paint line) {
  c.drawArc(
    Rect.fromCenter(center: const Offset(0, -.2), width: .8, height: .9),
    math.pi,
    math.pi,
    false,
    line
      ..color = p.muted
      ..strokeWidth = .14,
  );
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.55, -.2, .55, .76),
      const Radius.circular(.14),
    ),
    Paint()..color = p.muted,
  );
  c.drawCircle(const Offset(0, .2), .11, Paint()..color = p.surface);
}

void _check(Canvas c, BoardPalette p, Paint line) {
  c.drawCircle(Offset.zero, .85, Paint()..color = p.route);
  c.drawPath(
    Path()
      ..moveTo(-.42, .02)
      ..lineTo(-.1, .34)
      ..lineTo(.46, -.3),
    line
      ..color = p.onRoute
      ..strokeWidth = .16,
  );
}

void _video(Canvas c, BoardPalette p, Paint line) {
  c.drawCircle(Offset.zero, .85, Paint()..color = p.route);
  c.drawPath(
    Path()
      ..moveTo(-.2, -.4)
      ..lineTo(.48, 0)
      ..lineTo(-.2, .4)
      ..close(),
    Paint()..color = p.onRoute,
  );
}

void _research(Canvas c, BoardPalette p, Paint line) {
  final ink = line
    ..color = p.route
    ..strokeWidth = .09;
  const nodes = [Offset(0, -.6), Offset(-.62, .38), Offset(.62, .38)];
  c.drawLine(nodes[0], nodes[1], ink);
  c.drawLine(nodes[0], nodes[2], ink);
  c.drawLine(nodes[1], nodes[2], ink);
  for (final node in nodes) {
    c.drawCircle(node, .22, Paint()..color = p.accent);
    c.drawCircle(node, .22, ink..strokeWidth = .06);
  }
}

void _wheel(Canvas c, BoardPalette p, Paint line) {
  final rect = Rect.fromCircle(center: Offset.zero, radius: .85);
  for (var i = 0; i < 6; i++) {
    c.drawArc(
      rect,
      i * math.pi / 3,
      math.pi / 3,
      true,
      Paint()..color = i.isEven ? p.route : Color.lerp(p.route, p.accent, .55)!,
    );
  }
  c.drawCircle(Offset.zero, .85, line
    ..color = p.outlineFor(p.route)
    ..strokeWidth = .06);
  c.drawCircle(Offset.zero, .2, Paint()..color = p.accent);
  c.drawPath(
    Path()
      ..moveTo(-.16, -.95)
      ..lineTo(.16, -.95)
      ..lineTo(0, -.7)
      ..close(),
    Paint()..color = p.accent,
  );
}

void _timer(Canvas c, BoardPalette p, Paint line) {
  c.drawCircle(const Offset(0, .1), .72, line
    ..color = p.route
    ..strokeWidth = .12);
  c.drawLine(const Offset(0, .1), const Offset(0, -.3), line..strokeWidth = .12);
  c.drawLine(const Offset(0, .1), const Offset(.26, .2), line..strokeWidth = .1);
  c.drawLine(const Offset(-.15, -.82), const Offset(.15, -.82), line..strokeWidth = .12);
}

void _levels(Canvas c, BoardPalette p, Paint line) {
  for (var i = 0; i < 4; i++) {
    final x = (i % 2 == 0 ? -.42 : .42);
    final y = (i < 2 ? -.42 : .42);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: .7, height: .7),
        const Radius.circular(.14),
      ),
      Paint()..color = i == 3 ? p.accent : p.route,
    );
  }
}

void _calendar(Canvas c, BoardPalette p, Paint line) {
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.8, -.65, .8, .8),
      const Radius.circular(.16),
    ),
    Paint()..color = p.route,
  );
  c.drawRect(
    const Rect.fromLTRB(-.8, -.3, .8, .8),
    Paint()..color = p.surface,
  );
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.8, -.65, .8, .8),
      const Radius.circular(.16),
    ),
    line
      ..color = p.route
      ..strokeWidth = .08,
  );
  for (final x in [-.45, .45]) {
    c.drawLine(Offset(x, -.85), Offset(x, -.5), line..strokeWidth = .12);
  }
  c.drawCircle(const Offset(.1, .28), .2, Paint()..color = p.accent);
}
