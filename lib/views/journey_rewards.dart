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
      widget.model.canMultiplyCompletion &&
      widget.model.onlineReady;

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
      if (_current && !ads.videoReady) {
        await ads.prepare(canPresent: () => _current);
      }
      if (_current && ads.videoReady) {
        shown = await ads.watchVideo(
          reward,
          waitForReward: true,
          canPresent: () => _current,
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
    return GameCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
              const SizedBox(height: 8),
              ActionPill(
                label: 'Stop',
                tone: ActionTone.primary,
                icon: Icons.touch_app_rounded,
                onTap: _stopAtCurrent,
              ),
            ],
          ],
          if (selected != null || _reduced) ...[
            const SizedBox(height: 8),
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
          height: 54,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 14,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
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
                          child: Container(
                            margin: EdgeInsets.only(
                              right: index < multiplierRegions.length - 1
                                  ? 2
                                  : 0,
                            ),
                            decoration: BoxDecoration(
                              color: stopped && index == activeIndex
                                  ? (region.$2 == 4
                                        ? palette.accent
                                        : palette.route)
                                  : region.$2 == 4
                                  ? Color.lerp(
                                      palette.surface,
                                      palette.accent,
                                      palette.dark ? .42 : .34,
                                    )!
                                  : region.$2 == 3
                                  ? Color.lerp(
                                      palette.surface,
                                      palette.route,
                                      palette.dark ? .26 : .20,
                                    )!
                                  : palette.quiet,
                              border: stopped && index == activeIndex
                                  ? Border.all(color: palette.ink, width: 2)
                                  : null,
                            ),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${region.$2}×',
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: stopped && index == activeIndex
                                        ? (region.$2 == 4
                                              ? palette.onAccent
                                              : palette.onRoute)
                                        : palette.ink,
                                    fontWeight: region.$2 == 4
                                        ? FontWeight.w900
                                        : FontWeight.w800,
                                    fontSize: region.$2 == 4 ? 16 : 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: pointerX - 10,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  key: const ValueKey('multiplier-pointer'),
                  width: 20,
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
    final fill = Paint()
      ..color = palette.ink
      ..style = PaintingStyle.fill;
    final head = Path()
      ..moveTo(cx - 7, 2)
      ..lineTo(cx + 7, 2)
      ..lineTo(cx, 12)
      ..close();
    canvas.drawPath(head, halo);
    canvas.drawPath(head, fill);
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 2, 12, 4, size.height - 12),
      const Radius.circular(2),
    );
    canvas.drawRRect(bar, halo);
    canvas.drawRRect(bar, fill);
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
    final isTip = item.startsWith('tip/');
    final isTheme = item.startsWith('theme/');
    final tip = isTip ? PathTip.fromId(item.split('/').last) : null;
    final theme = isTheme
        ? PathwiseTheme.values
              .where((t) => t.name == item.split('/').last)
              .firstOrNull
        : null;
    final shadowColor = Color.lerp(palette.tile, palette.ink, .28)!;
    final Widget revealed = tip != null
        ? TipArtwork(tip: tip, palette: palette)
        : theme != null
        ? LevelOneBoardPreview(palette: BoardPalette.palettes[theme]!)
        : GameArt(ArtKind.coinStack3, palette: palette);
    final Widget silhouette = tip != null
        ? TipArtwork(tip: tip, palette: palette, concealed: true)
        : ColorFiltered(
            colorFilter: ColorFilter.mode(shadowColor, BlendMode.srcATop),
            child: revealed,
          );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          silhouette,
          if (clamped > 0)
            ClipRect(clipper: _BottomUpClipper(clamped), child: revealed),
        ],
      ),
    );
  }
}

class _BottomUpClipper extends CustomClipper<Rect> {
  const _BottomUpClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, size.height * (1.0 - fraction), size.width, size.height);

  @override
  bool shouldReclip(_BottomUpClipper old) => old.fraction != fraction;
}

class DiscoveryRow extends StatefulWidget {
  const DiscoveryRow(
    this.discovery, {
    this.reveal = false,
    this.onClaimLater,
    super.key,
  });
  final Discovery discovery;
  final bool reveal;
  final VoidCallback? onClaimLater;

  @override
  State<DiscoveryRow> createState() => _DiscoveryRowState();
}

