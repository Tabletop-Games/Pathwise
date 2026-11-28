import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/model/economy.dart';
import '../../lib/ui/art/game_assets.dart';

/// Terrain strips and biome backdrops are intentionally opaque.
bool _opaqueByDesign(String path) =>
    path.startsWith('assets/art/biomes/') || path.endsWith('_terrain.webp');

List<File> _files(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String _libSource() => [
  for (final file in _files('lib').where((f) => f.path.endsWith('.dart')))
    file.readAsStringSync(),
].join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every tip has artwork and the tips folder holds nothing else', () {
    final expected = {for (final tip in PathTip.values) tipAssetPath(tip)};
    final found = {
      for (final file in _files('assets/art/tips'))
        file.path.replaceAll('\\', '/'),
    };
    expect(found, expected);
  });

  test('every bundled asset folder is declared in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final folder in [
      'art/tips',
      'art/resources',
      'art/ui',
      'art/biomes',
    ]) {
      expect(pubspec, contains('assets/$folder/'), reason: folder);
    }
    expect(pubspec, contains('assets/art/journey/'));
    expect(pubspec, contains('assets/audio/'));
    expect(pubspec, contains('assets/data/fortune-prizes.json'));
  });

  test('no bundled artwork or sound is orphaned', () {
    final source = _libSource();
    final orphans = [
      for (final dir in ['assets/art', 'assets/audio'])
        for (final file in _files(dir))
          if (!file.path.startsWith('assets/art/tips/') &&
              !source.contains(file.path.replaceAll('\\', '/')))
            file.path,
    ];
    expect(orphans, isEmpty, reason: 'unreferenced assets: $orphans');
  });

  test('no two bundled assets are byte-identical', () {
    final seen = <String, String>{};
    for (final file in [..._files('assets/art'), ..._files('assets/audio')]) {
      final digest = sha256.convert(file.readAsBytesSync()).toString();
      expect(
        seen[digest],
        isNull,
        reason: '${file.path} duplicates ${seen[digest]}',
      );
      seen[digest] = file.path;
    }
  });

  test(
    'transparent artwork has no residual alpha in its outer 2px border',
    () async {
      final files = [
        for (final file in _files('assets/art'))
          if ((file.path.endsWith('.webp') || file.path.endsWith('.png')) &&
              !_opaqueByDesign(file.path.replaceAll('\\', '/')))
            file,
      ];
      expect(files.length, greaterThan(50));
      for (final file in files) {
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final width = image.width;
        final height = image.height;
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final border = x < 2 || x >= width - 2 || y < 2 || y >= height - 2;
            if (!border) continue;
            final alpha = data.getUint8((y * width + x) * 4 + 3);
            expect(
              alpha,
              0,
              reason: '${file.path} has residual alpha $alpha at ($x, $y)',
            );
          }
        }
        image.dispose();
        codec.dispose();
      }
    },
  );
}
