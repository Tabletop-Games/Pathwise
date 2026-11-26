part of 'campaign_journey_view.dart';

BiomeKind _biomeForChapter(int chapter) =>
    BiomeKind.values[chapter % BiomeKind.values.length];

double _routeX(int globalSlot) {
  const slotsPerChapter = chapterSize + 2;
  final chapter = globalSlot ~/ slotsPerChapter;
  final slot = globalSlot % slotsPerChapter;
  if (slot == 0 || slot > chapterSize) return .5;
  final edgeEase = math.min(1.0, math.min(slot, chapterSize + 1 - slot) / 2.2);
  final offset = switch (chapter % 4) {
    0 => .24 * math.sin(slot * math.pi / 4.2),
    1 => -.25 * math.sin(slot * math.pi / 5.5),
    2 => .25 * math.sin(slot * math.pi / 4.8 + .5) * math.cos(slot * .22),
    _ => .22 * math.sin(slot * math.pi / 3.6),
  };
  return .5 + offset * edgeEase;
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
    _paintProps(canvas, size);
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
    final overlap = size.height * .85;
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
        journeyTerrainPath(sceneBiome),
      );
      if (image == null) return;

      // Shared coordinates keep each crop stable as its rows move on screen.
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
        const [-.35, .35, .0][(sceneChapter + scene) % 3],
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
                ? .84
                : palette.dark
                ? .22
                : .06,
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
    const slotsPerChapter = chapterSize + 2;
    final globalSlot = chapter * slotsPerChapter + position;

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

    (Color active, Color resting, Color edgeShadow) trailColors(BiomeKind b) =>
        switch (b) {
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
            const Color(0xff526b80),
          ),
          BiomeKind.desert => (
            const Color(0xffecc283),
            const Color(0xffb48a6a),
            const Color(0xff6b4228),
          ),
        };

    void draw(Path path, bool reached, BiomeKind trailBiome) {
      final (active, resting, edgeShadow) = trailColors(trailBiome);
      final surface = highContrast
          ? (reached ? palette.route : palette.mutedInk)
          : (reached ? active : resting);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (highContrast) {
        canvas.drawPath(
          path,
          paint
            ..strokeWidth = 22
            ..color = palette.canvas,
        );
        canvas.drawPath(
          path,
          paint
            ..strokeWidth = 16
            ..color = surface,
        );
        return;
      }
      // Soft terrain-integrated berm shadow instead of a harsh diagram outline.
      canvas.drawPath(
        path,
        paint
          ..strokeWidth = 22
          ..color = edgeShadow.withValues(alpha: reached ? .34 : .24),
      );
      canvas.drawPath(
        path,
        paint
          ..strokeWidth = 17
          ..color = surface.withValues(alpha: reached ? .96 : .82),
      );
      canvas.drawPath(
        path,
        paint
          ..strokeWidth = 8
          ..color = Colors.white.withValues(alpha: reached ? .18 : .10),
      );
    }

    if (position != 0 || chapter != 0) {
      final belowBiome = position == 0 && chapter > 0
          ? _biomeForChapter(chapter - 1)
          : biome;
      draw(section(globalSlot, size.height / 2), pathBelowReached, belowBiome);
    }
    draw(section(globalSlot + 1, -size.height / 2), pathAboveReached, biome);
  }

  void _paintProps(Canvas canvas, Size size) {
    if (highContrast) return;
    const slotsPerChapter = chapterSize + 2;
    final globalSlot = chapter * slotsPerChapter + position;

    void drawProp(String path, Offset center, double dim) {
      final img = GameAssetCache.instance.imageFor(path);
      if (img == null) return;
      // Soft ground shadow
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(0, dim * .34),
          width: dim * .72,
          height: dim * .22,
        ),
        Paint()..color = Colors.black.withValues(alpha: .18),
      );
      final src = Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      final dst = Rect.fromCenter(center: center, width: dim, height: dim);
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    if (position == 0 || position > chapterSize) return;

    // Deterministic environmental props tucked on the open side away from node & time pill.
    final hash = (globalSlot * 37 + chapter * 13) % 7;
    if (hash >= 4) return;
    final stopX = _routeX(globalSlot);
    final propX = stopX <= .5 ? size.width * .88 : size.width * .12;
    final propY = size.height * .52;
    final propPath = switch (biome) {
      BiomeKind.forest =>
        hash.isEven
            ? 'assets/art/journey/prop_forest_trees.webp'
            : 'assets/art/journey/prop_forest_rocks.webp',
      BiomeKind.winter =>
        hash.isEven
            ? 'assets/art/journey/prop_winter_pine.webp'
            : 'assets/art/journey/prop_winter_ice.webp',
      BiomeKind.ocean =>
        hash.isEven
            ? 'assets/art/journey/prop_ocean_palm.webp'
            : 'assets/art/journey/prop_forest_rocks.webp',
      BiomeKind.desert =>
        hash.isEven
            ? 'assets/art/journey/prop_desert_cactus.webp'
            : 'assets/art/journey/prop_forest_rocks.webp',
    };
    drawProp(propPath, Offset(propX, propY), 44);
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
