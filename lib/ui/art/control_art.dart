import 'package:material_ui/material_ui.dart';

import 'vector_path.dart';

enum ControlGlyph {
  home,
  levels,
  calendar,
  timer,
  collections,
  store,
  research,
  boost,
  wheel,
  statistics,
  settings,
  back,
  close,
  undo,
  clear,
  hint,
  play,
  pause,
  share,
  lock,
  check,
  cloud,
  connection,
  sound,
  haptics,
  accessibility,
}

final _glyphs = <ControlGlyph, Path>{
  for (final (glyph, data) in [
    (
      ControlGlyph.home,
      'M 3 11 L 12 4 L 21 11 L 21 20 L 15 20 L 15 14 L 9 14 L 9 20 L 3 20 Z',
    ),
    (
      ControlGlyph.levels,
      'M 3 7 L 12 3 L 21 7 L 12 11 Z M 3 12 L 12 16 L 21 12 M 3 17 L 12 21 L 21 17',
    ),
    (
      ControlGlyph.calendar,
      'M 4 6 L 20 6 L 20 21 L 4 21 Z M 8 3 L 8 8 M 16 3 L 16 8 M 4 11 L 20 11 M 9 16 L 11 18 L 15 14',
    ),
    (
      ControlGlyph.timer,
      'M 8 2 L 16 2 M 12 5 C 23 5 23 22 12 22 C 1 22 1 5 12 5 Z M 12 9 L 12 14 L 16 16',
    ),
    (
      ControlGlyph.collections,
      'M 4 5 L 8 4 L 8 21 L 4 22 Z M 10 4 L 16 4 L 16 21 L 10 21 Z M 18 5 L 21 4 L 23 20 L 20 21 Z',
    ),
    (
      ControlGlyph.store,
      'M 5 8 L 19 8 L 21 21 L 3 21 Z M 8 9 L 8 6 C 8 1 16 1 16 6 L 16 9',
    ),
    (
      ControlGlyph.research,
      'M 12 20 L 12 9 M 12 14 Q 4 14 4 6 Q 12 6 12 14 M 12 11 Q 12 4 20 3 Q 20 11 12 11 M 8 21 L 16 21',
    ),
    (
      ControlGlyph.boost,
      'M 3 11 L 12 5 L 21 11 L 12 17 Z M 3 16 L 12 22 L 21 16',
    ),
    (
      ControlGlyph.wheel,
      'M 12 3 C 24 3 24 21 12 21 C 0 21 0 3 12 3 Z M 12 3 L 12 21 M 4 8 L 20 16 M 20 8 L 4 16',
    ),
    (ControlGlyph.statistics, 'M 4 20 L 4 12 M 12 20 L 12 5 M 20 20 L 20 9'),
    (
      ControlGlyph.settings,
      'M 12 8.8 C 13.8 8.8 15.2 10.2 15.2 12 C 15.2 13.8 13.8 15.2 12 15.2 C 10.2 15.2 8.8 13.8 8.8 12 C 8.8 10.2 10.2 8.8 12 8.8 Z '
      'M 10.4 3 L 13.6 3 L 14.1 5.3 L 16 6.1 L 18 4.8 L 20.2 7 L 18.9 9 L 19.7 10.9 L 22 11.4 L 22 14.6 L 19.7 15.1 L 18.9 17 L 20.2 19 L 18 21.2 L 16 19.9 L 14.1 20.7 L 13.6 23 L 10.4 23 L 9.9 20.7 L 8 19.9 L 6 21.2 L 3.8 19 L 5.1 17 L 4.3 15.1 L 2 14.6 L 2 11.4 L 4.3 10.9 L 5.1 9 L 3.8 7 L 6 4.8 L 8 6.1 L 9.9 5.3 Z',
    ),
    (ControlGlyph.back, 'M 11 5 L 4 12 L 11 19 M 4 12 L 21 12'),
    (ControlGlyph.close, 'M 6 6 L 18 18 M 18 6 L 6 18'),
    (ControlGlyph.undo, 'M 9 5 L 3 11 L 9 17 M 3 11 L 15 11 Q 21 11 21 18'),
    (
      ControlGlyph.clear,
      'M 5 5 L 5 11 L 11 11 M 5 11 C 6 1 21 2 21 12 C 21 22 9 24 5 17',
    ),
    (
      ControlGlyph.hint,
      'M 9 18 Q 9 15 6 13 C 1 5 12 0 17 6 Q 21 10 16 14 Q 15 15 15 18 Z M 10 21 L 14 21',
    ),
    (ControlGlyph.play, 'M 7 4 L 20 12 L 7 20 Z'),
    (ControlGlyph.pause, 'M 9 4 L 9 20 M 15 4 L 15 20'),
    (
      ControlGlyph.share,
      'M 12 15 L 12 3 M 8 7 L 12 3 L 16 7 M 6 11 L 4 11 L 4 21 L 20 21 L 20 11 L 18 11',
    ),
    (
      ControlGlyph.lock,
      'M 5 10 L 19 10 L 19 21 L 5 21 Z M 8 10 L 8 6 C 8 1 16 1 16 6 L 16 10 M 12 14 L 12 17',
    ),
    (ControlGlyph.check, 'M 4 12 L 9 17 L 20 6'),
    (
      ControlGlyph.cloud,
      'M 7 19 C 0 19 0 9 7 9 C 8 1 20 3 19 11 C 25 12 23 19 18 19 Z',
    ),
    (
      ControlGlyph.connection,
      'M 2 8 Q 12 0 22 8 M 6 12 Q 12 7 18 12 M 9 16 Q 12 13 15 16 M 12 20 L 12 20.2',
    ),
    (
      ControlGlyph.sound,
      'M 3 9 L 7 9 L 12 5 L 12 19 L 7 15 L 3 15 Z M 16 8 Q 20 12 16 16 M 19 5 Q 25 12 19 19',
    ),
    (
      ControlGlyph.haptics,
      'M 8 4 L 16 4 L 16 20 L 8 20 Z M 4 8 L 4 16 M 1 10 L 1 14 M 20 8 L 20 16 M 23 10 L 23 14',
    ),
    (
      ControlGlyph.accessibility,
      'M 12 3 L 12 4 M 4 8 L 12 10 L 20 8 M 12 10 L 12 15 L 7 21 M 12 15 L 17 21',
    ),
  ])
    glyph: compileVector(data),
};

