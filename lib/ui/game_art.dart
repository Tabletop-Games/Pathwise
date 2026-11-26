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
  treasure,
  treasureOpen,
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

  String get _rasterAsset => switch (kind) {
    ArtKind.coin => 'assets/art/resources/coin.webp',
    ArtKind.coinStack1 => 'assets/art/resources/coin_stack_1.webp',
    ArtKind.coinStack2 => 'assets/art/resources/coin_stack_2.webp',
    ArtKind.coinStack3 => 'assets/art/resources/coin_stack_3.webp',
    ArtKind.coinStack4 => 'assets/art/resources/coin_stack_4.webp',
    ArtKind.coinStack5 => 'assets/art/resources/coin_stack_5.webp',
    ArtKind.hint => 'assets/art/resources/hint.webp',
    ArtKind.gift => 'assets/art/ui/gift.webp',
    ArtKind.treasure => 'assets/art/resources/chest_closed.webp',
    ArtKind.treasureOpen => 'assets/art/resources/chest_open.webp',
    ArtKind.crate => 'assets/art/resources/crate.webp',
    ArtKind.store => 'assets/art/ui/store.webp',
    ArtKind.noAds => 'assets/art/ui/remove_ads.webp',
    ArtKind.brush => 'assets/art/ui/themes_forever.webp',
    ArtKind.crown => 'assets/art/ui/premium.webp',
    ArtKind.levels => 'assets/art/ui/compass.webp',
    ArtKind.calendar => 'assets/art/ui/daily.webp',
    ArtKind.wheel => 'assets/art/ui/wheel_ticket.webp',
    ArtKind.research => 'assets/art/ui/research.webp',
    ArtKind.bolt => 'assets/art/ui/boost.webp',
    ArtKind.freeze => 'assets/art/ui/freeze.webp',
    ArtKind.timer => 'assets/art/ui/timer.webp',
    ArtKind.flame => 'assets/art/ui/flame.webp',
    ArtKind.trophy => 'assets/art/ui/trophy.webp',
    ArtKind.lock => 'assets/art/ui/lock.webp',
    ArtKind.check => 'assets/art/ui/check.webp',
    ArtKind.video => 'assets/art/ui/video_reward.webp',
  };

  @override
  Widget build(BuildContext context) {
    final asset = _rasterAsset;
    final decodePx = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(24, 192);
    final art = SizedBox.square(
      dimension: size,
      child: Image.asset(
        asset,
        width: size,
        height: size,
        cacheWidth: decodePx,
        cacheHeight: decodePx,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            CustomPaint(painter: _ArtPainter(kind, palette)),
      ),
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
    case ArtKind.treasure:
      paintResource(canvas, p, ResourceForm.treasure);
    case ArtKind.treasureOpen:
      paintResource(canvas, p, ResourceForm.treasureOpen);
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
