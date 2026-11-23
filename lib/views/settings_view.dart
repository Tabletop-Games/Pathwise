import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/user_preferences.dart';
import 'play_games_view.dart';
import 'puzzle_view.dart';
import 'store_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
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
                      for (final theme in PathwiseTheme.values.where(
                        model.ownsTheme,
                      ))
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
                ListTile(
                  title: const Text('Cosmetics'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const StoreView()),
                  ),
                ),
                if (ads.enabled)
                  ListTile(
                    title: const Text('Ad privacy'),
                    onTap: () async {
                      if (!ads.privacyRequired)
                        await ads.prepare(
                          canPresent: () =>
                              context.mounted &&
                              ModalRoute.isCurrentOf(context) == true,
                        );
                      if (context.mounted &&
                          ModalRoute.isCurrentOf(context) == true &&
                          ads.privacyRequired)
                        await ads.privacyOptions();
                    },
                  ),
                const Divider(),
                ListTile(
                  title: const Text('Play Games'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlayGamesView()),
                  ),
                ),
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
                      _Stat('Longest streak', '${model.longestStreak} days'),
                      _Stat(
                        'Highest level unlocked',
                        '${model.highestUnlocked}',
                      ),
                      _Stat('Total gameplay time', formatTime(model.playTime)),
                      _Stat('Coins earned', '${model.coinsEarned}'),
                      _Stat('Coins spent', '${model.coinsSpent}'),
                      _Stat(
                        'Themes owned',
                        '${model.ownedThemes} of ${PathwiseTheme.values.length}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final (mode, label, count) in [
                  (PlayMode.levels, 'Levels', model.levelsSolved),
                  (PlayMode.daily, 'Daily', model.dailySolved),
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
                const SizedBox(height: 18),
                Card(
                  child: Column(
                    children: [
                      _Stat(
                        'Expedition trails qualified',
                        '${model.trailsQualified}',
                      ),
                      _Stat('Time Attack best score', '${model.attackBest}'),
                      _Stat(
                        'Most puzzles in one run',
                        '${model.attackHighest}',
                      ),
                      for (final run in model.attackHistory.reversed.take(5))
                        _Stat(
                          'Recent run · ${run.clears.length} solved',
                          '${run.score} points',
                        ),
                    ],
                  ),
                ),
                Text(
                  'Achievements',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                for (final achievement in Achievement.values)
                  Card(
                    color: palette.surface,
                    child: ListTile(
                      leading: Icon(
                        model.hasAchievement(achievement)
                            ? Icons.workspace_premium_rounded
                            : Icons.lock_outline,
                      ),
                      title: Text(achievement.title),
                      subtitle: Text(achievement.description),
                      trailing: Text(
                        model.hasAchievement(achievement)
                            ? 'Earned'
                            : '+${achievement.coins} coins',
                      ),
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
