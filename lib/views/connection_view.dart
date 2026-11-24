import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../online/online_service.dart';
import 'components/brand_mark.dart';

/// Player-facing wording for each connection state. No technical detail.
({String title, String message, bool retry}) connectionCopy(
  ConnectionPhase phase, {
  required bool inPlay,
}) {
  return switch (phase) {
    ConnectionPhase.starting => (
      title: 'Connecting',
      message: 'Getting your game ready…',
      retry: false,
    ),
    ConnectionPhase.online => (title: '', message: '', retry: false),
    ConnectionPhase.noInternet => (
      title: inPlay ? 'Connection lost' : 'No internet connection',
      message: inPlay
          ? 'Your puzzle is paused and your progress is safe. Pathwise will resume as soon as you are back online.'
          : 'Pathwise needs the internet to play. Check your connection and try again.',
      retry: true,
    ),
    ConnectionPhase.backendUnavailable => (
      title: inPlay ? 'Reconnecting' : 'Pathwise is unavailable',
      message: inPlay
          ? 'We can’t reach the game right now. Your puzzle is paused and nothing has been lost.'
          : 'We can’t reach the game right now. Please try again in a moment.',
      retry: true,
    ),
    ConnectionPhase.authFailed => (
      title: 'Couldn’t verify this device',
      message: 'Pathwise couldn’t confirm that this device can sign in. Please try again later.',
      retry: true,
    ),
    ConnectionPhase.sessionExpired => (
      title: 'Session expired',
      message: 'For your security, please sign in again to continue.',
      retry: true,
    ),
    ConnectionPhase.updateRequired => (
      title: 'Update required',
      message: 'A newer version of Pathwise is required. Update from Google Play, then come back.',
      retry: true,
    ),
    ConnectionPhase.notConfigured => (
      title: 'Not connected to a game server',
      message:
          'This version of Pathwise isn’t set up to reach its game server.',
      retry: false,
    ),
  };
}

/// Covers the whole app whenever there is no verified online session. Because
/// it sits above the Navigator, no screen has to know about connectivity.
class ConnectionGate extends StatelessWidget {
  const ConnectionGate({required this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final online = context.watch<OnlineService>();
    final theme = context.select((AppModel model) => model.theme);
    final inPlay = context.select((AppModel model) => model.activeId != null);
    final palette = BoardPalette.palettes[theme]!;
    final blocked = !online.canPlay;
    return Stack(
      children: [
        ExcludeFocus(
          excluding: blocked,
          child: IgnorePointer(
            ignoring: blocked,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        if (blocked)
          Positioned.fill(
            child: ConnectionPane(
              online: online,
              palette: palette,
              inPlay: inPlay && online.everOnline,
            ),
          ),
      ],
    );
  }
}

/// Lives above the app's Navigator, so it uses inline confirmation rather
/// than dialogs.
class ConnectionPane extends StatefulWidget {
  const ConnectionPane({
    required this.online,
    required this.palette,
    required this.inPlay,
    super.key,
  });

  final OnlineService online;
  final BoardPalette palette;
  final bool inPlay;

  @override
  State<ConnectionPane> createState() => _ConnectionPaneState();
}

class _ConnectionPaneState extends State<ConnectionPane> {
  bool _confirmingNewProfile = false;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmingNewProfile = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.online;
    final palette = widget.palette;
    final inPlay = widget.inPlay;
    final copy = connectionCopy(online.phase, inPlay: inPlay);
    final connecting = online.phase == ConnectionPhase.starting || _busy;
    final scrim = inPlay || online.everOnline
        ? palette.canvas.withValues(alpha: 0.96)
        : palette.canvas;
    return Material(
      key: const ValueKey('pathwise-connection'),
      color: scrim,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 72,
                    child: BrandMark(
                      background: palette.route,
                      ink: palette.onRoute,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      copy.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    copy.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.muted, fontSize: 16),
                  ),
                  const SizedBox(height: 28),
                  if (connecting)
                    SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: palette.route,
                      ),
                    ),
                  if (copy.retry && !connecting)
                    FilledButton(
                      onPressed: () => _run(online.retryNow),
                      child: const Text('Try again'),
                    ),
                  if (online.phase == ConnectionPhase.sessionExpired &&
                      !connecting) ...[
                    if (online.gamesRecoveryAvailable) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _run(() async {
                          await online.restoreWithGames();
                        }),
                        child: const Text('Restore with Google Play Games'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (!_confirmingNewProfile)
                      TextButton(
                        onPressed: () =>
                            setState(() => _confirmingNewProfile = true),
                        child: const Text('Start a new profile'),
                      )
                    else ...[
                      Text(
                        'This device will start over. A profile linked to Google Play Games can still be restored later.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.muted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _confirmingNewProfile = false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _run(online.startNewProfile),
                            child: const Text('Start over'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
