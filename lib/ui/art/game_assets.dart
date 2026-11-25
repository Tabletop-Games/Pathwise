import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import '../../model/path_tips.dart';
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
