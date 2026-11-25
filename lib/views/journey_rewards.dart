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
    model.selectCompletionMultiplier(accessibleMultiplier);
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
    final selected = model.selectedMultiplier;
    final extra =
        economy.clearReward(PlayMode.levels) *
        ((selected ?? accessibleMultiplier) - 1);
    final buying = context.watch<BillingService>().buying;
    return Column(
      children: [
        if (!_reduced)
          AnimatedBuilder(
            animation: _track,
            builder: (context, _) {
              _visiblePosition = _track.value;
              return _MultiplierTrack(
                _visiblePosition,
                stopped: selected != null,
              );
            },
          ),
        if (selected == null && !_reduced)
          TextButton(
            onPressed: () {
              _track.stop();
              _track.value = _visiblePosition;
              model.selectCompletionMultiplier(multiplierAt(_visiblePosition));
            },
            child: const Text('Stop'),
          ),
        if (selected != null || _reduced) ...[
          Text('${selected ?? accessibleMultiplier}× base level reward'),
          TextButton.icon(
            icon: const Icon(Icons.play_circle_outline),
            onPressed: _busy || buying ? null : () => _claim(ads),
            label: Text(
              'Watch video for +$extra coins · ${model.completionCoins + extra} level coins',
            ),
          ),
          if (_unavailable)
            const Text('Video unavailable. Try again or continue.'),
        ],
      ],
    );
  }
}

class _MultiplierTrack extends StatelessWidget {
  const _MultiplierTrack(this.position, {required this.stopped});
  final double position;
  final bool stopped;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(9)),
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
                        child: ColoredBox(
                          color: Color.lerp(
                            colors.surface,
                            colors.primary,
                            stopped &&
                                    index ==
                                        multiplierRegions.indexWhere(
                                          (zone) => position <= zone.$1,
                                        )
                                ? .55
                                : switch (region.$2) {
                                    4 => .33,
                                    3 => .20,
                                    _ => .09,
                                  },
                          )!,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('${region.$2}×', maxLines: 1),
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
              left: (constraints.maxWidth * position - 1).clamp(
                0.0,
                constraints.maxWidth - 2,
              ),
              top: 0,
              bottom: 0,
              child: ColoredBox(
                key: const ValueKey('multiplier-pointer'),
                color: colors.onSurface,
                child: const SizedBox(width: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}

class DiscoveryRow extends StatefulWidget {
  const DiscoveryRow(this.discovery, {this.reveal = false, super.key});
  final Discovery discovery;
  final bool reveal;

  @override
  State<DiscoveryRow> createState() => _DiscoveryRowState();
}

class _DiscoveryRowState extends State<DiscoveryRow> {
  bool _busy = false;
  Discovery? _claimed;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final billing = context.watch<BillingService>();
    final palette = BoardPalette.palettes[model.theme]!;
    final discovery = _claimed ?? model.displayedDiscovery(widget.discovery);
    final fallback = discovery.item == Discovery.fallback;
    final tip = discovery.isTip
        ? PathTip.values.byName(discovery.cosmeticId)
        : null;
    final theme = !fallback && tip == null
        ? PathwiseTheme.values.byName(discovery.cosmeticId)
        : null;
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
                ),
                if (_claimed != null && !fallback)
                  TextButton(
                    onPressed: () async {
                      if (tip != null) {
                        await model.equipTip(tip);
                      } else if (theme != null) {
                        model.setTheme(theme);
                      }
                    },
                    child: const Text('Apply'),
                  )
                else if (_claimed == null)
                  TextButton(
                    onPressed:
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
                            if (mounted)
                              setState(() {
                                _busy = false;
                                _claimed = claimed ? discovery : null;
                              });
                          }
                        : null,
                    child: Text(
                      ads.videoReady
                          ? 'Watch to claim'
                          : 'Video temporarily unavailable',
                    ),
                  ),
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
            const SizedBox(height: 8),
            LinearProgressIndicator(value: model.discoveryPercent / 100),
            Text('Next discovery · ${model.discoveryPercent}%'),
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
