import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/path_tips.dart';
import '../../model/progression.dart';
import '../../model/user_preferences.dart';

enum BiomeKind { ocean, forest, winter, desert }

/// Maps each of the 22 themes to its corresponding illustrated environment.
BiomeKind biomeForTheme(PathwiseTheme theme) => switch (theme) {
  PathwiseTheme.oceanicBreeze ||
  PathwiseTheme.blackwater ||
  PathwiseTheme.midnightSlate ||
  PathwiseTheme.tidal ||
  PathwiseTheme.crt ||
  PathwiseTheme.neon => BiomeKind.ocean,
  PathwiseTheme.field ||
  PathwiseTheme.forestMint ||
  PathwiseTheme.koi ||
  PathwiseTheme.highPass => BiomeKind.forest,
  PathwiseTheme.glacier ||
  PathwiseTheme.chalk ||
  PathwiseTheme.amoledCarbon ||
  PathwiseTheme.royalVelvet ||
  PathwiseTheme.violet ||
  PathwiseTheme.signal => BiomeKind.winter,
  PathwiseTheme.terracotta ||
  PathwiseTheme.warmWalnut ||
  PathwiseTheme.canyon ||
  PathwiseTheme.parchment ||
  PathwiseTheme.gilded ||
  PathwiseTheme.basinGold ||
  PathwiseTheme.copperSky => BiomeKind.desert,
};

String biomeAssetPath(BiomeKind biome) => switch (biome) {
  BiomeKind.ocean => 'assets/art/biomes/ocean.png',
  BiomeKind.forest => 'assets/art/biomes/forest.png',
  BiomeKind.winter => 'assets/art/biomes/winter.png',
  BiomeKind.desert => 'assets/art/biomes/desert.png',
};

String tipAssetPath(PathTip tip) => tip == PathTip.classic
    ? 'assets/art/tips/robot.png'
    : 'assets/art/tips/${tip.name}.png';

String boostAssetPath(Boost boost) => switch (boost) {
  Boost.doubleTen || Boost.doubleFifteen => 'assets/art/ui/boost_2x_fast.png',
  Boost.doubleThirty || Boost.doubleSixty => 'assets/art/ui/boost_2x_long.png',
  Boost.tripleFifteen => 'assets/art/ui/boost_3x.png',
  Boost.quadrupleTen => 'assets/art/ui/boost_4x.png',
  Boost.crateFrequency => 'assets/art/resources/crate.png',
};

/// Normalized visible vertical bounds `(top, bottom)` inside each 192x192 tip
/// PNG (excluding transparent padding) so bottom-to-top discovery reveals map
/// directly to the visible collectible height.
const tipVisibleVerticalBounds = <PathTip, (double, double)>{
  PathTip.arrow: (0.047, 0.953),
  PathTip.bee: (0.010, 0.990),
  PathTip.cat: (0.104, 0.896),
  PathTip.crystal: (0.010, 0.990),
  PathTip.dog: (0.135, 0.865),
  PathTip.dragon: (0.042, 0.958),
  PathTip.flame: (0.010, 0.990),
  PathTip.fox: (0.052, 0.948),
  PathTip.frog: (0.047, 0.953),
  PathTip.ghost: (0.010, 0.990),
  PathTip.panda: (0.073, 0.927),
  PathTip.penguin: (0.036, 0.964),
  PathTip.phoenix: (0.010, 0.990),
  PathTip.rabbit: (0.010, 0.990),
  PathTip.robot: (0.057, 0.943),
  PathTip.rocket: (0.010, 0.990),
  PathTip.star: (0.010, 0.990),
  PathTip.turtle: (0.010, 0.990),
  PathTip.ufo: (0.083, 0.917),
};

/// Asynchronous decoded [ui.Image] cache for high-frequency [CustomPainter]s
/// such as the live gameplay board tip layer.
final class GameAssetCache extends ChangeNotifier {
  GameAssetCache._();
  static final instance = GameAssetCache._();

  final _images = <String, ui.Image>{};
  final _loading = <String>{};

  ui.Image? imageFor(String assetPath) {
    final cached = _images[assetPath];
    if (cached != null) return cached;
    if (_loading.add(assetPath)) {
      unawaited(_load(assetPath));
    }
    return null;
  }

  /// Preloads all illustrated tip PNGs at startup so gameplay boards and
  /// previews never briefly show fallback vector shapes.
  Future<void> preloadAll() async {
    final paths = <String>{
      for (final tip in PathTip.values)
        if (tip != PathTip.classic) tipAssetPath(tip),
    };
    await Future.wait([
      for (final path in paths)
        if (!_images.containsKey(path)) _load(path),
    ]);
  }

  Future<void> _load(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _images[assetPath] = frame.image;
      codec.dispose();
      notifyListeners();
    } catch (_) {
      // Headless unit tests without asset bundle fall back to vector painters.
    } finally {
      _loading.remove(assetPath);
    }
  }
}

/// Resolves the active [PathwiseTheme] from a [BoardPalette].
PathwiseTheme themeForPalette(BoardPalette palette) {
  for (final entry in BoardPalette.palettes.entries) {
    if (entry.value == palette) return entry.key;
  }
  return PathwiseTheme.field;
}
