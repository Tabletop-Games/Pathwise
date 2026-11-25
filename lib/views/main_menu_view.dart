import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import '../model/journey.dart';
import '../model/progression.dart';
import '../ui/art/control_art.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import '../ui/journey_art.dart';
import 'campaign_journey_view.dart';
import 'developer_view.dart';
import 'fortune_view.dart';
import 'journey_rewards.dart';
import 'level_one_demo.dart';
import 'levels_view.dart';
import 'progression_view.dart';
import 'puzzle_view.dart';
import 'settings_view.dart';
import 'store_view.dart';
import 'streak_view.dart';

Future<void> openPuzzle(
  BuildContext context,
  PuzzleId id, {
  bool replay = false,
  bool timeAttack = false,
}) async {
  final model = context.read<AppModel>();
  if (model.activeId != null ||
      (id.mode == PlayMode.levels && !model.canPlayLevel(id.level)))
    return;
  final ads = context.read<AdService>();
  if (timeAttack) {
    final started = await model.openAttack();
    if (!context.mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Time Attack needs the device clock and local storage.',
          ),
        ),
      );
      return;
    }
  } else {
    unawaited(model.open(id, replay: replay));
  }
  await Navigator.of(context)
      .push<void>(MaterialPageRoute(builder: (_) => const PuzzleView()));
  final finished = model.completedThisVisit;
  model.close();
  if (!timeAttack && finished && !model.adFree && context.mounted) {
    bool canPresent() =>
        context.mounted &&
        !model.adFree &&
        model.activeId == null &&
        ModalRoute.isCurrentOf(context) == true &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(
      ads.afterCompletedExit(
        canPresent: canPresent(),
        stillPresent: canPresent,
      ),
    );
    if (canPresent()) unawaited(ads.prepare(canPresent: canPresent));
  }
}

class MainMenuView extends StatefulWidget {
  const MainMenuView({
    this.offerDailySpin = false,
    this.offerLevelOneDemo = false,
    super.key,
  });

  final bool offerLevelOneDemo;
  final bool offerDailySpin;

  @override
  State<MainMenuView> createState() => _MainMenuViewState();
}

