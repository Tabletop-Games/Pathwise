import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/path_tips.dart';

/// Semantic colour roles for one illustration. Every role is derived from the
/// equipped palette so each character belongs to its theme, while an identity
/// hue keeps animals recognisable (a fox stays warm, a frog stays green).
final class TipColors {
  const TipColors({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.highlight,
    required this.detail,
    required this.depth,
    required this.outline,
    required this.eye,
  });

  final Color primary,
      secondary,
      accent,
      highlight,
      detail,
      depth,
      outline,
      eye;

  /// [identity] is the character's natural colour. It is pulled toward the
  /// theme accent by [adopt] so it matches the theme, then clamped so it keeps
  /// at least [minContrast] against the route colour it is drawn over.
  factory TipColors.resolve(
    BoardPalette palette,
    Color identity, {
    Color? second,
    double adopt = .38,
    double minContrast = 1.9,
  }) {
    var primary = Color.lerp(identity, palette.accent, adopt)!;
    primary = _ensureContrast(
      primary,
      palette.surface,
      palette.route,
      minContrast,
    );
    final secondary = _shift(
      second == null
          ? primary
          : Color.lerp(second, palette.accent, adopt * .6)!,
      second == null ? (palette.dark ? .16 : -.16) : 0,
    );
    final outline = _shift(primary, palette.dark ? -.50 : -.46, saturate: .1);
    return TipColors(
      primary: primary,
      secondary: _ensureContrast(
        secondary,
        palette.surface,
        palette.route,
        1.5,
      ),
      accent: Color.lerp(palette.accent, primary, .25)!,
      highlight: _shift(primary, palette.dark ? .26 : .30),
      detail: _shift(primary, palette.dark ? .12 : -.22, saturate: .1),
      depth: _shift(primary, palette.dark ? -.16 : -.2),
      outline: outline,
      eye: palette.dark && outline.computeLuminance() > .4
          ? const Color(0xff10141a)
          : _shift(primary, -.55, saturate: .05),
    );
  }

  static Color _shift(Color c, double lightness, {double saturate = 0}) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + lightness).clamp(.05, .95))
        .withSaturation((hsl.saturation + saturate).clamp(0, 1))
        .toColor();
  }

  /// Moves [c] along lightness until it contrasts with both backgrounds.
  static Color _ensureContrast(Color c, Color a, Color b, double ratio) {
    double contrast(Color x, Color y) {
      final l1 = x.computeLuminance(), l2 = y.computeLuminance();
      return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
    }

    var best = c;
    for (final dir in [1.0, -1.0]) {
      var test = c;
      for (var i = 0; i < 14; i++) {
        if (contrast(test, a) >= ratio && contrast(test, b) >= ratio) {
          return test;
        }
        test = _shift(test, dir * .05);
      }
    }
    return best;
  }
}

/// Identity colours: the natural colour of each character before theming.
const _identity = <PathTip, (Color, Color?)>{
  PathTip.arrow: (Color(0xfff2b544), null),
  PathTip.crystal: (Color(0xff58c7e8), Color(0xff9a7cf0)),
  PathTip.star: (Color(0xfff6c846), null),
  PathTip.cat: (Color(0xfff0963c), Color(0xffffe2bd)),
  PathTip.dog: (Color(0xffc99456), Color(0xff7a5232)),
  PathTip.rabbit: (Color(0xfff2eadf), Color(0xfff4a6b8)),
  PathTip.fox: (Color(0xffe8742c), Color(0xfffff3e4)),
  PathTip.panda: (Color(0xfffafafa), Color(0xff2b2b30)),
  PathTip.frog: (Color(0xff5cbc4f), Color(0xffcdeb7e)),
  PathTip.penguin: (Color(0xff384a66), Color(0xfff6f6f2)),
  PathTip.turtle: (Color(0xff4fae6c), Color(0xffa5772f)),
  PathTip.bee: (Color(0xfff6c235), Color(0xff2e2a24)),
  PathTip.ghost: (Color(0xffeef0fb), Color(0xffb8c0e8)),
  PathTip.robot: (Color(0xffa9b6c6), Color(0xff4cc4d8)),
  PathTip.ufo: (Color(0xffb7c0d1), Color(0xff6ddc9b)),
  PathTip.flame: (Color(0xfff2762e), Color(0xfff9d24c)),
  PathTip.dragon: (Color(0xff58b36a), Color(0xffd9533c)),
  PathTip.phoenix: (Color(0xffef6a2e), Color(0xfff6c235)),
  PathTip.rocket: (Color(0xffe9ecf5), Color(0xffe5533d)),
};

