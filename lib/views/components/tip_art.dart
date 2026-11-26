import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/economy.dart';
import '../../model/user_preferences.dart';
import '../../ui/art/game_assets.dart';

/// Per-tip rendering metadata so every cosmetic tip shares a consistent
/// attachment, orientation, and visual footprint relative to the path.
final class TipRenderSpec {
  const TipRenderSpec({
    this.directional = false,
    this.nativeAngle = -math.pi / 2,
    this.scale = 1.16,
    this.forwardLead = 0.0,
  });

  /// Whether the tip rotates to face the active movement direction.
  final bool directional;

  /// Native forward direction (radians in Y-down canvas) of the source WebP.
  /// 0 = right, pi/2 = down, pi = left, -pi/2 = up.
  final double nativeAngle;

  /// Visual scale multiplier relative to the base tip radius.
  final double scale;

  /// Slight forward offset along the facing vector (in radius units) so the
  /// rear of directional tips seats directly onto the path endpoint.
  final double forwardLead;
}

const _defaultTipSpec = TipRenderSpec();

const tipRenderSpecs = <PathTip, TipRenderSpec>{
  PathTip.classic: TipRenderSpec(scale: 1.14),
  PathTip.arrow: TipRenderSpec(
    directional: true,
    nativeAngle: 0,
    scale: 1.08,
    forwardLead: 0.14,
  ),
  PathTip.turtle: TipRenderSpec(
    directional: true,
    nativeAngle: -math.pi / 4,
    scale: 1.14,
    forwardLead: 0.06,
  ),
  PathTip.rocket: TipRenderSpec(
    directional: true,
    nativeAngle: -math.pi / 2,
    scale: 1.16,
    forwardLead: 0.10,
  ),
  PathTip.bee: TipRenderSpec(scale: 1.14),
  PathTip.dragon: TipRenderSpec(scale: 1.16),
  PathTip.phoenix: TipRenderSpec(scale: 1.16),
};

TipRenderSpec tipSpecFor(PathTip tip) => tipRenderSpecs[tip] ?? _defaultTipSpec;

bool _isHighContrast(BoardPalette palette) =>
    palette == BoardPalette.palettes[PathwiseTheme.signal] ||
    palette == BoardPalette.palettes[PathwiseTheme.amoledCarbon];

/// Paints the equipped [PathTip] at [center] using its production WebP artwork.
/// High Contrast themes receive an accessible luminous halo ring around the
/// artwork rather than falling back to obsolete vector silhouettes.
void paintPathTip(
  Canvas canvas,
  Offset center,
  double radius,
  PathTip tip,
  BoardPalette palette, {
  int quarterTurns = 3,
  double? angleRadians,
  bool concealed = false,
  bool catalogue = false,
}) {
  final highContrast = _isHighContrast(palette);
  final spec = tipSpecFor(tip);
  final drawRadius = radius * spec.scale;
  final targetAngle = angleRadians ?? (quarterTurns % 4) * (math.pi / 2);
  final drawCenter = !catalogue && spec.directional && spec.forwardLead != 0
      ? center +
            Offset(math.cos(targetAngle), math.sin(targetAngle)) *
                (radius * spec.forwardLead)
      : center;

  if (highContrast && !concealed) {
    canvas.drawCircle(
      drawCenter,
      drawRadius * 1.04,
      Paint()
        ..color = palette.canvas
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      drawCenter,
      drawRadius * 1.04,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.14,
    );
  } else if (!catalogue && !concealed) {
    canvas.drawCircle(
      drawCenter.translate(radius * .05, radius * .09),
      drawRadius * .90,
      Paint()
        ..color = Colors.black.withValues(alpha: palette.dark ? .40 : .22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .12),
    );
  }

  final raster = GameAssetCache.instance.imageFor(tipAssetPath(tip));
  if (raster != null) {
    canvas.save();
    canvas.translate(drawCenter.dx, drawCenter.dy);
    if (spec.directional) {
      canvas.rotate(targetAngle - spec.nativeAngle);
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
  canvas.drawCircle(drawCenter, radius * .78, Paint()..color = fallbackColor);
  if (!concealed) {
    canvas.drawCircle(
      drawCenter,
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