void paintControl(Canvas canvas, ControlGlyph glyph, Color ink) {
  canvas.save();
  canvas.scale(1 / 12);
  canvas.translate(-12, -12);
  canvas.drawPath(
    _glyphs[glyph]!,
    Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.restore();
}

class PathIcon extends StatelessWidget {
  const PathIcon(this.glyph, {this.size = 22, super.key});
  final ControlGlyph glyph;
  final double size;

  static IconData iconFor(ControlGlyph glyph) => switch (glyph) {
    ControlGlyph.home => Icons.home_rounded,
    ControlGlyph.levels => Icons.explore_rounded,
    ControlGlyph.calendar => Icons.calendar_today_rounded,
    ControlGlyph.timer => Icons.timer_rounded,
    ControlGlyph.collections => Icons.collections_bookmark_rounded,
    ControlGlyph.store => Icons.storefront_rounded,
    ControlGlyph.research => Icons.science_rounded,
    ControlGlyph.boost => Icons.bolt_rounded,
    ControlGlyph.wheel => Icons.casino_rounded,
    ControlGlyph.statistics => Icons.bar_chart_rounded,
    ControlGlyph.settings => Icons.settings_rounded,
    ControlGlyph.back => Icons.arrow_back_rounded,
    ControlGlyph.close => Icons.close_rounded,
    ControlGlyph.undo => Icons.undo_rounded,
    ControlGlyph.clear => Icons.refresh_rounded,
    ControlGlyph.hint => Icons.lightbulb_outline_rounded,
    ControlGlyph.play => Icons.play_arrow_rounded,
    ControlGlyph.pause => Icons.pause_rounded,
    ControlGlyph.share => Icons.share_rounded,
    ControlGlyph.lock => Icons.lock_rounded,
    ControlGlyph.check => Icons.check_rounded,
    ControlGlyph.cloud => Icons.cloud_outlined,
    ControlGlyph.connection => Icons.wifi_rounded,
    ControlGlyph.sound => Icons.volume_up_rounded,
    ControlGlyph.haptics => Icons.vibration_rounded,
    ControlGlyph.accessibility => Icons.accessibility_new_rounded,
  };

  @override
  Widget build(BuildContext context) => Icon(iconFor(glyph), size: size);
}
