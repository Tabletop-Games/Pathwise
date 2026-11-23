import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/progression.dart';

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
      await showDialog<void>(
        context: context,
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
    final colors = Theme.of(context).colorScheme;
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
          child: Material(
            color: colors.tertiaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: colors.outline),
            ),
            child: IconButton(
              tooltip: 'Catch supply crate',
              onPressed: _catchCrate,
              icon: const Icon(Icons.inventory_2_rounded),
              color: colors.onTertiaryContainer,
              iconSize: 27,
              constraints: const BoxConstraints.tightFor(
                width: _size,
                height: _size,
              ),
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
          ? 'Video reward wasn’t verified. Try again.'
          : 'Video unavailable. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.inventory_2_rounded),
      title: const Text('Supply crate'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+${widget.crate.coins} coins',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Watch a short ad to claim your reward.'),
          if (_error case final message?)
            Semantics(liveRegion: true, child: Text(message)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('No Thanks'),
        ),
        FilledButton(
          onPressed: _busy ? null : _claim,
          child: Text(_busy ? 'Checking video…' : 'Watch Ad & Claim'),
        ),
      ],
    ),
  );
}
