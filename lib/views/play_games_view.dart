import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/achievement_sync.dart';
import '../logic/play_games.dart';
import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/native_achievements.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';

class PlayGamesView extends StatefulWidget {
  const PlayGamesView({super.key});
  @override
  State<PlayGamesView> createState() => _PlayGamesViewState();
}

class _PlayGamesViewState extends State<PlayGamesView> {
  bool _busy = false;
  String _message = '';

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    var message = '';
    try {
      message = await action();
    } catch (_) {
      message = 'Google Play is unavailable right now.';
    } finally {
      if (mounted) {
        setState(() {
          _message = message;
          _busy = false;
        });
      }
    }
  }

  String _accountMessage(AchievementSync sync) => sync.accountMismatch
      ? 'You switched Play Games accounts. Switch back to sync this save’s progress.'
      : 'Showing your progress and unlocks Google Play has confirmed.';

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final sync = context.watch<AchievementSync>();
    final counters = model.achievementCounters;
    return Scaffold(
      appBar: AppBar(title: const Text('Google Play Achievements')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (sync.enabled) ...[
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () async => switch (await sync.openNative()) {
                          NativeAchievementScreen.opened => '',
                          NativeAchievementScreen.signInUnavailable => 'Play Games sign-in is unavailable. You can keep earning achievements here.',
                          NativeAchievementScreen.unavailable =>
                            'Google Play’s achievement screen could not open.',
                        },
                      ),
                child: const Text('Open Google Play Achievements'),
              ),
              if (sync.configuredCount > 0)
                OutlinedButton(
                  onPressed:
                      _busy || sync.status == AchievementSyncStatus.syncing
                      ? null
                      : () => _run(() async {
                          await sync.refresh();
                          return '';
                        }),
                  child: const Text('Sync Progress'),
                ),
              for (final board in PlayGames.boards.entries)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          if (!await PlayGames.isSignedIn() &&
                              !await PlayGames.signIn()) {
                            return 'Sign in to Play Games to view this leaderboard.';
                          }
                          return await PlayGames.openLeaderboard(board.value)
                              ? ''
                              : 'Leaderboard unavailable.';
                        }),
                  child: Text(board.key),
                ),
            ],
            if (_message.isNotEmpty)
              Semantics(liveRegion: true, child: Text(_message)),
            Text(
              sync.configuredCount == 0 || !sync.enabled
                  ? 'Google Play synchronization is unavailable in this build. You can still earn achievements locally.'
                  : switch (sync.status) {
                      AchievementSyncStatus.syncing =>
                        'Checking Google Play progress…',
                      AchievementSyncStatus.confirmed => _accountMessage(sync),
                      _ => 'Google Play is unavailable. Local progress is saved for syncing.',
                    },
            ),
            const SizedBox(height: 12),
            for (final item in nativeAchievements)
              if (!item.hidden || item.earned(counters) || sync.confirmed(item))
                Builder(
                  builder: (context) {
                    final palette = BoardPalette.palettes[model.theme]!;
                    final earned =
                        item.earned(counters) || sync.confirmed(item);
                    final trophy = GameArt(
                      ArtKind.trophy,
                      palette: palette,
                      size: 38,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GameCard(
                        padding: EdgeInsets.zero,
                        selected: earned,
                        child: ListTile(
                          leading: earned
                              ? trophy
                              : ColorFiltered(
                                  colorFilter: const ColorFilter.matrix(
                                    <double>[
                                      0.2126,
                                      0.7152,
                                      0.0722,
                                      0,
                                      0,
                                      0.2126,
                                      0.7152,
                                      0.0722,
                                      0,
                                      0,
                                      0.2126,
                                      0.7152,
                                      0.0722,
                                      0,
                                      0,
                                      0,
                                      0,
                                      0,
                                      1,
                                      0,
                                    ],
                                  ),
                                  child: trophy,
                                ),
                          title: Text(
                            item.name,
                            style: TextStyle(
                              color: earned ? palette.ink : palette.mutedInk,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [
                              item.description,
                              if (sync.confirmed(item))
                                'Confirmed by Google Play'
                              else if (item.earned(counters))
                                sync.ids.containsKey(item.id) && sync.enabled
                                    ? 'Earned locally · Pending Google Play sync'
                                    : 'Earned locally'
                              else if (item.incremental)
                                '${max(item.progress(counters), sync.confirmedSteps(item))} / ${item.target}',
                            ].join('\n'),
                            style: TextStyle(color: palette.mutedInk),
                          ),
                          trailing: earned
                              ? IconButton(
                                  tooltip: 'Share Achievement',
                                  icon: const Icon(Icons.share_outlined),
                                  onPressed: () =>
                                      const ShareDestinationService().open(
                                        ShareResult.achievement(
                                          item.name,
                                          item.description,
                                        ),
                                        ShareDestination.android,
                                      ),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}
