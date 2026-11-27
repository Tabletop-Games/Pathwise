part of 'campaign_journey_view.dart';

BiomeKind _biomeForChapter(int chapter) =>
    BiomeKind.values[chapter % BiomeKind.values.length];

enum _ChapterTemplate {
  shorelineCove,
  forestClearing,
  steppedRidge,
  canyonPass,
  glacialBridge,
  ruinTerrace,
}

_ChapterTemplate _templateForChapter(int chapter) {
  const templates = _ChapterTemplate.values;
  final raw = (chapter * 5 + (chapter ~/ 3)) % templates.length;
  if (chapter > 0) {
    final prev = ((chapter - 1) * 5 + ((chapter - 1) ~/ 3)) % templates.length;
    if (raw == prev) {
      return templates[(raw + 1) % templates.length];
    }
  }
  return templates[raw];
}

/// Deterministic, terrain-driven isometric route geometry. Every chapter starts
/// and ends at x = 0.50 so adjacent chapters connect without seams.
double _routeX(int globalSlot) {
  const slotsPerChapter = chapterSize + 2;
  final chapter = globalSlot ~/ slotsPerChapter;
  final slot = globalSlot % slotsPerChapter;
  if (slot == 0 || slot > chapterSize) return .50;

  final template = _templateForChapter(chapter);
  return switch (template) {
    _ChapterTemplate.shorelineCove => const <double>[
      .50,
      .38,
      .28,
      .26,
      .34,
      .46,
      .58,
      .68,
      .72,
      .64,
      .52,
      .50,
      .50,
      .38,
      .28,
      .26,
      .34,
      .48,
      .62,
      .72,
      .70,
      .58,
      .46,
      .38,
      .44,
      .50,
    ][slot],
    _ChapterTemplate.forestClearing => const <double>[
      .50,
      .60,
      .70,
      .72,
      .62,
      .50,
      .38,
      .28,
      .26,
      .36,
      .48,
      .50,
      .50,
      .62,
      .72,
      .70,
      .58,
      .44,
      .32,
      .26,
      .32,
      .44,
      .56,
      .64,
      .58,
      .50,
    ][slot],
    _ChapterTemplate.steppedRidge => const <double>[
      .50,
      .36,
      .24,
      .24,
      .24,
      .38,
      .52,
      .66,
      .76,
      .76,
      .76,
      .62,
      .48,
      .34,
      .24,
      .24,
      .36,
      .50,
      .64,
      .76,
      .76,
      .64,
      .50,
      .38,
      .44,
      .50,
    ][slot],
    _ChapterTemplate.canyonPass => const <double>[
      .50,
      .64,
      .74,
      .74,
      .60,
      .44,
      .28,
      .26,
      .26,
      .40,
      .54,
      .68,
      .74,
      .64,
      .50,
      .34,
      .26,
      .26,
      .38,
      .52,
      .66,
      .72,
      .62,
      .52,
      .50,
      .50,
    ][slot],
    _ChapterTemplate.glacialBridge => const <double>[
      .50,
      .50,
      .38,
      .28,
      .28,
      .40,
      .50,
      .50,
      .62,
      .72,
      .72,
      .60,
      .50,
      .50,
      .38,
      .28,
      .28,
      .40,
      .50,
      .62,
      .72,
      .72,
      .60,
      .50,
      .50,
      .50,
    ][slot],
    _ChapterTemplate.ruinTerrace => const <double>[
      .50,
      .34,
      .26,
      .36,
      .50,
      .64,
      .74,
      .64,
      .50,
      .36,
      .26,
      .34,
      .48,
      .62,
      .74,
      .66,
      .52,
      .38,
      .26,
      .34,
      .48,
      .60,
      .68,
      .58,
      .50,
      .50,
    ][slot],
  };
}

typedef _CrossingSpan = ({int startSlot, int endSlot, bool wood});

