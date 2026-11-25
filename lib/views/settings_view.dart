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
import '../ui/art/control_art.dart';
import '../ui/art/medallion_art.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'cloud_save_section.dart';
import 'components/brand_mark.dart';
import 'level_one_demo.dart';
import 'play_games_view.dart';
import 'puzzle_view.dart';
import 'share_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final p = context.palette;
    Widget group(List<Widget> tiles) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.cardEdge),
            tiles[i],
          ],
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 0,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                group([
                  SwitchListTile(
                    secondary: const PathIcon(ControlGlyph.haptics),
                    title: const Text('Haptic feedback'),
                    value: model.haptics,
                    onChanged: model.setHaptics,
                  ),
                  SwitchListTile(
                    title: const Text('Suggest sharing achievements'),
                    value: model.suggestSharing,
                    onChanged: model.setSharingSuggestions,
                  ),
                ]),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: CloudSaveSection(),
                ),
                group([
                  ListTile(
                    leading: GameArt(ArtKind.levels, palette: p, size: 28),
                    title: const Text('Demo'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openLevelOneDemo(context),
                  ),
                  ListTile(
                    leading: GameArt(ArtKind.trophy, palette: p, size: 28),
                    title: const Text('Google Play Achievements'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PlayGamesView()),
                    ),
                  ),
                  if (ads.canManagePrivacy)
                    ListTile(
                      title: const Text('Ad privacy'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        if (!ads.privacyRequired) {
                          await ads.prepare(
                            canPresent: () =>
                                context.mounted &&
                                ModalRoute.isCurrentOf(context) == true,
                          );
                        }
                        if (context.mounted &&
                            ModalRoute.isCurrentOf(context) == true &&
                            ads.privacyRequired) {
                          await ads.privacyOptions();
                        }
                      },
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
                        'Play an endless campaign, a three-puzzle Daily Challenge, '
                        'or race the clock in Time Attack.',
                      ),
                    ],
                  ),
                ]),
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
    Widget tile(ArtKind art, String label, String value) =>
        _StatTile(art: art, label: label, value: value, palette: palette);
    Widget grid(List<Widget> tiles) => Column(children: tiles);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 0,
        title: const Text(
          'Statistics',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                Text(
                  'Your journey',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                grid([
                  tile(ArtKind.check, 'Puzzles solved', '${model.solved}'),
                  tile(
                    ArtKind.hint,
                    'Solved without hints',
                    '${model.unassisted}',
                  ),
                  tile(ArtKind.flame, 'Daily streak', '${model.dailyStreak}'),
                  tile(
                    ArtKind.trophy,
                    'Longest streak',
                    '${model.longestStreak}',
                  ),
                  tile(
                    ArtKind.levels,
                    'Highest level unlocked',
                    '${model.highestUnlocked}',
                  ),
                  tile(
                    ArtKind.timer,
                    'Total gameplay time',
                    formatTime(model.playTime),
                  ),
                  tile(
                    ArtKind.coinStack2,
                    'Coins earned',
                    '${model.coinsEarned}',
                  ),
                  tile(ArtKind.coin, 'Coins spent', '${model.coinsSpent}'),
                  tile(
                    ArtKind.brush,
                    'Themes owned',
                    '${model.ownedThemes}/${PathwiseTheme.values.length}',
                  ),
                ]),
                const SizedBox(height: 10),
                grid([
                  for (final (mode, label, count) in [
                    (PlayMode.levels, 'Levels', model.levelsSolved),
                    (PlayMode.daily, 'Daily', model.dailySolved),
                  ]) ...[
                    tile(
                      mode == PlayMode.levels
                          ? ArtKind.levels
                          : ArtKind.calendar,
                      '$label solved',
                      '$count',
                    ),
                    if (model.best(mode) case final best?)
                      tile(ArtKind.timer, '$label best', formatTime(best)),
                  ],
                ]),
                if (SharePromptPolicy.lastLevelMilestone(
                      model.highestUnlocked - 1,
                    )
                    case final level?
                    when model.result(PuzzleId.level(level)) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ShareResultButton(
                      result: ShareResult.level(
                        level: level,
                        total: model.levelsSolved,
                      ),
                      label: 'Share Level Milestone',
                    ),
                  ),
                const SizedBox(height: 10),
                grid([
                  tile(
                    ArtKind.timer,
                    'Time Attack best score',
                    '${model.attackBest}',
                  ),
                  tile(
                    ArtKind.levels,
                    'Most puzzles in one run',
                    '${model.attackHighest}',
                  ),
                ]),
                if (model.attackHistory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GameCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final run in model.attackHistory.reversed.take(5))
                          _Stat(
                            'Recent run · ${run.clears.length} solved',
                            '${run.score} points',
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pathwise Achievements',
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    ActionPill(
                      label: 'Play Games',
                      icon: Icons.emoji_events_outlined,
                      semanticLabel: 'Google Play Achievements',
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const PlayGamesView(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final achievement in Achievement.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AchievementCard(
                      achievement: achievement,
                      earned: model.hasAchievement(achievement),
                      palette: palette,
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.art,
    required this.label,
    required this.value,
    required this.palette,
  });

  final ArtKind art;
  final String label, value;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, $value',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          GameArt(art, palette: palette, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.achievement,
    required this.earned,
    required this.palette,
  });

  final Achievement achievement;
  final bool earned;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Opacity(
      opacity: earned ? 1 : .7,
      child: Row(
        children: [
          AchievementEmblem(achievement, earned: earned, palette: palette),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  achievement.description,
                  style: TextStyle(color: palette.mutedInk, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (earned)
            IconButton(
              tooltip: 'Share Achievement',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => const ShareDestinationService().open(
                ShareResult.achievement(
                  achievement.title,
                  achievement.description,
                ),
                ShareDestination.android,
              ),
            )
          else
            RewardAmount(achievement.coins, size: 18),
        ],
      ),
    ),
  );
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
