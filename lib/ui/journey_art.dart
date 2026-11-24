import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../model/app_themes.dart';
import '../model/user_preferences.dart';

class JourneyArt extends StatelessWidget {
  const JourneyArt(
    this.palette, {
    this.chapter = 0,
    this.height = 128,
    super.key,
  });
  final BoardPalette palette;
  final int chapter;
  final double height;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: double.infinity,
      height:
          palette == BoardPalette.palettes[PathwiseTheme.amoledCarbon] ||
              palette == BoardPalette.palettes[PathwiseTheme.signal]
          ? 12
          : height,
      child: CustomPaint(painter: _Landscape(palette, chapter)),
    ),
  );
}

class _Landscape extends CustomPainter {
  const _Landscape(this.palette, this.chapter);
  final BoardPalette palette;
  final int chapter;

  @override
  void paint(Canvas canvas, Size size) {
    if (palette == BoardPalette.palettes[PathwiseTheme.amoledCarbon] ||
        palette == BoardPalette.palettes[PathwiseTheme.signal])
      return;
    canvas.save();
    canvas.scale(size.width / 320, size.height / 128);
    final route = Paint()
      ..color = palette.route.withValues(alpha: .47)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    final land = Paint()..color = palette.route.withValues(alpha: .09);
    final sun = Paint()..color = palette.accent.withValues(alpha: .55);
    bool uses(PathwiseTheme theme) => palette == BoardPalette.palettes[theme];
    final sea = uses(PathwiseTheme.oceanicBreeze) || uses(PathwiseTheme.tidal);
    final frost = uses(PathwiseTheme.glacier) || uses(PathwiseTheme.highPass);
    final grove = uses(PathwiseTheme.forestMint);
    final dunes = uses(PathwiseTheme.terracotta) || uses(PathwiseTheme.canyon);
    final night =
        uses(PathwiseTheme.midnightSlate) || uses(PathwiseTheme.blackwater);
    final phase = chapter * .8;
    final horizon = 36 + 8 * math.cos(phase);
    canvas.drawCircle(
      Offset(235 + 25 * math.sin(phase), horizon),
      night ? 13 : 19,
      sun,
    );
    if (night || frost) {
      final haze = Paint()..color = palette.ink.withValues(alpha: .27);
      for (var i = 0; i < 10; i++) {
        canvas.drawCircle(
          Offset(21.0 + i * 28, 17.0 + i * 13 % 32),
          i.isEven ? 1.4 : .85,
          haze,
        );
      }
    }
    for (var layer = 0; layer < 4; layer++) {
      final hill = Path();
      for (var x = 0; x <= 320; x += 4) {
        final wave = math.sin(
          x /
                  (sea
                      ? 26
                      : dunes
                      ? 72
                      : 47) +
              layer * .64 +
              phase,
        );
        final y =
            68 +
            layer * 13 +
            (frost ? wave.abs() : wave) *
                (sea
                    ? 7
                    : dunes
                    ? 30
                    : 19);
        if (x == 0) {
          hill.moveTo(0, y);
        } else {
          hill.lineTo(x.toDouble(), y);
        }
      }
      canvas.drawPath(hill, route);
      hill.lineTo(320, 128);
      hill.lineTo(0, 128);
      hill.close();
      canvas.drawPath(hill, land);
    }
    if (grove) {
      for (var i = 0; i < 7; i++) {
        final x = 26.0 + i * 13;
        final y = 42.0 + 11 * math.sin(i.toDouble());
        canvas.drawPath(
          Path()
            ..moveTo(x, y + 24)
            ..lineTo(x + 5, y)
            ..lineTo(x + 11, y + 24)
            ..close(),
          route,
        );
      }
    }
    final trail = Path()
      ..moveTo(22, 109)
      ..cubicTo(91, 102, 100, 126, 156, 92)
      ..cubicTo(193, 67, 221, 99, 293, 65);
    canvas.drawPath(trail, route..strokeWidth = 2.5);
    final point = Paint()..color = palette.route;
    canvas.drawCircle(const Offset(22, 109), 3, point);
    canvas.drawCircle(const Offset(293, 65), 4, point);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Landscape oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.chapter != chapter;
}