class _MainMenuViewState extends State<MainMenuView>
    with WidgetsBindingObserver {
  Timer? _wheelTicker;
  bool _launchChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLaunch());
    _wheelTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ModalRoute.isCurrentOf(context) == true) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_launchChecked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkLaunch());
    }
  }

  Future<void> _checkLaunch() async {
    if (!mounted ||
        _launchChecked ||
        (!widget.offerDailySpin && !widget.offerLevelOneDemo) ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
      return;
    _launchChecked = true;
    final model = context.read<AppModel>();
    if (ModalRoute.isCurrentOf(context) != true ||
        model.activeId != null ||
        model.attack?.finished == false ||
        model.storageError) {
      return;
    }
    if (widget.offerLevelOneDemo && model.shouldOfferLevelOneDemo) {
      if (await model.markLevelOneDemoSeen() &&
          mounted &&
          ModalRoute.isCurrentOf(context) == true) {
        await openLevelOneDemo(context);
      }
      return;
    }
    if (widget.offerDailySpin &&
        (model.fortuneWait == 0 || model.pendingFortune != null)) {
      _openWheel();
    }
  }

  void _openWheel() =>
      Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => const FortuneView()));

  @override
  void dispose() {
    _wheelTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.select(
      (AppModel model) => (
        model.theme,
        model.streak.count,
        model.hintsRemaining,
        model.dailyCurrent(model.daily.value as String).key,
        model.highestUnlocked,
        model.levelsSolved,
        model.pendingChapterChests.length,
        model.developerMode,
        model.progression,
        model.coinBalance,
        model.attack?.finished,
        model.attackBest,
        model.storageError,
        model.result(model.daily),
        model.activeId == null,
      ),
    );
    final model = context.read<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final chapter = chapterFor(model.highestUnlocked);
    final chapterProgress = model.chapterClears(chapter);
    final daily = model.daily;
    final result = model.result(daily);
    final currentDaily = model.dailyCurrent(daily.value as String);
    final researched = Research.values
        .where((item) => model.progression.rank(item) > 0)
        .length;
    final owned = model.progression.inventory.values.fold<int>(
      0,
      (sum, quantity) => sum + quantity,
    );
    final active = Boost.values
        .where(
          (boost) =>
              model.progression.remaining(boost, model.progressionTime) > 0,
        )
        .length;
    final spinReady = model.fortuneWait == 0 && !model.storageError;
    final dailyDone = result != null
        ? dailyCheckpointCount
        : currentDaily.checkpoint == null
        ? dailyCheckpointCount - 1
        : currentDaily.checkpoint! - 1;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pathwise',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                      ),
                    ),
                  ),
                  BalanceChip(
                    coins: model.coinBalance,
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const StoreView(section: StoreSection.coins),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Statistics',
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => const StatisticsView()),
                    ),
                    icon: const PathIcon(ControlGlyph.statistics),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsView()),
                    ),
                    icon: const PathIcon(ControlGlyph.settings),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 530),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                children: [
                  Row(
                    children: [
                      _CounterChip(
                        key: const ValueKey('streak-chip'),
                        art: ArtKind.flame,
                        palette: palette,
                        value: '${model.streak.count}',
                        label: '${model.streak.count}-day streak',
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => const StreakView()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CounterChip(
                        key: const ValueKey('hint-chip'),
                        art: ArtKind.hint,
                        palette: palette,
                        value: '${model.hintsRemaining}',
                        label: '${model.hintsRemaining} hints. Get hints',
                        onTap: () => showHintShop(context, model),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                    child: JourneyArt(palette, chapter: chapter),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    chapterName(chapter),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('$chapterProgress / $chapterSize puzzles'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: chapterProgress / chapterSize,
                    backgroundColor: palette.tile,
                    color: palette.route,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          GameTokens.cardRadius,
                        ),
                      ),
                    ),
                    onPressed: () => openPuzzle(
                      context,
                      PuzzleId.level(model.highestUnlocked),
                    ),
                    icon: const PathIcon(ControlGlyph.play),
                    label: Text(
                      model.levelsSolved == 0
                          ? 'Play level 1'
                          : 'Continue · Level ${model.highestUnlocked}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (model.pendingChapterChests.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => showChapterTreasures(context),
                      icon: const Icon(Icons.card_giftcard_outlined),
                      label: Text(
                        'Chapter treasures · ${model.pendingChapterChests.length}',
                      ),
                    ),
                  _DailyCard(
                    palette: palette,
                    done: dailyDone,
                    time: result == null
                        ? null
                        : formatTime(
                            Duration(milliseconds: result.milliseconds),
                          ),
                    action: result != null
                        ? 'View result'
                        : model.hasAttempt(currentDaily)
                        ? 'Resume'
                        : 'Play daily',
                    onTap: () => openPuzzle(context, currentDaily),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Explore',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ListTile(
                    leading: const PathIcon(ControlGlyph.collections),
                    title: const Text('Collections'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CollectionsView(),
                      ),
                    ),
                  ),
                  _ModeTile(
                    palette: palette,
                    art: ArtKind.levels,
                    title: 'Levels',
                    trailing: '${model.levelsSolved} solved',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => const LevelsView()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ModeTile(
                    palette: palette,
                    art: ArtKind.timer,
                    title: 'Time Attack',
                    trailing: model.attack != null && !model.attack!.finished
                        ? 'Resume'
                        : model.attackBest > 0
                        ? 'Best ${model.attackBest}'
                        : null,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const _AttackSetup()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StoreCard(
                    palette: palette,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const StoreView()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ModeTile(
                    key: const ValueKey('wheel-tile'),
                    palette: palette,
                    art: ArtKind.wheel,
                    title: 'Fortune Wheel',
                    featured: spinReady,
                    trailing: spinReady
                        ? 'Free spin'
                        : model.fortuneWait > 0
                        ? fortuneCountdown(model.fortuneWait)
                        : null,
                    onTap: _openWheel,
                  ),
                  const SizedBox(height: 8),
                  _ShortcutRow(
                    children: [
                      _HomeShortcut(
                        art: ArtKind.research,
                        palette: palette,
                        title: 'Research',
                        badge: researched > 0 ? '$researched' : null,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ProgressionView(),
                          ),
                        ),
                      ),
                      _HomeShortcut(
                        art: ArtKind.bolt,
                        palette: palette,
                        title: 'Boosts',
                        featured: active > 0,
                        badge: active > 0
                            ? '$active on'
                            : owned > 0
                            ? '$owned'
                            : null,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ProgressionView(boosts: true),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (model.developerMode)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const DeveloperView(),
                        ),
                      ),
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Developer dashboard'),
                    ),
                  if (model.storageError)
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text('Local progress is temporarily unavailable.'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: children.first),
        const SizedBox(width: 8),
        Expanded(child: children.last),
      ],
    ),
  );
}

