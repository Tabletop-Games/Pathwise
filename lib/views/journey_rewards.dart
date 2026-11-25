import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/billing_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/journey.dart';
import '../model/user_preferences.dart';
import '../ui/art/game_assets.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'components/puzzle_board.dart';
import 'components/tip_art.dart';

class CompletionBonus extends StatefulWidget {
  const CompletionBonus(this.model, {super.key});
  final AppModel model;

  @override
  State<CompletionBonus> createState() => _CompletionBonusState();
}

class _CompletionBonusState extends State<CompletionBonus>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _track = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  );
  bool _busy = false;
  bool _unavailable = false;
  var _visiblePosition = 0.0;
  var _reduced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    _updateMotion(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _updateMotion(state);

  void _updateMotion(AppLifecycleState? state) {
    if (!_reduced &&
        widget.model.selectedMultiplier == null &&
        widget.model.canMultiplyCompletion &&
        (state == null || state == AppLifecycleState.resumed)) {
      if (!_track.isAnimating) {
        _track.repeat(reverse: true);
      }
    } else {
      _track.stop();
    }
  }

  bool get _current =>
      mounted &&
      ModalRoute.isCurrentOf(context) == true &&
      widget.model.canMultiplyCompletion;

  Future<void> _claim(AdService ads) async {
    final model = widget.model;
    if (model.selectedMultiplier == null) {
      model.selectCompletionMultiplier(accessibleMultiplier);
    }
    final reward = model.completionRewardCallback();
    if (reward == null) return;
    setState(() {
      _busy = true;
      _unavailable = false;
    });
    var shown = false;
    try {
      if (model.onlineReady && _current && !ads.videoReady) {
        await ads.prepare(canPresent: () => _current && model.onlineReady);
      }
      if (model.onlineReady && _current && ads.videoReady) {
        shown = await ads.watchVideo(
          reward,
          waitForReward: true,
          canPresent: () => _current && model.onlineReady,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _unavailable = !shown;
        });
      }
    }
  }

  void _stopAtCurrent() {
    final model = widget.model;
    if (model.selectedMultiplier != null) return;
    _track.stop();
    _track.value = _visiblePosition;
    model.selectCompletionMultiplier(multiplierAt(_visiblePosition));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _track.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (!model.canMultiplyCompletion) return const SizedBox.shrink();
    final ads = context.read<AdService>();
    final palette = context.palette;
    final selected = model.selectedMultiplier;
    final mult = selected ?? accessibleMultiplier;
    final extra = economy.clearReward(PlayMode.levels) * (mult - 1);
    final total = model.completionCoins + extra;
    final buying = context.watch<BillingService>().buying;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        children: [
          if (!_reduced) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: selected == null ? _stopAtCurrent : null,
              child: AnimatedBuilder(
                animation: _track,
                builder: (context, _) {
                  _visiblePosition = _track.value;
                  return _MultiplierTrack(
                    _visiblePosition,
                    stopped: selected != null,
                    palette: palette,
                  );
                },
              ),
            ),
            if (selected == null) ...[
              const SizedBox(height: 10),
              ActionPill(
                label: 'Stop',
                tone: ActionTone.primary,
                icon: Icons.touch_app_rounded,
                onTap: _stopAtCurrent,
              ),
            ],
          ],
          if (selected != null || _reduced) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CoinMark(size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$mult× bonus · +$extra coins ($total total)',
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ActionPill(
              label: _busy ? 'Preparing…' : 'Watch ad for +$extra coins',
              tone: ActionTone.primary,
              icon: Icons.play_circle_filled_rounded,
              onTap: _busy || buying ? null : () => _claim(ads),
            ),
            if (_unavailable)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Video unavailable. Try again or continue.',
                  style: TextStyle(color: palette.mutedInk, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MultiplierTrack extends StatelessWidget {
  const _MultiplierTrack(
    this.position, {
    required this.stopped,
    required this.palette,
  });
  final double position;
  final bool stopped;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final activeIndex = multiplierRegions.indexWhere(
      (zone) => position <= zone.$1,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final pointerX = (constraints.maxWidth * position).clamp(
          10.0,
          constraints.maxWidth - 10.0,
        );
        return SizedBox(
          height: 60,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 15,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: palette.dark ? .40 : .14,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                    child: Row(
                      children: [
                        for (final (index, region) in multiplierRegions.indexed)
                          Expanded(
                            flex:
                                ((region.$1 -
                                            (index == 0
                                                ? 0
                                                : multiplierRegions[index - 1]
                                                      .$1)) *
                                        100)
                                    .round(),
                            child: _MultiplierSegment(
                              multiplier: region.$2,
                              active: index == activeIndex,
                              stopped: stopped,
                              isFirst: index == 0,
                              isLast: index == multiplierRegions.length - 1,
                              palette: palette,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: pointerX - 12,
                top: 0,
                height: 18,
                child: SizedBox(
                  key: const ValueKey('multiplier-pointer'),
                  width: 24,
                  child: CustomPaint(painter: _PointerPainter(palette)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MultiplierSegment extends StatelessWidget {
  const _MultiplierSegment({
    required this.multiplier,
    required this.active,
    required this.stopped,
    required this.isFirst,
    required this.isLast,
    required this.palette,
  });

  final int multiplier;
  final bool active;
  final bool stopped;
  final bool isFirst;
  final bool isLast;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final selected = stopped && active;
    final isJackpot = multiplier == 4;
    final jackpotGold = Color.lerp(
      palette.accent,
      const Color(0xFFFFC247),
      palette.dark ? .55 : .42,
    )!;
    final colors = selected
        ? (isJackpot
              ? [Color.lerp(jackpotGold, Colors.white, .22)!, jackpotGold]
              : [palette.buttonTop, palette.buttonBottom])
        : isJackpot
        ? [
            Color.lerp(palette.surface, jackpotGold, palette.dark ? .72 : .68)!,
            Color.lerp(palette.surface, jackpotGold, palette.dark ? .48 : .44)!,
          ]
        : multiplier == 3
        ? [
            Color.lerp(
              palette.surface,
              palette.route,
              palette.dark ? .44 : .34,
            )!,
            Color.lerp(
              palette.surface,
              palette.route,
              palette.dark ? .24 : .18,
            )!,
          ]
        : [
            Color.lerp(palette.cardTop, palette.ink, palette.dark ? .06 : .04)!,
            Color.lerp(palette.quiet, palette.ink, palette.dark ? .08 : .06)!,
          ];
    final jackpotInk =
        ThemeData.estimateBrightnessForColor(jackpotGold) == Brightness.dark
        ? Colors.white
        : const Color(0xFF2B1A04);
    final labelColor = selected
        ? (isJackpot ? jackpotInk : palette.onRoute)
        : (isJackpot ? jackpotInk : palette.ink);
    return Container(
      margin: EdgeInsets.only(right: isLast ? 0 : 1.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        border: selected
            ? Border.all(
                color: isJackpot ? palette.ink : palette.accent,
                width: 2.2,
              )
            : (!stopped && active)
            ? Border.all(
                color: (isJackpot ? jackpotGold : palette.route).withValues(
                  alpha: .85,
                ),
                width: 1.5,
              )
            : Border(
                top: BorderSide(
                  color: Colors.white.withValues(
                    alpha: palette.dark ? .22 : .65,
                  ),
                  width: 1,
                ),
                bottom: BorderSide(
                  color: Colors.black.withValues(
                    alpha: palette.dark ? .42 : .18,
                  ),
                  width: 1.5,
                ),
                left: isFirst
                    ? BorderSide(color: palette.cardEdge, width: 1)
                    : BorderSide.none,
                right: isLast
                    ? BorderSide(color: palette.cardEdge, width: 1)
                    : BorderSide.none,
              ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!stopped && active)
            DecoratedBox(
              decoration: BoxDecoration(
                color: (isJackpot ? jackpotGold : palette.route).withValues(
                  alpha: palette.dark ? .22 : .16,
                ),
              ),
            ),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$multiplier×',
                maxLines: 1,
                style: TextStyle(
                  color: labelColor,
                  fontWeight: isJackpot ? FontWeight.w900 : FontWeight.w800,
                  fontSize: isJackpot ? 18 : 15,
                  letterSpacing: -.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter(this.palette);
  final BoardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final halo = Paint()
      ..color = palette.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeJoin = StrokeJoin.round;
    final goldCap = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(palette.accent, Colors.white, .34)!,
          palette.accent,
        ],
      ).createShader(Rect.fromLTWH(cx - 10, 0, 20, 17))
      ..style = PaintingStyle.fill;
    final head = Path()
      ..moveTo(cx - 9.5, 1.5)
      ..lineTo(cx + 9.5, 1.5)
      ..lineTo(cx, 16.5)
      ..close();
    canvas.drawPath(head, halo);
    canvas.drawPath(head, goldCap);
    canvas.drawPath(
      head,
      Paint()
        ..color = palette.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.palette != palette;
}

/// Progressive bottom-to-top reveal of the upcoming mystery collectible.
class ProgressiveDiscoveryArt extends StatelessWidget {
  const ProgressiveDiscoveryArt({
    required this.item,
    required this.palette,
    required this.progress,
    this.size = 96,
    super.key,
  });

  final String item;
  final BoardPalette palette;
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final parsed = Discovery(0, item);
    final tip = parsed.tip;
    final theme = parsed.theme;
    final boost = parsed.boost;
    final shadowColor = Color.lerp(palette.tile, palette.ink, .28)!;
    final (topFrac, bottomFrac) = tip != null
        ? (tipVisibleVerticalBounds[tip] ?? (0.02, 0.98))
        : (0.04, 0.96);
    final Widget revealed = tip != null
        ? TipArtwork(tip: tip, palette: palette, scale: .5)
        : boost != null
        ? Image.asset(boostAssetPath(boost), fit: BoxFit.contain)
        : theme != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.14),
            child: LevelOneBoardPreview(palette: BoardPalette.palettes[theme]!),
          )
        : GameArt(ArtKind.coinStack3, palette: palette);
    final Widget silhouette = tip != null
        ? TipArtwork(tip: tip, palette: palette, scale: .5, concealed: true)
        : theme != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.14),
            child: ColoredBox(
              color: shadowColor,
              child: const SizedBox.expand(),
            ),
          )
        : ColorFiltered(
            colorFilter: ColorFilter.mode(shadowColor, BlendMode.srcATop),
            child: revealed,
          );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (clamped >= 1 ? palette.accent : palette.route).withValues(
                    alpha: clamped >= 1
                        ? (palette.dark ? .34 : .24)
                        : (palette.dark ? .20 : .12),
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(padding: EdgeInsets.all(size * .08), child: silhouette),
          if (clamped > 0)
            Padding(
              padding: EdgeInsets.all(size * .08),
              child: ClipRect(
                clipper: _BottomUpClipper(
                  clamped,
                  topFraction: topFrac,
                  bottomFraction: bottomFrac,
                ),
                child: revealed,
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomUpClipper extends CustomClipper<Rect> {
  const _BottomUpClipper(
    this.fraction, {
    this.topFraction = 0.0,
    this.bottomFraction = 1.0,
  });
  final double fraction;
  final double topFraction;
  final double bottomFraction;

  @override
  Rect getClip(Size size) {
    if (fraction <= 0) return Rect.zero;
    if (fraction >= 1) return Rect.fromLTWH(0, 0, size.width, size.height);
    final visibleHeight = (bottomFraction - topFraction) * size.height;
    final revealTop = bottomFraction * size.height - visibleHeight * fraction;
    return Rect.fromLTRB(0, revealTop, size.width, size.height);
  }

  @override
  bool shouldReclip(_BottomUpClipper old) =>
      old.fraction != fraction ||
      old.topFraction != topFraction ||
      old.bottomFraction != bottomFraction;
}

class DiscoveryRow extends StatefulWidget {
  const DiscoveryRow(
    this.discovery, {
    this.reveal = false,
    this.onSkip,
    super.key,
  });
  final Discovery discovery;
  final bool reveal;
  final VoidCallback? onSkip;

  @override
  State<DiscoveryRow> createState() => _DiscoveryRowState();
}

class _DiscoveryRowState extends State<DiscoveryRow> {
  bool _busy = false;
  bool _unavailable = false;
  Discovery? _claimed;
  bool _justApplied = false;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final billing = context.watch<BillingService>();
    final palette = BoardPalette.palettes[model.theme]!;
    final discovery = _claimed ?? model.displayedDiscovery(widget.discovery);
    final isClaimed = _claimed != null || model.latestDiscoveryClaimed;
    final tip = discovery.tip;
    final theme = discovery.theme;
    final boost = discovery.boost;
    final equipped = tip != null
        ? model.equippedTip == tip
        : theme != null && model.theme == theme;
    final art = SizedBox.square(
      dimension: widget.reveal ? 156 : 52,
      child: tip != null
          ? TipArtwork(tip: tip, palette: palette)
          : boost != null
          ? Image.asset(boostAssetPath(boost), fit: BoxFit.contain)
          : theme != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(widget.reveal ? 18 : 8),
              child: LevelOneBoardPreview(
                palette: BoardPalette.palettes[theme]!,
              ),
            )
          : GameArt(ArtKind.coinStack3, palette: palette),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Flex(
        direction: widget.reveal ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.reveal)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .88, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 310),
              curve: Curves.easeOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: art,
            )
          else
            art,
          SizedBox(width: 12, height: widget.reveal ? 8 : 0),
          Flexible(
            child: Column(
              crossAxisAlignment: widget.reveal
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  tip?.label ??
                      theme?.label ??
                      (boost != null
                          ? '${boost.multiplier}× ${boost.title}'
                          : '${discovery.coinAmount} coins'),
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: widget.reveal ? 17 : 15,
                  ),
                ),
                if (isClaimed) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 16,
                        color: palette.route,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        discovery.isCoins
                            ? '+${discovery.coinAmount} coins added!'
                            : boost != null
                            ? 'Added to Boosts!'
                            : 'Unlocked!',
                        style: TextStyle(
                          color: palette.route,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (tip != null || theme != null) ...[
                    const SizedBox(height: 6),
                    if (equipped)
                      ActionPill(
                        label: _justApplied ? 'Applied' : 'Equipped',
                        icon: _justApplied
                            ? Icons.check_circle_rounded
                            : Icons.check_rounded,
                        tone: ActionTone.selected,
                      )
                    else
                      ActionPill(
                        label: 'Apply',
                        tone: ActionTone.primary,
                        onTap: () async {
                          if (tip != null) {
                            final ok = await model.equipTip(tip);
                            if (ok && mounted) {
                              model.haptic.selection();
                              setState(() => _justApplied = true);
                            }
                          } else if (theme != null) {
                            model.setTheme(theme);
                            if (mounted) {
                              model.haptic.selection();
                              setState(() => _justApplied = true);
                            }
                          }
                        },
                      ),
                  ],
                ] else ...[
                  const SizedBox(height: 6),
                  ActionPill(
                    label: _busy
                        ? 'Loading video…'
                        : !model.onlineReady
                        ? 'Offline · tap to retry'
                        : _unavailable
                        ? 'Video unavailable · retry'
                        : 'Watch to claim',
                    tone: ActionTone.primary,
                    icon: _busy ? null : Icons.play_circle_filled_rounded,
                    onTap: !_busy && !billing.buying && !model.storageError
                        ? () async {
                            final callback = model.mysteryRewardCallback();
                            if (callback == null) return;
                            setState(() {
                              _busy = true;
                              _unavailable = false;
                            });
                            var shown = false;
                            try {
                              if (model.onlineReady && !ads.videoReady) {
                                await ads.prepare(
                                  canPresent: () =>
                                      mounted &&
                                      model.onlineReady &&
                                      ModalRoute.isCurrentOf(context) == true,
                                );
                              }
                              if (model.onlineReady && ads.videoReady) {
                                shown = await ads.watchVideo(
                                  callback,
                                  waitForReward: true,
                                  canPresent: () =>
                                      mounted &&
                                      model.onlineReady &&
                                      ModalRoute.isCurrentOf(context) == true,
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _busy = false;
                                  _unavailable = !shown;
                                  if (shown && model.latestDiscoveryClaimed) {
                                    _claimed = model.latestDiscovery;
                                  }
                                });
                              }
                            }
                          }
                        : null,
                  ),
                  if (widget.onSkip != null && !_busy)
                    TextButton(
                      onPressed: widget.onSkip,
                      child: const Text('Skip'),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CollectionsView extends StatelessWidget {
  const CollectionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final owned =
        PathTip.values.where(model.ownsTip).length + model.ownedThemes;
    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '$owned of ${PathTip.values.length + PathwiseTheme.values.length} collected',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              GameCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    ProgressiveDiscoveryArt(
                      item: model.upcomingDiscoveryItem,
                      palette: palette,
                      progress: model.discoveryPercent / 100,
                      size: 108,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Next mystery reward',
                            style: TextStyle(
                              color: palette.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${model.discoveryPercent}% revealed',
                            style: TextStyle(
                              color: palette.route,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _Album(
                title: 'Path tips',
                children: [
                  for (final tip in PathTip.values)
                    _AlbumItem(
                      label: tip.label,
                      silhouette:
                          !model.ownsTip(tip) &&
                              model.upcomingDiscoveryItem == 'tip/${tip.name}'
                          ? ProgressiveDiscoveryArt(
                              item: model.upcomingDiscoveryItem,
                              palette: palette,
                              progress: model.discoveryPercent / 100,
                              size: 62,
                            )
                          : TipArtwork(
                              tip: tip,
                              palette: palette,
                              concealed: true,
                            ),
                      owned: model.ownsTip(tip),
                      artwork: TipArtwork(tip: tip, palette: palette),
                      apply: tip == model.equippedTip
                          ? null
                          : () => model.equipTip(tip),
                    ),
                ],
              ),
              _Album(
                title: 'Themes',
                children: [
                  for (final theme in PathwiseTheme.values)
                    _AlbumItem(
                      label: theme.label,
                      silhouette:
                          !model.ownsTheme(theme) &&
                              model.upcomingDiscoveryItem ==
                                  'theme/${theme.name}'
                          ? ProgressiveDiscoveryArt(
                              item: model.upcomingDiscoveryItem,
                              palette: palette,
                              progress: model.discoveryPercent / 100,
                              size: 62,
                            )
                          : _ThemeSilhouette(theme.index),
                      owned: model.ownsTheme(theme),
                      artwork: LevelOneBoardPreview(
                        palette: BoardPalette.palettes[theme]!,
                        tip: model.equippedTip,
                      ),
                      apply: theme == model.theme
                          ? null
                          : () => model.setTheme(theme),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Album extends StatelessWidget {
  const _Album({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 6, children: children),
      ],
    ),
  );
}

class _ThemeSilhouette extends StatelessWidget {
  const _ThemeSilhouette(this.index);
  final int index;
  @override
  Widget build(BuildContext context) => Center(
    child: Transform.rotate(
      angle: (index % 5 - 2) * .09,
      child: Container(
        width: 34,
        height: 43,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: const BorderRadius.all(Radius.circular(5)),
        ),
        child: Center(
          child: Container(
            width: 18 + (index % 3) * 3,
            height: 2,
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
      ),
    ),
  );
}

class _AlbumItem extends StatelessWidget {
  const _AlbumItem({
    required this.label,
    required this.owned,
    required this.artwork,
    required this.silhouette,
    required this.apply,
  });
  final String label;
  final bool owned;
  final Widget artwork;
  final Widget silhouette;
  final VoidCallback? apply;

  @override
  Widget build(BuildContext context) => Semantics(
    label: owned
        ? (apply == null ? '$label, equipped' : label)
        : 'Undiscovered',
    button: owned,
    child: ExcludeSemantics(
      child: InkWell(
        onTap: !owned
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: Text(label),
                  content: SizedBox(width: 200, child: artwork),
                  actions: [
                    if (apply != null)
                      TextButton(
                        onPressed: () {
                          apply!();
                          Navigator.pop(dialog);
                        },
                        child: const Text('Apply'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
        child: SizedBox(
          width: 82,
          child: Column(
            children: [
              SizedBox.square(
                dimension: 62,
                child: owned ? artwork : silhouette,
              ),
              if (owned) Text(label, maxLines: 2, textAlign: TextAlign.center),
              if (owned && apply == null) const Icon(Icons.check, size: 14),
            ],
          ),
        ),
      ),
    ),
  );
}
