import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/connectivity_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../ui/game_ui.dart';
import 'components/brand_mark.dart';

/// Player-facing wording. No technical detail.
({String title, String message, bool retry}) connectionCopy(
  ConnectivityState state, {
  required bool inPlay,
}) {
  return switch (state) {
    ConnectivityState.checking => (
      title: 'Checking connection',
      message: 'You can keep playing while we check your connection.',
      retry: false,
    ),
    ConnectivityState.online => (title: '', message: '', retry: false),
    ConnectivityState.offline => (
      title: "You're offline",
      message: 'Cloud sync is unavailable and progress will not be synced right now. Continue playing and saving locally?',
      retry: true,
    ),
  };
}

/// Non-blocking offline notification wrapper. Pathwise is local-first: gameplay
/// continues uninterrupted offline, and this notice appears at most once per
/// offline period when the player is not actively drawing.
class ConnectionGate extends StatefulWidget {
  const ConnectionGate({
    required this.connectivity,
    required this.child,
    super.key,
  });

  final ConnectivityService connectivity;
  final Widget? child;

  @override
  State<ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends State<ConnectionGate> {
  static const _periodicCheckInterval = Duration(seconds: 30);

  bool _shownThisOutage = false;
  bool _visible = false;
  Timer? _periodicCheckTimer;

  @override
  void initState() {
    super.initState();
    _periodicCheckTimer = Timer.periodic(_periodicCheckInterval, (_) {
      if (!mounted) return;
      unawaited(widget.connectivity.check());
    });
  }

  @override
  void dispose() {
    _periodicCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.select(
      (ConnectivityService service) => service.state,
    );
    final isDrawing = context.select((AppModel model) => model.isDrawing);
    final theme = context.select((AppModel model) => model.theme);

    if (state == ConnectivityState.online) {
      if (_visible || _shownThisOutage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _visible = false;
            _shownThisOutage = false;
          });
        });
      }
    } else if (state == ConnectivityState.offline &&
        !_shownThisOutage &&
        !isDrawing &&
        !_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _shownThisOutage) return;
        setState(() {
          _shownThisOutage = true;
          _visible = true;
        });
      });
    }

    final palette = BoardPalette.palettes[theme]!;
    return Stack(
      children: [
        widget.child ?? const SizedBox.shrink(),
        if (_visible)
          Positioned.fill(
            child: ConnectionPane(
              state: ConnectivityState.offline,
              palette: palette,
              inPlay: false,
              onRetry: widget.connectivity.retry,
              onDismiss: () => setState(() => _visible = false),
            ),
          ),
      ],
    );
  }
}

class OfflineStatusChip extends StatelessWidget {
  const OfflineStatusChip({required this.palette, super.key});

  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('offline-status-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.quiet,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.cardEdge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: palette.mutedInk),
          const SizedBox(width: 5),
          Text(
            'Offline',
            style: TextStyle(
              color: palette.mutedInk,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectionPane extends StatelessWidget {
  const ConnectionPane({
    required this.state,
    required this.palette,
    required this.inPlay,
    required this.onRetry,
    this.onDismiss,
    super.key,
  });

  final ConnectivityState state;
  final BoardPalette palette;
  final bool inPlay;
  final Future<void> Function() onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final copy = connectionCopy(state, inPlay: inPlay);
    return Material(
      key: const ValueKey('pathwise-connection'),
      color: palette.canvas.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: GameCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 56,
                      child: BrandMark(
                        background: palette.route,
                        ink: palette.onRoute,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        copy.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      copy.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.mutedInk,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ActionPill(
                      label: 'Continue playing',
                      tone: ActionTone.primary,
                      onTap: onDismiss ?? () => onRetry(),
                    ),
                    if (copy.retry && onDismiss != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => onRetry(),
                        child: Text(
                          'Retry connection',
                          style: TextStyle(color: palette.route),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
