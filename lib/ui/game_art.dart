import 'package:material_ui/material_ui.dart';

/// The illustrations [GameArt] can show. Each maps to a bundled raster asset.
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

/// A square illustration drawn from the bundled artwork, decoded at display size.
class GameArt extends StatelessWidget {
  const GameArt(
    this.kind, {
    this.size = 40,
    this.semanticLabel,
    super.key,
  });

  final ArtKind kind;
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
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: art);
    return Semantics(image: true, label: semanticLabel, child: art);
  }
}
