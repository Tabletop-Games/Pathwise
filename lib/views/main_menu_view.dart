import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/journey.dart';
import '../model/progression.dart';
import '../model/user_preferences.dart';
import '../ui/art/control_art.dart';
import '../ui/art/game_assets.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'campaign_journey_view.dart';
import 'connection_view.dart';
import 'developer_view.dart';
import 'fortune_view.dart';
import 'journey_rewards.dart';
import 'level_one_demo.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLaunch();
      if (!mounted) return;
      final model = context.read<AppModel>();
      if (!model.adFree && model.onlineReady) {
        unawaited(
          context.read<AdService>().prepare(
            canPresent: () =>
                mounted &&
                !model.adFree &&
                model.activeId == null &&
                ModalRoute.isCurrentOf(context) == true,
          ),
        );
      }
    });
    _wheelTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ModalRoute.isCurrentOf(context) == true) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_launchChecked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkLaunch();
        if (!mounted) return;
        final model = context.read<AppModel>();
        if (!model.adFree && model.onlineReady) {
          unawaited(
            context.read<AdService>().prepare(
              canPresent: () =>
                  mounted &&
                  !model.adFree &&
                  model.activeId == null &&
                  ModalRoute.isCurrentOf(context) == true,
            ),
          );
        }
      });
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
        model.equippedTip,
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
    final attackRunning = model.attack != null && !model.attack!.finished;

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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                      if (!model.onlineReady) ...[
                        const SizedBox(width: 8),
                        OfflineStatusChip(palette: palette),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _CampaignHeroCard(
                    palette: palette,
                    theme: model.theme,
                    equippedTip: model.equippedTip,
                    chapterNameText: chapterName(chapter),
                    chapterProgress: chapterProgress,
                    playLabel: model.levelsSolved == 0
                        ? 'Play level 1'
                        : 'Continue · Level ${model.highestUnlocked}',
                    onPlay: () => openPuzzle(
                      context,
                      PuzzleId.level(model.highestUnlocked),
                    ),
                  ),
                  if (model.pendingChapterChests.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _PendingTreasureBanner(
                      palette: palette,
                      count: model.pendingChapterChests.length,
                      onTap: () => showChapterTreasures(context),
                    ),
                  ],
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 10),
                  _ShortcutRow(
                    children: [
                      _ActivityTile(
                        palette: palette,
                        title: 'Journey',
                        subtitle: '${model.levelsSolved} solved',
                        icon: _UiArtIcon(
                          assetPath: 'assets/art/ui/compass.webp',
                          fallback: GameArt(
                            ArtKind.levels,
                            palette: palette,
                            size: 32,
                          ),
                          size: 32,
                        ),
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CampaignJourneyView(),
                          ),
                        ),
                      ),
                      _ActivityTile(
                        palette: palette,
                        title: 'Collections',
                        subtitle: 'Themes & tips',
                        icon: Image.asset(
                          'assets/art/ui/collections.webp',
                          width: 34,
                          height: 34,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CollectionsView(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _TimeAttackCard(
                    palette: palette,
                    running: attackRunning,
                    best: model.attackBest,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const _AttackSetup()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _StoreCard(
                    palette: palette,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const StoreView()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _WheelCard(
                    key: const ValueKey('wheel-tile'),
                    palette: palette,
                    spinReady: spinReady,
                    waitSeconds: model.fortuneWait,
                    onTap: _openWheel,
                  ),
                  const SizedBox(height: 10),
                  _ShortcutRow(
                    children: [
                      _ActivityTile(
                        palette: palette,
                        title: 'Research',
                        subtitle: researched > 0
                            ? '$researched unlocked'
                            : 'Permanent upgrades',
                        icon: GameArt(
                          ArtKind.research,
                          palette: palette,
                          size: 30,
                        ),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ProgressionView(),
                          ),
                        ),
                      ),
                      _ActivityTile(
                        palette: palette,
                        title: 'Boosts',
                        featured: active > 0,
                        subtitle: active > 0
                            ? '$active on'
                            : owned > 0
                            ? '$owned ready'
                            : '2×–4× multipliers',
                        icon: GameArt(ArtKind.bolt, palette: palette, size: 30),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ProgressionView(boosts: true),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (model.developerMode) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const DeveloperView(),
                        ),
                      ),
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Developer dashboard'),
                    ),
                  ],
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

class _CampaignHeroCard extends StatelessWidget {
  const _CampaignHeroCard({
    required this.palette,
    required this.theme,
    required this.equippedTip,
    required this.chapterNameText,
    required this.chapterProgress,
    required this.playLabel,
    required this.onPlay,
  });

  final BoardPalette palette;
  final PathwiseTheme theme;
  final PathTip equippedTip;
  final String chapterNameText;
  final int chapterProgress;
  final String playLabel;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final tipPath = tipAssetPath(equippedTip);
    final biomePath = biomeAssetPath(biomeForTheme(theme));
    final scrimLeft = palette.surface.withValues(
      alpha: palette.dark ? .92 : .94,
    );
    final scrimMid = palette.surface.withValues(
      alpha: palette.dark ? .76 : .80,
    );
    final scrimRight = palette.surface.withValues(
      alpha: palette.dark ? .26 : .30,
    );

    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameTokens.cardRadius),
        side: BorderSide(color: palette.cardEdge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  biomePath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.route.withValues(alpha: .22),
                          palette.surface,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [scrimLeft, scrimMid, scrimRight],
                      stops: const [0.0, 0.56, 1.0],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapterNameText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w800,
                                  height: 1.12,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$chapterProgress / $chapterSize puzzles',
                            style: TextStyle(
                              color: palette.mutedInk,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              GameTokens.pillRadius,
                            ),
                            child: LinearProgressIndicator(
                              minHeight: 8,
                              value: (chapterProgress / chapterSize).clamp(
                                0.0,
                                1.0,
                              ),
                              backgroundColor: palette.track,
                              color: palette.route,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: Image.asset(
                        tipPath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: _TactilePlayButton(
              palette: palette,
              label: playLabel,
              onPressed: onPlay,
            ),
          ),
        ],
      ),
    );
  }
}

