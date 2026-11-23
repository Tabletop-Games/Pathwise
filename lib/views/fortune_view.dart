import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/economy_activity.dart';
import '../model/fortune.dart';

class FortuneView extends StatefulWidget {
  const FortuneView({super.key});

  @override
  State<FortuneView> createState() => _FortuneViewState();
}

class _FortuneViewState extends State<FortuneView> {
  late final Future<FortuneCatalog> _catalog;
  Timer? _ticker;
  FortunePrize? _reveal, _pending;
  double _rotation = 0;
  bool _working = false, _checkingVideos = false;
  int _availabilityTicks = 0;

  @override
  void initState() {
    super.initState();
    _catalog = loadFortuneCatalog();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (++_availabilityTicks % 30 == 0) unawaited(_refreshVideos());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_current()) return;
      context.read<AppModel>().recordActivity(EconomyEvent.wheelOpened);
      unawaited(_refreshVideos());
    });
  }

  Future<void> _refreshVideos() async {
    if (!_current() || _working || _pending != null || _checkingVideos) return;
    final ads = context.read<AdService>();
    if (!ads.wheelConfigured) return;
    _checkingVideos = true;
    try {
      await ads.prepare(canPresent: _current);
    } finally {
      _checkingVideos = false;
    }
  }

  bool _current() =>
      mounted &&
      ModalRoute.isCurrentOf(context) == true &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _spin(FortuneCatalog catalog, {bool video = false}) async {
    if (_working || _pending != null) return;
    final model = context.read<AppModel>();
    setState(() => _working = true);
    try {
      if (video) {
        model.recordActivity(EconomyEvent.wheelRequested);
        await context.read<AdService>().watchVideo(
          (receipt) async {
            final prize = await model.spinRewardedFortune(catalog, receipt);
            if (mounted && prize != null) _show(catalog, prize);
            return prize != null;
          },
          placement: RewardPlacement.wheel,
          canPresent: _current,
          waitForReward: true,
        );
      } else {
        final prize = await model.spinFreeFortune(catalog);
        if (mounted && prize != null) _show(catalog, prize);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _show(FortuneCatalog catalog, FortunePrize prize) {
    final haptic = context.read<AppModel>().haptic;
    haptic.selection();
    final reduced = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _rotation = catalog.destination(
        _rotation,
        prize,
        rotations: reduced ? 0 : 5,
      );
      _reveal = reduced ? prize : null;
      _pending = reduced ? null : prize;
    });
    if (reduced) haptic.complete();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final theme = Theme.of(context);
    final wait = model.fortuneWait;
    final remaining = model.fortuneVideosRemaining;
    final showVideo =
        ads.wheelConfigured &&
        ads.readyFor(RewardPlacement.wheel) &&
        remaining > 0;
    final busy = _working || _pending != null;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fortune Wheel')),
      body: SafeArea(
        child: FutureBuilder<FortuneCatalog>(
          future: _catalog,
          builder: (context, snapshot) {
            final catalog = snapshot.data;
            if (snapshot.hasError) {
              return const Center(
                child: Text('The wheel could not be loaded.'),
              );
            }
            if (catalog == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Center(
                      child: Chip(
                        avatar: const Icon(Icons.toll_rounded, size: 19),
                        label: Text('${model.coinBalance} coins'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Semantics(
                            label: 'Coin wheel. Rewards 8, 15, 25, 40, 70, and 100 coins.',
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: _rotation),
                                  duration: reduced
                                      ? Duration.zero
                                      : const Duration(milliseconds: 3200),
                                  curve: Curves.easeInOutCubic,
                                  onEnd: () {
                                    if (_pending == null) return;
                                    setState(() {
                                      _reveal = _pending;
                                      _pending = null;
                                    });
                                    model.haptic.complete();
                                  },
                                  builder: (_, turns, _) => RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _WheelPainter(catalog, turns),
                                    ),
                                  ),
                                ),
                                const Align(
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(
                                    width: 30,
                                    height: 27,
                                    child: CustomPaint(
                                      painter: _PointerPainter(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      liveRegion: true,
                      child: AnimatedSwitcher(
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        child: Text(
                          _pending != null
                              ? 'Spinning…'
                              : _reveal != null
                              ? '+${_reveal!.coins} coins'
                              : 'One free spin every 24 hours',
                          key: ValueKey((_pending?.id, _reveal?.id)),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: !busy && wait == 0 && !model.storageError
                          ? () => _spin(catalog)
                          : null,
                      icon: const Icon(Icons.rotate_right_rounded),
                      label: Text(
                        wait > 0
                            ? 'Next free spin in ${fortuneCountdown(wait)}'
                            : 'Free spin',
                      ),
                    ),
                    if (wait < 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'The device clock is temporarily unavailable.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (showVideo) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => _spin(catalog, video: true),
                        child: Text('Watch for a spin · $remaining left'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<FortuneCatalog> loadFortuneCatalog() => rootBundle
    .loadString('backend/fortune-prizes.json')
    .then(FortuneCatalog.new);

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.catalog, this.turns);
  final FortuneCatalog catalog;
  final double turns;

  static const _segments = [
    Color(0xFF133044),
    Color(0xFF13545A),
    Color(0xFF253B57),
    Color(0xFF176D66),
    Color(0xFF423B37),
    Color(0xFFEAC278),
  ];
  static const _navy = Color(0xFF0D2335);
  static const _gold = Color(0xFFFFD789);

  @override
  void paint(Canvas canvas, Size size) {
    const full = math.pi * 2;
    const sweep = full * FortuneCatalog.segmentTurns;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawCircle(center, radius + 4, paint..color = _navy);
    for (final (index, prize) in catalog.prizes.indexed) {
      final start = -math.pi / 2 + ((turns % 1) * full) + index * sweep;
      canvas.drawArc(rect, start, sweep, true, paint..color = _segments[index]);
      canvas.drawLine(
        center,
        center + Offset(math.cos(start), math.sin(start)) * radius,
        paint
          ..color = _gold.withValues(alpha: .6)
          ..strokeWidth = 1.5,
      );
      final angle = start + sweep / 2;
      final spot =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * .68);
      final ink = index == 5 ? _navy : const Color(0xFFFFF2D6);
      final coin = spot.translate(0, -radius * .085);
      final iconSize = radius * .065;
      canvas.drawCircle(coin, iconSize, paint..color = ink);
      canvas.drawCircle(coin, iconSize * .66, paint..color = _segments[index]);
      canvas.drawLine(
        coin.translate(-iconSize * .3, 0),
        coin.translate(iconSize * .3, 0),
        paint
          ..color = ink
          ..strokeWidth = 1.2,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${prize.coins}',
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w800,
            fontSize: radius * .145,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, spot.translate(-label.width / 2, 1));
      label.dispose();
    }
    canvas.drawCircle(
      center,
      radius + 1,
      paint
        ..color = _gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * .16, paint..color = _navy);
    canvas.drawCircle(center, radius * .092, paint..color = _gold);
    canvas.drawCircle(center, radius * .046, paint..color = _navy);
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.turns != turns;
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pointer = Path()
      ..moveTo(3, 3)
      ..lineTo(size.width - 3, 3)
      ..lineTo(size.width / 2, size.height - 2)
      ..close();
    canvas.drawPath(pointer, Paint()..color = const Color(0xFFFFD789));
    canvas.drawPath(
      pointer,
      Paint()
        ..color = const Color(0xFF0D2335)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => false;
}

String fortuneCountdown(int wait) {
  final seconds = (wait + 999) ~/ 1000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m ${seconds % 60}s';
}
