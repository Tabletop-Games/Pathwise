import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/economy.dart';
import '../../model/native_achievements.dart';
import '../../model/progression.dart';
import 'control_art.dart';

class AchievementEmblem extends StatelessWidget {
  const AchievementEmblem(
    this.achievement, {
    required this.palette,
    required this.earned,
    this.size = 40,
    super.key,
  });
  final Achievement achievement;
  final BoardPalette palette;
  final bool earned;
  final double size;

  @override
  Widget build(BuildContext context) {
    final glyph = switch (achievement) {
      Achievement.trailhead ||
      Achievement.trailblazer ||
      Achievement.pathfinder => ControlGlyph.levels,
      Achievement.dailyHabit ||
      Achievement.weeklyRitual => ControlGlyph.calendar,
      Achievement.unaided => ControlGlyph.check,
      Achievement.collector => ControlGlyph.collections,
      Achievement.timeTrial => ControlGlyph.timer,
      Achievement.researcher => ControlGlyph.research,
      Achievement.legendaryCrate => ControlGlyph.store,
      _ => ControlGlyph.home,
    };
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _Medallion(palette, glyph, earned, achievement.index),
      ),
    );
  }
}

class NativeAchievementEmblem extends StatelessWidget {
  const NativeAchievementEmblem(
    this.item, {
    required this.palette,
    required this.earned,
    super.key,
  });
  final NativeAchievement item;
  final BoardPalette palette;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final glyph = switch (item.metric) {
      AchievementMetric.solves => ControlGlyph.levels,
      AchievementMetric.hintFree ||
      AchievementMetric.precision => ControlGlyph.check,
      AchievementMetric.daily => ControlGlyph.calendar,
      AchievementMetric.attackFinished ||
      AchievementMetric.attackScore => ControlGlyph.timer,
      AchievementMetric.research => ControlGlyph.research,
      AchievementMetric.themes => ControlGlyph.collections,
      AchievementMetric.crates => ControlGlyph.store,
    };
    return SizedBox.square(
      dimension: 38,
      child: CustomPaint(
        painter: _Medallion(palette, glyph, earned, item.metric.index),
      ),
    );
  }
}

class BoostArtwork extends StatelessWidget {
  const BoostArtwork(
    this.boost, {
    required this.palette,
    this.size = 44,
    super.key,
  });
  final Boost boost;
  final BoardPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _BoostPainter(palette, boost)),
  );
}

class _Medallion extends CustomPainter {
  const _Medallion(this.palette, this.glyph, this.earned, this.rank);
  final BoardPalette palette;
  final ControlGlyph glyph;
  final bool earned;
  final int rank;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide * .46);
    final badge = Path()
      ..moveTo(0, -.98)
      ..lineTo(.83, -.52)
      ..lineTo(.83, .47)
      ..quadraticBezierTo(.49, .80, 0, .97)
      ..quadraticBezierTo(-.49, .80, -.83, .47)
      ..lineTo(-.83, -.52)
      ..close();
    final tint = [
      palette.route,
      palette.accent,
      const Color(0xff88809c),
    ][rank % 3];
    canvas.drawPath(
      badge,
      Paint()..color = Color.lerp(palette.surface, tint, earned ? .37 : .10)!,
    );
    canvas.drawPath(
      badge,
      Paint()
        ..color = earned ? palette.route : palette.muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = .06,
    );
    canvas.save();
    canvas.scale(.52);
    paintControl(canvas, glyph, earned ? palette.ink : palette.muted);
    canvas.restore();
    if (earned)
      canvas.drawCircle(
        const Offset(0, .72),
        .065,
        Paint()..color = palette.route,
      );
  }

  @override
  bool shouldRepaint(_Medallion oldDelegate) =>
      palette != oldDelegate.palette ||
      glyph != oldDelegate.glyph ||
      earned != oldDelegate.earned ||
      rank != oldDelegate.rank;
}

class _BoostPainter extends CustomPainter {
  const _BoostPainter(this.palette, this.boost);
  final BoardPalette palette;
  final Boost boost;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide / 2);
    final color = Color.lerp(
      switch (boost.multiplier) {
        2 => const Color(0xff6e8f86),
        3 => const Color(0xff897ba1),
        _ => const Color(0xffaf8260),
      },
      palette.route,
      .22,
    )!;
    final layers = boost.multiplier.clamp(1, 4);
    final width = .63 + boost.minutes.clamp(10, 60) * .004;
    for (var index = layers - 1; index >= 0; index--) {
      final top = -.55 + .30 * index;
      final slab = Path()
        ..moveTo(0, top - .27)
        ..lineTo(width, top + .10)
        ..lineTo(0, top + .47)
        ..lineTo(-width, top + .10)
        ..close();
      canvas.drawPath(
        slab,
        Paint()..color = Color.lerp(color, palette.surface, index * .16)!,
      );
    }
    if (boost.minutes >= 30) {
      canvas.drawLine(
        Offset(-width * .32, -.44),
        Offset(width * .32, -.44),
        Paint()
          ..color = palette.onRoute
          ..strokeWidth = .07
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_BoostPainter oldDelegate) =>
      palette != oldDelegate.palette || boost != oldDelegate.boost;
}
