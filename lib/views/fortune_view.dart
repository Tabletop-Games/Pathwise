import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/haptic_service.dart';
import '../logic/sound_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy_activity.dart';
import '../model/fortune.dart';
import '../ui/art/control_art.dart';
import '../ui/art/game_assets.dart';
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

  @override
  void initState() {
    super.initState();
    _catalog = loadFortuneCatalog();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      unawaited(_refreshVideos());
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
        final messenger = ScaffoldMessenger.of(context);
        final ads = context.read<AdService>();
        var rewarded = false;
        final shown = await ads.watchVideo(
          (receipt) async {
            final prize = await model.spinRewardedFortune(catalog, receipt);
            if (prize != null) {
              rewarded = true;
              if (mounted) _show(catalog, prize);
            }
            return prize != null;
          },
          placement: RewardPlacement.wheel,
          canPresent: _current,
          waitForReward: true,
        );
        if (mounted && !rewarded) {
          final fallback = shown
              ? 'Video closed before the reward finished.'
              : 'Video unavailable. Try again shortly.';
          messenger.showSnackBar(
            SnackBar(content: Text(ads.message ?? fallback)),
          );
        }
      } else {
        final prize = await model.spinFreeFortune(catalog);
        if (mounted && prize != null) _show(catalog, prize);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _show(FortuneCatalog catalog, FortunePrize prize) {
    context.read<AppModel>().feedback(
      HapticEvent.wheelTick,
      SoundEvent.wheelTick,
    );
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
      if (saved) {
        model.feedback(HapticEvent.wheelResult, SoundEvent.wheelResult);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final palette = BoardPalette.palettes[model.theme]!;
    final wait = model.fortuneWait;
    final remaining = model.fortuneVideosRemaining;
    final showVideo = ads.wheelConfigured;
    final videoReady = ads.readyFor(RewardPlacement.wheel);
    final busy = _working || _pending != null;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final canSpin = !busy && wait == 0 && !model.storageError;
    final canVideoSpin = !busy && remaining > 0 && videoReady;
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
                                button: canSpin,
                                label: 'Coin wheel. Rewards 8, 15, 25, 40, 70, and 100 coins.',
                                onTap: canSpin ? () => _spin(catalog) : null,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: canSpin ? () => _spin(catalog) : null,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0, end: _rotation),
                                        duration: reduced
                                            ? Duration.zero
                                            : const Duration(
                                                milliseconds: 3200,
                                              ),
                                        curve: Curves.easeInOutCubic,
                                        onEnd: _finish,
                                        builder: (_, turns, _) =>
                                            RepaintBoundary(
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
                                          width: 38,
                                          height: 36,
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
                        _WheelSpinButton(
                          wait: wait,
                          canSpin: canSpin,
                          onSpin: () => _spin(catalog),
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
                          FilledButton.icon(
                            key: const ValueKey('wheel-video'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: const StadiumBorder(),
                              backgroundColor: palette.accent,
                              foregroundColor: palette.onAccent,
                              disabledBackgroundColor: palette.quiet,
                              disabledForegroundColor: palette.mutedInk,
                              textStyle: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                            ),
                            onPressed: canVideoSpin
                                ? () => _spin(catalog, video: true)
                                : null,
                            icon: Icon(
                              remaining <= 0
                                  ? Icons.block_rounded
                                  : (videoReady
                                        ? Icons.play_arrow_rounded
                                        : Icons.hourglass_top_rounded),
                            ),
                            label: Text(
                              remaining <= 0
                                  ? 'No video spins left'
                                  : (videoReady
                                        ? 'Spin · $remaining left'
                                        : 'Loading video'),
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
      .50,
    )!;
    final brassDark = Color.lerp(palette.accent, const Color(0xFF7A5610), .50)!;
    final gemHighlight = Color.lerp(palette.ink, palette.accent, .26)!;
    return Container(
      width: 60,
      height: 60,
      padding: const EdgeInsets.all(4.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brassLight, palette.accent, brassDark, palette.accent],
          stops: const [0.0, 0.35, 0.72, 1.0],
        ),
        border: Border.all(color: palette.ink, width: 2.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .36),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.32, -0.36),
            radius: 0.95,
            colors: [gemHighlight, palette.ink],
          ),
          border: Border.all(
            color: brassLight.withValues(alpha: .85),
            width: 1.2,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: const Alignment(-0.45, -0.55),
              child: Container(
                width: 16,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white.withValues(alpha: .16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(7.5),
              child: Image.asset(
                'assets/art/ui/wheel_ticket.webp',
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.3),
                        colors: [brassLight, palette.accent],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelSpinButton extends StatefulWidget {
  const _WheelSpinButton({
    required this.wait,
    required this.canSpin,
    required this.onSpin,
  });

  final int wait;
  final bool canSpin;
  final VoidCallback onSpin;

  @override
  State<_WheelSpinButton> createState() => _WheelSpinButtonState();
}

class _WheelSpinButtonState extends State<_WheelSpinButton> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _WheelSpinButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wait != widget.wait) _sync();
  }

  void _sync() {
    if (widget.wait > 0) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wait = context.read<AppModel>().fortuneWait;
    final canSpin = widget.canSpin || (wait == 0 && widget.wait > 0);
    return FilledButton.icon(
      key: const ValueKey('wheel-spin'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      onPressed: canSpin ? widget.onSpin : null,
      icon: PathIcon(
        wait > 0 ? ControlGlyph.timer : ControlGlyph.wheel,
        size: 22,
      ),
      label: Text(wait > 0 ? fortuneCountdown(wait) : 'Free spin'),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.catalog, this.turns, this.palette)
    : super(repaint: GameAssetCache.instance);
  final FortuneCatalog catalog;
  final double turns;
  final BoardPalette palette;

  /// Segment fills come from the equipped theme. The top prize uses the accent.
  List<Color> get _segments => [
    for (var i = 0; i < 5; i++)
      i.isEven
          ? Color.lerp(
              palette.route,
              palette.surface,
              palette.dark ? .08 : .14,
            )!
          : Color.lerp(palette.route, palette.ink, .44)!,
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
    final brassLight = Color.lerp(_gold, const Color(0xFFFFE58F), .50)!;
    final brassDark = Color.lerp(_gold, const Color(0xFF7A5610), .50)!;
    final coinImage = GameAssetCache.instance.imageFor(
      'assets/art/resources/coin.webp',
    );

    // Soft drop shadow behind the wheel.
    canvas.drawCircle(
      center.translate(0, 4),
      rimOuter,
      Paint()
        ..color = Colors.black.withValues(alpha: palette.dark ? .48 : .24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
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
      rimOuter - 1.8,
      Paint()
        ..color = brassLight.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Recessed rim studs / warm jewel bulbs around the brass perimeter.
    const bulbCount = 18;
    final bulbRadius = radius + 5.2;
    final bulbSocket = Paint()..color = _navy.withValues(alpha: .72);
    final bulbGlow = Paint()
      ..color = const Color(0xFFFFF4C2).withValues(alpha: .42);
    final bulbCore = Paint()..color = const Color(0xFFFFF9E2);
    final bulbSpec = Paint()..color = Colors.white.withValues(alpha: .9);
    for (var i = 0; i < bulbCount; i++) {
      final angle = -math.pi / 2 + (i / bulbCount) * full;
      final pt = center + Offset(math.cos(angle), math.sin(angle)) * bulbRadius;
      canvas.drawCircle(pt, 3.6, bulbGlow);
      canvas.drawCircle(pt, 2.7, bulbSocket);
      canvas.drawCircle(pt, 2.0, bulbCore);
      canvas.drawCircle(pt.translate(-0.6, -0.6), 0.7, bulbSpec);
    }

    // Radial/gradient segments.
    final dividerShadow = Paint()
      ..color = _navy.withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    final dividerGold = Paint()
      ..color = brassLight.withValues(alpha: .88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final imagePaint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    final fallbackPaint = Paint()..isAntiAlias = true;

    for (final (index, prize) in catalog.prizes.indexed) {
      final start = -math.pi / 2 + ((turns % 1) * full) + index * sweep;
      final base = _segments[index];
      final innerTone = Color.lerp(base, _navy, .26)!;
      final outerTone = Color.lerp(
        base,
        Colors.white,
        palette.dark ? .12 : .20,
      )!;
      final segPaint = Paint()
        ..isAntiAlias = true
        ..shader = RadialGradient(
          colors: [innerTone, base, outerTone],
          stops: const [0.0, 0.56, 1.0],
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, true, segPaint);

      final edgeEnd =
          center + Offset(math.cos(start), math.sin(start)) * radius;
      canvas.drawLine(center, edgeEnd, dividerShadow);
      canvas.drawLine(center, edgeEnd, dividerGold);

      final angle = start + sweep / 2;
      final spot =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * .66);
      final ink = palette.onColor(outerTone);
      final coinCenter = spot.translate(0, -radius * .11);
      final coinRadius = radius * .115;

      // Soft shadow behind the wedge coin.
      canvas.drawCircle(
        coinCenter.translate(0, 1.5),
        coinRadius * .92,
        fallbackPaint
          ..color = Colors.black.withValues(alpha: palette.dark ? .42 : .24)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      );
      fallbackPaint.maskFilter = null;

      if (coinImage != null) {
        final src = Rect.fromLTWH(
          0,
          0,
          coinImage.width.toDouble(),
          coinImage.height.toDouble(),
        );
        final dst = Rect.fromCircle(center: coinCenter, radius: coinRadius);
        canvas.drawImageRect(coinImage, src, dst, imagePaint);
      } else {
        final coinRect = Rect.fromCircle(
          center: coinCenter,
          radius: coinRadius,
        );
        canvas.drawCircle(
          coinCenter,
          coinRadius,
          fallbackPaint
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.35),
              colors: [brassLight, _gold, brassDark],
            ).createShader(coinRect),
        );
        fallbackPaint.shader = null;
        canvas.drawCircle(
          coinCenter,
          coinRadius,
          Paint()
            ..color = _navy.withValues(alpha: .6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        canvas.drawCircle(
          coinCenter,
          coinRadius * .68,
          Paint()
            ..color = brassLight.withValues(alpha: .75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }

      final label = TextPainter(
        text: TextSpan(
          text: '${prize.coins}',
          style: TextStyle(
            color: ink,
            fontFamily: 'Bricolage',
            fontWeight: FontWeight.w800,
            fontSize: radius * .152,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: palette.dark ? .45 : .20),
                offset: const Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, spot.translate(-label.width / 2, radius * .015));
      label.dispose();
    }

    // Subtle top-left lighting sheen across the wheel face.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: palette.dark ? .08 : .14),
            Colors.transparent,
            Colors.black.withValues(alpha: palette.dark ? .16 : .06),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // Inner bezel shadow & gold ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _navy.withValues(alpha: .52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );
    canvas.drawCircle(
      center,
      radius + 1.2,
      Paint()
        ..color = brassLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Hub collar beneath the central medallion widget.
    canvas.drawCircle(center, radius * .22, Paint()..color = _navy);
    canvas.drawCircle(
      center,
      radius * .22,
      Paint()
        ..color = brassLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
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
    final brassLight = Color.lerp(gold, const Color(0xFFFFE58F), .55)!;
    final brassDark = Color.lerp(gold, const Color(0xFF7A5610), .48)!;
    final cx = size.width / 2;
    final pointer = Path()
      ..moveTo(4, 5)
      ..quadraticBezierTo(cx, 0, size.width - 4, 5)
      ..lineTo(size.width - 6, 13)
      ..lineTo(cx, size.height - 2)
      ..lineTo(6, 13)
      ..close();

    // Soft drop shadow.
    canvas.drawPath(
      pointer.shift(const Offset(0, 2.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: .38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    // Dimensional left/right facets.
    final leftFacet = Path()
      ..moveTo(4, 5)
      ..quadraticBezierTo(cx, 0, cx, 2.0)
      ..lineTo(cx, size.height - 2)
      ..lineTo(6, 13)
      ..close();
    final rightFacet = Path()
      ..moveTo(cx, 2.0)
      ..quadraticBezierTo(cx, 0, size.width - 4, 5)
      ..lineTo(size.width - 6, 13)
      ..lineTo(cx, size.height - 2)
      ..close();
    canvas.drawPath(leftFacet, Paint()..color = brassLight);
    canvas.drawPath(rightFacet, Paint()..color = brassDark);

    // Center ridge highlight and crisp outline.
    canvas.drawLine(
      Offset(cx, 12),
      Offset(cx, size.height - 4),
      Paint()
        ..color = Colors.white.withValues(alpha: .45)
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      pointer,
      Paint()
        ..color = palette.ink
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2,
    );

    // Top jewel rivet.
    final rivetCenter = Offset(cx, 9.0);
    canvas.drawCircle(rivetCenter, 4.0, Paint()..color = palette.ink);
    canvas.drawCircle(
      rivetCenter,
      2.6,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          colors: [Colors.white, brassLight, gold],
        ).createShader(Rect.fromCircle(center: rivetCenter, radius: 2.6)),
    );
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
