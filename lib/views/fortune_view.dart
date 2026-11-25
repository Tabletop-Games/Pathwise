import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy_activity.dart';
import '../model/fortune.dart';
import '../ui/art/control_art.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'store_view.dart';

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
      _catalog.then((catalog) {
        if (!mounted) return;
        final prize = context.read<AppModel>().pendingFortune;
        if (prize != null && _pending == null) _show(catalog, prize);
      });
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
      _reveal = null;
      _pending = prize;
    });
    if (reduced) WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
  }

  Future<void> _finish() async {
    if (!mounted || _pending == null) return;
    final prize = _pending!;
    final model = context.read<AppModel>();
    setState(() {
      _reveal = prize;
      _pending = null;
      _working = true;
    });
    final saved = await model.settleFortune(prize);
    if (mounted) {
      setState(() => _working = false);
      if (saved) model.haptic.complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final palette = BoardPalette.palettes[model.theme]!;
    final wait = model.fortuneWait;
    final remaining = model.fortuneVideosRemaining;
    final showVideo =
        ads.wheelConfigured &&
        ads.readyFor(RewardPlacement.wheel) &&
        remaining > 0;
    final busy = _working || _pending != null;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final canSpin = !busy && wait == 0 && !model.storageError;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(palette),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          titleSpacing: 0,
          title: const Text(
            'Fortune Wheel',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
          ),
          actions: [
            BalanceChip(
              coins: model.coinBalance,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const StoreView(section: StoreSection.coins),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: AtmosphericBackdrop(
          child: SafeArea(
            child: FutureBuilder<FortuneCatalog>(
              future: _catalog,
              builder: (context, snapshot) {
                final catalog = snapshot.data;
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GameArt(ArtKind.wheel, palette: palette, size: 72),
                        const SizedBox(height: 12),
                        const Text('The wheel could not be loaded.'),
                      ],
                    ),
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
                                      onEnd: _finish,
                                      builder: (_, turns, _) => RepaintBoundary(
                                        child: CustomPaint(
                                          painter: _WheelPainter(
                                            catalog,
                                            turns,
                                            palette,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IgnorePointer(
                                      child: Center(
                                        child: _WheelHubMedallion(
                                          palette: palette,
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        width: 34,
                                        height: 30,
                                        child: CustomPaint(
                                          painter: _PointerPainter(palette),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: Semantics(
                            liveRegion: true,
                            child: AnimatedSwitcher(
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              child: Center(
                                key: ValueKey((_pending?.id, _reveal?.id)),
                                child: _reveal != null && _pending == null
                                    ? RewardAmount(_reveal!.coins, size: 40)
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const ValueKey('wheel-spin'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: const StadiumBorder(),
                            textStyle: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                          ),
                          onPressed: canSpin ? () => _spin(catalog) : null,
                          icon: PathIcon(
                            wait > 0 ? ControlGlyph.timer : ControlGlyph.wheel,
                            size: 22,
                          ),
                          label: Text(
                            wait > 0 ? fortuneCountdown(wait) : 'Free spin',
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
                          FilledButton.tonalIcon(
                            key: const ValueKey('wheel-video'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: busy
                                ? null
                                : () => _spin(catalog, video: true),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              'Spin · $remaining left',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

Future<FortuneCatalog> loadFortuneCatalog() => rootBundle
    .loadString('assets/data/fortune-prizes.json')
    .then(FortuneCatalog.new);

class _WheelHubMedallion extends StatelessWidget {
  const _WheelHubMedallion({required this.palette});
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final brassLight = Color.lerp(
      palette.accent,
      const Color(0xFFFFE58F),
      .45,
    )!;
    final brassDark = Color.lerp(palette.accent, const Color(0xFF7A5610), .45)!;
    return Container(
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brassLight, palette.accent, brassDark],
        ),
        border: Border.all(color: palette.ink, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.ink,
          border: Border.all(color: brassLight.withValues(alpha: .7), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Image.asset(
            'assets/art/ui/wheel_ticket.png',
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.catalog, this.turns, this.palette);
  final FortuneCatalog catalog;
  final double turns;
  final BoardPalette palette;

  /// Segment fills come from the equipped theme. The top prize uses the accent.
  List<Color> get _segments => [
    for (var i = 0; i < 5; i++)
      Color.lerp(palette.route, palette.ink, i.isEven ? .10 : .36)!,
    palette.accent,
  ];
  Color get _navy => palette.ink;
  Color get _gold => palette.accent;

  @override
  void paint(Canvas canvas, Size size) {
    const full = math.pi * 2;
    const sweep = full * FortuneCatalog.segmentTurns;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final rimOuter = radius + 10;
    final brassLight = Color.lerp(_gold, const Color(0xFFFFE58F), .48)!;
    final brassDark = Color.lerp(_gold, const Color(0xFF7A5610), .48)!;

    // Soft drop shadow behind the wheel.
    canvas.drawCircle(
      center.translate(0, 3),
      rimOuter,
      Paint()
        ..color = Colors.black.withValues(alpha: palette.dark ? .45 : .22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Dimensional golden/brass outer rim.
    final rimRect = Rect.fromCircle(center: center, radius: rimOuter);
    canvas.drawCircle(
      center,
      rimOuter,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brassLight, _gold, brassDark, _gold],
          stops: const [0.0, 0.35, 0.72, 1.0],
        ).createShader(rimRect),
    );
    canvas.drawCircle(
      center,
      rimOuter,
      Paint()
        ..color = _navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawCircle(
      center,
      rimOuter - 1.5,
      Paint()
        ..color = brassLight.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Static warm decorative bulb dots around the brass perimeter.
    const bulbCount = 18;
    final bulbRadius = radius + 5.2;
    final bulbGlow = Paint()
      ..color = const Color(0xFFFFF4C2).withValues(alpha: .38);
    final bulbCore = Paint()..color = const Color(0xFFFFF9E2);
    final bulbRim = Paint()
      ..color = brassDark.withValues(alpha: .75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    for (var i = 0; i < bulbCount; i++) {
      final angle = -math.pi / 2 + (i / bulbCount) * full;
      final pt = center + Offset(math.cos(angle), math.sin(angle)) * bulbRadius;
      canvas.drawCircle(pt, 3.3, bulbGlow);
      canvas.drawCircle(pt, 2.0, bulbCore);
      canvas.drawCircle(pt, 2.0, bulbRim);
    }

    // Radial/gradient segments.
    final paint = Paint()..isAntiAlias = true;
    for (final (index, prize) in catalog.prizes.indexed) {
      final start = -math.pi / 2 + ((turns % 1) * full) + index * sweep;
      final base = _segments[index];
      final innerTone = Color.lerp(base, _navy, .22)!;
      final outerTone = Color.lerp(
        base,
        Colors.white,
        palette.dark ? .08 : .14,
      )!;
      final segPaint = Paint()
        ..isAntiAlias = true
        ..shader = RadialGradient(
          colors: [innerTone, base, outerTone],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, true, segPaint);
      canvas.drawLine(
        center,
        center + Offset(math.cos(start), math.sin(start)) * radius,
        paint
          ..shader = null
          ..color = brassLight.withValues(alpha: .75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      paint.style = PaintingStyle.fill;

      final angle = start + sweep / 2;
      final spot =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * .68);
      final ink = palette.onColor(base);
      final coin = spot.translate(0, -radius * .09);
      final iconSize = radius * .07;
      canvas.drawCircle(coin, iconSize, paint..color = ink);
      canvas.drawCircle(coin, iconSize * .66, paint..color = base);
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
            fontFamily: 'Bricolage',
            fontWeight: FontWeight.w800,
            fontSize: radius * .148,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, spot.translate(-label.width / 2, 1));
      label.dispose();
    }

    // Inner bezel shadow & gold ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _navy.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      center,
      radius + 1,
      Paint()
        ..color = brassLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Hub collar beneath the central medallion widget.
    canvas.drawCircle(center, radius * .21, Paint()..color = _navy);
    canvas.drawCircle(
      center,
      radius * .21,
      Paint()
        ..color = brassLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.turns != turns || oldDelegate.palette != palette;
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter(this.palette);
  final BoardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final gold = palette.accent;
    final brassLight = Color.lerp(gold, const Color(0xFFFFE58F), .5)!;
    final brassDark = Color.lerp(gold, const Color(0xFF7A5610), .45)!;
    final cx = size.width / 2;
    final pointer = Path()
      ..moveTo(4, 3)
      ..quadraticBezierTo(cx, 0, size.width - 4, 3)
      ..lineTo(cx, size.height - 2)
      ..close();

    // Soft drop shadow.
    canvas.drawPath(
      pointer.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: .3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Dimensional left/right facets.
    final leftFacet = Path()
      ..moveTo(4, 3)
      ..quadraticBezierTo(cx, 0, cx, 1.5)
      ..lineTo(cx, size.height - 2)
      ..close();
    final rightFacet = Path()
      ..moveTo(cx, 1.5)
      ..quadraticBezierTo(cx, 0, size.width - 4, 3)
      ..lineTo(cx, size.height - 2)
      ..close();
    canvas.drawPath(leftFacet, Paint()..color = brassLight);
    canvas.drawPath(rightFacet, Paint()..color = brassDark);

    // Crisp outline and top brass rivet.
    canvas.drawPath(
      pointer,
      Paint()
        ..color = palette.ink
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(Offset(cx, 7.5), 3.0, Paint()..color = palette.ink);
    canvas.drawCircle(Offset(cx, 7.5), 1.6, Paint()..color = brassLight);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

String fortuneCountdown(int wait) {
  final seconds = (wait + 999) ~/ 1000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m ${seconds % 60}s';
}
