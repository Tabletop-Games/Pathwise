import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/economy.dart';
import '../../model/user_preferences.dart';
import '../../ui/art/game_assets.dart';

/// Per-tip rendering metadata so every cosmetic tip shares a consistent
/// upright scale and visual footprint relative to the path.
final class TipRenderSpec {
  const TipRenderSpec({this.scale = 1.16});

  /// Visual scale multiplier relative to the base tip radius.
  final double scale;
}

const _defaultTipSpec = TipRenderSpec();

const tipRenderSpecs = <PathTip, TipRenderSpec>{
  PathTip.classic: TipRenderSpec(scale: 1.14),
  PathTip.turtle: TipRenderSpec(scale: 1.14),
  PathTip.rocket: TipRenderSpec(scale: 1.16),
  PathTip.bee: TipRenderSpec(scale: 1.14),
  PathTip.dragon: TipRenderSpec(scale: 1.16),
  PathTip.phoenix: TipRenderSpec(scale: 1.16),
};

TipRenderSpec tipSpecFor(PathTip tip) => tipRenderSpecs[tip] ?? _defaultTipSpec;

bool _isHighContrast(BoardPalette palette) =>
    palette == BoardPalette.palettes[PathwiseTheme.signal] ||
    palette == BoardPalette.palettes[PathwiseTheme.amoledCarbon];

/// Paints the equipped [PathTip] upright at [center] using its production WebP
/// artwork. High Contrast themes receive an accessible luminous halo ring
/// around the artwork.
void paintPathTip(
  Canvas canvas,
  Offset center,
  double radius,
  PathTip tip,
  BoardPalette palette, {
  bool concealed = false,
  bool catalogue = false,
}) {
  final highContrast = _isHighContrast(palette);
  final spec = tipSpecFor(tip);
  final drawRadius = radius * spec.scale;

  if (highContrast && !concealed && !catalogue) {
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
  }

  final raster = GameAssetCache.instance.imageFor(tipAssetPath(tip));
  if (raster != null) {
    final src = Rect.fromLTWH(
      0,
      0,
      raster.width.toDouble(),
      raster.height.toDouble(),
    );
    final dst = Rect.fromCircle(center: center, radius: drawRadius);
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (concealed) {
      paint.colorFilter = ColorFilter.mode(
        Color.lerp(palette.tile, palette.ink, .28)!,
        BlendMode.srcIn,
      );
    }
    canvas.drawImageRect(raster, src, dst, paint);
    return;
  }
}

/// Square catalogue/preview widget for any [PathTip].
class TipArtwork extends StatelessWidget {
  const TipArtwork({
    required this.tip,
    required this.palette,
    this.concealed = false,
    this.showContrastRing = false,
    super.key,
  });

  final PathTip tip;
  final BoardPalette palette;
  final bool concealed;
  final bool showContrastRing;

  @override
  Widget build(BuildContext context) {
    final highContrast = showContrastRing && _isHighContrast(palette);
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
          showContrastRing: showContrastRing,
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
    required this.showContrastRing,
  });

  final PathTip tip;
  final BoardPalette palette;
  final bool concealed;
  final bool showContrastRing;

  @override
  void paint(Canvas canvas, Size size) {
    paintPathTip(
      canvas,
      size.center(Offset.zero),
      size.shortestSide * .38,
      tip,
      palette,
      concealed: concealed,
      catalogue: !showContrastRing,
    );
  }

  @override
  bool shouldRepaint(_TipPlaceholderPainter old) =>
      old.tip != tip ||
      old.palette != palette ||
      old.concealed != concealed ||
      old.showContrastRing != showContrastRing;
}
