part of 'campaign_journey_view.dart';

BiomeKind _biomeForChapter(int chapter) =>
    BiomeKind.values[chapter % BiomeKind.values.length];

double _routeX(int position) {
  final slot = position % (chapterSize + 2);
  if (slot == 0 || slot > chapterSize) return .5;
  return .5 + .25 * math.sin(slot * math.pi / 4);
}

class _JourneyLandscape extends CustomPainter {
  _JourneyLandscape({
    required this.chapter,
    required this.position,
    required this.palette,
    required this.biome,
    required this.highContrast,
    required this.pathBelowReached,
    required this.pathAboveReached,
  }) : super(repaint: GameAssetCache.instance);

  final int chapter;
  final int position;
  final BoardPalette palette;
  final BiomeKind biome;
  final bool highContrast;
  final bool pathBelowReached;
  final bool pathAboveReached;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds, doAntiAlias: false);
    _paintLandscape(canvas, size);
    _paintTrail(canvas, size);
    canvas.restore();
  }

  Color _ground(BiomeKind biome) {
    final base = switch (biome) {
      BiomeKind.ocean => const Color(0xff163c51),
      BiomeKind.forest => const Color(0xff2f4738),
      BiomeKind.winter => const Color(0xff466f88),
      BiomeKind.desert => const Color(0xff854a32),
    };
    return Color.lerp(base, palette.canvas, highContrast ? .82 : .24)!;
  }

  void _paintLandscape(Canvas canvas, Size size) {
    const slotsPerChapter = chapterSize + 2;
    const rowsPerScene = 9;
    final overlap = size.height * .65;
    final bounds = Offset.zero & size;
    final sceneStart = position ~/ rowsPerScene * rowsPerScene;
    final sceneEnd = math.min(sceneStart + rowsPerScene, slotsPerChapter);

    void drawScene(int sceneChapter, int sceneRow) {
      final scene = sceneRow ~/ rowsPerScene;
      final firstRow = scene * rowsPerScene;
      final endRow = math.min(firstRow + rowsPerScene, slotsPerChapter);
      final relativeRow = (chapter - sceneChapter) * slotsPerChapter + position;
      final frame = Rect.fromLTWH(
        0,
        size.height * (relativeRow - endRow + 1) - overlap,
        size.width,
        size.height * (endRow - firstRow) + overlap * 2,
      );
      final sceneBiome = _biomeForChapter(sceneChapter);
      final ground = _ground(sceneBiome);
      canvas.drawRect(bounds, Paint()..color = ground);
      final image = GameAssetCache.instance.imageFor(
        biomeAssetPath(sceneBiome),
      );
      if (image == null) return;

      // Shared coordinates keep each crop stable as its rows move on screen.
      final imageHeight = image.height.toDouble();
      final cropBounds = Rect.fromLTWH(
        0,
        imageHeight * .022,
        image.width.toDouble(),
        imageHeight * .956,
      );
      final crop = applyBoxFit(
        BoxFit.cover,
        cropBounds.size,
        frame.size,
      ).source;
      final alignment = Alignment(
        const [-.72, .62, .06][(sceneChapter + scene) % 3],
        0,
      );
      canvas.drawImageRect(
        image,
        alignment.inscribe(crop, cropBounds),
        frame,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.drawRect(
        bounds,
        Paint()
          ..color = ground.withValues(
            alpha: highContrast
                ? .86
                : palette.dark
                ? .27
                : .12,
          ),
      );
    }

    // At a join, both rows composite the same pair of crops. The upper scene
    // fades into the lower scene across their overlap, including biome changes.
    void blendScenes({
      required int lowerChapter,
      required int lowerRow,
      required int upperChapter,
      required int upperRow,
      required double boundary,
    }) {
      drawScene(lowerChapter, lowerRow);
      canvas.saveLayer(bounds, Paint());
      drawScene(upperChapter, upperRow);
      final blend = Rect.fromLTRB(
        0,
        boundary - overlap,
        size.width,
        boundary + overlap,
      );
      canvas.drawRect(
        bounds,
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
            stops: [0, .17, .83, 1],
          ).createShader(blend),
      );
      canvas.restore();
    }

    if (position == sceneEnd - 1) {
      final chapterBoundary = sceneEnd == slotsPerChapter;
      blendScenes(
        lowerChapter: chapter,
        lowerRow: position,
        upperChapter: chapterBoundary ? chapter + 1 : chapter,
        upperRow: chapterBoundary ? 0 : sceneEnd,
        boundary: 0,
      );
    } else if (position == sceneStart && (position != 0 || chapter != 0)) {
      final chapterBoundary = sceneStart == 0;
      blendScenes(
        lowerChapter: chapterBoundary ? chapter - 1 : chapter,
        lowerRow: chapterBoundary ? slotsPerChapter - 1 : sceneStart - 1,
        upperChapter: chapter,
        upperRow: position,
        boundary: size.height,
      );
    } else {
      drawScene(chapter, position);
    }
  }

  void _paintTrail(Canvas canvas, Size size) {
    // Both rows sharing a trail section paint the same full curve. Clipping
    // it at the row boundary keeps the outline and slope continuous.
    Path section(int start, double y) {
      final previous = _routeX(start + 1) * size.width;
      final from = _routeX(start) * size.width;
      final to = _routeX(start - 1) * size.width;
      final next = _routeX(start - 2) * size.width;
      return Path()
        ..moveTo(from, y)
        ..cubicTo(
          from + (to - previous) / 6,
          y + size.height / 3,
          to - (next - from) / 6,
          y + size.height * 2 / 3,
          to,
          y + size.height,
        );
    }

    final active = switch (biome) {
      BiomeKind.ocean => const Color(0xffe7d0a2),
      BiomeKind.forest => const Color(0xffe7be77),
      BiomeKind.winter => const Color(0xffdaedef),
      BiomeKind.desert => const Color(0xffffd291),
    };
    final resting = switch (biome) {
      BiomeKind.ocean => const Color(0xff8faea9),
      BiomeKind.forest => const Color(0xffaca478),
      BiomeKind.winter => const Color(0xff94aab8),
      BiomeKind.desert => const Color(0xffb18464),
    };

    void draw(Path path, bool reached) {
      final surface = highContrast
          ? (reached ? palette.route : palette.mutedInk)
          : (reached ? active : resting);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(
        path,
        paint
          ..strokeWidth = 24
          ..color = Colors.black.withValues(alpha: reached ? .53 : .39),
      );
      canvas.drawPath(
        path,
        paint
          ..strokeWidth = 19
          ..color = surface.withValues(
            alpha: highContrast || reached ? 1 : .86,
          ),
      );
      if (!highContrast) {
        canvas.drawPath(
          path,
          paint
            ..strokeWidth = 13
            ..color = Colors.white.withValues(alpha: reached ? .10 : .07),
        );
      }
    }

    if (position != 0 || chapter != 0) {
      draw(section(position, size.height / 2), pathBelowReached);
    }
    draw(section(position + 1, -size.height / 2), pathAboveReached);
  }

  @override
  bool shouldRepaint(_JourneyLandscape oldDelegate) =>
      chapter != oldDelegate.chapter ||
      position != oldDelegate.position ||
      palette != oldDelegate.palette ||
      biome != oldDelegate.biome ||
      highContrast != oldDelegate.highContrast ||
      pathBelowReached != oldDelegate.pathBelowReached ||
      pathAboveReached != oldDelegate.pathAboveReached;
}