List<_CrossingSpan> _crossingSpans(_ChapterTemplate template) =>
    switch (template) {
      _ChapterTemplate.shorelineCove => const [
        (startSlot: 11, endSlot: 12, wood: true),
      ],
      _ChapterTemplate.forestClearing => const [
        (startSlot: 11, endSlot: 12, wood: true),
      ],
      _ChapterTemplate.glacialBridge => const [
        (startSlot: 6, endSlot: 7, wood: false),
        (startSlot: 12, endSlot: 13, wood: false),
        (startSlot: 23, endSlot: 24, wood: false),
      ],
      _ChapterTemplate.canyonPass => const [
        (startSlot: 13, endSlot: 14, wood: false),
      ],
      _ => const [],
    };

class _JourneyWorldPainter extends CustomPainter {
  _JourneyWorldPainter({
    required this.scroll,
    required this.extent,
    required this.palette,
    required this.highContrast,
    required this.highestUnlocked,
  }) : super(repaint: Listenable.merge([scroll, GameAssetCache.instance]));

  final ScrollController scroll;
  final double extent;
  final BoardPalette palette;
  final bool highContrast;
  final int highestUnlocked;

  static const int _slotsPerChapter = chapterSize + 2;
  static const int _rowsPerScene = 9;

  double _scrollOffset() => scroll.hasClients ? scroll.offset : 0.0;

  double _slotBottomY(int globalSlot, double viewportH, double offset) =>
      viewportH - (globalSlot * extent - offset);

  double _slotCenterY(int globalSlot, double viewportH, double offset) =>
      _slotBottomY(globalSlot, viewportH, offset) - extent * .5;