/// Compact icon-and-number counter in the header row.
class _CounterChip extends StatelessWidget {
  const _CounterChip({
    required this.art,
    required this.palette,
    required this.value,
    required this.label,
    required this.onTap,
    super.key,
  });

  final ArtKind art;
  final BoardPalette palette;
  final String value, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: InkResponse(
      onTap: onTap,
      radius: 32,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: GameTokens.minTouch),
        child: Center(
          widthFactor: 1,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: palette.quiet,
              borderRadius: BorderRadius.circular(GameTokens.pillRadius),
              border: Border.all(color: palette.cardEdge),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameArt(art, palette: palette, size: 20),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _HomeShortcut extends StatelessWidget {
  const _HomeShortcut({
    required this.art,
    required this.palette,
    required this.title,
    required this.onTap,
    this.badge,
    this.featured = false,
  });

  final ArtKind art;
  final BoardPalette palette;
  final String title;
  final String? badge;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    onTap: onTap,
    leading: GameArt(art, palette: palette, size: 24),
    title: Text(title),
    subtitle: badge == null
        ? null
        : Text(
            badge!,
            style: TextStyle(
              color: featured ? palette.route : palette.mutedInk,
            ),
          ),
  );
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.palette,
    required this.done,
    required this.time,
    required this.action,
    required this.onTap,
  });

  final BoardPalette palette;
  final int done;
  final String? time;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily challenge',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 4,
                children: [
                  _OnRoutePips(done: done, palette: palette),
                  if (time != null) ...[
                    Text(
                      time!,
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GameTokens.pillRadius),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(action)),
          ),
        ),
      ],
    ),
  );
}

/// Three stage pips drawn on the route-coloured daily card.
class _OnRoutePips extends StatelessWidget {
  const _OnRoutePips({required this.done, required this.palette});
  final int done;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$done of $dailyCheckpointCount puzzles solved today',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < dailyCheckpointCount; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < done ? palette.accent : Colors.transparent,
              border: Border.all(
                color: i < done
                    ? palette.accent
                    : palette.route.withValues(alpha: .6),
                width: 2,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.palette,
    required this.art,
    required this.title,
    required this.onTap,
    this.trailing,
    this.featured = false,
    super.key,
  });

  final BoardPalette palette;
  final ArtKind art;
  final String title;
  final String? trailing;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    onTap: onTap,
    leading: GameArt(art, palette: palette, size: 28),
    title: Text(title),
    subtitle: trailing == null
        ? null
        : Text(
            trailing!,
            style: TextStyle(
              color: featured ? palette.route : palette.mutedInk,
            ),
          ),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}

/// The Store is a destination, not a settings entry: full width, illustrated
/// and tinted with the theme accent.
class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.palette, required this.onTap});
  final BoardPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('store-card'),
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    onTap: onTap,
    leading: GameArt(ArtKind.store, palette: palette, size: 28),
    title: const Text('Store'),
    subtitle: const Text('Themes, tips & more'),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}

class _AttackSetup extends StatelessWidget {
  const _AttackSetup();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final running = model.attack?.finished == false;
    return Scaffold(
      appBar: AppBar(title: const Text('Time Attack')),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final minutes in [1, 3, 5])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GameCard(
                        selected: model.attackMinutes == minutes,
                        onTap: running
                            ? null
                            : () => model.selectAttackMinutes(minutes),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        semanticLabel:
                            '$minutes minutes. Best ${model.attackBestFor(minutes)} points',
                        child: Row(
                          children: [
                            GameArt(ArtKind.timer, palette: palette, size: 34),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                '$minutes min',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                            GameArt(ArtKind.trophy, palette: palette, size: 22),
                            const SizedBox(width: 6),
                            Text(
                              '${model.attackBestFor(minutes)}',
                              style: TextStyle(
                                color: palette.mutedInk,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          GameTokens.cardRadius,
                        ),
                      ),
                    ),
                    onPressed: () => openPuzzle(
                      context,
                      const PuzzleId.attack('start/0'),
                      timeAttack: true,
                    ),
                    icon: const PathIcon(ControlGlyph.play),
                    label: Text(running ? 'Resume' : 'Play'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
