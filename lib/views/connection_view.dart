import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/connectivity_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import 'components/brand_mark.dart';

/// Player-facing wording. No technical detail.
({String title, String message, bool retry}) connectionCopy(
  ConnectivityState state, {
  required bool inPlay,
}) {
  return switch (state) {
    ConnectivityState.checking => (
      title: 'Connecting',
      message: 'Checking your internet connection…',
      retry: false,
    ),
    ConnectivityState.online => (title: '', message: '', retry: false),
    ConnectivityState.offline when inPlay => (
      title: 'Connection lost',
      message:
          'Your puzzle is paused and your route is saved. It resumes as soon as you are back online.',
      retry: true,
    ),
    ConnectivityState.offline => (
      title: 'No internet connection',
      message:
          'Pathwise needs an internet connection to play. Connect to Wi-Fi or mobile data, then try again.',
      retry: true,
    ),
  };
}

/// Covers the whole app while there is no confirmed internet connection. It
/// sits above the Navigator, so individual screens do not check the network.
class ConnectionGate extends StatelessWidget {
  const ConnectionGate({
    required this.connectivity,
    required this.child,
    super.key,
  });

  final ConnectivityService connectivity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final state = context.select((ConnectivityService service) => service.state);
    final inPlay = context.select((AppModel model) => model.activeId != null);
    final theme = context.select((AppModel model) => model.theme);
    final blocked = state != ConnectivityState.online;
    return Stack(
      children: [
        IgnorePointer(
          ignoring: blocked,
          child: ExcludeFocus(
            excluding: blocked,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        if (blocked)
          Positioned.fill(
            child: ConnectionPane(
              state: state,
              palette: BoardPalette.palettes[theme]!,
              inPlay: inPlay,
              onRetry: connectivity.retry,
            ),
          ),
      ],
    );
  }
}

class ConnectionPane extends StatelessWidget {
  const ConnectionPane({
    required this.state,
    required this.palette,
    required this.inPlay,
    required this.onRetry,
    super.key,
  });

  final ConnectivityState state;
  final BoardPalette palette;
  final bool inPlay;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = connectionCopy(state, inPlay: inPlay);
    final checking = state == ConnectivityState.checking;
    return Material(
      key: const ValueKey('pathwise-connection'),
      // Keep the board visible behind the overlay during play.
      color: inPlay
          ? palette.canvas.withValues(alpha: 0.94)
          : palette.canvas,
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
                  if (checking)
                    SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: palette.route,
                      ),
                    ),
                  if (copy.retry)
                    FilledButton(
                      onPressed: () => onRetry(),
                      child: const Text('Retry'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