  ({Color ground, Color bank, Color water, Color waterLight, Color foam})
  _biomeColors(BiomeKind b) {
    final base = switch (b) {
      BiomeKind.ocean => (
        ground: const Color(0xff235166),
        bank: const Color(0xffc9b286),
        water: const Color(0xff165a75),
        waterLight: const Color(0xff2a8ea8),
        foam: const Color(0xffbcebf2),
      ),
      BiomeKind.forest => (
        ground: const Color(0xff345440),
        bank: const Color(0xff6b7c50),
        water: const Color(0xff1f5c6e),
        waterLight: const Color(0xff348294),
        foam: const Color(0xffbfe3e8),
      ),
      BiomeKind.winter => (
        ground: const Color(0xff527991),
        bank: const Color(0xff9bb8ca),
        water: const Color(0xff234c6b),
        waterLight: const Color(0xff3d789e),
        foam: const Color(0xffe1f3fc),
      ),
      BiomeKind.desert => (
        ground: const Color(0xff8c5538),
        bank: const Color(0xffbd8352),
        water: const Color(0xff266570),
        waterLight: const Color(0xff3c8c96),
        foam: const Color(0xffc7e8eb),
      ),
    };
    if (highContrast) {
      return (
        ground: palette.canvas,
        bank: palette.surface,
        water: palette.quiet,
        waterLight: palette.quiet,
        foam: palette.ink,
      );
    }
    final blend = palette.dark ? .26 : .14;
    return (
      ground: Color.lerp(base.ground, palette.canvas, blend)!,
      bank: Color.lerp(base.bank, palette.canvas, blend * .5)!,
      water: Color.lerp(base.water, palette.canvas, blend * .45)!,
      waterLight: Color.lerp(base.waterLight, palette.canvas, blend * .35)!,
      foam: base.foam,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final offset = _scrollOffset();
    final minSlot = math.max(0, (offset / extent).floor() - 3);
    final maxSlot = ((offset + size.height) / extent).ceil() + 3;

    canvas.save();
    canvas.clipRect(Offset.zero & size, doAntiAlias: false);

    _paintTerrain(canvas, size, offset, minSlot, maxSlot);
    _paintCrossings(canvas, size, offset, minSlot, maxSlot);
    _paintTrail(canvas, size, offset, minSlot, maxSlot);
    _paintBridges(canvas, size, offset, minSlot, maxSlot);
    _paintLandmarksAndProps(canvas, size, offset, minSlot, maxSlot);

    canvas.restore();
  }

  void _paintTerrain(
    Canvas canvas,
    Size size,
    double offset,
    int minSlot,
    int maxSlot,
  ) {
    final firstSceneIndex = minSlot ~/ _rowsPerScene;
    final lastSceneIndex = maxSlot ~/ _rowsPerScene;
    final overlap = extent * .85;

    void drawSceneBand(int sceneIndex, Rect clipRect) {
      final chapter = sceneIndex ~/ 3;
      final scene = sceneIndex % 3;
      final startSlot = sceneIndex * _rowsPerScene;
      final endSlot = startSlot + _rowsPerScene - 1;
      final topY = _slotBottomY(endSlot, size.height, offset) - extent;
      final bottomY = _slotBottomY(startSlot, size.height, offset);
      final frame = Rect.fromLTRB(
        0,
        topY - overlap,
        size.width,
        bottomY + overlap,
      );
      final sceneBiome = _biomeForChapter(chapter);
      final colors = _biomeColors(sceneBiome);

      canvas.save();
      canvas.clipRect(clipRect, doAntiAlias: false);
      canvas.drawRect(clipRect, Paint()..color = colors.ground);
      if (!highContrast) {
        final image = GameAssetCache.instance.imageFor(
          journeyTerrainPath(sceneBiome),
        );
        if (image != null) {
          final cropBounds = Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          );
          final crop = applyBoxFit(
            BoxFit.cover,
            cropBounds.size,
            frame.size,
          ).source;
          final alignment = Alignment(
            const [-.35, .35, .0][(chapter + scene) % 3],
            0,
          );
          canvas.drawImageRect(
            image,
            alignment.inscribe(crop, cropBounds),
            frame,
            Paint()..filterQuality = FilterQuality.medium,
          );
          canvas.drawRect(
            clipRect,
            Paint()
              ..color = colors.ground.withValues(
                alpha: palette.dark ? .24 : .08,
              ),
          );
        }
      }
      canvas.restore();
    }

    for (var s = firstSceneIndex; s <= lastSceneIndex; s++) {
      final startSlot = s * _rowsPerScene;
      final endSlot = startSlot + _rowsPerScene - 1;
      final topY = _slotBottomY(endSlot, size.height, offset) - extent;
      final bottomY = _slotBottomY(startSlot, size.height, offset);
      drawSceneBand(
        s,
        Rect.fromLTRB(0, topY - overlap, size.width, bottomY + overlap),
      );
    }

    if (highContrast) return;

    // Smooth gradient blend across visible scene/chapter boundaries.
    for (var s = firstSceneIndex; s < lastSceneIndex; s++) {
      final boundarySlot = (s + 1) * _rowsPerScene;
      final boundaryY = _slotBottomY(boundarySlot, size.height, offset);
      final blendRect = Rect.fromLTRB(
        0,
        boundaryY - overlap,
        size.width,
        boundaryY + overlap,
      );
      if (blendRect.bottom < 0 || blendRect.top > size.height) continue;
      // Paint lower scene across the full blend strip, then fade upper scene in.
      drawSceneBand(s, blendRect);
      canvas.saveLayer(blendRect, Paint());
      drawSceneBand(s + 1, blendRect);
      canvas.drawRect(
        blendRect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              Colors.transparent,
              Colors.transparent,
            ],
            stops: [0, .12, .88, 1],
          ).createShader(blendRect),
      );
      canvas.restore();
    }
  }

  void _paintCrossings(
    Canvas canvas,
    Size size,
    double offset,
    int minSlot,
    int maxSlot,
  ) {
    if (highContrast) return;
    final firstChapter = minSlot ~/ _slotsPerChapter;
    final lastChapter = maxSlot ~/ _slotsPerChapter;

    for (var ch = firstChapter; ch <= lastChapter; ch++) {
      final template = _templateForChapter(ch);
      final biome = _biomeForChapter(ch);
      final colors = _biomeColors(biome);
      for (final span in _crossingSpans(template)) {
        final gStart = ch * _slotsPerChapter + span.startSlot;
        final gEnd = ch * _slotsPerChapter + span.endSlot;
        if (gEnd < minSlot - 1 || gStart > maxSlot + 1) continue;

        final topY = _slotCenterY(gEnd, size.height, offset) - extent * .42;
        final bottomY =
            _slotCenterY(gStart, size.height, offset) + extent * .42;
        final centerY = (topY + bottomY) * .5;
        final halfH = (bottomY - topY) * .5;
        final phase = (ch * 1.7 + span.startSlot * .5);

        Path riverBand(double extraHalfH) {
          const steps = 24;
          final path = Path();
          for (var i = 0; i <= steps; i++) {
            final t = i / steps;
            final x = t * size.width;
            final wave = math.sin(t * math.pi * 2.2 + phase) * 11.0;
            final y = centerY - (halfH + extraHalfH) + wave;
            if (i == 0) {
              path.moveTo(x, y);
            } else {
              path.lineTo(x, y);
            }
          }
          for (var i = steps; i >= 0; i--) {
            final t = i / steps;
            final x = t * size.width;
            final wave = math.sin(t * math.pi * 2.2 + phase) * 11.0;
            final y = centerY + (halfH + extraHalfH) + wave;
            path.lineTo(x, y);
          }
          path.close();
          return path;
        }

        // 1. Organic riverbank edge.
        canvas.drawPath(
          riverBand(11),
          Paint()..color = colors.bank.withValues(alpha: .78),
        );
        // 2. Deep water body with subtle vertical depth gradient.
        final waterPath = riverBand(0);
        canvas.drawPath(
          waterPath,
          Paint()
            ..shader =
                LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.water, colors.waterLight, colors.water],
                ).createShader(
                  Rect.fromLTRB(0, topY - 12, size.width, bottomY + 12),
                ),
        );
        // 3. Soft current shimmer ribbon along mid-stream.
        final currentPath = Path();
        for (var i = 0; i <= 24; i++) {
          final t = i / 24;
          final x = t * size.width;
          final y = centerY + math.sin(t * math.pi * 2.2 + phase) * 11.0;
          if (i == 0) {
            currentPath.moveTo(x, y);
          } else {
            currentPath.lineTo(x, y);
          }
        }
        canvas.drawPath(
          currentPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = halfH * .38
            ..strokeCap = StrokeCap.round
            ..color = colors.foam.withValues(alpha: .16),
        );

        // 4. Subtle shoreline foam lines along top and bottom banks.
        Path bankLine(double dy) {
          final p = Path();
          for (var i = 0; i <= 24; i++) {
            final t = i / 24;
            final x = t * size.width;
            final y = centerY + dy + math.sin(t * math.pi * 2.2 + phase) * 11.0;
            if (i == 0) {
              p.moveTo(x, y);
            } else {
              p.lineTo(x, y);
            }
          }
          return p;
        }

        final foamPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = colors.foam.withValues(alpha: .35);
        canvas.drawPath(bankLine(-halfH + 2), foamPaint);
        canvas.drawPath(bankLine(halfH - 2), foamPaint);
      }
    }
  }

  Offset _slotPoint(int slot, double width, double viewportH, double offset) =>
      Offset(_routeX(slot) * width, _slotCenterY(slot, viewportH, offset));

  Path _buildSmoothSpline(
    int fromSlot,
    int toSlot,
    double width,
    double viewportH,
    double offset,
  ) {
    final path = Path();
    if (fromSlot >= toSlot) return path;
    final p0 = _slotPoint(fromSlot, width, viewportH, offset);
    path.moveTo(p0.dx, p0.dy);
    for (var s = fromSlot; s < toSlot; s++) {
      final a = _slotPoint(math.max(0, s - 1), width, viewportH, offset);
      final b = _slotPoint(s, width, viewportH, offset);
      final c = _slotPoint(s + 1, width, viewportH, offset);
      final d = _slotPoint(s + 2, width, viewportH, offset);
      // Catmull-Rom to cubic Bezier conversion for C1-continuous curves.
      final cp1 = Offset(
        b.dx + (c.dx - a.dx) / 6.0,
        b.dy + (c.dy - a.dy) / 6.0,
      );
      final cp2 = Offset(
        c.dx - (d.dx - b.dx) / 6.0,
        c.dy - (d.dy - b.dy) / 6.0,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, c.dx, c.dy);
    }
    return path;
  }

  int _slotForLevel(int level) => level + chapterFor(level) * 2;

  void _paintTrail(
    Canvas canvas,
    Size size,
    double offset,
    int minSlot,
    int maxSlot,
  ) {
    final reachedSlot = _slotForLevel(highestUnlocked);
    final fullSpline = _buildSmoothSpline(
      minSlot,
      maxSlot,
      size.width,
      size.height,
      offset,
    );

    final centerChapter = ((minSlot + maxSlot) ~/ 2) ~/ _slotsPerChapter;
    final biome = _biomeForChapter(centerChapter);
    final (active, resting, skirt) = switch (biome) {
      BiomeKind.ocean => (
        const Color(0xffe9d4a6),
        const Color(0xff9ab3ac),
        const Color(0xff3e6469),
      ),
      BiomeKind.forest => (
        const Color(0xffdec08a),
        const Color(0xffa7a17b),
        const Color(0xff3b4d36),
      ),
      BiomeKind.winter => (
        const Color(0xffd7e8f0),
        const Color(0xff9cb0be),
        const Color(0xff476175),
      ),
      BiomeKind.desert => (
        const Color(0xffecc283),
        const Color(0xffb48a6a),
        const Color(0xff6b4228),
      ),
    };

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (highContrast) {
      canvas.drawPath(
        fullSpline,
        strokePaint
          ..strokeWidth = 18
          ..color = palette.canvas,
      );
      if (reachedSlot >= minSlot) {
        final reachedEnd = math.min(maxSlot, reachedSlot);
        final reachedPath = _buildSmoothSpline(
          minSlot,
          reachedEnd,
          size.width,
          size.height,
          offset,
        );
        canvas.drawPath(
          reachedPath,
          strokePaint
            ..strokeWidth = 13
            ..color = palette.route,
        );
      }
      if (reachedSlot < maxSlot) {
        final lockedStart = math.max(minSlot, reachedSlot);
        final lockedPath = _buildSmoothSpline(
          lockedStart,
          maxSlot,
          size.width,
          size.height,
          offset,
        );
        canvas.drawPath(
          lockedPath,
          strokePaint
            ..strokeWidth = 13
            ..color = palette.mutedInk,
        );
      }
      return;
    }

    // Continuous 2.5D underside extrusion skirt across the entire visible path.
    canvas.save();
    canvas.translate(0, 4.0);
    canvas.drawPath(
      fullSpline,
      strokePaint
        ..strokeWidth = 17
        ..color = skirt.withValues(alpha: .70),
    );
    canvas.restore();

    // Locked portion drawn first, then reached portion cleanly on top up to
    // the current node center so there are never exposed joins or caps.
    if (reachedSlot < maxSlot) {
      final lockedStart = math.max(minSlot, reachedSlot);
      final lockedPath = _buildSmoothSpline(
        lockedStart,
        maxSlot,
        size.width,
        size.height,
        offset,
      );
      canvas.drawPath(
        lockedPath,
        strokePaint
          ..strokeWidth = 14
          ..color = resting,
      );
      canvas.drawPath(
        lockedPath,
        strokePaint
          ..strokeWidth = 5
          ..color = Colors.white.withValues(alpha: .10),
      );
    }

    if (reachedSlot >= minSlot) {
      final reachedEnd = math.min(maxSlot, reachedSlot);
      final reachedPath = _buildSmoothSpline(
        minSlot,
        reachedEnd,
        size.width,
        size.height,
        offset,
      );
      canvas.drawPath(
        reachedPath,
        strokePaint
          ..strokeWidth = 14
          ..color = active,
      );
      canvas.drawPath(
        reachedPath,
        strokePaint
          ..strokeWidth = 5
          ..color = Colors.white.withValues(alpha: .22),
      );
    }
  }

  void _paintBridges(
    Canvas canvas,
    Size size,
    double offset,
    int minSlot,
    int maxSlot,
  ) {
    final firstChapter = minSlot ~/ _slotsPerChapter;
    final lastChapter = maxSlot ~/ _slotsPerChapter;

    for (var ch = firstChapter; ch <= lastChapter; ch++) {
      final template = _templateForChapter(ch);
      for (final span in _crossingSpans(template)) {
        final gStart = ch * _slotsPerChapter + span.startSlot;
        final gEnd = ch * _slotsPerChapter + span.endSlot;
        if (gEnd < minSlot - 1 || gStart > maxSlot + 1) continue;

        final pStart = _slotPoint(gStart - 1, size.width, size.height, offset);
        final pEnd = _slotPoint(gEnd + 1, size.width, size.height, offset);
        final entry = Offset.lerp(
          pStart,
          _slotPoint(gStart, size.width, size.height, offset),
          .46,
        )!;
        final exit = Offset.lerp(
          _slotPoint(gEnd, size.width, size.height, offset),
          pEnd,
          .54,
        )!;

        // Build coherent bridge spine passing through entry -> span nodes -> exit.
        final points = <Offset>[
          entry,
          for (var s = gStart; s <= gEnd; s++)
            _slotPoint(s, size.width, size.height, offset),
          exit,
        ];
        final bridgePath = Path()..moveTo(points.first.dx, points.first.dy);
        for (var i = 1; i < points.length; i++) {
          final prev = points[i - 1];
          final curr = points[i];
          final mid = Offset(
            (prev.dx + curr.dx) * .5,
            (prev.dy + curr.dy) * .5,
          );
          bridgePath.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
          if (i == points.length - 1) {
            bridgePath.lineTo(curr.dx, curr.dy);
          }
        }

        final deckColor = highContrast
            ? palette.card
            : (span.wood ? const Color(0xffc99052) : const Color(0xffb7b2a6));
        final railColor = highContrast
            ? palette.ink
            : (span.wood ? const Color(0xff784922) : const Color(0xff6b6963));
        final shadowColor = Colors.black.withValues(alpha: .28);

        // 1. Bridge shadow on river.
        canvas.save();
        canvas.translate(0, 8);
        canvas.drawPath(
          bridgePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 34
            ..strokeCap = StrokeCap.butt
            ..strokeJoin = StrokeJoin.round
            ..color = shadowColor,
        );
        canvas.restore();

        // 2. Side railings / parapets.
        canvas.drawPath(
          bridgePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 34
            ..strokeCap = StrokeCap.butt
            ..strokeJoin = StrokeJoin.round
            ..color = railColor,
        );

        // 3. Continuous bridge deck.
        canvas.drawPath(
          bridgePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 26
            ..strokeCap = StrokeCap.butt
            ..strokeJoin = StrokeJoin.round
            ..color = deckColor,
        );

        // 4. Plank / cobble joints and bank abutments along the bridge.
        final metrics = bridgePath.computeMetrics();
        final plankPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = railColor.withValues(alpha: .42);
        final abutmentPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7.0
          ..strokeCap = StrokeCap.round
          ..color = railColor;
        final postPaint = Paint()..color = railColor;
        for (final metric in metrics) {
          final len = metric.length;
          for (final endOffset in [2.0, math.max(2.0, len - 2.0)]) {
            final tan = metric.getTangentForOffset(endOffset);
            if (tan == null) continue;
            final normal = Offset(-tan.vector.dy, tan.vector.dx);
            canvas.drawLine(
              tan.position + normal * 15.5,
              tan.position - normal * 15.5,
              abutmentPaint,
            );
          }
          for (var d = 10.0; d < len - 8.0; d += 12.0) {
            final tan = metric.getTangentForOffset(d);
            if (tan == null) continue;
            final normal = Offset(-tan.vector.dy, tan.vector.dx);
            final p1 = tan.position + normal * 13;
            final p2 = tan.position - normal * 13;
            canvas.drawLine(p1, p2, plankPaint);
            if ((d ~/ 12) % 2 == 0) {
              canvas.drawCircle(tan.position + normal * 15.5, 2.8, postPaint);
              canvas.drawCircle(tan.position - normal * 15.5, 2.8, postPaint);
            }
          }
        }
      }
    }
  }

  void _paintLandmarksAndProps(
    Canvas canvas,
    Size size,
    double offset,
    int minSlot,
    int maxSlot,
  ) {
    if (highContrast) return;

    void drawSprite(
      String path,
      Offset center,
      double maxDim, {
      bool shadow = true,
    }) {
      final img = GameAssetCache.instance.imageFor(path);
      if (img == null) return;
      final aspect = img.width / math.max(1, img.height);
      final w = aspect >= 1 ? maxDim : maxDim * aspect;
      final h = aspect >= 1 ? maxDim / aspect : maxDim;
      if (shadow) {
        canvas.drawOval(
          Rect.fromCenter(
            center: center.translate(0, h * .38),
            width: w * .72,
            height: h * .20,
          ),
          Paint()..color = Colors.black.withValues(alpha: .20),
        );
      }
      final src = Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      final dst = Rect.fromCenter(center: center, width: w, height: h);
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    for (var globalSlot = minSlot; globalSlot <= maxSlot; globalSlot++) {
      final chapter = globalSlot ~/ _slotsPerChapter;
      final position = globalSlot % _slotsPerChapter;
      if (position == 0 || position > chapterSize) continue;

      final template = _templateForChapter(chapter);
      final biome = _biomeForChapter(chapter);
      final spans = _crossingSpans(template);
      final nearCrossing = spans.any(
        (span) =>
            position >= span.startSlot - 1 && position <= span.endSlot + 1,
      );
      if (nearCrossing) continue;

      final stopX = _routeX(globalSlot);
      final onRight = stopX <= .52;
      final sideX = onRight ? size.width * .80 : size.width * .20;
      final altX = onRight ? size.width * .15 : size.width * .85;
      final centerY = _slotCenterY(globalSlot, size.height, offset);

      // Large multi-level biome landmarks (unclipped across rows).
      if (position == 5 || position == 17 || position == 22) {
        final landmarkPath = switch (biome) {
          BiomeKind.ocean => 'assets/art/journey/iso_ocean_cove.png',
          BiomeKind.forest => 'assets/art/journey/iso_forest_grove.png',
          BiomeKind.winter => 'assets/art/journey/iso_winter_glacier.png',
          BiomeKind.desert => 'assets/art/journey/iso_desert_mesa.png',
        };
        drawSprite(landmarkPath, Offset(sideX, centerY), 132);
        continue;
      }

      if (template == _ChapterTemplate.ruinTerrace &&
          (position == 10 || position == 20)) {
        drawSprite(
          'assets/art/journey/iso_ruin_terrace.png',
          Offset(sideX, centerY),
          110,
        );
        continue;
      }

      // Avoid placing small props right next to a hero landmark row.
      if (position == 4 ||
          position == 6 ||
          position == 16 ||
          position == 18 ||
          position == 21 ||
          position == 23) {
        continue;
      }

      final hash = (globalSlot * 37 + chapter * 13) % 5;
      if (hash < 2) {
        final propPath = switch (biome) {
          BiomeKind.forest =>
            hash == 0
                ? 'assets/art/journey/prop_forest_trees.webp'
                : 'assets/art/journey/prop_forest_rocks.webp',
          BiomeKind.winter =>
            hash == 0
                ? 'assets/art/journey/prop_winter_pine.webp'
                : 'assets/art/journey/prop_winter_ice.webp',
          BiomeKind.ocean =>
            hash == 0
                ? 'assets/art/journey/prop_ocean_palm.webp'
                : 'assets/art/journey/prop_forest_rocks.webp',
          BiomeKind.desert =>
            hash == 0
                ? 'assets/art/journey/prop_desert_cactus.webp'
                : 'assets/art/journey/prop_forest_rocks.webp',
        };
        drawSprite(propPath, Offset(sideX, centerY), 54);
        if (template == _ChapterTemplate.forestClearing &&
            hash == 0 &&
            (stopX - .5).abs() < .18) {
          drawSprite(propPath, Offset(altX, centerY + 6), 44);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_JourneyWorldPainter oldDelegate) =>
      scroll != oldDelegate.scroll ||
      extent != oldDelegate.extent ||
      palette != oldDelegate.palette ||
      highContrast != oldDelegate.highContrast ||
      highestUnlocked != oldDelegate.highestUnlocked;
}
