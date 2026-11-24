import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/progression.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';

class FallingCrate extends StatefulWidget {
  const FallingCrate({required this.crate, super.key});
  final Crate crate;

  @override
  State<FallingCrate> createState() => _FallingCrateState();
}

class _FallingCrateState extends State<FallingCrate>
    with SingleTickerProviderStateMixin {
  static const _size = 52.0;
  static const _edge = 4.0;
  late final AnimationController _flight;
  final _horizontal = Random().nextDouble();
  bool _caught = false;

  @override
  void initState() {
    super.initState();
    final model = context.read<AppModel>();
    _flight =
        AnimationController(
          vsync: this,
          duration: model.progression.crateFlightTime,
          animationBehavior: AnimationBehavior.preserve,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed)
            model.dismissCrate(widget.crate);
        });
    _flight.forward();
  }

  Future<void> _catchCrate() async {
    final model = context.read<AppModel>();
    final crate = widget.crate;
    if (ModalRoute.isCurrentOf(context) != true || !model.revealCrate(crate))
      return;
    _flight.stop();
    setState(() => _caught = true);
    try {
      await showGameDialog<void>(
        context,
        builder: (_) => _CrateReward(crate: crate),
      );
    } finally {
      model.dismissCrate(crate);
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_caught) return const SizedBox.shrink();
    final reduce = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (_, constraints) => ClipRect(
        child: AnimatedBuilder(
          animation: _flight,
          builder: (_, child) {
            final time = _flight.value;
            final distance = time * (.65 + .35 * time);
            final horizontalRoom = max(
              0.0,
              constraints.maxWidth - _size - 2 * _edge,
            );
            return Stack(
              children: [
                Positioned(
                  left: _edge + _horizontal * horizontalRoom,
                  top: reduce
                      ? constraints.maxHeight * .12
                      : -_size + (constraints.maxHeight + _size) * distance,
                  child: Transform.rotate(
                    angle: reduce ? 0 : .14 * (time * 2 - 1),
                    child: child,
                  ),
                ),
              ],
            );
          },
          child: IconButton(
            tooltip: 'Catch supply crate',
            onPressed: _catchCrate,
            padding: EdgeInsets.zero,
            icon: GameArt(ArtKind.crate, palette: context.palette, size: _size),
            constraints: const BoxConstraints.tightFor(
              width: _size,
              height: _size,
            ),
          ),
        ),
      ),
    );
  }
}

class _CrateReward extends StatefulWidget {
  const _CrateReward({required this.crate});
  final Crate crate;

  @override
  State<_CrateReward> createState() => _CrateRewardState();
}

class _CrateRewardState extends State<_CrateReward> {
  bool _busy = false;
  String? _error;

  bool _current() => mounted && ModalRoute.isCurrentOf(context) == true;

  Future<void> _claim() async {
    if (_busy) return;
    final ads = context.read<AdService>();
    final model = context.read<AppModel>();
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!ads.readyFor(RewardPlacement.crate)) {
      await ads.prepare(canPresent: _current);
    }
    if (!_current()) return;
    var accepting = true;
    var credited = false;
    final shown = await ads.watchVideo(
      (receipt) async {
        if (!accepting || !_current()) return false;
        credited = await model.claimVerifiedCrate(widget.crate, receipt);
        return credited;
      },
      placement: RewardPlacement.crate,
      canPresent: _current,
      waitForReward: true,
    );
    accepting = false;
    if (!_current()) return;
    if (credited || model.fallingCrate != widget.crate) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = shown
          ? 'Video ended without a reward. Try again.'
          : 'Video unavailable. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: GameDialog(
      art: GameArt(ArtKind.crate, palette: context.palette, size: 84),
      title: 'Supply crate',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: RewardAmount(widget.crate.coins, size: 40)),
          if (_error case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.mutedInk),
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (kDebugMode && widget.crate.id.startsWith('crate/debug/')) ...[
          ActionPill(
            label: 'Simulate failure',
            onTap: _busy
                ? null
                : () =>
                      setState(() => _error = 'Video unavailable. Try again.'),
          ),
          ActionPill(
            label: 'Simulate reward',
            onTap: _busy
                ? null
                : () async {
                    final model = context.read<AppModel>();
                    if (await model.claimVerifiedCrate(
                          widget.crate,
                          widget.crate.id,
                        ) &&
                        mounted) {
                      Navigator.of(this.context).pop();
                    }
                  },
          ),
        ],
        ActionPill(
          label: 'Not now',
          onTap: _busy ? null : () => Navigator.of(context).pop(),
        ),
        ActionPill(
          label: _busy ? 'Working…' : 'Watch',
          icon: _busy ? null : Icons.play_arrow_rounded,
          tone: ActionTone.primary,
          onTap: _busy ? null : _claim,
        ),
      ],
    ),
  );
}
