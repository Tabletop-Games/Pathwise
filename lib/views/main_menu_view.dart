import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import 'components/brand_mark.dart';
import 'puzzle_view.dart';
import 'settings_view.dart';

Future<void> openPuzzle(
  BuildContext context,
  PuzzleId id, {
  bool replay = false,
}) async {
  final model = context.read<AppModel>();
  model.open(id, replay: replay);
  await Navigator.of(context)
      .push<void>(MaterialPageRoute(builder: (_) => const PuzzleView()));
  model.close();
}

class MainMenuView extends StatelessWidget {
  const MainMenuView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
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
                  subtitle: '${model.levelsSolved} of $levelCount solved',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const LevelsView()),
                  ),
                ),
                const SizedBox(height: 10),
                _ModeTile(
                  palette: palette,
                  icon: Icons.all_inclusive_rounded,
                  title: 'Endless',
                  subtitle: model.hasAttempt(model.endless)
                      ? 'Resume puzzle ${model.endless.value}'
                      : 'Play puzzle ${model.endless.value}',
                  onTap: () => openPuzzle(context, model.endless),
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
            Text(
              date,
              style: TextStyle(
                color: palette.onRoute,
                fontWeight: FontWeight.w600,
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

class LevelsView extends StatelessWidget {
  const LevelsView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    return Scaffold(
      appBar: AppBar(title: const Text('Levels')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
              itemCount: levelCount,
              itemBuilder: (context, index) {
                final id = PuzzleId.level(index + 1);
                final result = model.result(id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ModeTile(
                    palette: palette,
                    icon: result != null
                        ? Icons.check_rounded
                        : Icons.grid_view_rounded,
                    title: id.title,
                    subtitle: result != null
                        ? '${id.size} × ${id.size} · ${formatTime(Duration(milliseconds: result.milliseconds))}'
                        : '${id.size} × ${id.size}${model.hasAttempt(id) ? ' · In progress' : ''}',
                    onTap: () => openPuzzle(
                      context,
                      id,
                      replay: result != null && !model.hasAttempt(id),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
