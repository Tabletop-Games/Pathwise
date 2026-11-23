import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import '../model/progression.dart';
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
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Pathwise',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StoreView(),
                            ),
                          ),
                          icon: const Icon(Icons.toll_rounded),
                          label: Text('${model.coinBalance}'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(50, 48),
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
                            MaterialPageRoute(
                              builder: (_) => const SettingsView(),
                            ),
                          ),
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => const StreakView()),
                        ),
                        icon: _StreakFlame(count: model.streak.count),
                        label: Text('${model.streak.count}-day streak'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FilledButton.tonalIcon(
                        onPressed: () => showHintShop(context, model),
                        icon: const Icon(Icons.lightbulb_outline_rounded),
                        label: Text('${model.hintsRemaining} hints'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _DailyCard(
                  palette: palette,
                  date: '${daily.value}',
                  detail: result != null
                      ? 'Solved in ${formatTime(Duration(milliseconds: result.milliseconds))}'
                      : model.hasAttempt(currentDaily)
                      ? 'In progress'
                      : 'Three puzzles each day',
                  action: result != null
                      ? 'View result'
                      : model.hasAttempt(currentDaily)
                      ? 'Resume'
                      : 'Play daily',
                  onTap: () => openPuzzle(context, currentDaily),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
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
                const SizedBox(height: 14),
                _ModeTile(
                  palette: palette,
                  icon: Icons.layers_outlined,
                  title: 'Levels',
                  subtitle:
                      'Level ${model.highestUnlocked} · ${model.levelsSolved} solved',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const LevelsView()),
                  ),
                ),
                const SizedBox(height: 10),
                _ModeTile(
                  palette: palette,
                  icon: Icons.timer_outlined,
                  title: 'Time Attack',
                  subtitle: model.attack != null && !model.attack!.finished
                      ? 'Resume challenge'
                      : '1, 3, or 5 minutes',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const _AttackSetup()),
                  ),
                ),
                const SizedBox(height: 10),
                _ShortcutRow(
                  children: [
                    _HomeShortcut(
                      icon: Icons.cyclone_rounded,
                      title: 'Fortune Wheel',
                      featured: spinReady,
                      detail: spinReady
                          ? 'Free spin ready'
                          : model.fortuneWait > 0
                          ? 'Next spin in ${fortuneCountdown(model.fortuneWait)}'
                          : 'Free spin unavailable',
                      onTap: _openWheel,
                    ),
                    _HomeShortcut(
                      icon: Icons.palette_outlined,
                      title: 'Themes',
                      detail: 'Preview palettes',
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const StoreView(themesOnly: true),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ShortcutRow(
                  children: [
                    _HomeShortcut(
                      icon: Icons.hub_outlined,
                      title: 'Research',
                      detail: switch (researched) {
                        0 => 'Permanent upgrades',
                        1 => '1 upgrade begun',
                        _ => '$researched upgrades begun',
                      },
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const ProgressionView(),
                        ),
                      ),
                    ),
                    _HomeShortcut(
                      icon: Icons.bolt_rounded,
                      title: 'Boosts',
                      detail: active > 0
                          ? '$active active · $owned in reserve'
                          : owned > 0
                          ? '$owned in reserve'
                          : 'Timed effects',
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

class _StreakFlame extends StatelessWidget {
  const _StreakFlame({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const Icon(Icons.local_fire_department_outlined);
    final flame = Icon(
      Icons.local_fire_department_rounded,
      color: Theme.of(context).colorScheme.tertiary,
    );
    if (MediaQuery.disableAnimationsOf(context)) return flame;
    return TweenAnimationBuilder<double>(
      key: ValueKey(count),
      tween: Tween<double>(begin: 0.8, end: 1),
      curve: Curves.elasticOut,
      duration: const Duration(milliseconds: 850),
      child: flame,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
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
        const SizedBox(width: 10),
        Expanded(child: children.last),
      ],
    ),
  );
}

class _HomeShortcut extends StatelessWidget {
  const _HomeShortcut({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.featured = false,
  });

  final IconData icon;
  final String title, detail;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: featured ? colors.primaryContainer : colors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(detail, style: TextStyle(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.palette,
    required this.date,
    required this.detail,
    required this.action,
    required this.onTap,
  });

  final BoardPalette palette;
  final String date, detail, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: palette.route,
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              color: palette.onRoute,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date,
                style: TextStyle(
                  color: palette.onRoute,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Daily challenge',
          style: TextStyle(
            color: palette.onRoute,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(detail, style: TextStyle(color: palette.onRoute, fontSize: 15)),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.onAccent,
          ),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(action),
        ),
      ],
    ),
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final BoardPalette palette;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: palette.surface,
    borderRadius: BorderRadius.circular(20),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      leading: CircleAvatar(
        backgroundColor: palette.tile,
        foregroundColor: palette.ink,
        child: Icon(icon),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _AttackSetup extends StatelessWidget {
  const _AttackSetup();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final running = model.attack?.finished == false;
    return Scaffold(
      appBar: AppBar(title: const Text('Time Attack')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Text('How long can you keep going?'),
                const SizedBox(height: 16),
                for (final minutes in [1, 3, 5])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        enabled: !running,
                        selected: model.attackMinutes == minutes,
                        leading: const Icon(Icons.timer_outlined),
                        title: Text('$minutes min'),
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        minTileHeight: 72,
                        subtitle: Text(
                          'Best: ${model.attackBestFor(minutes)} points',
                        ),
                        trailing: model.attackMinutes == minutes
                            ? const Icon(Icons.check_circle_outline)
                            : null,
                        onTap: running
                            ? null
                            : () => model.selectAttackMinutes(minutes),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
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
