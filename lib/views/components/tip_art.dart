import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/path_tips.dart';

/// Paints original path-tip artwork in normalized coordinates, pointing right.
/// The same painter is used in the catalogue, preview and gameplay.
void paintPathTip(
  Canvas canvas,
  Offset center,
  double radius,
  PathTip tip,
  BoardPalette palette, {
  int quarterTurns = 0,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(quarterTurns * math.pi / 2);
  canvas.scale(radius);
  final routeLum = palette.route.computeLuminance();
  final accentLum = palette.accent.computeLuminance();
  final routeContrast =
      (math.max(routeLum, accentLum) + .05) /
      (math.min(routeLum, accentLum) + .05);
  final outline = Paint()
    ..color = routeContrast >= 3 ? palette.route : palette.onAccent
    ..style = PaintingStyle.stroke
    ..strokeWidth = .105
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final fill = Paint()..color = palette.accent;
  // Mix toward the accent's own foreground rather than the screen surface:
  // dark surfaces would make facial detail disappear on dark palettes.
  final light = Paint()
    ..color = Color.lerp(palette.accent, palette.onRoute, .12)!;
  final ink = Paint()..color = palette.onAccent;
  final secondary = Paint()
    ..color = Color.lerp(palette.accent, palette.route, .35)!;
  void shape(List<Offset> points, [Paint? color]) {
    final p = Path()..moveTo(points.first.dx, points.first.dy);
    for (final pt in points.skip(1)) {
      p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    canvas.drawPath(p, color ?? fill);
    canvas.drawPath(p, outline);
  }

  void oval(double x, double y, double w, double h, [Paint? color]) {
    final r = Rect.fromCenter(center: Offset(x, y), width: w, height: h);
    canvas.drawOval(r, color ?? fill);
    canvas.drawOval(r, outline);
  }

  void circle(double x, double y, double r, [Paint? color]) {
    canvas.drawCircle(Offset(x, y), r, color ?? fill);
    canvas.drawCircle(Offset(x, y), r, outline);
  }

  void line(double x, double y, double a, double b, [Paint? color]) =>
      canvas.drawLine(Offset(x, y), Offset(a, b), color ?? outline);
  void eye(double x, double y) => canvas.drawCircle(Offset(x, y), .075, ink);
  void face() {
    eye(.27, -.20);
    eye(.27, .20);
    line(
      .47,
      -.07,
      .47,
      .07,
      Paint()
        ..color = palette.onAccent
        ..strokeWidth = .07
        ..strokeCap = StrokeCap.round,
    );
  }

  switch (tip) {
    case PathTip.classic:
      canvas.drawCircle(Offset.zero, .95, Paint()..color = palette.route);
      canvas.drawCircle(Offset.zero, .57, Paint()..color = palette.accent);
    case PathTip.arrow:
      shape([
        const Offset(-.85, -.45),
        const Offset(.08, -.45),
        const Offset(.08, -.75),
        const Offset(.90, 0),
        const Offset(.08, .75),
        const Offset(.08, .45),
        const Offset(-.85, .45),
      ]);
      line(-.58, 0, .18, 0);
    case PathTip.crystal:
      shape([
        const Offset(-.82, 0),
        const Offset(-.35, -.72),
        const Offset(.42, -.72),
        const Offset(.88, 0),
        const Offset(.42, .72),
        const Offset(-.35, .72),
      ]);
      line(-.82, 0, .88, 0);
      line(-.35, -.72, -.05, 0);
      line(.42, -.72, .15, 0);
      line(-.05, 0, -.35, .72);
      line(.15, 0, .42, .72);
    case PathTip.star:
      final points = List.generate(10, (i) {
        final a = -math.pi / 2 + i * math.pi / 5;
        final r = i.isEven ? .91 : .43;
        return Offset(math.cos(a) * r, math.sin(a) * r);
      });
      shape(points);
      circle(0, 0, .15, light);
    case PathTip.cat:
      shape([
        const Offset(-.62, -.55),
        const Offset(-.77, -.92),
        const Offset(-.20, -.67),
        const Offset(.42, -.67),
        const Offset(.76, -.39),
        const Offset(.76, .39),
        const Offset(.42, .67),
        const Offset(-.20, .67),
        const Offset(-.77, .92),
        const Offset(-.62, .55),
      ]);
      face();
      line(-.1, -.36, .19, -.30);
      line(-.1, .36, .19, .30);
    case PathTip.dog:
      oval(-.50, -.55, .55, .85, secondary);
      oval(-.50, .55, .55, .85, secondary);
      oval(.04, 0, 1.45, 1.35);
      oval(.54, 0, .45, .58, light);
      face();
    case PathTip.rabbit:
      oval(-.47, -.60, .45, .95, light);
      oval(-.47, .60, .45, .95, light);
      oval(.03, 0, 1.46, 1.18);
      face();
    case PathTip.fox:
      shape([
        const Offset(-.78, -.86),
        const Offset(-.12, -.64),
        const Offset(.42, -.68),
        const Offset(.88, 0),
        const Offset(.42, .68),
        const Offset(-.12, .64),
        const Offset(-.78, .86),
        const Offset(-.56, 0),
      ]);
      shape([
        const Offset(-.25, -.48),
        const Offset(.43, -.46),
        const Offset(.8, 0),
        const Offset(.43, .46),
        const Offset(-.25, .48),
        const Offset(.02, 0),
      ], light);
      face();
    case PathTip.panda:
      circle(-.45, -.55, .30, secondary);
      circle(-.45, .55, .30, secondary);
      oval(.02, 0, 1.50, 1.35, light);
      oval(.27, -.29, .48, .36, secondary);
      oval(.27, .29, .48, .36, secondary);
      face();
    case PathTip.frog:
      circle(-.18, -.57, .32);
      circle(-.18, .57, .32);
      oval(.06, 0, 1.50, 1.10);
      eye(.1, -.55);
      eye(.1, .55);
      line(.48, -.25, .48, .25);
    case PathTip.penguin:
      oval(-.05, 0, 1.60, 1.42, secondary);
      oval(.15, 0, 1.16, 1.05, light);
      shape([
        const Offset(.27, -.20),
        const Offset(.78, 0),
        const Offset(.27, .20),
      ]);
      eye(.12, -.35);
      eye(.12, .35);
    case PathTip.turtle:
      oval(-.42, -.65, .45, .35);
      oval(-.42, .65, .45, .35);
      oval(.32, -.64, .42, .34);
      oval(.32, .64, .42, .34);
      oval(-.15, 0, 1.30, 1.35, secondary);
      circle(.65, 0, .30);
      line(-.6, 0, .25, 0);
      line(-.15, -.57, -.15, .57);
    case PathTip.bee:
      oval(-.24, -.63, .72, .42, light);
      oval(-.24, .63, .72, .42, light);
      oval(-.04, 0, 1.55, 1.05);
      line(-.35, -.45, -.35, .45);
      line(.02, -.48, .02, .48);
      eye(.48, -.16);
      eye(.48, .16);
      shape([
        const Offset(-.8, -.18),
        const Offset(-.98, 0),
        const Offset(-.8, .18),
      ], secondary);
    case PathTip.ghost:
      final p = Path()
        ..moveTo(.8, 0)
        ..cubicTo(.8, -.65, .35, -.78, -.35, -.72)
        ..lineTo(-.76, -.69)
        ..lineTo(-.52, -.36)
        ..lineTo(-.76, 0)
        ..lineTo(-.52, .36)
        ..lineTo(-.76, .69)
        ..lineTo(-.35, .72)
        ..cubicTo(.35, .78, .8, .65, .8, 0)
        ..close();
      canvas.drawPath(p, light);
      canvas.drawPath(p, outline);
      face();
    case PathTip.robot:
      final box = RRect.fromRectAndRadius(
        const Rect.fromLTRB(-.63, -.62, .66, .62),
        const Radius.circular(.17),
      );
      canvas.drawRRect(box, secondary);
      canvas.drawRRect(box, outline);
      line(-.62, 0, -.9, 0);
      circle(-.9, 0, .10);
      oval(.18, 0, .55, .75, light);
      eye(.28, -.20);
      eye(.28, .20);
    case PathTip.ufo:
      oval(-.10, 0, 1.15, 1.38, light);
      oval(.15, 0, .80, 1.80, secondary);
      circle(.13, -.55, .07);
      circle(.13, 0, .07);
      circle(.13, .55, .07);
    case PathTip.flame:
      shape([
        const Offset(-.75, -.52),
        const Offset(-.34, -.46),
        const Offset(.05, -.83),
        const Offset(.05, -.35),
        const Offset(.78, 0),
        const Offset(.05, .35),
        const Offset(.05, .83),
        const Offset(-.34, .46),
        const Offset(-.75, .52),
        const Offset(-.48, 0),
      ]);
      shape([
        const Offset(-.45, -.20),
        const Offset(.05, -.18),
        const Offset(.42, 0),
        const Offset(.05, .18),
        const Offset(-.45, .20),
        const Offset(-.25, 0),
      ], light);
    case PathTip.dragon:
      shape([
        const Offset(-.80, -.72),
        const Offset(-.36, -.57),
        const Offset(-.20, -.90),
        const Offset(.02, -.62),
        const Offset(.43, -.55),
        const Offset(.80, -.22),
        const Offset(.72, 0),
        const Offset(.80, .22),
        const Offset(.43, .55),
        const Offset(.02, .62),
        const Offset(-.20, .90),
        const Offset(-.36, .57),
        const Offset(-.80, .72),
        const Offset(-.55, 0),
      ], secondary);
      eye(.32, -.25);
      eye(.32, .25);
      line(.5, -.08, .65, -.08);
      line(.5, .08, .65, .08);
      line(-.40, -.30, -.18, -.18);
      line(-.40, .30, -.18, .18);
    case PathTip.phoenix:
      shape([
        const Offset(-.92, -.86),
        const Offset(-.47, -.33),
        const Offset(-.68, -.10),
        const Offset(-.33, 0),
        const Offset(-.68, .10),
        const Offset(-.47, .33),
        const Offset(-.92, .86),
        const Offset(-.10, .53),
        const Offset(.35, .42),
        const Offset(.82, 0),
        const Offset(.35, -.42),
        const Offset(-.10, -.53),
      ]);
      line(-.6, -.60, .02, -.22);
      line(-.6, .60, .02, .22);
      eye(.30, -.12);
      eye(.30, .12);
      shape([
        const Offset(.46, -.13),
        const Offset(.88, 0),
        const Offset(.46, .13),
      ], secondary);
    case PathTip.rocket:
      shape([
        const Offset(-.65, -.30),
        const Offset(-.66, -.72),
        const Offset(-.16, -.45),
        const Offset(.34, -.35),
        const Offset(.88, 0),
        const Offset(.34, .35),
        const Offset(-.16, .45),
        const Offset(-.66, .72),
        const Offset(-.65, .30),
        const Offset(-.85, .22),
        const Offset(-.85, -.22),
      ]);
      circle(.16, 0, .22, light);
      shape([
        const Offset(-.76, -.18),
        const Offset(-.98, 0),
        const Offset(-.76, .18),
      ], secondary);
  }
  canvas.restore();
}

class TipArtwork extends StatelessWidget {
  const TipArtwork({
    required this.tip,
    required this.palette,
    this.quarterTurns = 0,
    super.key,
  });
  final PathTip tip;
  final BoardPalette palette;
  final int quarterTurns;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '${tip.label} path tip',
    child: AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(painter: _TipPainter(tip, palette, quarterTurns)),
    ),
  );
}

class _TipPainter extends CustomPainter {
  _TipPainter(this.tip, this.palette, this.quarterTurns);
  final PathTip tip;
  final BoardPalette palette;
  final int quarterTurns;
  @override
  void paint(Canvas canvas, Size size) => paintPathTip(
    canvas,
    size.center(Offset.zero),
    size.shortestSide * .39,
    tip,
    palette,
    quarterTurns: quarterTurns,
  );
  @override
  bool shouldRepaint(_TipPainter old) =>
      old.tip != tip ||
      old.palette != palette ||
      old.quarterTurns != quarterTurns;
}
