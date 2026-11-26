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

bool _isBridgeSlot(_ChapterTemplate template, int slot) => switch (template) {
  _ChapterTemplate.shorelineCove => slot == 11 || slot == 12,
  _ChapterTemplate.forestClearing => slot == 11 || slot == 12,
  _ChapterTemplate.glacialBridge =>
    slot == 6 || slot == 7 || slot == 12 || slot == 13 || slot == 24,
  _ChapterTemplate.canyonPass => slot == 14,
  _ => false,
};

bool _isWaterBand(_ChapterTemplate template, int slot) => switch (template) {
  _ChapterTemplate.shorelineCove => slot == 11 || slot == 12,
  _ChapterTemplate.forestClearing => slot == 11 || slot == 12,
  _ChapterTemplate.glacialBridge =>
    slot == 6 || slot == 7 || slot == 12 || slot == 13 || slot == 24,
  _ => false,
};

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
    _paintIsometricTerrain(canvas, size);
    _paintTrail(canvas, size);
    _paintLandmarksAndProps(canvas, size);
    canvas.restore();
  }

  ({Color ground, Color ridge, Color highlight, Color water}) _biomeColors(
    BiomeKind b,
  ) {
    final base = switch (b) {
      BiomeKind.ocean => (
        ground: const Color(0xff235166),
        ridge: const Color(0xff183b4d),
        highlight: const Color(0xff35738c),
        water: const Color(0xff134760),
      ),
      BiomeKind.forest => (
        ground: const Color(0xff345440),
        ridge: const Color(0xff233b2d),
        highlight: const Color(0xff4a7358),
        water: const Color(0xff235d6e),
      ),
      BiomeKind.winter => (
        ground: const Color(0xff527991),
        ridge: const Color(0xff3a5a70),
        highlight: const Color(0xff78a2ba),
        water: const Color(0xff264e6b),
      ),
      BiomeKind.desert => (
        ground: const Color(0xff8c5538),
        ridge: const Color(0xff663a24),
        highlight: const Color(0xffb57652),
        water: const Color(0xff2c6a73),
      ),
    };
    if (highContrast) {
      return (
        ground: palette.canvas,
        ridge: palette.surface,
        highlight: palette.card,
        water: palette.quiet,
      );
    }
    final blend = palette.dark ? .26 : .14;
    return (
      ground: Color.lerp(base.ground, palette.canvas, blend)!,
      ridge: Color.lerp(base.ridge, palette.canvas, blend)!,
      highlight: Color.lerp(base.highlight, palette.canvas, blend * .7)!,
      water: Color.lerp(base.water, palette.canvas, blend * .6)!,
    );
  }

  void _paintIsometricTerrain(Canvas canvas, Size size) {
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
      final colors = _biomeColors(sceneBiome);
      canvas.drawRect(bounds, Paint()..color = colors.ground);
      if (highContrast) return;
      final image = GameAssetCache.instance.imageFor(
        journeyTerrainPath(sceneBiome),
      );
      if (image == null) return;
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
          ..color = colors.ground.withValues(alpha: palette.dark ? .24 : .08),
      );
    }

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

    // Illustrated shoreline/stream crossing on bridge rows.
    final template = _templateForChapter(chapter);
    if (!highContrast && _isWaterBand(template, position)) {
      final colors = _biomeColors(biome);
      final waterRect = Rect.fromLTWH(
        0,
        size.height * .08,
        size.width,
        size.height * .84,
      );
      canvas.drawRect(
        waterRect,
        Paint()..color = colors.water.withValues(alpha: .88),
      );
    }
  }

  void _paintTrail(Canvas canvas, Size size) {
    const slotsPerChapter = chapterSize + 2;
    final globalSlot = chapter * slotsPerChapter + position;
    final template = _templateForChapter(chapter);

    Path section(int start, double y) {
      final from = _routeX(start) * size.width;
      final to = _routeX(start - 1) * size.width;
      final midY = y + size.height * .5;
      // Crisp isometric angled corridor with rounded corner bevels.
      return Path()
        ..moveTo(from, y)
        ..lineTo(from, y + size.height * .18)
        ..lineTo(to, midY + size.height * .32)
        ..lineTo(to, y + size.height);
    }

    (Color active, Color resting, Color skirt) trailColors(BiomeKind b) =>
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
            const Color(0xff476175),
          ),
          BiomeKind.desert => (
            const Color(0xffecc283),
            const Color(0xffb48a6a),
            const Color(0xff6b4228),
          ),
        };

    void drawSegment(
      Path path,
      bool reached,
      BiomeKind trailBiome, {
      bool bridge = false,
    }) {
      final (active, resting, skirt) = trailColors(trailBiome);
      final surface = highContrast
          ? (reached ? palette.route : palette.mutedInk)
          : bridge
          ? (reached ? const Color(0xffc9935b) : const Color(0xff8c6d53))
          : (reached ? active : resting);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (highContrast) {
        canvas.drawPath(
          path,
          paint
            ..strokeWidth = 24
            ..color = palette.canvas,
        );
        canvas.drawPath(
          path,
          paint
            ..strokeWidth = 17
            ..color = surface,
        );
        return;
      }

      // 2.5D extruded underside skirt shifted downward for isometric depth.
      canvas.save();
      canvas.translate(0, 5.5);
      canvas.drawPath(
        path,
        paint
          ..strokeWidth = bridge ? 26 : 23
          ..color = skirt.withValues(alpha: .72),
      );
      canvas.restore();

      // Top walkway surface.
      canvas.drawPath(
        path,
        paint
          ..strokeWidth = bridge ? 24 : 20
          ..color = surface,
      );

      // Subtle inner highlight bevel.
      canvas.drawPath(
        path,
        paint
          ..strokeWidth = bridge ? 10 : 8
          ..color = Colors.white.withValues(alpha: reached ? .22 : .10),
      );
    }

    if (position != 0 || chapter != 0) {
      final belowBiome = position == 0 && chapter > 0
          ? _biomeForChapter(chapter - 1)
          : biome;
      drawSegment(
        section(globalSlot, size.height / 2),
        pathBelowReached,
        belowBiome,
        bridge: _isBridgeSlot(template, position),
      );
    }
    drawSegment(
      section(globalSlot + 1, -size.height / 2),
      pathAboveReached,
      biome,
      bridge: _isBridgeSlot(template, position + 1),
    );
  }

  void _paintLandmarksAndProps(Canvas canvas, Size size) {
    if (highContrast) return;
    if (position == 0 || position > chapterSize) return;

    const slotsPerChapter = chapterSize + 2;
    final globalSlot = chapter * slotsPerChapter + position;
    final template = _templateForChapter(chapter);

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
            width: w * .76,
            height: h * .22,
          ),
          Paint()..color = Colors.black.withValues(alpha: .22),
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

    final stopX = _routeX(globalSlot);
    final routeCenterX = stopX * size.width;

    // Illustrated isometric bridge spanning the water crossing on the route.
    if (_isBridgeSlot(template, position)) {
      final bridgePath =
          template == _ChapterTemplate.shorelineCove ||
              template == _ChapterTemplate.forestClearing
          ? 'assets/art/journey/iso_bridge_wood.png'
          : 'assets/art/journey/iso_bridge_stone.png';
      drawSprite(
        bridgePath,
        Offset(routeCenterX, size.height * .50),
        104,
        shadow: false,
      );
      return;
    }

    // Illustrated stairway placed directly on the route for elevation climbs.
    if ((template == _ChapterTemplate.steppedRidge ||
            template == _ChapterTemplate.canyonPass) &&
        (position == 8 || position == 18)) {
      drawSprite(
        'assets/art/journey/iso_stairway.png',
        Offset(routeCenterX, size.height * .50),
        88,
        shadow: false,
      );
      return;
    }

    final onRight = stopX <= .52;
    final sideX = onRight ? size.width * .82 : size.width * .18;
    final altX = onRight ? size.width * .14 : size.width * .86;

    // Major biome-specific isometric landmarks on hero rows.
    if (position == 5 || position == 16 || position == 22) {
      final landmarkPath = switch (biome) {
        BiomeKind.ocean => 'assets/art/journey/iso_ocean_cove.png',
        BiomeKind.forest => 'assets/art/journey/iso_forest_grove.png',
        BiomeKind.winter => 'assets/art/journey/iso_winter_glacier.png',
        BiomeKind.desert => 'assets/art/journey/iso_desert_mesa.png',
      };
      drawSprite(landmarkPath, Offset(sideX, size.height * .48), 116);
      return;
    }

    // Architectural isometric ruin terrace spaced away from hero landmarks.
    if (template == _ChapterTemplate.ruinTerrace &&
        (position == 10 || position == 20)) {
      drawSprite(
        'assets/art/journey/iso_ruin_terrace.png',
        Offset(sideX, size.height * .50),
        96,
      );
      return;
    }

    // Complementary smaller biome props for natural environmental framing.
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
      drawSprite(propPath, Offset(sideX, size.height * .48), 54);
      if (template == _ChapterTemplate.forestClearing &&
          hash == 0 &&
          (stopX - .5).abs() < .18) {
        drawSprite(propPath, Offset(altX, size.height * .54), 44);
      }
    }
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
