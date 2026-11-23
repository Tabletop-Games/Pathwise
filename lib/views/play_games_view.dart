import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/play_games.dart';
import '../model/app_model.dart';

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
    if (mounted)
      setState(() {
        _message = message;
        _busy = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Play Games')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              title: const Text('Local Time Attack best'),
              trailing: Text('${model.attackBest}'),
            ),
            ListTile(
              title: const Text('Most puzzles solved'),
              trailing: Text('${model.attackHighest}'),
            ),
            if (PlayGames.enabled) ...[
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () async => await PlayGames.call<bool>('signIn') == true
                            ? 'Signed into Play Games.'
                            : 'Play Games sign-in unavailable.',
                      ),
                child: const Text('Sign in to Play Games'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final count = await PlayGames.syncAchievements(model);
                        final opened =
                            await PlayGames.call<bool>('achievements') == true;
                        return opened
                            ? '$count earned achievements synced.'
                            : 'Sign in to view Play Games achievements.';
                      }),
                child: const Text('View and sync achievements'),
              ),
              for (final board in PlayGames.boards.entries)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () async =>
                              await PlayGames.call<bool>('leaderboard', {
                                    'id': board.value,
                                  }) ==
                                  true
                              ? 'Leaderboard opened.'
                              : 'Leaderboard unavailable.',
                        ),
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
          ],
        ),
      ),
    );
  }
}
