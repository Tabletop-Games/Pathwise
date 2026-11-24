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
import '../ui/journey_art.dart';
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
  bool _moving = false;
  var _visiblePosition = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _track.stop();
      if (mounted) setState(() => _moving = false);
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
    final ads = context.watch<AdService>();
    final model = widget.model;
    if (!model.canMultiplyCompletion || !ads.enabled)
      return const SizedBox.shrink();
    final selected = model.selectedMultiplier;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final extra =
        economy.clearReward(PlayMode.levels) *
        ((selected ?? accessibleMultiplier) - 1);
    final ready = ads.videoReady && !context.watch<BillingService>().buying;
    return Column(
      children: [
        if (!reduced && (ready || selected != null))
          AnimatedBuilder(
            animation: _track,
            builder: (context, _) {
              _visiblePosition = _track.value;
              return _MultiplierTrack(_visiblePosition);
            },
          ),
        if (ready && selected == null && !reduced)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: !ready
                    ? null
                    : () {
                        if (!_moving) {
                          setState(() => _moving = true);
                          _track.repeat(reverse: true);
                        } else {
                          _track.stop();
                          model.selectCompletionMultiplier(
                            multiplierAt(_visiblePosition),
                          );
                        }
                      },
                child: Text(_moving ? 'Stop' : 'Start bonus track'),
              ),
              TextButton(
                onPressed: !ready
                    ? null
                    : () {
                        _track.stop();
                        _track.value = .35;
                        model.selectCompletionMultiplier(accessibleMultiplier);
                      },
                child: const Text('Choose fixed 3×'),
              ),
            ],
          ),
        if (selected != null || reduced) ...[
          Text('${selected ?? accessibleMultiplier}× base level reward'),
          TextButton.icon(
            icon: const Icon(Icons.play_circle_outline),
            onPressed: !ready || _busy
                ? null
                : () async {
                    final multiplier = selected ?? accessibleMultiplier;
                    model.selectCompletionMultiplier(multiplier);
                    final reward = model.completionRewardCallback();
                    if (reward == null) return;
                    setState(() => _busy = true);
                    await ads.watchVideo(
                      reward,
                      waitForReward: true,
                      canPresent: () =>
                          mounted &&
                          ModalRoute.isCurrentOf(context) == true &&
                          model.canMultiplyCompletion,
                    );
                    if (mounted) setState(() => _busy = false);
                  },
            label: Text(
              'Watch for +$extra coins · ${model.completionCoins + extra} level coins',
            ),
          ),
        ],
        if (!ready && ads.enabled)
          const Text('Optional video temporarily unavailable'),
      ],
    );
  }
}

class _MultiplierTrack extends StatelessWidget {
  const _MultiplierTrack(this.position);
  final double position;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  for (final (index, region) in multiplierRegions.indexed)
                    Expanded(
                      flex:
                          ((region.$1 -
                                      (index == 0
                                          ? 0
                                          : multiplierRegions[index - 1].$1)) *
                                  100)
                              .round(),
                      child: ColoredBox(
                        color: index.isEven
                            ? colors.secondaryContainer
                            : colors.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '${region.$2}×',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
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
  const DiscoveryRow(this.discovery, {super.key});
  final Discovery discovery;

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: tip != null
                ? TipArtwork(tip: tip, palette: palette)
                : theme != null
                ? LevelOneBoardPreview(palette: BoardPalette.palettes[theme]!)
                : GameArt(ArtKind.coinStack3, palette: palette, size: 46),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
            JourneyArt(palette, height: 92),
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

class _AlbumItem extends StatelessWidget {
  const _AlbumItem({
    required this.label,
    required this.owned,
    required this.artwork,
    required this.apply,
  });
  final String label;
  final bool owned;
  final Widget artwork;
  final VoidCallback? apply;

  @override
  Widget build(BuildContext context) => Semantics(
    label: owned ? label : 'Undiscovered',
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
                child: owned
                    ? artwork
                    : Icon(
                        Icons.change_history,
                        color: Theme.of(context).colorScheme.outline,
                      ),
              ),
              if (owned) Text(label, maxLines: 2, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
