import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

bool _isIntentionalOpaque(String path) =>
    path.startsWith('assets/art/biomes/') || path.endsWith('_terrain.webp');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('audit all assets for transparency defects and render contact sheets', () async {
    final files =
        Directory('assets/art')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.png') || f.path.endsWith('.webp'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final outDir = Directory('/tmp/asset_audit')..createSync(recursive: true);
    final findings = <String>[];
    final transparentAssets = <({String path, ui.Image image, int w, int h})>[];

    for (final file in files) {
      final relPath = file.path.replaceAll('\\', '/');
      if (_isIntentionalOpaque(relPath)) continue;

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      codec.dispose();

      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = bd!.buffer.asUint8List();
      final w = img.width;
      final h = img.height;

      var nonZero = 0;
      var lowAlpha = 0;
      var borderNonZero = 0;
      var cornerAlphaSum = 0;
      var minX = w, minY = h, maxX = -1, maxY = -1;
      var clipEdges = <String>{};

      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          final a = rgba[i + 3];
          if (a > 0) {
            nonZero++;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            if (a <= 20) lowAlpha++;
            if (x == 0 || y == 0 || x == w - 1 || y == h - 1) {
              borderNonZero++;
              if (a > 20) {
                if (x == 0) clipEdges.add('L');
                if (x == w - 1) clipEdges.add('R');
                if (y == 0) clipEdges.add('T');
                if (y == h - 1) clipEdges.add('B');
              }
            }
            if ((x < 4 || x >= w - 4) && (y < 4 || y >= h - 4)) {
              cornerAlphaSum += a;
            }
          }
        }
      }

      final area = w * h;
      final lowRatio = lowAlpha / math.max(1, area);
      final issues = <String>[];
      if (cornerAlphaSum > 0) {
        issues.add('corner_alpha_sum=$cornerAlphaSum');
      }
      if (borderNonZero > 0) {
        issues.add('border_nonzero=$borderNonZero');
      }
      if (clipEdges.isNotEmpty) {
        issues.add('clipped_edges=${clipEdges.join()}');
      }
      if (lowRatio > 0.04) {
        issues.add('low_alpha_haze=${(lowRatio * 100).toStringAsFixed(1)}%');
      }
      if (nonZero == 0) {
        issues.add('empty_image');
      }

      final status = issues.isEmpty ? 'OK' : 'DEFECT: ${issues.join(", ")}';
      if (issues.isNotEmpty) {
        findings.add('$relPath (${w}x$h): $status');
      }
      // ignore: avoid_print
      print(
        '${relPath.padRight(42)} ${w}x$h bbox=($minX,$minY,$maxX,$maxY) $status',
      );
      transparentAssets.add((path: relPath, image: img, w: w, h: h));
    }

    // Generate contact sheets in chunks of 18 assets per sheet across 5 backgrounds.
    const cols = 5; // White, Black, Magenta, Checker, Ocean/Sand
    const cellW = 128.0;
    const cellH = 128.0;
    const labelW = 220.0;
    const perPage = 16;

    for (var page = 0; page * perPage < transparentAssets.length; page++) {
      final slice = transparentAssets
          .skip(page * perPage)
          .take(perPage)
          .toList();
      final totalW = labelW + cols * cellW;
      final totalH = slice.length * cellH;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, totalW, totalH));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, totalW, totalH),
        Paint()..color = const Color(0xFF202225),
      );

      for (var r = 0; r < slice.length; r++) {
        final item = slice[r];
        final top = r * cellH;
        final tp = TextPainter(
          text: TextSpan(
            text: '${item.path.split('/').last}\n${item.w}x${item.h}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: labelW - 16);
        tp.paint(canvas, Offset(8, top + (cellH - tp.height) / 2));

        final bgs = [
          const Color(0xFFFFFFFF),
          const Color(0xFF000000),
          const Color(0xFFFF00FF),
          null, // checkerboard
          const Color(0xFFEADBB9), // Journey sand
        ];
        for (var c = 0; c < cols; c++) {
          final rect = Rect.fromLTWH(labelW + c * cellW, top, cellW, cellH);
          if (bgs[c] != null) {
            canvas.drawRect(rect, Paint()..color = bgs[c]!);
          } else {
            const sq = 16.0;
            for (var sy = 0; sy < (cellH / sq).ceil(); sy++) {
              for (var sx = 0; sx < (cellW / sq).ceil(); sx++) {
                canvas.drawRect(
                  Rect.fromLTWH(
                    rect.left + sx * sq,
                    rect.top + sy * sq,
                    sq,
                    sq,
                  ),
                  Paint()
                    ..color = ((sx + sy) % 2 == 0)
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF999999),
                );
              }
            }
          }
          final fitted = applyBoxFit(
            BoxFit.contain,
            Size(item.w.toDouble(), item.h.toDouble()),
            const Size(cellW - 12, cellH - 12),
          );
          final dst = Alignment.center.inscribe(fitted.destination, rect);
          canvas.drawImageRect(
            item.image,
            Rect.fromLTWH(0, 0, item.w.toDouble(), item.h.toDouble()),
            dst,
            Paint()..filterQuality = FilterQuality.medium,
          );
        }
      }

      final pic = recorder.endRecording();
      final sheet = await pic.toImage(totalW.toInt(), totalH.toInt());
      final png = await sheet.toByteData(format: ui.ImageByteFormat.png);
      final outPath = '${outDir.path}/sheet_${page + 1}.png';
      File(outPath).writeAsBytesSync(Uint8List.view(png!.buffer));
      sheet.dispose();
      pic.dispose();
    }

    for (final a in transparentAssets) {
      a.image.dispose();
    }

    // ignore: avoid_print
    print(
      '\n=== SUMMARY: ${transparentAssets.length} transparent assets, ${findings.length} flagged ===',
    );
    for (final f in findings) {
      // ignore: avoid_print
      print('  ! $f');
    }
  });
}
