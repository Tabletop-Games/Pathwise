import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import 'components/brand_mark.dart';
import 'fortune_view.dart';
import 'levels_view.dart';
import 'progression_view.dart';
import 'puzzle_view.dart';
import 'settings_view.dart';
import 'store_view.dart';

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
  const MainMenuView({this.offerDailySpin = false, super.key});
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

  void _checkLaunch() {
    if (!mounted ||
        _launchChecked ||
        !widget.offerDailySpin ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
      return;
    _launchChecked = true;
    final model = context.read<AppModel>();
    if (ModalRoute.isCurrentOf(context) != true ||
        model.activeId != null ||
        model.attack?.finished == false ||
        model.storageError ||
        model.fortuneWait != 0)
      return;
    _openWheel();
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
        model.daily.key,
        model.highestUnlocked,
        model.levelsSolved,
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
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              children: [
                Row(
                  children: [
                    BrandMark(background: palette.route, ink: palette.onRoute),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(builder: (_) => const StoreView()),
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
                        MaterialPageRoute(builder: (_) => const SettingsView()),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Text(
                  'Pathwise',
                  style: TextStyle(
                    fontSize: 51,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2.5,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'One route through every tile.',
                  style: TextStyle(fontSize: 17, color: palette.muted),
                ),
                const SizedBox(height: 25),
                _DailyCard(
                  palette: palette,
                  date: '${daily.value}',
                  detail: result != null
                      ? 'Solved in ${formatTime(Duration(milliseconds: result.milliseconds))}'
                      : model.hasAttempt(daily)
                      ? 'In progress'
                      : 'A new 6 × 6 puzzle each day',
                  action: result != null
                      ? 'View result'
                      : model.hasAttempt(daily)
                      ? 'Resume'
                      : 'Play daily',
                  onTap: () => openPuzzle(context, daily),
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
                      : '10 minutes · Best ${model.attackBest}',
                  onTap: () => openPuzzle(
                    context,
                    const PuzzleId.attack('start/0'),
                    timeAttack: true,
                  ),
                ),
                const SizedBox(height: 10),
                _ModeTile(
                  palette: palette,
                  icon: Icons.cyclone_rounded,
                  title: 'Fortune Wheel',
                  featured: model.fortuneWait == 0 && !model.storageError,
                  subtitle: model.fortuneWait == 0 && !model.storageError
                      ? 'Free spin ready'
                      : model.fortuneWait > 0
                      ? 'Next free spin in ${fortuneCountdown(model.fortuneWait)}'
                      : 'Free spin temporarily unavailable',
                  onTap: _openWheel,
                ),
                const SizedBox(height: 10),
                const ProgressionEntrances(),
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
    this.featured = false,
  });

  final BoardPalette palette;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) => Material(
    color: featured ? palette.covered : palette.surface,
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
