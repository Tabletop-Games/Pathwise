import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/path_tips.dart';
import '../../model/user_preferences.dart';
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
final _inks = <(BoardPalette, PathTip), (Paint, Paint, Paint, Paint)>{};

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

(Paint, Paint, Paint, Paint) _palette(
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
    Paint()..color = base,
    Paint()..color = light,
    Paint()..color = detail,
    Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = highContrast ? 1.25 : .75
      ..strokeJoin = StrokeJoin.round,
  );
});

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
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate((quarterTurns - 3) * math.pi / 2);
  if (tip == PathTip.classic) {
    canvas.drawCircle(
      Offset.zero,
      radius * .95,
      Paint()..color = palette.route,
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .57,
      Paint()..color = palette.accent,
    );
  } else {
    final (seed, silhouette, light, detail) = _art[tip]!;
    canvas.scale(radius / 12);
    canvas.translate(-12, -12);
    if (concealed) {
      canvas.drawPath(
        silhouette,
        Paint()..color = Color.lerp(palette.tile, palette.ink, .24)!,
      );
    } else {
      final (baseInk, lightInk, detailInk, edgeInk) = _palette(
        palette,
        tip,
        seed,
      );
      canvas.drawPath(silhouette, baseInk);
      canvas.drawPath(light, lightInk);
      canvas.drawPath(detail, detailInk);
      if (!catalogue ||
          palette == BoardPalette.palettes[PathwiseTheme.signal]) {
        canvas.drawPath(silhouette, edgeInk);
      }
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
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: concealed ? 'Undiscovered' : '${tip.label} path tip',
    child: AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _TipArtPainter(tip, palette, quarterTurns, scale, concealed),
      ),
    ),
  );
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
