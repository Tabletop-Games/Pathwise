import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update_flutter/in_app_update_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/user_preferences.dart';
import 'cloud_save_section.dart';
import 'components/brand_mark.dart';
import 'level_one_demo.dart';
import 'play_games_view.dart';
import 'puzzle_view.dart';
import 'share_view.dart';
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
                SwitchListTile(
                  title: const Text('Suggest sharing achievements'),
                  subtitle: const Text(
                    'Show a Share action in achievement celebrations.',
                  ),
                  value: model.suggestSharing,
                  onChanged: model.setSharingSuggestions,
                ),
                const CloudSaveSection(),
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Demo'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openLevelOneDemo(context),
                ),
                ListTile(
                  title: const Text('Themes'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const StoreView(section: StoreSection.themes),
                    ),
                  ),
                ),
                if (ads.canManagePrivacy) ...[
                  const Divider(),
                  const ListTile(title: Text('Privacy')),
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
                ],
                const Divider(),
                ListTile(
                  title: const Text('Google Play Achievements'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlayGamesView()),
                  ),
                ),
                if (defaultTargetPlatform == TargetPlatform.android)
                  const _CheckForUpdates(),
                AboutListTile(
                  applicationName: 'Pathwise',
                  applicationVersion: '1.0.0',
                  icon: const Icon(Icons.info_outline_rounded),
                  applicationIcon: BrandMark(
                    background: Theme.of(context).colorScheme.primary,
                    ink: Theme.of(context).colorScheme.onPrimary,
                  ),
                  aboutBoxChildren: const [
                    Text(
                      'A route puzzle by Tabletop Games. Draw one continuous '
                      'path through every tile, visiting checkpoints in order.',
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Play 1,000 Levels, a three-puzzle Daily Challenge, '
                      'or race the clock in Time Attack.',
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
                if (SharePromptPolicy.lastLevelMilestone(
                      model.highestUnlocked - 1,
                    )
                    case final level?
                    when model.result(PuzzleId.level(level)) != null)
                  ShareResultButton(
                    result: ShareResult.level(
                      level: level,
                      total: model.levelsSolved,
                    ),
                    label: 'Share Level Milestone',
                  ),
                const SizedBox(height: 18),
                Card(
                  child: Column(
                    children: [
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
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const PlayGamesView()),
                  ),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Google Play Achievements'),
                ),
                Text(
                  'Pathwise Achievements',
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
                      subtitle: Text(
                        '${achievement.description} · '
                        '${model.hasAchievement(achievement) ? 'Earned' : '+${achievement.coins} coins'}',
                      ),
                      trailing: model.hasAchievement(achievement)
                          ? IconButton(
                              tooltip: 'Share Achievement',
                              icon: const Icon(Icons.share_outlined),
                              onPressed: () =>
                                  const ShareDestinationService().open(
                                    ShareResult.achievement(
                                      achievement.title,
                                      achievement.description,
                                    ),
                                    ShareDestination.android,
                                  ),
                            )
                          : null,
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

class _CheckForUpdates extends StatefulWidget {
  const _CheckForUpdates();

  @override
  State<_CheckForUpdates> createState() => _CheckForUpdatesState();
}

class _CheckForUpdatesState extends State<_CheckForUpdates> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    var message = 'Unable to check for updates. Try again later.';
    try {
      final updates = InAppUpdateFlutter();
      final info = await updates.checkUpdateAndroid();
      if (info.installStatus == InstallStatusAndroid.downloaded) {
        await updates.completeUpdateAndroid();
        message = 'Installing update.';
      } else if (info.updateAvailability ==
              UpdateAvailabilityAndroid.updateAvailable &&
          info.isImmediateUpdateAllowed) {
        final result = await updates.startImmediateUpdateAndroid();
        message = result == UpdateResultAndroid.success
            ? 'Update started.'
            : 'Update was not completed.';
      } else if (info.updateAvailability ==
          UpdateAvailabilityAndroid.updateNotAvailable) {
        message = 'Pathwise is up to date.';
      } else {
        message = 'No update is currently available.';
      }
    } on PlatformException {
      // Play services can be unavailable for offline or sideloaded installs.
    } on MissingPluginException {
      // Unsupported installations remain fully playable.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.system_update_alt_rounded),
    title: const Text('Check for updates'),
    trailing: _busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.chevron_right),
    onTap: _busy ? null : _check,
  );
}
