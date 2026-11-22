import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import '../model/user_preferences.dart';
import 'puzzle_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  title: const Text('Haptic feedback'),
                  value: model.haptics,
                  onChanged: model.setHaptics,
                ),
                const Divider(),
                const ListTile(title: Text('Theme')),
                RadioGroup<PathwiseTheme>(
                  groupValue: model.theme,
                  onChanged: (theme) {
                    if (theme != null) model.setTheme(theme);
                  },
                  child: Column(
                    children: [
                      for (final theme in PathwiseTheme.values)
                        RadioListTile<PathwiseTheme>(
                          title: Text(theme.label),
                          value: theme,
                          secondary: CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                BoardPalette.palettes[theme]!.route,
                            child: CircleAvatar(
                              radius: 5,
                              backgroundColor:
                                  BoardPalette.palettes[theme]!.accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                AboutListTile(
                  applicationName: 'Pathwise',
                  applicationVersion: '1.0.0',
                  icon: const Icon(Icons.info_outline_rounded),
                  aboutBoxChildren: const [
                    Text(
                      'Pathwise adapts the GPL-3.0 Flutter architecture of shenmareparas/Chess.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatisticsView extends StatelessWidget {
  const StatisticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Card(
                  color: palette.surface,
                  child: Column(
                    children: [
                      _Stat('Puzzles solved', '${model.solved}'),
                      _Stat('Solved without hints', '${model.unassisted}'),
                      _Stat('Daily streak', '${model.dailyStreak} days'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final (mode, label, count) in [
                  (PlayMode.levels, 'Levels', model.levelsSolved),
                  (PlayMode.daily, 'Daily', model.dailySolved),
                  (PlayMode.endless, 'Endless', model.endlessSolved),
                ])
                  Card(
                    color: palette.surface,
                    child: Column(
                      children: [
                        _Stat(label, '$count solved'),
                        if (model.best(mode) case final best?)
                          _Stat('Best time', formatTime(best)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.title, this.value);

  final String title, value;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}
