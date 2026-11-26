import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

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
  BiomeKind.ocean => 'assets/art/biomes/ocean.webp',
  BiomeKind.forest => 'assets/art/biomes/forest.webp',
  BiomeKind.winter => 'assets/art/biomes/winter.webp',
  BiomeKind.desert => 'assets/art/biomes/desert.webp',
};

String journeyTerrainPath(BiomeKind biome) => switch (biome) {
  BiomeKind.ocean => 'assets/art/journey/ocean_terrain.webp',
  BiomeKind.forest => 'assets/art/journey/forest_terrain.webp',
  BiomeKind.winter => 'assets/art/journey/winter_terrain.webp',
  BiomeKind.desert => 'assets/art/journey/desert_terrain.webp',
};

const journeyPropPaths = <String>[
  'assets/art/journey/prop_forest_trees.webp',
  'assets/art/journey/prop_forest_rocks.webp',
  'assets/art/journey/prop_winter_pine.webp',
  'assets/art/journey/prop_winter_ice.webp',
  'assets/art/journey/prop_ocean_palm.webp',
  'assets/art/journey/prop_desert_cactus.webp',
  'assets/art/journey/prop_signpost.webp',
  'assets/art/journey/iso_platform_completed.png',
  'assets/art/journey/iso_platform_current.png',
  'assets/art/journey/iso_platform_locked.png',
  'assets/art/journey/iso_pedestal.png',
  'assets/art/journey/iso_bridge_wood.png',
  'assets/art/journey/iso_bridge_stone.png',
  'assets/art/journey/iso_ruin_terrace.png',
  'assets/art/journey/iso_ocean_cove.png',
  'assets/art/journey/iso_forest_grove.png',
  'assets/art/journey/iso_winter_glacier.png',
  'assets/art/journey/iso_desert_mesa.png',
];

String tipAssetPath(PathTip tip) => 'assets/art/tips/${tip.name}.webp';

String boostAssetPath(Boost boost) => switch (boost) {
  Boost.doubleTen || Boost.doubleFifteen => 'assets/art/ui/boost_2x_fast.webp',
  Boost.doubleThirty || Boost.doubleSixty => 'assets/art/ui/boost_2x_long.webp',
  Boost.tripleFifteen => 'assets/art/ui/boost_3x.webp',
  Boost.quadrupleTen => 'assets/art/ui/boost_4x.webp',
  Boost.crateFrequency => 'assets/art/resources/crate.webp',
};

/// Normalized visible vertical bounds `(top, bottom)` inside each 192x192 tip
/// PNG (excluding transparent padding) so bottom-to-top discovery reveals map
/// directly to the visible collectible height.
const tipVisibleVerticalBounds = <PathTip, (double, double)>{
  PathTip.classic: (0.040, 0.960),
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

  /// Preloads lightweight shared coin art at startup; tip art loads lazily on
  /// demand so unused tip textures do not occupy startup CPU/memory.
  Future<void> preloadAll() async {
    const coinPath = 'assets/art/resources/coin.webp';
    if (!_images.containsKey(coinPath)) {
      await _load(coinPath, targetWidth: 96, targetHeight: 96);
    }
  }

  /// Decodes the shared Journey terrains and props ahead of rendering.
  Future<void> preloadBiomes() => Future.wait([
    for (final biome in BiomeKind.values)
      if (!_images.containsKey(journeyTerrainPath(biome)))
        _load(journeyTerrainPath(biome)),
    for (final prop in journeyPropPaths)
      if (!_images.containsKey(prop)) _load(prop),
  ]);

  /// Evicts Journey-specific terrain and prop textures when leaving the Journey
  /// screen so decoded bitmaps do not remain pinned across other views.
  int _journeyGeneration = 0;

  void evictJourneyAssets() {
    _journeyGeneration++;
    final keys = <String>[
      for (final biome in BiomeKind.values) journeyTerrainPath(biome),
      ...journeyPropPaths,
    ];
    for (final key in keys) {
      final image = _images.remove(key);
      image?.dispose();
    }
  }

  static bool _isJourneyAsset(String assetPath) =>
      assetPath.startsWith('assets/art/biomes/') ||
      assetPath.startsWith('assets/art/journey/');

  Future<void> _load(
    String assetPath, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    final generation = _isJourneyAsset(assetPath) ? _journeyGeneration : -1;
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (generation != -1 && generation != _journeyGeneration) {
        frame.image.dispose();
        return;
      }
      _images[assetPath] = frame.image;
      notifyListeners();
    } catch (_) {
      // Headless unit tests without asset bundle fall back to vector painters.
    } finally {
      _loading.remove(assetPath);
    }
  }
}
