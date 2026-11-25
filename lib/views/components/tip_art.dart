import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/economy.dart';
import '../../model/user_preferences.dart';
import '../../ui/art/game_assets.dart';

bool _rotatesWithDirection(PathTip tip) => switch (tip) {
  PathTip.arrow ||
  PathTip.turtle ||
  PathTip.bee ||
  PathTip.dragon ||
  PathTip.phoenix ||
  PathTip.rocket => true,
  _ => false,
};

bool _isHighContrast(BoardPalette palette) =>
    palette == BoardPalette.palettes[PathwiseTheme.signal] ||
    palette == BoardPalette.palettes[PathwiseTheme.amoledCarbon];

/// Paints the equipped [PathTip] at [center] using its production PNG artwork.
/// High Contrast themes receive an accessible luminous halo ring around the
/// artwork rather than falling back to obsolete vector silhouettes.
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
  final highContrast = _isHighContrast(palette);
  final drawRadius = radius * 1.18;

  if (highContrast && !concealed) {
    canvas.drawCircle(
      center,
      drawRadius * 1.04,
      Paint()
        ..color = palette.canvas
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      drawRadius * 1.04,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.14,
    );
  } else if (!catalogue && !concealed) {
    canvas.drawCircle(
      center.translate(radius * .05, radius * .09),
      drawRadius * .92,
      Paint()
        ..color = Colors.black.withValues(alpha: palette.dark ? .40 : .22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .12),
    );
  }

  final raster = GameAssetCache.instance.imageFor(tipAssetPath(tip));
  if (raster != null) {
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
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (concealed) {
      paint.colorFilter = ColorFilter.mode(
        Color.lerp(palette.tile, palette.ink, .28)!,
        BlendMode.srcIn,
      );
    }
    canvas.drawImageRect(raster, src, dst, paint);
    canvas.restore();
    return;
  }

  // Minimal geometric placeholder only while an async image decode completes
  // in headless tests without asset bundles.
  final fallbackColor = concealed
      ? Color.lerp(palette.tile, palette.ink, .28)!
      : (highContrast ? palette.accent : palette.route);
  canvas.drawCircle(center, radius * .78, Paint()..color = fallbackColor);
  if (!concealed) {
    canvas.drawCircle(
      center,
      radius * .78,
      Paint()
        ..color = palette.onRoute
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, radius * .12),
    );
  }
}

/// Square catalogue/preview widget for any [PathTip] (all 20 tips use PNG art).
class TipArtwork extends StatelessWidget {
  const TipArtwork({
    required this.tip,
    required this.palette,
    this.scale = .62,
    this.concealed = false,
    super.key,
  });

  final PathTip tip;
  final BoardPalette palette;
  final double scale;
  final bool concealed;

  @override
  Widget build(BuildContext context) {
    final highContrast = _isHighContrast(palette);
    final shadowColor = Color.lerp(palette.tile, palette.ink, .28)!;
    final img = Image.asset(
      tipAssetPath(tip),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      color: concealed ? shadowColor : null,
      colorBlendMode: concealed ? BlendMode.srcIn : null,
      errorBuilder: (_, _, _) => CustomPaint(
        painter: _TipPlaceholderPainter(
          tip: tip,
          palette: palette,
          concealed: concealed,
        ),
      ),
    );
    final Widget badge = !highContrast || concealed
        ? img
        : DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.accent, width: 2),
            ),
            child: Padding(padding: const EdgeInsets.all(3), child: img),
          );
    return Semantics(
      image: true,
      label: concealed ? 'Undiscovered path tip' : '${tip.label} path tip',
      child: badge,
    );
  }
}

class _TipPlaceholderPainter extends CustomPainter {
  const _TipPlaceholderPainter({
    required this.tip,
    required this.palette,
    required this.concealed,
  });

  final PathTip tip;
  final BoardPalette palette;
  final bool concealed;

  @override
  void paint(Canvas canvas, Size size) {
    paintPathTip(
      canvas,
      size.center(Offset.zero),
      size.shortestSide * .38,
      tip,
      palette,
      concealed: concealed,
      catalogue: true,
    );
  }

  @override
  bool shouldRepaint(_TipPlaceholderPainter old) =>
      old.tip != tip || old.palette != palette || old.concealed != concealed;
}
