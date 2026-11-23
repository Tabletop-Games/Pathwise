import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/achievement_sync.dart';
import '../logic/play_games.dart';
import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/native_achievements.dart';
import 'share_view.dart';

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
    final message = await action();
    if (mounted) {
      setState(() {
        _message = message;
        _busy = false;
      });
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
                          if (await PlayGames.call<bool>('status') != true &&
                              await PlayGames.call<bool>('signIn') != true) {
                            return 'Sign in to Play Games to view this leaderboard.';
                          }
                          return await PlayGames.call<bool>('leaderboard', {
                                    'id': board.value,
                                  }) ==
                                  true
                              ? ''
                              : 'Leaderboard unavailable.';
                        }),
                  child: Text(board.key),
                ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () async => await PlayGames.link(model)
                            ? 'Play Games account linked.'
                            : 'Account link unavailable.',
                      ),
                child: const Text('Link online account'),
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
                Card(
                  child: ListTile(
                    leading: Icon(
                      item.earned(counters) || sync.confirmed(item)
                          ? Icons.emoji_events_outlined
                          : Icons.lock_outline,
                    ),
                    title: Text(item.name),
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
                    ),
                    trailing: item.earned(counters) || sync.confirmed(item)
                        ? IconButton(
                            tooltip: 'Share Achievement',
                            icon: const Icon(Icons.share_outlined),
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => ShareView(
                                  result: ShareResult.achievement(
                                    item.name,
                                    item.description,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
