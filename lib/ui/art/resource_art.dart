import 'package:material_ui/material_ui.dart';

import '../../model/app_themes.dart';
import 'vector_path.dart';

enum ResourceForm {
  gift,
  crate,
  treasure,
  treasureOpen,
  hint,
  flame,
  freeze,
  crown,
  pass,
  shield,
  medal,
}

const _resourceLayers = <ResourceForm, (String, String, String)>{
  ResourceForm.gift: (
    'M 3 9 L 21 9 L 20 21 L 4 21 Z',
    'M 1 8 L 23 8 L 23 12 L 1 12 Z M 9 8 Q 0 4 6 2 Q 10 1 12 7 Q 16 0 20 3 Q 23 6 15 8 Z',
    'M 10 8 L 14 8 L 14 21 L 10 21 Z',
  ),
  ResourceForm.crate: (
    'M 1 10 L 12 4 L 23 9 L 23 16 L 12 22 L 1 17 Z',
    'M 1 10 L 12 4 L 23 9 L 12 15 Z',
    'M 12 15 L 23 9 L 23 16 L 12 22 Z M 9 10 L 12 8 L 15 9 L 12 11 Z',
  ),
  ResourceForm.treasure: (
    'M 2 11 L 22 11 L 22 19 Q 22 21 20 21 L 4 21 Q 2 21 2 19 Z',
    'M 2 11 L 2 9 Q 2 4 7 4 L 17 4 Q 22 4 22 9 L 22 11 Z',
    'M 10 10 L 14 10 L 14 16 L 10 16 Z M 5 18 L 19 18 L 19 19 L 5 19 Z',
  ),
  ResourceForm.treasureOpen: (
    'M 2 13 L 22 13 L 22 19 Q 22 21 20 21 L 4 21 Q 2 21 2 19 Z',
    'M 2 11 L 3 6 Q 4 3 8 3 L 18 3 Q 21 3 21 6 L 22 8 Z',
    'M 10 12 L 14 12 L 14 16 L 10 16 Z M 6 17 L 18 17 L 18 19 L 6 19 Z',
  ),
  ResourceForm.hint: (
    'M 8 18 Q 8 15 5 12 C 1 3 12 0 17 4 Q 23 9 17 14 Q 15 16 15 18 Z M 9 20 L 15 20 L 14 22 L 10 22 Z',
    'M 8 12 Q 4 8 8 5 Q 11 2 15 5 Q 11 5 10 11 L 10 16 Z',
    'M 11 10 L 13 10 L 13 17 L 11 17 Z',
  ),
  ResourceForm.flame: (
    'M 13 1 C 13 8 21 9 21 16 C 21 25 3 25 3 16 Q 3 11 9 7 L 9 12 Q 12 8 13 1 Z',
    'M 13 12 Q 18 17 14 21 Q 8 23 8 18 Q 8 15 13 12 Z',
    '',
  ),
  ResourceForm.freeze: (
    'M 12 1 L 21 7 L 21 17 L 12 23 L 3 17 L 3 7 Z',
    'M 12 1 L 12 23 L 3 17 L 3 7 Z',
    'M 11 5 L 13 5 L 13 19 L 11 19 Z M 6 8 L 19 15 L 18 17 L 5 10 Z M 18 8 L 19 10 L 6 17 L 5 15 Z',
  ),
  ResourceForm.crown: (
    'M 3 19 L 2 6 L 8 10 L 12 3 L 16 10 L 22 6 L 21 19 Z',
    'M 3 17 L 21 17 L 21 21 L 3 21 Z',
    'M 12 10 L 15 13 L 12 16 L 9 13 Z',
  ),
  ResourceForm.pass: (
    'M 3 5 L 18 2 L 22 17 L 7 21 Z',
    'M 5 11 L 11 8 L 14 11 L 18 7 L 21 14 L 6 18 Z',
    'M 12 5 L 15 4 L 16 7 L 13 8 Z',
  ),
  ResourceForm.shield: (
    'M 12 2 L 21 6 L 20 14 Q 18 20 12 22 Q 6 20 4 14 L 3 6 Z',
    'M 12 2 L 12 22 Q 6 20 4 14 L 3 6 Z',
    'M 7 12 L 9 10 L 11 13 L 16 8 L 18 10 L 11 17 Z',
  ),
  ResourceForm.medal: (
    'M 12 1 L 21 6 L 21 16 L 12 22 L 3 16 L 3 6 Z',
    'M 12 4 L 18 8 L 18 15 L 12 19 L 6 15 L 6 8 Z',
    'M 11 7 L 14 10 L 17 11 L 14 13 L 12 17 L 10 13 L 7 11 L 10 10 Z',
  ),
};

final _vectors = {
  for (final MapEntry(key: kind, value: path) in _resourceLayers.entries)
    kind: (
      compileVector(path.$1),
      compileVector(path.$2),
      compileVector(path.$3),
    ),
};

Color _base(BoardPalette p, ResourceForm form) => switch (form) {
  ResourceForm.freeze => Color.lerp(const Color(0xff83a5ac), p.route, .25)!,
  ResourceForm.flame => Color.lerp(const Color(0xffbc775e), p.accent, .25)!,
  ResourceForm.treasure ||
  ResourceForm.treasureOpen ||
  ResourceForm.crown ||
  ResourceForm.medal ||
  ResourceForm.hint => Color.lerp(const Color(0xffb39567), p.accent, .35)!,
  _ => Color.lerp(const Color(0xff789389), p.route, .32)!,
};

void paintResource(Canvas canvas, BoardPalette palette, ResourceForm form) {
  final (base, light, detail) = _vectors[form]!;
  final color = _base(palette, form);
  canvas.save();
  canvas.scale(1 / 12);
  canvas.translate(-12, -12);
  canvas.drawPath(base, Paint()..color = color);
  canvas.drawPath(
    light,
    Paint()
      ..color = Color.lerp(
        color,
        palette.dark ? palette.ink : palette.surface,
        .5,
      )!,
  );
  canvas.drawPath(
    detail,
    Paint()
      ..color = Color.lerp(
        color,
        palette.dark ? palette.canvas : palette.ink,
        .5,
      )!,
  );
  canvas.restore();
}

void paintCoins(Canvas canvas, BoardPalette palette, int count) {
  final face = Color.lerp(const Color(0xffd6bc8a), palette.accent, .31)!;
  final edge = Color.lerp(
    face,
    palette.dark ? palette.canvas : palette.ink,
    .40,
  )!;
  void coin(Offset center, double radius) {
    canvas.drawCircle(
      center.translate(0, radius * .09),
      radius,
      Paint()..color = edge,
    );
    canvas.drawCircle(center, radius * .94, Paint()..color = face);
    canvas.drawCircle(
      center,
      radius * .73,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .08,
    );
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - radius * .47, center.dy + radius * .24)
        ..relativeLineTo(radius * .37, 0)
        ..relativeLineTo(0, -radius * .44)
        ..relativeLineTo(radius * .53, 0),
      Paint()
        ..color = edge
        ..strokeWidth = radius * .11
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  if (count == 1) {
    coin(Offset.zero, .82);
    return;
  }
  for (var index = count - 1; index >= 0; index--) {
    coin(Offset((index % 3 - 1) * .48, index < 3 ? .34 : -.24), .43);
  }
}