class _DiscoveryRowState extends State<DiscoveryRow> {
  bool _busy = false;
  Discovery? _claimed;
  bool _justApplied = false;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final billing = context.watch<BillingService>();
    final palette = BoardPalette.palettes[model.theme]!;
    final pending = model.hasPendingDiscovery(widget.discovery.number);
    final discovery = _claimed ?? model.displayedDiscovery(widget.discovery);
    final isClaimed = _claimed != null || !pending;
    final fallback = discovery.item == Discovery.fallback;
    final tip = discovery.isTip
        ? PathTip.values.byName(discovery.cosmeticId)
        : null;
    final theme = !fallback && tip == null
        ? PathwiseTheme.values.byName(discovery.cosmeticId)
        : null;
    final equipped = tip != null
        ? model.equippedTip == tip
        : theme != null && model.theme == theme;
    final art = SizedBox.square(
      dimension: widget.reveal ? 112 : 52,
      child: tip != null
          ? TipArtwork(tip: tip, palette: palette)
          : theme != null
          ? LevelOneBoardPreview(palette: BoardPalette.palettes[theme]!)
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
                  tip?.label ?? theme?.label ?? '$discoveryFallbackCoins coins',
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
                        'Unlocked!',
                        style: TextStyle(
                          color: palette.route,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (!fallback) ...[
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
                        ? 'Unlocking…'
                        : ads.videoReady
                        ? 'Watch to unlock'
                        : 'Video temporarily unavailable',
                    tone: ActionTone.primary,
                    icon: _busy
                        ? null
                        : ads.videoReady
                        ? Icons.play_circle_filled_rounded
                        : null,
                    onTap:
                        !_busy &&
                            !billing.buying &&
                            ads.videoReady &&
                            model.onlineReady &&
                            !model.storageError
                        ? () async {
                            setState(() => _busy = true);
                            var claimed = false;
                            await ads.watchVideo(
                              (_) async {
                                claimed = await model.claimDiscovery(
                                  discovery.number,
                                );
                                return claimed;
                              },
                              waitForReward: true,
                              canPresent: () =>
                                  mounted &&
                                  model.onlineReady &&
                                  ModalRoute.isCurrentOf(context) == true,
                            );
                            if (mounted) {
                              setState(() {
                                _busy = false;
                                _claimed = claimed ? discovery : null;
                              });
                            }
                          }
                        : null,
                  ),
                  if (widget.onClaimLater != null && !_busy)
                    TextButton(
                      onPressed: widget.onClaimLater,
                      child: const Text('Claim later'),
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
    final pending = model.pendingDiscoveries;
    final owned =
        PathTip.values.where(model.ownsTip).length + model.ownedThemes;
    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '$owned of ${PathTip.values.length + PathwiseTheme.values.length} collected',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ProgressiveDiscoveryArt(
                  item: model.upcomingDiscoveryItem,
                  palette: palette,
                  progress: model.discoveryPercent / 100,
                  size: 56,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next discovery · ${model.discoveryPercent}%',
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: model.discoveryPercent / 100,
                        backgroundColor: palette.tile,
                        color: palette.route,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (pending.isNotEmpty)
              ExpansionTile(
                initiallyExpanded: true,
                title: Text('Discoveries · ${pending.length}'),
                children: [
                  for (final discovery in pending.take(3))
                    DiscoveryRow(discovery, key: ValueKey(discovery.number)),
                  if (pending.length > 3)
                    TextButton(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const _PendingDiscoveries(),
                        ),
                      ),
                      child: const Text('See all discoveries'),
                    ),
                ],
              ),
            _Album(
              title: 'Path tips',
              children: [
                for (final tip in PathTip.values)
                  _AlbumItem(
                    label: tip.label,
                    silhouette: TipArtwork(
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
                    silhouette: _ThemeSilhouette(theme.index),
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
    );
  }
}

class _PendingDiscoveries extends StatelessWidget {
  const _PendingDiscoveries();

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<AppModel>().pendingDiscoveries;
    return Scaffold(
      appBar: AppBar(title: const Text('Discoveries')),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: pending.length,
          itemBuilder: (context, index) => DiscoveryRow(
            pending[index],
            key: ValueKey(pending[index].number),
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
