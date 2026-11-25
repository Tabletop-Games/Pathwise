import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/path_tips.dart';
import '../../model/user_preferences.dart';
import '../../ui/art/directional_tip_shapes.dart';
import '../../ui/art/game_assets.dart';
import '../../ui/art/tip_shapes.dart';
import '../../ui/art/vector_path.dart';

final _art = {
  for (final MapEntry(key: tip, value: shape) in tipShapes.entries)
    tip: (
      Color(0xff000000 | shape.$1),
      compileVector(shape.$2),
      compileVector(shape.$3),
      compileVector(shape.$4),
    ),
};
final _directionalArt = {
  for (final MapEntry(key: tip, value: shape) in directionalTipShapes.entries)
    tip: (
      Color(0xff000000 | tipShapes[tip]!.$1),
      compileVector(shape.$1),
      compileVector(shape.$2),
      compileVector(shape.$3),
    ),
};
final _inks = <(BoardPalette, PathTip), (Paint, Paint, Paint, Paint, Paint)>{};

const _artBounds = Rect.fromLTWH(0, 0, 24, 24);

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

(Paint, Paint, Paint, Paint, Paint) _palette(
  BoardPalette palette,
  PathTip tip,
  Color seed,
) => _inks.putIfAbsent((palette, tip), () {
  final highContrast = palette == BoardPalette.palettes[PathwiseTheme.signal];
  var base = Color.lerp(seed, palette.route, .18)!;
  if (highContrast) {
    base = palette.accent;
  } else if (_contrast(base, palette.tile) < 1.65) {
    base = Color.lerp(base, palette.ink, .27)!;
  }
  final light = Color.lerp(
    base,
    palette.dark ? palette.ink : palette.surface,
    .54,
  )!;
  final detail = highContrast
      ? palette.onAccent
      : Color.lerp(base, palette.dark ? palette.canvas : palette.ink, .70)!;
  final edge = highContrast
      ? palette.onAccent
      : _contrast(base, palette.route) < 1.8
      ? palette.onRoute
      : Color.lerp(base, palette.ink, .28)!;
  return (
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(
            base,
            Colors.white,
            highContrast ? .08 : (palette.dark ? .22 : .26),
          )!,
          base,
          Color.lerp(base, Colors.black, highContrast ? .12 : .24)!,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(_artBounds),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(light, Colors.white, highContrast ? .10 : .28)!,
          light,
          Color.lerp(light, base, highContrast ? .08 : .20)!,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(_artBounds),
    Paint()..color = detail,
    Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = highContrast ? 1.25 : .75
      ..strokeJoin = StrokeJoin.round,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.center,
        colors: [
          Colors.white.withValues(alpha: highContrast ? .22 : .42),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(_artBounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85
      ..strokeJoin = StrokeJoin.round,
  );
});

bool _rotatesWithDirection(PathTip tip) => switch (tip) {
  PathTip.arrow ||
  PathTip.turtle ||
  PathTip.bee ||
  PathTip.dragon ||
  PathTip.phoenix ||
  PathTip.rocket => true,
  _ => false,
};

/// A single vector is shared by the active tip, the catalogue and the album.
/// Rotation uses the existing cardinal direction without changing its radius.
void paintPathTip(
  Canvas canvas,
  Offset center,
  double radius,
  PathTip tip,
  BoardPalette palette, {
  int quarterTurns = 3,
  bool concealed = false,
  bool catalogue = false,
}) {
  final highContrast = palette == BoardPalette.palettes[PathwiseTheme.signal];
  if (tip != PathTip.classic && !concealed) {
    final raster = GameAssetCache.instance.imageFor(tipAssetPath(tip));
    if (raster != null) {
      final drawRadius = radius * (tip == PathTip.classic ? 1.25 : 1.18);
      if (!catalogue) {
        canvas.drawCircle(
          center.translate(radius * .05, radius * .09),
          drawRadius * .92,
          Paint()
            ..color = Colors.black.withValues(alpha: palette.dark ? .40 : .22)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .12),
        );
      }
      canvas.save();
      canvas.translate(center.dx, center.dy);
      if (_rotatesWithDirection(tip)) {
        canvas.rotate((quarterTurns - 3) * math.pi / 2);
      }
      final src = Rect.fromLTWH(
        0,
        0,
        raster.width.toDouble(),
        raster.height.toDouble(),
      );
      final dst = Rect.fromCircle(center: Offset.zero, radius: drawRadius);
      canvas.drawImageRect(
        raster,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
      return;
    }
  }
  if (tip == PathTip.classic) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (concealed) {
      canvas.drawCircle(
        Offset.zero,
        radius * .95,
        Paint()..color = Color.lerp(palette.tile, palette.ink, .24)!,
      );
      canvas.restore();
      return;
    }
    if (!catalogue) {
      canvas.drawCircle(
        Offset(radius * .05, radius * .09),
        radius * .96,
        Paint()
          ..color = Colors.black.withValues(alpha: palette.dark ? .40 : .22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .10),
      );
    }
    final outerRect = Rect.fromCircle(
      center: Offset.zero,
      radius: radius * .95,
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .95,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 1.05,
          colors: highContrast
              ? [
                  Color.lerp(palette.route, Colors.white, .10)!,
                  palette.route,
                  Color.lerp(palette.route, Colors.black, .15)!,
                ]
              : [
                  Color.lerp(
                    palette.route,
                    Colors.white,
                    palette.dark ? .20 : .24,
                  )!,
                  palette.route,
                  Color.lerp(palette.route, Colors.black, .22)!,
                ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(outerRect),
    );
    final innerRect = Rect.fromCircle(
      center: Offset.zero,
      radius: radius * .57,
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .57,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: highContrast
              ? [
                  palette.accent,
                  palette.accent,
                  Color.lerp(palette.accent, Colors.black, .12)!,
                ]
              : [
                  palette.accent,
                  palette.accent,
                  Color.lerp(palette.accent, Colors.black, .20)!,
                ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(innerRect),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .75,
      Paint()
        ..color = palette.onRoute.withValues(alpha: .48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .09,
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .91,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: highContrast ? .28 : .42),
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: .18),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(outerRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .07,
    );
    canvas.drawCircle(
      Offset(-radius * .26, -radius * .26),
      radius * .16,
      Paint()
        ..color = Colors.white.withValues(alpha: highContrast ? .24 : .38)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .05),
    );
    canvas.restore();
    return;
  }

  final (seed, silhouette, light, detail) =
      (catalogue ? null : _directionalArt[tip]) ?? _art[tip]!;
  if (!catalogue && !concealed) {
    canvas.save();
    canvas.translate(center.dx + radius * .05, center.dy + radius * .09);
    canvas.rotate((quarterTurns - 3) * math.pi / 2);
    canvas.scale(radius / 12);
    canvas.translate(-12, -12);
    canvas.drawPath(
      silhouette,
      Paint()
        ..color = Colors.black.withValues(alpha: palette.dark ? .40 : .22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.restore();
  }
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate((quarterTurns - 3) * math.pi / 2);
  canvas.scale(radius / 12);
  canvas.translate(-12, -12);
  if (concealed) {
    canvas.drawPath(
      silhouette,
      Paint()..color = Color.lerp(palette.tile, palette.ink, .24)!,
    );
  } else {
    final (baseInk, lightInk, detailInk, edgeInk, sheenInk) = _palette(
      palette,
      tip,
      seed,
    );
    canvas.drawPath(silhouette, baseInk);
    canvas.drawPath(light, lightInk);
    canvas.drawPath(detail, detailInk);
    canvas.save();
    canvas.clipPath(silhouette);
    canvas.drawPath(silhouette, sheenInk);
    canvas.restore();
    if (!catalogue || highContrast) {
      canvas.drawPath(silhouette, edgeInk);
    }
  }
  canvas.restore();
}

class TipArtwork extends StatelessWidget {
  const TipArtwork({
    required this.tip,
    required this.palette,
    this.quarterTurns = 3,
    this.scale = .41,
    this.concealed = false,
    super.key,
  });
  final PathTip tip;
  final BoardPalette palette;
  final int quarterTurns;
  final double scale;
  final bool concealed;
  @override
  Widget build(BuildContext context) {
    final Widget fallback = CustomPaint(
      painter: _TipArtPainter(tip, palette, quarterTurns, scale, concealed),
    );
    final Widget art = tip == PathTip.classic
        ? fallback
        : FractionallySizedBox(
            widthFactor: (scale * 2.0).clamp(0.6, 1.0),
            heightFactor: (scale * 2.0).clamp(0.6, 1.0),
            child: Image.asset(
              tipAssetPath(tip),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              color: concealed
                  ? Color.lerp(palette.tile, palette.ink, .24)
                  : null,
              colorBlendMode: concealed ? BlendMode.srcIn : null,
              errorBuilder: (_, _, _) => fallback,
            ),
          );
    return Semantics(
      image: true,
      label: concealed ? 'Undiscovered' : '${tip.label} path tip',
      child: AspectRatio(aspectRatio: 1, child: art),
    );
  }
}

class _TipArtPainter extends CustomPainter {
  _TipArtPainter(
    this.tip,
    this.palette,
    this.quarterTurns,
    this.scale,
    this.concealed,
  );
  final PathTip tip;
  final BoardPalette palette;
  final int quarterTurns;
  final double scale;
  final bool concealed;
  @override
  void paint(Canvas canvas, Size size) => paintPathTip(
    canvas,
    size.center(Offset.zero),
    size.shortestSide * scale * (tip == PathTip.classic ? .9 : 1.0),
    tip,
    palette,
    quarterTurns: quarterTurns,
    concealed: concealed,
    catalogue: true,
  );
  @override
  bool shouldRepaint(_TipArtPainter old) =>
      old.tip != tip ||
      old.palette != palette ||
      old.quarterTurns != quarterTurns ||
      old.scale != scale ||
      old.concealed != concealed;
}
