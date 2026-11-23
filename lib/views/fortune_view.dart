import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/economy_activity.dart';
import '../model/fortune.dart';
import '../model/time_attack.dart';

class FortuneView extends StatefulWidget {
  const FortuneView({super.key});

  @override
  State<FortuneView> createState() => _FortuneViewState();
}

class _FortuneViewState extends State<FortuneView> {
  late final Future<FortuneCatalog> _catalog;
  Timer? _ticker;
  FortuneStatus? _status;
  BootTime? _receiptClock;
  FortunePrize? _reveal;
  FortunePrize? _pending;
  double _rotation = 0;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _catalog = rootBundle
        .loadString('backend/fortune-prizes.json')
        .then(FortuneCatalog.new);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<AppModel>().recordActivity(EconomyEvent.wheelOpened);
      final ads = context.read<AdService>();
      if (!ads.wheelConfigured) return;
      unawaited(ads.prepare(canPresent: _current));
      final catalog = await _catalog;
      if (mounted) await _sync(catalog);
    });
  }

  bool _current() => mounted && ModalRoute.isCurrentOf(context) == true;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<bool> _sync(FortuneCatalog catalog, {String? receipt}) async {
    if (!mounted) return false;
    final ads = context.read<AdService>();
    final model = context.read<AppModel>();
    final data = await ads.verifier?.fortune();
    if (data == null) return false;
    final FortuneStatus status;
    try {
      status = FortuneStatus.fromJson(data);
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
    final saved = await model.applyVerifiedFortune(catalog, status);
    if (!mounted) return saved;
    setState(() {
      _status = status;
      _receiptClock = model.fortuneClock;
    });
    if (saved && status.last != null) {
      final prize = catalog.prizes
          .where((item) => item.id == status.last)
          .firstOrNull;
      if (prize == null) return saved;
      if (receipt != null && receipt == status.receipt) {
        _show(catalog, prize);
      } else {
        setState(() => _reveal = prize);
      }
    }
    return saved;
  }

  Future<void> _free(FortuneCatalog catalog) async {
    final model = context.read<AppModel>();
    setState(() => _working = true);
    final prize = await model.spinFreeFortune(catalog);
    if (!mounted) return;
    setState(() => _working = false);
    if (prize != null) _show(catalog, prize);
  }

  Future<void> _video(FortuneCatalog catalog) async {
    final ads = context.read<AdService>();
    context.read<AppModel>().recordActivity(EconomyEvent.wheelRequested);
    final shown = await ads.watchVideo(
      (receipt) => _sync(catalog, receipt: receipt),
      placement: RewardPlacement.wheel,
      canPresent: _current,
    );
    if (!shown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A wheel video is unavailable.')),
      );
    }
  }

  void _show(FortuneCatalog catalog, FortunePrize prize) {
    final destination = 1 - catalog.center(prize);
    context.read<AppModel>().haptic.selection();
    final reduced = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _rotation += (reduced ? 0 : 5) + ((destination - _rotation % 1) % 1);
      _reveal = reduced ? prize : null;
      _pending = reduced ? null : prize;
    });
    if (reduced) context.read<AppModel>().haptic.complete();
  }

  String _countdown(int wait) {
    final minutes = (wait + 59999) ~/ 60000;
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final ads = context.watch<AdService>();
    final colors = Theme.of(context).colorScheme;
    final wait = model.fortuneWait;
    final boot = model.fortuneClock;
    final anchor = _receiptClock;
    final elapsed = boot != null && anchor != null && boot.boot == anchor.boot
        ? boot.milliseconds - anchor.milliseconds
        : 0;
    final remaining = _status?.remaining(elapsed);
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
                child: Text('The wheel catalog could not be loaded.'),
              );
            }
            if (catalog == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 286),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.topCenter,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: _rotation),
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 2700),
                            curve: Curves.easeInOutCubic,
                            onEnd: () {
                              if (_pending == null) return;
                              setState(() {
                                _reveal = _pending;
                                _pending = null;
                              });
                              model.haptic.complete();
                            },
                            builder: (_, turns, _) => CustomPaint(
                              painter: _WheelPainter(catalog, colors, turns),
                            ),
                          ),
                          Align(
                            alignment: Alignment.topCenter,
                            child: Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 42,
                              color: colors.onSurface,
                            ),
                          ),
                          Center(
                            child: CircleAvatar(
                              backgroundColor: colors.surface,
                              child: Icon(
                                Icons.auto_awesome,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  child: Text(
                    _reveal?.label ?? 'One free spin every 24 hours',
                    key: ValueKey(_reveal?.id),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  runSpacing: 8,
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: !busy && wait == 0 && !model.storageError
                          ? () => _free(catalog)
                          : null,
                      child: Text(
                        wait > 0 ? 'Free in ${_countdown(wait)}' : 'Free spin',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: ads.wheelConfigured && !busy && remaining != 0
                          ? () => _video(catalog)
                          : null,
                      child: const Text('Watch for a spin'),
                    ),
                  ],
                ),
                if (wait < 0)
                  const Text(
                    'A device elapsed-time reading is needed for the free spin.',
                    textAlign: TextAlign.center,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    ads.wheelConfigured
                        ? remaining == null
                              ? 'Connect to check your four video spins.'
                              : '$remaining of 4 video spins available'
                        : 'Optional wheel videos are unavailable.',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (ads.message case final message?)
                  Text(message, textAlign: TextAlign.center),
                Text(
                  'Prize odds',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final prize in catalog.prizes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_icon(prize)),
                    title: Text(prize.label),
                    trailing: Text('${prize.weight}%'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

IconData _icon(FortunePrize prize) => switch (prize.id) {
  'boost' => Icons.bolt,
  'cache' => Icons.inventory_2_outlined,
  'summit' => Icons.star_rounded,
  _ => Icons.toll,
};

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.catalog, this.colors, this.turns);
  final FortuneCatalog catalog;
  final ColorScheme colors;
  final double turns;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()..isAntiAlias = true;
    var angle = -math.pi / 2 + turns * math.pi * 2;
    for (final (index, prize) in catalog.prizes.indexed) {
      final sweep = prize.weight * math.pi * 2 / 100;
      paint.color = index.isEven
          ? colors.primaryContainer
          : colors.secondaryContainer;
      canvas.drawArc(rect, angle, sweep, true, paint);
      paint.color = colors.surface;
      paint.strokeWidth = 2;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        paint,
      );
      if (prize.weight >= 4) {
        final icon = _icon(prize);
        final text = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: index.isEven
                  ? colors.onPrimaryContainer
                  : colors.onSecondaryContainer,
              fontSize: prize.weight < 8 ? 15 : 23,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final middle = angle + sweep / 2;
        text.paint(
          canvas,
          center +
              Offset(math.cos(middle), math.sin(middle)) * (radius * .72) -
              Offset(text.width / 2, text.height / 2),
        );
        text.dispose();
      }
      angle += sweep;
    }
    paint
      ..color = colors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.turns != turns || oldDelegate.colors != colors;
}
