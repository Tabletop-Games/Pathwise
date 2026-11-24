import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/billing_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/progression.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'developer_view.dart';
import 'fortune_view.dart';
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
    if (canPresent() &&
        ads.videoReady &&
        model.canOfferCoinVideo &&
        !context.read<BillingService>().buying &&
        await model.recordCoinOffer() &&
        canPresent()) {
      final watch = await showGameDialog<bool>(
    context,
        builder: (dialog) => GameDialog(
          art: GameArt(
            ArtKind.coinStack3,
            palette: dialog.palette,
            size: 72,
          ),
          child: Center(child: RewardAmount(economy.rewardedAdCoins)),
          actions: [
            ActionPill(
              label: 'Not now',
              onTap: () => Navigator.pop(dialog, false),
            ),
            ActionPill(
              label: 'Watch video',
              tone: ActionTone.primary,
              icon: Icons.play_arrow_rounded,
              onTap: () => Navigator.pop(dialog, true),
            ),
          ],
        ),
      );
      if (watch == true &&
          canPresent() &&
          ads.videoReady &&
          model.canEarnAdBonus) {
        await ads.watchVideo(model.grantAdBonus, canPresent: canPresent);
      }
      unawaited(ads.afterCompletedExit(canPresent: false));
      return;
    }
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
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pathwise',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
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
                        MaterialPageRoute(
                          builder: (_) => const StatisticsView(),
                        ),
                      ),
                      icon: const Icon(Icons.insights_rounded),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsView()),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
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
                _DailyCard(
                  palette: palette,
                  done: dailyDone,
                  time: result == null
                      ? null
                      : formatTime(Duration(milliseconds: result.milliseconds)),
                  action: result != null
                      ? 'View result'
                      : model.hasAttempt(currentDaily)
                      ? 'Resume'
                      : 'Play daily',
                  onTap: () => openPuzzle(context, currentDaily),
                ),
                const SizedBox(height: 10),
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
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    model.levelsSolved == 0
                        ? 'Play level 1'
                        : 'Continue · Level ${model.highestUnlocked}',
                  ),
                ),
                const SizedBox(height: 10),
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
                      MaterialPageRoute(builder: (_) => const DeveloperView()),
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
  Widget build(BuildContext context) => GameCard(
    onTap: onTap,
    selected: false,
    color: featured
        ? Color.lerp(palette.card, palette.accent, palette.dark ? .14 : .2)
        : null,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    semanticLabel: badge == null ? title : '$title, $badge',
    child: Row(
      children: [
        GameArt(art, palette: palette, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        if (badge != null)
          Text(
            badge!,
            style: TextStyle(
              color: palette.mutedInk,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
      ],
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
    decoration: BoxDecoration(
      color: palette.route,
      borderRadius: BorderRadius.circular(GameTokens.cardRadius + 4),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily challenge',
                style: TextStyle(
                  color: palette.onRoute,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _OnRoutePips(done: done, palette: palette),
                  if (time != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      time!,
                      style: TextStyle(
                        color: palette.onRoute,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.onAccent,
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GameTokens.pillRadius),
            ),
          ),
          child: Text(action),
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
                    : palette.onRoute.withValues(alpha: .6),
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
  Widget build(BuildContext context) => GameCard(
    onTap: onTap,
    color: featured
        ? Color.lerp(palette.card, palette.accent, palette.dark ? .14 : .2)
        : null,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    semanticLabel: trailing == null ? title : '$title, $trailing',
    child: Row(
      children: [
        GameArt(art, palette: palette, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: featured ? palette.ink : palette.mutedInk,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, color: palette.mutedInk),
      ],
    ),
  );
}

/// The Store is a destination, not a settings entry: full width, illustrated
/// and tinted with the theme accent.
class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.palette, required this.onTap});
  final BoardPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GameCard(
    key: const ValueKey('store-card'),
    onTap: onTap,
    color: Color.lerp(palette.card, palette.accent, palette.dark ? .18 : .26),
    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
    semanticLabel: 'Store. Themes, tips and more',
    child: Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: .7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: GameArt(ArtKind.store, palette: palette, size: 40),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Store',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
              Text(
                'Themes, tips & more',
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: palette.ink),
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
      body: SafeArea(
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
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(running ? 'Resume' : 'Play'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
