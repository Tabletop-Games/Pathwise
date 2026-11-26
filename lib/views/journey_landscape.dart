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
    final colors = _biomeColors(biome);
    final template = _templateForChapter(chapter);
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = colors.ground);

    if (highContrast) return;

    // Continuous diagonal isometric terrace planes that align across row edges.
    final slope = size.height * .48;
    final bandPaint = Paint()..color = colors.ridge.withValues(alpha: .26);
    final hiPaint = Paint()..color = colors.highlight.withValues(alpha: .16);
    final phase = ((chapter * slotsPerChapter + position) % 6) / 6.0;
    final xShift = (phase - 0.5) * size.width * 0.18;

    final leftTerrace = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * .32 + xShift, 0)
      ..lineTo(size.width * .18 + xShift, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(leftTerrace, bandPaint);

    final rightTerrace = Path()
      ..moveTo(size.width * .72 - xShift, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * .84 - xShift, size.height)
      ..close();
    canvas.drawPath(rightTerrace, hiPaint);

    // Water channel / lagoon band on bridge rows.
    if (_isWaterBand(template, position)) {
      final waterRect = Rect.fromLTWH(
        0,
        size.height * .16,
        size.width,
        size.height * .68,
      );
      canvas.drawRect(waterRect, Paint()..color = colors.water);
      canvas.drawLine(
        Offset(0, waterRect.top),
        Offset(size.width, waterRect.top),
        Paint()
          ..color = Colors.white.withValues(alpha: .22)
          ..strokeWidth = 2.5,
      );
      canvas.drawLine(
        Offset(0, waterRect.bottom),
        Offset(size.width, waterRect.bottom),
        Paint()
          ..color = colors.ridge.withValues(alpha: .55)
          ..strokeWidth = 3.0,
      );
    }

    // Natural diagonal isometric biome transition at chapter entry/exit.
    if (position == 0 && chapter > 0) {
      final prevColors = _biomeColors(_biomeForChapter(chapter - 1));
      final wedge = Path()
        ..moveTo(0, size.height * .65)
        ..lineTo(size.width, size.height * .95)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(wedge, Paint()..color = prevColors.ground);
      canvas.drawLine(
        Offset(0, size.height * .65),
        Offset(size.width, size.height * .95),
        Paint()
          ..color = colors.highlight.withValues(alpha: .50)
          ..strokeWidth = 3,
      );
    } else if (position == slotsPerChapter - 1) {
      final nextColors = _biomeColors(_biomeForChapter(chapter + 1));
      final wedge = Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height * .28)
        ..lineTo(0, size.height * .04)
        ..close();
      canvas.drawPath(wedge, Paint()..color = nextColors.ground);
      canvas.drawLine(
        Offset(0, size.height * .04),
        Offset(size.width, size.height * .28),
        Paint()
          ..color = nextColors.highlight.withValues(alpha: .50)
          ..strokeWidth = 3,
      );
    }
    if (slope < 0) return;
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

    // Illustrated isometric bridge across water channels / canyon gaps.
    if (_isBridgeSlot(template, position)) {
      final bridgePath =
          template == _ChapterTemplate.shorelineCove ||
              template == _ChapterTemplate.forestClearing
          ? 'assets/art/journey/iso_bridge_wood.webp'
          : 'assets/art/journey/iso_bridge_stone.webp';
      drawSprite(
        bridgePath,
        Offset(routeCenterX, size.height * .52),
        96,
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
        BiomeKind.ocean => 'assets/art/journey/iso_ocean_cove.webp',
        BiomeKind.forest => 'assets/art/journey/iso_forest_grove.webp',
        BiomeKind.winter => 'assets/art/journey/iso_winter_glacier.webp',
        BiomeKind.desert => 'assets/art/journey/iso_desert_mesa.webp',
      };
      drawSprite(landmarkPath, Offset(sideX, size.height * .48), 112);
      return;
    }

    // Architectural isometric structures (ruin terraces & stairways) spaced
    // away from hero landmarks so adjacent rows never overlap.
    if ((template == _ChapterTemplate.ruinTerrace ||
            template == _ChapterTemplate.steppedRidge) &&
        (position == 10 || position == 20)) {
      final structPath = position.isEven
          ? 'assets/art/journey/iso_ruin_terrace.webp'
          : 'assets/art/journey/iso_stairway.webp';
      drawSprite(structPath, Offset(sideX, size.height * .50), 92);
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