class _TactilePlayButton extends StatelessWidget {
  const _TactilePlayButton({
    required this.palette,
    required this.label,
    required this.onPressed,
  });

  final BoardPalette palette;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [palette.buttonTop, palette.buttonBottom],
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: palette.route.withValues(alpha: palette.dark ? .14 : .12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: palette.onRoute,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onPressed,
      icon: const PathIcon(ControlGlyph.play),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
  );
}

class _PendingTreasureBanner extends StatelessWidget {
  const _PendingTreasureBanner({
    required this.palette,
    required this.count,
    required this.onTap,
  });

  final BoardPalette palette;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GameCard(
    selected: true,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        GameArt(ArtKind.treasure, palette: palette, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Chapter treasures · $count',
            style: TextStyle(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        ActionPill(label: 'Claim', tone: ActionTone.primary, onTap: onTap),
      ],
    ),
  );
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
        const SizedBox(width: 10),
        Expanded(child: children.last),
      ],
    ),
  );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.palette,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.featured = false,
  });

  final BoardPalette palette;
  final String title;
  final String? subtitle;
  final Widget icon;
  final bool featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GameCard(
    selected: featured,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: Row(
      children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: featured ? palette.route : palette.mutedInk,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _UiArtIcon extends StatelessWidget {
  const _UiArtIcon({
    required this.assetPath,
    required this.fallback,
    this.size = 32,
  });

  final String assetPath;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
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
  Widget build(BuildContext context) => GameCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 268 ||
            (constraints.maxWidth < 290 &&
                MediaQuery.textScalerOf(context).scale(1) > 1.2);
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Daily challenge',
                maxLines: 1,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                _OnRoutePips(done: done, palette: palette),
                if (time != null)
                  Text(
                    time!,
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        );
        final pill = ActionPill(
          label: action,
          tone: done >= dailyCheckpointCount
              ? ActionTone.selected
              : ActionTone.primary,
          onTap: onTap,
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              info,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: pill),
            ],
          );
        }
        return Row(
          children: [
            GameArt(ArtKind.calendar, palette: palette, size: 36),
            const SizedBox(width: 12),
            Expanded(child: info),
            const SizedBox(width: 8),
            pill,
          ],
        );
      },
    ),
  );
}

/// Three stage pips drawn on the daily card.
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

class _TimeAttackCard extends StatelessWidget {
  const _TimeAttackCard({
    required this.palette,
    required this.running,
    required this.best,
    required this.onTap,
  });

  final BoardPalette palette;
  final bool running;
  final int best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GameCard(
    selected: running,
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    child: Row(
      children: [
        GameArt(ArtKind.timer, palette: palette, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Time Attack',
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                running
                    ? 'Run in progress'
                    : best > 0
                    ? 'Best $best'
                    : '1 · 3 · 5 min rush',
                style: TextStyle(
                  color: running ? palette.route : palette.mutedInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        ActionPill(
          label: running ? 'Resume' : 'Start',
          tone: running ? ActionTone.primary : ActionTone.quiet,
          onTap: onTap,
        ),
      ],
    ),
  );
}

/// Full-width illustrated Store destination.
class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.palette, required this.onTap});
  final BoardPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GameCard(
    key: const ValueKey('store-card'),
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Row(
      children: [
        GameArt(ArtKind.store, palette: palette, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Store',
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Themes, tips & more',
                style: TextStyle(
                  color: palette.mutedInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: palette.mutedInk),
      ],
    ),
  );
}

class _WheelCard extends StatelessWidget {
  const _WheelCard({
    required this.palette,
    required this.spinReady,
    required this.waitSeconds,
    required this.onTap,
    super.key,
  });

  final BoardPalette palette;
  final bool spinReady;
  final int waitSeconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GameCard(
    selected: spinReady,
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    child: Row(
      children: [
        _UiArtIcon(
          assetPath: 'assets/art/ui/wheel_ticket.webp',
          fallback: GameArt(ArtKind.wheel, palette: palette, size: 34),
          size: 34,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fortune Wheel',
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              if (!spinReady && waitSeconds > 0) ...[
                const SizedBox(height: 2),
                Text(
                  fortuneCountdown(waitSeconds),
                  style: TextStyle(
                    color: palette.mutedInk,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (spinReady)
          ActionPill(label: 'Free spin', tone: ActionTone.primary, onTap: onTap)
        else
          Icon(Icons.chevron_right_rounded, color: palette.mutedInk),
      ],
    ),
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
                  GameCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        GameArt(ArtKind.timer, palette: palette, size: 48),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Beat the clock',
                                style: TextStyle(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Solve as many puzzles as you can before time runs out.',
                                style: TextStyle(
                                  color: palette.mutedInk,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
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
                              '${model.attackBestFor(minutes)} pts',
                              style: TextStyle(
                                color: palette.mutedInk,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _TactilePlayButton(
                    palette: palette,
                    label: running ? 'Resume' : 'Play',
                    onPressed: () => openPuzzle(
                      context,
                      const PuzzleId.attack('start/0'),
                      timeAttack: true,
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
}
