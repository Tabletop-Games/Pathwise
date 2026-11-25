import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../model/app_themes.dart';
import '../model/user_preferences.dart';
import 'art/vector_path.dart';

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
    final scene = chapter % _horizons.length;
    final cycle = (chapter ~/ _horizons.length) % 5;
    final dusk = palette.dark || scene == 6 || scene == 7;
    final air = Color.lerp(palette.canvas, palette.route, dusk ? .21 : .085)!;
    final ridge = Color.lerp(
      palette.canvas,
      palette.route,
      .24 + cycle * .025,
    )!;
    final ground = Color.lerp(palette.canvas, palette.route, .55)!;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 320, 128), Paint()..color = air);
    final sun = Offset(204 + 23 * math.sin(chapter * .8), 35 - cycle * 3);
    canvas.drawCircle(
      sun,
      scene == 5 ? 25 : 15,
      Paint()..color = Color.lerp(palette.accent, air, .30)!,
    );
    canvas.drawPath(_horizons[scene], Paint()..color = ridge);
    canvas.drawPath(_foregrounds[scene], Paint()..color = ground);
    final trail = Paint()
      ..color = palette.onRoute.withValues(alpha: .88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_trails[scene], trail);
    final endpoint = _endpoints[scene];
    canvas.drawCircle(endpoint, 3, Paint()..color = palette.onRoute);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Landscape oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.chapter != chapter;
}

// The chapter's silhouette supplies its identity. Cycling revisits these
// environments at different light levels and sun positions.
final _horizons = [
  'M 0 100 L 55 63 L 100 86 L 154 34 L 233 88 L 265 73 L 320 100 L 320 128 L 0 128 Z',
  'M 0 108 L 13 70 L 25 93 L 42 39 L 62 86 L 76 52 L 97 96 L 128 56 L 154 106 L 187 84 L 220 105 L 277 75 L 320 101 L 320 128 L 0 128 Z',
  'M 0 70 Q 46 66 89 81 L 221 81 Q 272 61 320 70 L 320 128 L 0 128 Z',
  'M 0 47 Q 25 25 58 62 Q 86 87 122 99 Q 181 120 223 58 Q 269 6 320 44 L 320 128 L 0 128 Z',
  'M 0 108 L 41 76 L 64 77 L 104 24 L 132 57 L 154 42 L 220 104 L 260 65 L 320 107 L 320 128 L 0 128 Z',
  'M 0 72 Q 68 59 119 88 Q 164 103 230 59 Q 288 24 320 45 L 320 128 L 0 128 Z',
  'M 0 93 L 37 67 L 64 69 L 86 55 L 119 65 L 161 86 L 203 65 L 256 45 L 320 74 L 320 128 L 0 128 Z',
  'M 0 98 L 43 82 L 70 89 L 105 65 L 151 92 L 204 72 L 235 90 L 287 58 L 320 88 L 320 128 L 0 128 Z',
].map(compileVector).toList();

final _foregrounds = [
  'M 0 109 Q 72 84 150 109 Q 205 122 264 101 Q 292 95 320 102 L 320 128 L 0 128 Z',
  'M 0 108 Q 53 82 118 103 Q 205 126 320 90 L 320 128 L 0 128 Z',
  'M 0 101 Q 51 109 91 97 Q 140 86 187 102 Q 232 113 320 94 L 320 128 L 0 128 Z',
  'M 0 91 Q 82 117 143 113 Q 217 102 320 81 L 320 128 L 0 128 Z',
  'M 0 108 Q 55 116 96 91 Q 126 80 162 101 Q 210 119 320 98 L 320 128 L 0 128 Z',
  'M 0 106 Q 125 57 184 100 Q 233 122 320 90 L 320 128 L 0 128 Z',
  'M 0 109 L 41 92 L 85 94 L 125 110 L 171 105 L 230 81 L 274 95 L 320 101 L 320 128 L 0 128 Z',
  'M 0 109 Q 53 83 119 107 Q 183 124 235 97 Q 273 80 320 94 L 320 128 L 0 128 Z',
].map(compileVector).toList();

final _trails = [
  'M 23 118 Q 81 97 138 113 Q 191 126 256 111',
  'M 28 114 C 96 90 158 130 279 105',
  'M 29 114 Q 87 118 129 108 Q 169 101 216 112',
  'M 42 112 Q 117 132 178 113 Q 219 105 259 100',
  'M 35 120 Q 76 115 103 104 Q 127 93 162 112 Q 189 122 229 114',
  'M 24 111 Q 111 74 172 102 Q 222 124 285 106',
  'M 26 116 L 62 102 L 110 113 L 154 116 L 222 95 L 267 104',
  'M 34 114 Q 79 95 134 118 Q 185 126 256 104',
].map(compileVector).toList();

final _endpoints = [
  for (final path in _trails)
    for (final metric in path.computeMetrics())
      metric.getTangentForOffset(metric.length)!.position,
];
