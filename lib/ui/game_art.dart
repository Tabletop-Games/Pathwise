import 'package:material_ui/material_ui.dart';

import '../model/app_themes.dart';
import 'art/control_art.dart';
import 'art/resource_art.dart';

/// Colour helpers shared by all original artwork. Every colour is derived from
/// the equipped palette so illustrations belong to the active theme.
/// The kinds of artwork [GameArt] can paint.
enum ArtKind {
  coin,
  coinStack1,
  coinStack2,
  coinStack3,
  coinStack4,
  coinStack5,
  gift,
  crate,
  store,
  noAds,
  brush,
  crown,
  bolt,
  hint,
  flame,
  freeze,
  trophy,
  lock,
  check,
  video,
  research,
  wheel,
  timer,
  levels,
  calendar,
}

/// A square illustration. Painted in a unit box so it scales cleanly.
class GameArt extends StatelessWidget {
  const GameArt(
    this.kind, {
    required this.palette,
    this.size = 40,
    this.semanticLabel,
    super.key,
  });

  final ArtKind kind;
  final BoardPalette palette;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final art = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ArtPainter(kind, palette)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: art);
    return Semantics(image: true, label: semanticLabel, child: art);
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.kind, this.palette);
  final ArtKind kind;
  final BoardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide / 2);
    paintArt(canvas, kind, palette);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.kind != kind || old.palette != palette;
}

/// Paints [kind] in a [-1, 1] box centred on the origin.
void paintArt(Canvas canvas, ArtKind kind, BoardPalette p) {
  switch (kind) {
    case ArtKind.coin:
    case ArtKind.coinStack1:
    case ArtKind.coinStack2:
    case ArtKind.coinStack3:
    case ArtKind.coinStack4:
    case ArtKind.coinStack5:
      paintCoins(canvas, p, kind == ArtKind.coin ? 1 : kind.index + 1);
    case ArtKind.gift:
      paintResource(canvas, p, ResourceForm.gift);
    case ArtKind.crate:
      paintResource(canvas, p, ResourceForm.crate);
    case ArtKind.noAds:
      paintResource(canvas, p, ResourceForm.shield);
    case ArtKind.brush:
      paintResource(canvas, p, ResourceForm.pass);
    case ArtKind.crown:
      paintResource(canvas, p, ResourceForm.crown);
    case ArtKind.hint:
      paintResource(canvas, p, ResourceForm.hint);
    case ArtKind.flame:
      paintResource(canvas, p, ResourceForm.flame);
    case ArtKind.freeze:
      paintResource(canvas, p, ResourceForm.freeze);
    case ArtKind.trophy:
      paintResource(canvas, p, ResourceForm.medal);
    case ArtKind.store:
      paintControl(canvas, ControlGlyph.store, p.ink);
    case ArtKind.bolt:
      paintControl(canvas, ControlGlyph.boost, p.ink);
    case ArtKind.lock:
      paintControl(canvas, ControlGlyph.lock, p.ink);
    case ArtKind.check:
      paintControl(canvas, ControlGlyph.check, p.route);
    case ArtKind.video:
      paintControl(canvas, ControlGlyph.play, p.ink);
    case ArtKind.research:
      paintControl(canvas, ControlGlyph.research, p.ink);
    case ArtKind.wheel:
      paintControl(canvas, ControlGlyph.wheel, p.ink);
    case ArtKind.timer:
      paintControl(canvas, ControlGlyph.timer, p.ink);
    case ArtKind.levels:
      paintControl(canvas, ControlGlyph.levels, p.ink);
    case ArtKind.calendar:
      paintControl(canvas, ControlGlyph.calendar, p.ink);
  }
}