/// Paints [tip] centred at [center] with the given [radius]. Artwork is drawn
/// upright (forward is up); [quarterTurns] follows the route facing:
/// 0 right, 1 down, 2 left, 3 up. The catalogue passes 3 so characters stand
/// upright, and gameplay rotates them to match the path.
void paintPathTip(
  Canvas canvas,
  Offset center,
  double radius,
  PathTip tip,
  BoardPalette palette, {
  int quarterTurns = 3,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  // Artwork forward is up; facing 3 (up) needs no rotation.
  canvas.rotate((quarterTurns - 3) * math.pi / 2);
  canvas.scale(radius);
  if (tip == PathTip.classic) {
    canvas.drawCircle(Offset.zero, .95, Paint()..color = palette.route);
    canvas.drawCircle(Offset.zero, .57, Paint()..color = palette.accent);
  } else {
    final id = _identity[tip]!;
    final colors = TipColors.resolve(palette, id.$1, second: id.$2);
    _Artist(canvas, colors, palette).draw(tip);
  }
  canvas.restore();
}

/// Layered Bézier illustrations in a [-1, 1] box. Each character has a
/// distinct silhouette, an inner layer, facial or structural detail and a
/// small highlight.
class _Artist {
  _Artist(this.c, this.k, this.p);
  final Canvas c;
  final TipColors k;
  final BoardPalette p;

  static const _w = .075;

  Paint fill(Color color) => Paint()..color = color;
  Paint get stroke => Paint()
    ..color = k.outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = _w
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  void shape(Path path, Color color, {bool outline = true}) {
    c.drawPath(path, fill(color));
    if (outline) c.drawPath(path, stroke);
  }

  void oval(
    double x,
    double y,
    double w,
    double h,
    Color color, {
    bool outline = true,
  }) {
    final rect = Rect.fromCenter(center: Offset(x, y), width: w, height: h);
    c.drawOval(rect, fill(color));
    if (outline) c.drawOval(rect, stroke);
  }

  void line(
    double x1,
    double y1,
    double x2,
    double y2, {
    double w = _w,
    Color? color,
  }) => c.drawLine(
    Offset(x1, y1),
    Offset(x2, y2),
    stroke
      ..strokeWidth = w
      ..color = color ?? k.outline,
  );

  void curve(Path path, {double w = _w, Color? color}) => c.drawPath(
    path,
    stroke
      ..strokeWidth = w
      ..color = color ?? k.outline,
  );

  /// Expressive eye: sclera, iris and a catch-light.
  void eye(double x, double y, {double r = .105, bool shine = true}) {
    oval(x, y, r * 2.15, r * 2.35, const Color(0xfffdfdfd));
    c.drawCircle(Offset(x, y + r * .08), r * .78, fill(k.eye));
    if (shine) {
      c.drawCircle(
        Offset(x - r * .28, y - r * .34),
        r * .3,
        fill(const Color(0xfffdfdfd)),
      );
    }
  }

  void blush(double x, double y) =>
      oval(x, y, .2, .12, k.accent.withValues(alpha: .55), outline: false);

  void draw(PathTip tip) {
    switch (tip) {
      case PathTip.classic:
        break;
      case PathTip.arrow:
        _arrow();
      case PathTip.crystal:
        _crystal();
      case PathTip.star:
        _star();
      case PathTip.cat:
        _cat();
      case PathTip.dog:
        _dog();
      case PathTip.rabbit:
        _rabbit();
      case PathTip.fox:
        _fox();
      case PathTip.panda:
        _panda();
      case PathTip.frog:
        _frog();
      case PathTip.penguin:
        _penguin();
      case PathTip.turtle:
        _turtle();
      case PathTip.bee:
        _bee();
      case PathTip.ghost:
        _ghost();
      case PathTip.robot:
        _robot();
      case PathTip.ufo:
        _ufo();
      case PathTip.flame:
        _flame();
      case PathTip.dragon:
        _dragon();
      case PathTip.phoenix:
        _phoenix();
      case PathTip.rocket:
        _rocket();
    }
  }

  // ---- geometric -----------------------------------------------------------

  void _arrow() {
    final body = Path()
      ..moveTo(0, -.95)
      ..cubicTo(.18, -.72, .66, -.2, .8, -.02)
      ..cubicTo(.84, .04, .8, .12, .72, .12)
      ..lineTo(.34, .12)
      ..lineTo(.34, .8)
      ..cubicTo(.34, .9, .28, .95, .18, .95)
      ..lineTo(-.18, .95)
      ..cubicTo(-.28, .95, -.34, .9, -.34, .8)
      ..lineTo(-.34, .12)
      ..lineTo(-.72, .12)
      ..cubicTo(-.8, .12, -.84, .04, -.8, -.02)
      ..cubicTo(-.66, -.2, -.18, -.72, 0, -.95)
      ..close();
    shape(body, k.primary);
    final inner = Path()
      ..moveTo(0, -.7)
      ..lineTo(.5, -.04)
      ..lineTo(.16, -.04)
      ..lineTo(.16, .78)
      ..lineTo(-.16, .78)
      ..lineTo(-.16, -.04)
      ..lineTo(-.5, -.04)
      ..close();
    c.drawPath(inner, fill(k.highlight.withValues(alpha: .55)));
    line(-.02, -.66, -.02, .7, w: .06, color: k.detail);
  }

  void _crystal() {
    final gem = Path()
      ..moveTo(0, -.95)
      ..lineTo(.62, -.4)
      ..lineTo(.62, .3)
      ..lineTo(0, .95)
      ..lineTo(-.62, .3)
      ..lineTo(-.62, -.4)
      ..close();
    shape(gem, k.primary);
    final left = Path()
      ..moveTo(0, -.95)
      ..lineTo(-.62, -.4)
      ..lineTo(-.62, .3)
      ..lineTo(0, .95)
      ..lineTo(-.18, -.05)
      ..close();
    c.drawPath(left, fill(k.secondary));
    final top = Path()
      ..moveTo(0, -.95)
      ..lineTo(.62, -.4)
      ..lineTo(0, -.14)
      ..lineTo(-.62, -.4)
      ..close();
    c.drawPath(top, fill(k.highlight));
    c.drawPath(gem, stroke);
    line(-.62, -.4, 0, -.14, w: .06);
    line(.62, -.4, 0, -.14, w: .06);
    line(0, -.14, 0, .95, w: .06);
    c.drawCircle(const Offset(-.28, -.46), .07, fill(const Color(0xfffdfdfd)));
  }

  void _star() {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? .96 : .5;
      final pt = Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    shape(path, k.primary);
    final shine = Path()
      ..moveTo(0, -.78)
      ..lineTo(.2, -.22)
      ..lineTo(0, -.12)
      ..lineTo(-.2, -.22)
      ..close();
    c.drawPath(shine, fill(k.highlight));
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      line(0, 0, math.cos(a) * .52, math.sin(a) * .52, w: .05, color: k.detail);
    }
    c.drawCircle(Offset.zero, .12, fill(k.accent));
  }

  // ---- animals -------------------------------------------------------------

  void _cat() {
    final earL = Path()
      ..moveTo(-.74, -.2)
      ..cubicTo(-.8, -.62, -.66, -.9, -.5, -.96)
      ..cubicTo(-.3, -.86, -.12, -.7, -.06, -.58)
      ..close();
    final earR = Path()
      ..moveTo(.74, -.2)
      ..cubicTo(.8, -.62, .66, -.9, .5, -.96)
      ..cubicTo(.3, -.86, .12, -.7, .06, -.58)
      ..close();
    shape(earL, k.primary);
    shape(earR, k.primary);
    c.drawPath(
      Path()
        ..moveTo(-.6, -.34)
        ..cubicTo(-.62, -.62, -.54, -.74, -.5, -.78)
        ..cubicTo(-.36, -.7, -.26, -.6, -.2, -.52)
        ..close(),
      fill(k.accent),
    );
    c.drawPath(
      Path()
        ..moveTo(.6, -.34)
        ..cubicTo(.62, -.62, .54, -.74, .5, -.78)
        ..cubicTo(.36, -.7, .26, -.6, .2, -.52)
        ..close(),
      fill(k.accent),
    );
    final head = Path()
      ..moveTo(0, -.66)
      ..cubicTo(.7, -.66, .9, -.18, .86, .24)
      ..cubicTo(.82, .74, .4, .92, 0, .92)
      ..cubicTo(-.4, .92, -.82, .74, -.86, .24)
      ..cubicTo(-.9, -.18, -.7, -.66, 0, -.66)
      ..close();
    shape(head, k.primary);
    oval(0, .5, .62, .42, k.secondary, outline: false);
    for (final x in [-.18, 0.0, .18]) {
      line(x, -.64, x * .9, -.46, w: .05, color: k.detail);
    }
    eye(-.34, -.1);
    eye(.34, -.1);
    blush(-.54, .24);
    blush(.54, .24);
    c.drawPath(
      Path()
        ..moveTo(-.07, .22)
        ..lineTo(.07, .22)
        ..lineTo(0, .32)
        ..close(),
      fill(k.accent),
    );
    curve(
      Path()
        ..moveTo(0, .32)
        ..quadraticBezierTo(-.08, .46, -.2, .44)
        ..moveTo(0, .32)
        ..quadraticBezierTo(.08, .46, .2, .44),
      w: .05,
    );
    for (final s in [-1.0, 1.0]) {
      line(s * .5, .3, s * .94, .22, w: .035, color: k.highlight);
      line(s * .5, .38, s * .94, .42, w: .035, color: k.highlight);
    }
  }

  void _dog() {
    final earL = Path()
      ..moveTo(-.5, -.5)
      ..cubicTo(-.98, -.56, -1.0, .1, -.84, .34)
      ..cubicTo(-.7, .3, -.58, .04, -.5, -.2)
      ..close();
    final earR = Path()
      ..moveTo(.5, -.5)
      ..cubicTo(.98, -.56, 1.0, .1, .84, .34)
      ..cubicTo(.7, .3, .58, .04, .5, -.2)
      ..close();
    shape(earL, k.secondary);
    shape(earR, k.secondary);
    final head = Path()
      ..moveTo(0, -.84)
      ..cubicTo(.6, -.84, .78, -.34, .74, .1)
      ..cubicTo(.7, .62, .4, .9, 0, .9)
      ..cubicTo(-.4, .9, -.7, .62, -.74, .1)
      ..cubicTo(-.78, -.34, -.6, -.84, 0, -.84)
      ..close();
    shape(head, k.primary);
    c.drawPath(
      Path()
        ..moveTo(-.18, -.82)
        ..cubicTo(-.46, -.5, -.3, -.2, -.1, -.22)
        ..cubicTo(.1, -.4, .1, -.7, -.18, -.82)
        ..close(),
      fill(k.secondary.withValues(alpha: .85)),
    );
    oval(0, .42, .74, .56, k.highlight, outline: true);
    eye(-.3, -.1, r: .1);
    eye(.3, -.1, r: .1);
    c.drawPath(
      Path()
        ..moveTo(-.16, .26)
        ..cubicTo(-.16, .18, .16, .18, .16, .26)
        ..cubicTo(.16, .36, .06, .4, 0, .4)
        ..cubicTo(-.06, .4, -.16, .36, -.16, .26)
        ..close(),
      fill(k.eye),
    );
    curve(
      Path()
        ..moveTo(0, .4)
        ..lineTo(0, .5)
        ..moveTo(0, .5)
        ..quadraticBezierTo(-.1, .64, -.24, .58)
        ..moveTo(0, .5)
        ..quadraticBezierTo(.1, .64, .24, .58),
      w: .05,
    );
    c.drawPath(
      Path()
        ..moveTo(-.1, .6)
        ..quadraticBezierTo(0, .86, .1, .6)
        ..close(),
      fill(k.accent),
    );
    for (final s in [-1.0, 1.0]) {
      c.drawCircle(Offset(s * .5, .22), .03, fill(k.eye.withValues(alpha: .5)));
    }
  }

  void _rabbit() {
    for (final s in [-1.0, 1.0]) {
      final ear = Path()
        ..moveTo(s * .14, -.5)
        ..cubicTo(s * .04, -.98, s * .22, -1.02, s * .36, -1.0)
        ..cubicTo(s * .56, -.96, s * .5, -.6, s * .46, -.42)
        ..close();
      shape(ear, k.primary);
      c.drawPath(
        Path()
          ..moveTo(s * .22, -.52)
          ..cubicTo(s * .16, -.86, s * .28, -.9, s * .36, -.88)
          ..cubicTo(s * .46, -.84, s * .42, -.62, s * .4, -.5)
          ..close(),
        fill(k.secondary),
      );
    }
    final head = Path()
      ..moveTo(0, -.52)
      ..cubicTo(.66, -.52, .86, -.04, .8, .34)
      ..cubicTo(.74, .78, .38, .92, 0, .92)
      ..cubicTo(-.38, .92, -.74, .78, -.8, .34)
      ..cubicTo(-.86, -.04, -.66, -.52, 0, -.52)
      ..close();
    shape(head, k.primary);
    oval(0, .52, .5, .34, k.highlight.withValues(alpha: .7), outline: false);
    eye(-.32, .02);
    eye(.32, .02);
    blush(-.5, .34);
    blush(.5, .34);
    c.drawPath(
      Path()
        ..moveTo(-.07, .3)
        ..lineTo(.07, .3)
        ..lineTo(0, .4)
        ..close(),
      fill(k.secondary),
    );
    curve(
      Path()
        ..moveTo(0, .4)
        ..lineTo(0, .5)
        ..moveTo(0, .5)
        ..quadraticBezierTo(-.1, .62, -.2, .56)
        ..moveTo(0, .5)
        ..quadraticBezierTo(.1, .62, .2, .56),
      w: .05,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-.09, .58, .09, .74),
        const Radius.circular(.03),
      ),
      fill(const Color(0xfffdfdfd)),
    );
    line(0, .58, 0, .74, w: .03);
  }

  void _fox() {
    for (final s in [-1.0, 1.0]) {
      final ear = Path()
        ..moveTo(s * .84, -.1)
        ..cubicTo(s * .96, -.56, s * .78, -.86, s * .62, -1.0)
        ..cubicTo(s * .38, -.86, s * .2, -.7, s * .1, -.5)
        ..close();
      shape(ear, k.primary);
      c.drawPath(
        Path()
          ..moveTo(s * .7, -.28)
          ..cubicTo(s * .76, -.58, s * .68, -.76, s * .6, -.82)
          ..cubicTo(s * .44, -.7, s * .32, -.58, s * .26, -.46)
          ..close(),
        fill(k.eye.withValues(alpha: .85)),
      );
    }
    final head = Path()
      ..moveTo(0, -.58)
      ..cubicTo(.54, -.58, .96, -.2, .9, .12)
      ..cubicTo(.84, .42, .42, .72, 0, .98)
      ..cubicTo(-.42, .72, -.84, .42, -.9, .12)
      ..cubicTo(-.96, -.2, -.54, -.58, 0, -.58)
      ..close();
    shape(head, k.primary);
    for (final s in [-1.0, 1.0]) {
      c.drawPath(
        Path()
          ..moveTo(s * .9, .1)
          ..cubicTo(s * .74, .5, s * .34, .66, 0, .98)
          ..cubicTo(s * .1, .52, s * .26, .22, s * .52, .1)
          ..cubicTo(s * .7, .02, s * .82, .04, s * .9, .1)
          ..close(),
        fill(k.highlight),
      );
    }
    c.drawPath(head, stroke);
    c.drawPath(
      Path()
        ..moveTo(0, -.56)
        ..quadraticBezierTo(-.18, -.34, 0, -.1)
        ..quadraticBezierTo(.18, -.34, 0, -.56)
        ..close(),
      fill(k.secondary.withValues(alpha: .7)),
    );
    eye(-.36, -.04, r: .09);
    eye(.36, -.04, r: .09);
    c.drawCircle(const Offset(0, .86), .1, fill(k.eye));
    curve(
      Path()
        ..moveTo(0, .88)
        ..lineTo(0, .94),
      w: .04,
    );
  }

  void _panda() {
    for (final s in [-1.0, 1.0]) {
      c.drawCircle(Offset(s * .6, -.6), .3, fill(k.secondary));
      c.drawCircle(Offset(s * .6, -.6), .3, stroke);
    }
    final head = Path()
      ..moveTo(0, -.72)
      ..cubicTo(.78, -.72, .94, -.14, .88, .26)
      ..cubicTo(.8, .72, .42, .9, 0, .9)
      ..cubicTo(-.42, .9, -.8, .72, -.88, .26)
      ..cubicTo(-.94, -.14, -.78, -.72, 0, -.72)
      ..close();
    shape(head, k.primary);
    for (final s in [-1.0, 1.0]) {
      c.save();
      c.translate(s * .38, -.02);
      c.rotate(s * .5);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: .36, height: .52),
        fill(k.secondary),
      );
      c.restore();
      eye(s * .38, -.04, r: .075);
    }
    oval(0, .42, .5, .36, k.highlight, outline: false);
    c.drawPath(
      Path()
        ..moveTo(-.11, .28)
        ..quadraticBezierTo(0, .22, .11, .28)
        ..quadraticBezierTo(.1, .38, 0, .4)
        ..quadraticBezierTo(-.1, .38, -.11, .28)
        ..close(),
      fill(k.secondary),
    );
    curve(
      Path()
        ..moveTo(0, .4)
        ..quadraticBezierTo(-.06, .52, -.17, .5)
        ..moveTo(0, .4)
        ..quadraticBezierTo(.06, .52, .17, .5),
      w: .05,
    );
    blush(-.62, .36);
    blush(.62, .36);
  }

  void _frog() {
    for (final s in [-1.0, 1.0]) {
      c.drawCircle(Offset(s * .46, -.56), .36, fill(k.primary));
      c.drawCircle(Offset(s * .46, -.56), .36, stroke);
    }
    final head = Path()
      ..moveTo(0, -.46)
      ..cubicTo(.8, -.46, 1.0, .06, .94, .4)
      ..cubicTo(.88, .8, .46, .94, 0, .94)
      ..cubicTo(-.46, .94, -.88, .8, -.94, .4)
      ..cubicTo(-1.0, .06, -.8, -.46, 0, -.46)
      ..close();
    shape(head, k.primary);
    oval(0, .5, 1.1, .6, k.secondary.withValues(alpha: .65), outline: false);
    for (final s in [-1.0, 1.0]) {
      eye(s * .46, -.56, r: .17);
      c.drawCircle(Offset(s * .26, .1), .045, fill(k.detail));
      blush(s * .66, .3);
    }
    curve(
      Path()
        ..moveTo(-.46, .34)
        ..quadraticBezierTo(0, .72, .46, .34),
      w: .06,
    );
    c.drawCircle(const Offset(-.14, -.4), .0, fill(k.eye));
  }

  void _penguin() {
    final body = Path()
      ..moveTo(0, -.94)
      ..cubicTo(.66, -.94, .94, -.4, .9, .16)
      ..cubicTo(.86, .66, .52, .96, 0, .96)
      ..cubicTo(-.52, .96, -.86, .66, -.9, .16)
      ..cubicTo(-.94, -.4, -.66, -.94, 0, -.94)
      ..close();
    shape(body, k.primary);
    final belly = Path()
      ..moveTo(0, -.34)
      ..cubicTo(.5, -.3, .74, .1, .66, .5)
      ..cubicTo(.58, .84, .3, .9, 0, .9)
      ..cubicTo(-.3, .9, -.58, .84, -.66, .5)
      ..cubicTo(-.74, .1, -.5, -.3, 0, -.34)
      ..close();
    c.drawPath(belly, fill(k.secondary));
    final face = Path()
      ..moveTo(0, -.62)
      ..cubicTo(-.22, -.76, -.5, -.6, -.5, -.36)
      ..cubicTo(-.5, -.12, -.2, -.1, 0, -.22)
      ..cubicTo(.2, -.1, .5, -.12, .5, -.36)
      ..cubicTo(.5, -.6, .22, -.76, 0, -.62)
      ..close();
    c.drawPath(face, fill(k.secondary));
    c.drawPath(body, stroke);
    for (final s in [-1.0, 1.0]) {
      eye(s * .26, -.4, r: .085);
      final wing = Path()
        ..moveTo(s * .84, -.1)
        ..cubicTo(s * 1.0, .1, s * .96, .46, s * .8, .62)
        ..cubicTo(s * .7, .4, s * .72, .1, s * .84, -.1)
        ..close();
      shape(wing, k.depth);
      oval(s * .3, .94, .34, .16, k.accent);
    }
    final beak = Path()
      ..moveTo(-.12, -.22)
      ..quadraticBezierTo(0, -.12, .12, -.22)
      ..quadraticBezierTo(.1, -.08, 0, -.04)
      ..quadraticBezierTo(-.1, -.08, -.12, -.22)
      ..close();
    shape(beak, k.accent);
    blush(-.5, -.18);
    blush(.5, -.18);
  }

  void _turtle() {
    for (final s in [-1.0, 1.0]) {
      oval(s * .76, .34, .38, .5, k.secondary);
      oval(s * .62, -.4, .34, .46, k.secondary);
    }
    final head = Path()
      ..moveTo(0, -.98)
      ..cubicTo(.3, -.98, .34, -.62, .3, -.5)
      ..lineTo(-.3, -.5)
      ..cubicTo(-.34, -.62, -.3, -.98, 0, -.98)
      ..close();
    shape(head, k.secondary);
    eye(-.14, -.78, r: .06);
    eye(.14, -.78, r: .06);
    curve(
      Path()
        ..moveTo(-.1, -.62)
        ..quadraticBezierTo(0, -.55, .1, -.62),
      w: .04,
    );
    final shell = Path()
      ..moveTo(0, -.58)
      ..cubicTo(.7, -.58, .94, -.1, .9, .3)
      ..cubicTo(.86, .74, .46, .94, 0, .94)
      ..cubicTo(-.46, .94, -.86, .74, -.9, .3)
      ..cubicTo(-.94, -.1, -.7, -.58, 0, -.58)
      ..close();
    shape(shell, k.primary);
    final plate = Path()
      ..moveTo(0, -.3)
      ..lineTo(.34, -.1)
      ..lineTo(.3, .3)
      ..lineTo(0, .5)
      ..lineTo(-.3, .3)
      ..lineTo(-.34, -.1)
      ..close();
    c.drawPath(plate, fill(k.depth.withValues(alpha: .9)));
    c.drawPath(plate, stroke..strokeWidth = .06);
    for (final pt in [
      const Offset(0, -.3),
      const Offset(.34, -.1),
      const Offset(.3, .3),
      const Offset(0, .5),
      const Offset(-.3, .3),
      const Offset(-.34, -.1),
    ]) {
      line(pt.dx, pt.dy, pt.dx * 2.3, pt.dy * 1.7, w: .05, color: k.outline);
    }
    c.drawArc(
      Rect.fromCircle(center: const Offset(-.2, -.2), radius: .55),
      math.pi * 1.1,
      math.pi * .35,
      false,
      Paint()
        ..color = k.highlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = .06
        ..strokeCap = StrokeCap.round,
    );
  }

  void _bee() {
    for (final s in [-1.0, 1.0]) {
      c.save();
      c.translate(s * .5, -.2);
      c.rotate(s * .55);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: .62, height: .98),
        fill(const Color(0xfff2fbff).withValues(alpha: .86)),
      );
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: .62, height: .98),
        stroke..strokeWidth = .05,
      );
      c.drawLine(
        const Offset(0, -.3),
        const Offset(0, .24),
        stroke..strokeWidth = .035,
      );
      c.restore();
    }
    final body = Path()
      ..moveTo(0, -.96)
      ..cubicTo(.54, -.96, .72, -.42, .68, .08)
      ..cubicTo(.64, .62, .34, .98, 0, .98)
      ..cubicTo(-.34, .98, -.64, .62, -.68, .08)
      ..cubicTo(-.72, -.42, -.54, -.96, 0, -.96)
      ..close();
    shape(body, k.primary);
    c.save();
    c.clipPath(body);
    for (final y in [.0, .46]) {
      c.drawRect(Rect.fromLTRB(-1, y, 1, y + .22), fill(k.secondary));
    }
    c.restore();
    c.drawPath(body, stroke);
    c.drawPath(
      Path()
        ..moveTo(0, .98)
        ..lineTo(-.06, 1.1)
        ..lineTo(.06, 1.1)
        ..close(),
      fill(k.secondary),
    );
    for (final s in [-1.0, 1.0]) {
      line(s * .12, -.9, s * .3, -1.12, w: .05);
      c.drawCircle(Offset(s * .3, -1.12), .06, fill(k.secondary));
      eye(s * .26, -.52, r: .1);
    }
    curve(
      Path()
        ..moveTo(-.12, -.32)
        ..quadraticBezierTo(0, -.22, .12, -.32),
      w: .045,
    );
  }

  void _ghost() {
    final body = Path()
      ..moveTo(0, -.96)
      ..cubicTo(.62, -.96, .84, -.5, .84, -.1)
      ..lineTo(.84, .6)
      ..cubicTo(.84, .84, .7, .94, .56, .82)
      ..cubicTo(.44, .72, .38, .72, .28, .86)
      ..cubicTo(.18, .98, .1, .98, 0, .86)
      ..cubicTo(-.1, .98, -.18, .98, -.28, .86)
      ..cubicTo(-.38, .72, -.44, .72, -.56, .82)
      ..cubicTo(-.7, .94, -.84, .84, -.84, .6)
      ..lineTo(-.84, -.1)
      ..cubicTo(-.84, -.5, -.62, -.96, 0, -.96)
      ..close();
    shape(body, k.primary);
    final shade = Path()
      ..moveTo(.84, -.1)
      ..lineTo(.84, .6)
      ..cubicTo(.84, .84, .7, .94, .56, .82)
      ..cubicTo(.6, .5, .66, .2, .5, -.1)
      ..close();
    c.drawPath(shade, fill(k.secondary.withValues(alpha: .75)));
    c.drawPath(body, stroke);
    eye(-.28, -.22, r: .13);
    eye(.28, -.22, r: .13);
    oval(0, .14, .16, .22, k.eye);
    blush(-.5, .1);
    blush(.5, .1);
    c.drawArc(
      Rect.fromCircle(center: const Offset(-.1, -.4), radius: .6),
      math.pi * 1.12,
      math.pi * .3,
      false,
      Paint()
        ..color = const Color(0xfffdfdfd).withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .07
        ..strokeCap = StrokeCap.round,
    );
  }

  // ---- machines and mythical ------------------------------------------------

  void _robot() {
    c.drawLine(
      const Offset(0, -.74),
      const Offset(0, -.96),
      stroke..strokeWidth = .07,
    );
    c.drawCircle(const Offset(0, -.98), .1, fill(k.secondary));
    c.drawCircle(const Offset(0, -.98), .1, stroke);
    for (final s in [-1.0, 1.0]) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(s * .92, .06), width: .2, height: .5),
          const Radius.circular(.08),
        ),
        fill(k.depth),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(s * .92, .06), width: .2, height: .5),
          const Radius.circular(.08),
        ),
        stroke,
      );
    }
    final head = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-.82, -.74, .82, .86),
      const Radius.circular(.34),
    );
    c.drawRRect(head, fill(k.primary));
    c.drawRRect(head, stroke);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-.62, -.52, .62, .26),
        const Radius.circular(.22),
      ),
      fill(const Color(0xff161c26)),
    );
    for (final s in [-1.0, 1.0]) {
      c.drawCircle(Offset(s * .28, -.14), .15, fill(k.secondary));
      c.drawCircle(
        Offset(s * .28, -.14),
        .15,
        fill(k.secondary.withValues(alpha: 1)),
      );
      c.drawCircle(Offset(s * .22, -.2), .045, fill(const Color(0xfffdfdfd)));
    }
    curve(
      Path()
        ..moveTo(-.22, .1)
        ..quadraticBezierTo(0, .2, .22, .1),
      w: .05,
      color: k.secondary,
    );
    for (var i = -2; i <= 2; i++) {
      line(i * .15, .54, i * .15, .72, w: .05, color: k.detail);
    }
    c.drawArc(
      Rect.fromCenter(center: const Offset(0, -.3), width: 1.4, height: 1.0),
      math.pi * 1.15,
      math.pi * .25,
      false,
      Paint()
        ..color = k.highlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = .06
        ..strokeCap = StrokeCap.round,
    );
  }

  void _ufo() {
    final beam = Path()
      ..moveTo(-.28, .42)
      ..lineTo(-.62, .98)
      ..lineTo(.62, .98)
      ..lineTo(.28, .42)
      ..close();
    c.drawPath(beam, fill(k.secondary.withValues(alpha: .32)));
    final dome = Path()
      ..moveTo(-.46, -.02)
      ..cubicTo(-.46, -.66, .46, -.66, .46, -.02)
      ..close();
    c.drawPath(dome, fill(k.secondary.withValues(alpha: .85)));
    c.drawPath(dome, stroke);
    c.drawArc(
      Rect.fromCircle(center: const Offset(-.1, -.3), radius: .26),
      math.pi * 1.1,
      math.pi * .45,
      false,
      Paint()
        ..color = const Color(0xfffdfdfd).withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .06
        ..strokeCap = StrokeCap.round,
    );
    final saucer = Path()
      ..moveTo(-.96, .2)
      ..cubicTo(-.96, -.06, -.5, -.12, 0, -.12)
      ..cubicTo(.5, -.12, .96, -.06, .96, .2)
      ..cubicTo(.96, .5, .5, .58, 0, .58)
      ..cubicTo(-.5, .58, -.96, .5, -.96, .2)
      ..close();
    shape(saucer, k.primary);
    c.drawPath(
      Path()
        ..moveTo(-.96, .2)
        ..cubicTo(-.96, .5, -.5, .58, 0, .58)
        ..cubicTo(.5, .58, .96, .5, .96, .2)
        ..cubicTo(.7, .36, -.7, .36, -.96, .2)
        ..close(),
      fill(k.depth),
    );
    c.drawPath(saucer, stroke);
    for (final x in [-.62, -.2, .2, .62]) {
      c.drawCircle(Offset(x, .22), .075, fill(k.secondary));
    }
  }

  void _flame() {
    final outer = Path()
      ..moveTo(.04, -1.0)
      ..cubicTo(.18, -.62, .86, -.34, .82, .24)
      ..cubicTo(.78, .74, .4, .98, 0, .98)
      ..cubicTo(-.4, .98, -.82, .74, -.82, .26)
      ..cubicTo(-.82, -.04, -.52, -.2, -.5, -.5)
      ..cubicTo(-.24, -.4, -.1, -.72, .04, -1.0)
      ..close();
    shape(outer, k.primary);
    final mid = Path()
      ..moveTo(0, -.32)
      ..cubicTo(.1, -.12, .56, .02, .52, .42)
      ..cubicTo(.48, .76, .24, .86, 0, .86)
      ..cubicTo(-.24, .86, -.52, .76, -.52, .46)
      ..cubicTo(-.52, .2, -.24, .1, -.2, -.1)
      ..cubicTo(-.1, -.08, -.04, -.2, 0, -.32)
      ..close();
    c.drawPath(mid, fill(k.secondary));
    final core = Path()
      ..moveTo(0, .1)
      ..cubicTo(.06, .22, .3, .3, .28, .54)
      ..cubicTo(.26, .74, .12, .78, 0, .78)
      ..cubicTo(-.12, .78, -.28, .74, -.28, .56)
      ..cubicTo(-.28, .36, -.06, .3, 0, .1)
      ..close();
    c.drawPath(core, fill(k.highlight));
    eye(-.18, .46, r: .06, shine: false);
    eye(.18, .46, r: .06, shine: false);
  }

  void _dragon() {
    for (final s in [-1.0, 1.0]) {
      final wing = Path()
        ..moveTo(s * .72, -.1)
        ..cubicTo(s * 1.1, -.2, s * 1.2, -.52, s * 1.14, -.74)
        ..cubicTo(s * 1.0, -.62, s * .9, -.62, s * .84, -.56)
        ..cubicTo(s * .86, -.44, s * .76, -.4, s * .66, -.4)
        ..close();
      shape(wing, k.secondary);
      final horn = Path()
        ..moveTo(s * .3, -.62)
        ..cubicTo(s * .34, -.88, s * .52, -1.02, s * .68, -1.04)
        ..cubicTo(s * .6, -.88, s * .56, -.74, s * .5, -.56)
        ..close();
      shape(horn, k.highlight);
    }
    final head = Path()
      ..moveTo(0, -.7)
      ..cubicTo(.54, -.7, .78, -.32, .72, .06)
      ..cubicTo(.68, .42, .52, .76, .34, .9)
      ..lineTo(-.34, .9)
      ..cubicTo(-.52, .76, -.68, .42, -.72, .06)
      ..cubicTo(-.78, -.32, -.54, -.7, 0, -.7)
      ..close();
    shape(head, k.primary);
    for (final y in [-.56, -.4, -.24]) {
      final spike = Path()
        ..moveTo(-.1, y)
        ..lineTo(0, y - .14)
        ..lineTo(.1, y)
        ..close();
      c.drawPath(spike, fill(k.secondary));
    }
    final snout = Path()
      ..moveTo(0, .1)
      ..cubicTo(.42, .1, .5, .5, .44, .72)
      ..cubicTo(.4, .88, .2, .94, 0, .94)
      ..cubicTo(-.2, .94, -.4, .88, -.44, .72)
      ..cubicTo(-.5, .5, -.42, .1, 0, .1)
      ..close();
    c.drawPath(snout, fill(k.highlight));
    c.drawPath(snout, stroke..strokeWidth = .06);
    for (final s in [-1.0, 1.0]) {
      c.drawCircle(Offset(s * .15, .6), .045, fill(k.eye));
      c.save();
      c.translate(s * .38, -.14);
      c.rotate(s * -.35);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: .34, height: .24),
        fill(const Color(0xfffdfdfd)),
      );
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: .34, height: .24),
        stroke..strokeWidth = .05,
      );
      c.drawOval(
        Rect.fromCenter(center: const Offset(0, .01), width: .1, height: .2),
        fill(k.eye),
      );
      c.restore();
      line(s * .26, -.42, s * .52, -.32, w: .06);
    }
    for (final s in [-1.0, 1.0]) {
      final tooth = Path()
        ..moveTo(s * .22, .86)
        ..lineTo(s * .28, .98)
        ..lineTo(s * .34, .86)
        ..close();
      c.drawPath(tooth, fill(const Color(0xfffdfdfd)));
    }
  }

  void _phoenix() {
    for (final s in [-1.0, 1.0]) {
      for (var i = 0; i < 3; i++) {
        final t = i / 2;
        final feather = Path()
          ..moveTo(s * .3, .1 - t * .14)
          ..cubicTo(
            s * (.68 + t * .1),
            -.12 - t * .3,
            s * (.98 - t * .1),
            -.2 - t * .3,
            s * (1.04 - t * .06),
            .06 + t * .3 - .5,
          )
          ..cubicTo(
            s * (.96 - t * .1),
            .26 - t * .1,
            s * (.62 - t * .1),
            .34,
            s * .3,
            .24,
          )
          ..close();
        shape(feather, i == 0 ? k.secondary : (i == 1 ? k.primary : k.accent));
      }
    }
    final tail = Path()
      ..moveTo(0, .4)
      ..cubicTo(-.3, .6, -.5, .86, -.34, 1.04)
      ..cubicTo(-.2, .94, -.12, .9, 0, .84)
      ..cubicTo(.12, .9, .2, .94, .34, 1.04)
      ..cubicTo(.5, .86, .3, .6, 0, .4)
      ..close();
    shape(tail, k.secondary);
    final body = Path()
      ..moveTo(0, -.7)
      ..cubicTo(.34, -.7, .46, -.34, .4, .1)
      ..cubicTo(.34, .5, .2, .72, 0, .72)
      ..cubicTo(-.2, .72, -.34, .5, -.4, .1)
      ..cubicTo(-.46, -.34, -.34, -.7, 0, -.7)
      ..close();
    shape(body, k.primary);
    c.drawPath(
      Path()
        ..moveTo(0, -.1)
        ..cubicTo(.2, -.06, .26, .2, .2, .42)
        ..cubicTo(.14, .6, .06, .62, 0, .62)
        ..cubicTo(-.06, .62, -.14, .6, -.2, .42)
        ..cubicTo(-.26, .2, -.2, -.06, 0, -.1)
        ..close(),
      fill(k.highlight),
    );
    for (final dx in [-.22, 0.0, .22]) {
      final crest = Path()
        ..moveTo(dx - .08, -.62)
        ..cubicTo(dx - .1, -.84, dx, -.96, dx + .04, -1.04)
        ..cubicTo(dx + .1, -.9, dx + .12, -.74, dx + .08, -.62)
        ..close();
      shape(crest, dx == 0 ? k.accent : k.secondary);
    }
    final beak = Path()
      ..moveTo(-.1, -.44)
      ..quadraticBezierTo(0, -.2, .1, -.44)
      ..quadraticBezierTo(.06, -.36, 0, -.3)
      ..quadraticBezierTo(-.06, -.36, -.1, -.44)
      ..close();
    shape(beak, k.detail);
    for (final s in [-1.0, 1.0]) {
      eye(s * .17, -.52, r: .065);
    }
  }

  void _rocket() {
    for (final s in [-1.0, 1.0]) {
      final fin = Path()
        ..moveTo(s * .34, .24)
        ..cubicTo(s * .7, .3, s * .92, .62, s * .88, .94)
        ..cubicTo(s * .7, .9, s * .46, .8, s * .34, .72)
        ..close();
      shape(fin, k.secondary);
    }
    final flame = Path()
      ..moveTo(-.22, .8)
      ..cubicTo(-.28, 1.0, -.1, 1.04, 0, 1.12)
      ..cubicTo(.1, 1.04, .28, 1.0, .22, .8)
      ..close();
    c.drawPath(flame, fill(k.accent));
    c.drawPath(
      Path()
        ..moveTo(-.1, .8)
        ..quadraticBezierTo(0, 1.02, .1, .8)
        ..close(),
      fill(k.highlight),
    );
    final body = Path()
      ..moveTo(0, -1.0)
      ..cubicTo(.4, -.78, .54, -.28, .5, .3)
      ..cubicTo(.48, .62, .4, .8, .3, .86)
      ..lineTo(-.3, .86)
      ..cubicTo(-.4, .8, -.48, .62, -.5, .3)
      ..cubicTo(-.54, -.28, -.4, -.78, 0, -1.0)
      ..close();
    shape(body, k.primary);
    final cone = Path()
      ..moveTo(0, -1.0)
      ..cubicTo(.26, -.86, .38, -.6, .42, -.46)
      ..lineTo(-.42, -.46)
      ..cubicTo(-.38, -.6, -.26, -.86, 0, -1.0)
      ..close();
    c.save();
    c.clipPath(body);
    c.drawPath(cone, fill(k.secondary));
    c.restore();
    c.drawPath(body, stroke);
    line(-.42, -.46, .42, -.46, w: .06);
    c.drawCircle(const Offset(0, -.08), .26, fill(k.outline));
    c.drawCircle(const Offset(0, -.08), .2, fill(const Color(0xff8fd4ee)));
    c.drawArc(
      Rect.fromCircle(center: const Offset(0, -.08), radius: .14),
      math.pi * 1.1,
      math.pi * .5,
      false,
      Paint()
        ..color = const Color(0xfffdfdfd)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .05
        ..strokeCap = StrokeCap.round,
    );
    line(-.4, .5, .4, .5, w: .05, color: k.detail);
    c.drawArc(
      Rect.fromCenter(center: const Offset(-.18, -.2), width: .5, height: 1.2),
      math.pi * 1.0,
      math.pi * .3,
      false,
      Paint()
        ..color = k.highlight.withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .06
        ..strokeCap = StrokeCap.round,
    );
  }
}

/// A catalogue or preview tip. Characters stand upright unless a facing is
/// given; gameplay passes the route facing instead.
class TipArtwork extends StatelessWidget {
  const TipArtwork({
    required this.tip,
    required this.palette,
    this.quarterTurns = 3,
    this.scale = .41,
    super.key,
  });
  final PathTip tip;
  final BoardPalette palette;
  final int quarterTurns;
  final double scale;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '${tip.label} path tip',
    child: AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _TipArtPainter(tip, palette, quarterTurns, scale),
      ),
    ),
  );
}

class _TipArtPainter extends CustomPainter {
  _TipArtPainter(this.tip, this.palette, this.quarterTurns, this.scale);
  final PathTip tip;
  final BoardPalette palette;
  final int quarterTurns;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) => paintPathTip(
    canvas,
    size.center(Offset.zero),
    size.shortestSide * scale * (tip == PathTip.classic ? .9 : 1.0),
    tip,
    palette,
    quarterTurns: quarterTurns,
  );
  @override
  bool shouldRepaint(_TipArtPainter old) =>
      old.tip != tip ||
      old.palette != palette ||
      old.quarterTurns != quarterTurns ||
      old.scale != scale;
}
