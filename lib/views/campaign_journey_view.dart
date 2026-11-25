import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import '../model/journey.dart';
import '../model/user_preferences.dart';
import '../ui/art/game_assets.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'levels_view.dart';
import 'main_menu_view.dart';
import 'puzzle_view.dart';

/// Reverse list with one fixed-size slot per level and one per chapter chest.
/// A distant jump targets a pixel offset without visiting preceding levels.
class CampaignJourneyView extends StatefulWidget {
  const CampaignJourneyView({super.key});

  @override
  State<CampaignJourneyView> createState() => _CampaignJourneyViewState();
}

class _CampaignJourneyViewState extends State<CampaignJourneyView> {
  ScrollController? _scroll;
  int? _lastFocusedLevel;
  double _lastViewportHeight = 0;

  double get _extent =>
      MediaQuery.textScalerOf(context).scale(1) > 1.35 ? 176 : 138;

  static int _slotForLevel(int level) => level - 1 + chapterFor(level);

  double _focusedOffset(int slot, double viewportHeight) {
    final target = (slot + 0.5) * _extent - viewportHeight * 0.34;
    return math.max(0.0, target);
  }

  void _focusSlot(int slot, {bool animate = false}) {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    final viewportHeight = scroll.position.viewportDimension > 0
        ? scroll.position.viewportDimension
        : _lastViewportHeight;
    final target = _focusedOffset(slot, viewportHeight);
    if (!animate ||
        MediaQuery.disableAnimationsOf(context) ||
        (target - scroll.offset).abs() > viewportHeight * 2.5) {
      scroll.jumpTo(target);
    } else {
      scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final biome = biomeForTheme(model.theme);
    final highContrast =
        model.theme == PathwiseTheme.signal ||
        model.theme == PathwiseTheme.amoledCarbon;
    final highest = model.highestUnlocked;

    if (_lastFocusedLevel != null && _lastFocusedLevel != highest) {
      _lastFocusedLevel = highest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusSlot(_slotForLevel(highest), animate: true);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey'),
        actions: [
          IconButton(
            tooltip: 'Current level',
            icon: const Icon(Icons.my_location),
            onPressed: () =>
                _focusSlot(_slotForLevel(model.highestUnlocked), animate: true),
          ),
          IconButton(
            tooltip: 'Jump to level',
            icon: const Icon(Icons.explore_outlined),
            onPressed: () async {
              final level = await showDialog<int>(
                context: context,
                builder: (_) => const _JumpDialog(),
              );
              if (mounted && level != null) {
                _focusSlot(_slotForLevel(level), animate: true);
              }
            },
          ),
          IconButton(
            tooltip: 'Level grid',
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const LevelsView(quickNavigation: true),
              ),
            ),
          ),
        ],
      ),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              if (model.pendingChapterChests.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: GameCard(
                      selected: true,
                      onTap: () => showChapterTreasures(context),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          GameArt(ArtKind.treasure, palette: palette, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Treasures · ${model.pendingChapterChests.length}',
                              style: TextStyle(
                                color: palette.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          ActionPill(
                            label: 'Claim',
                            tone: ActionTone.primary,
                            onTap: () => showChapterTreasures(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _lastViewportHeight = constraints.maxHeight;
                        _lastFocusedLevel ??= highest;
                        _scroll ??= ScrollController(
                          initialScrollOffset: _focusedOffset(
                            _slotForLevel(highest),
                            constraints.maxHeight,
                          ),
                        );
                        return ListView.builder(
                          reverse: true,
                          itemExtent: _extent,
                          controller: _scroll,
                          itemBuilder: (context, index) {
                            final chapter = index ~/ (chapterSize + 1);
                            final position = index % (chapterSize + 1);
                            if (position == chapterSize) {
                              return _ChestStop(chapter, palette, model.theme);
                            }
                            final level = chapter * chapterSize + position + 1;
                            final id = PuzzleId.level(level);
                            final result = model.result(id);
                            final playable = model.canPlayLevel(level);
                            final current = level == model.highestUnlocked;
                            return CustomPaint(
                              painter: _JourneyLine(
                                index,
                                palette,
                                biome,
                                lit: playable,
                                current: current,
                                completed: result != null,
                                highContrast: highContrast,
                              ),
                              child: Align(
                                alignment: Alignment(_nodeX(index), 0),
                                child: _MedallionNode(
                                  key: ValueKey('journey-level-$level'),
                                  level: level,
                                  palette: palette,
                                  playable: playable,
                                  current: current,
                                  solveTime: result == null
                                      ? null
                                      : formatTime(
                                          Duration(
                                            milliseconds: result.milliseconds,
                                          ),
                                        ),
                                  onTap: playable
                                      ? () => openPuzzle(
                                          context,
                                          id,
                                          replay:
                                              result != null &&
                                              !model.hasAttempt(id),
                                        )
                                      : null,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedallionNode extends StatelessWidget {
  const _MedallionNode({
    required this.level,
    required this.palette,
    required this.playable,
    required this.current,
    required this.solveTime,
    required this.onTap,
    super.key,
  });

  final int level;
  final BoardPalette palette;
  final bool playable;
  final bool current;
  final String? solveTime;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final completed = solveTime != null;
    final diameter = current ? 68.0 : 58.0;
    final border = current
        ? palette.accent
        : completed
        ? palette.route
        : playable
        ? palette.cardEdge
        : palette.cardEdge.withValues(alpha: .55);
    final fg = current
        ? palette.onRoute
        : playable
        ? palette.ink
        : palette.mutedInk;

    final gradientColors = current
        ? [palette.buttonTop, palette.buttonBottom]
        : completed
        ? [
            Color.lerp(
              palette.cardTop,
              palette.route,
              palette.dark ? .14 : .08,
            )!,
            palette.surface,
          ]
        : playable
        ? [palette.cardTop, palette.cardBottom]
        : [palette.quiet, Color.lerp(palette.quiet, palette.canvas, .35)!];

    return Semantics(
      button: playable,
      label: 'Level $level',
      excludeSemantics: true,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: gradientColors,
                  ),
                  border: Border.all(
                    color: border,
                    width: current
                        ? 3
                        : completed
                        ? 2.4
                        : 1.8,
                  ),
                  boxShadow: current
                      ? [
                          BoxShadow(
                            color: palette.route.withValues(alpha: .44),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .22),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : playable
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: palette.dark ? .28 : .13,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: current
                            ? Colors.white.withValues(alpha: .28)
                            : completed
                            ? palette.route.withValues(alpha: .25)
                            : playable
                            ? palette.ink.withValues(alpha: .06)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!playable)
                            Icon(Icons.lock_outline, size: 15, color: fg)
                          else if (current)
                            Icon(Icons.play_arrow_rounded, size: 18, color: fg),
                          Text(
                            '$level',
                            maxLines: 1,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w800,
                              fontSize: level >= 10000 ? 11 : 14,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (solveTime != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(GameTokens.pillRadius),
                border: Border.all(color: palette.cardEdge),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: palette.dark ? .24 : .08,
                    ),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                solveTime!,
                style: TextStyle(
                  color: palette.mutedInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

double _nodeX(int index) => math.sin(index * .91) * .63;

class _JourneyLine extends CustomPainter {
  const _JourneyLine(
    this.index,
    this.palette,
    this.biome, {
    required this.lit,
    required this.current,
    required this.completed,
    required this.highContrast,
  });

  final int index;
  final BoardPalette palette;
  final BiomeKind biome;
  final bool lit;
  final bool current;
  final bool completed;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int level) => size.width * (.5 + _nodeX(level) * .32);
    final mid = size.height / 2;
    final here = x(index);
    final from = (here + x(index + 1)) / 2;
    final to = (here + x(index - 1)) / 2;

    if (!highContrast) {
      _paintBiomeAccents(canvas, size, here, mid);
      _paintNodeGrounding(canvas, Offset(here, mid));
    }

    final trail = Path()
      ..moveTo(from, 0)
      ..cubicTo(from, mid * .7, here, mid * .64, here, mid);
    if (index > 0) {
      trail.cubicTo(here, mid * 1.36, to, mid * 1.3, to, size.height);
    }

    // Layered glowing path: wide soft outer glow, mid halo, crisp core, inner gleam.
    canvas.drawPath(
      trail,
      Paint()
        ..color = palette.route.withValues(alpha: lit ? .16 : .07)
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      trail,
      Paint()
        ..color = palette.route.withValues(alpha: lit ? .34 : .14)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      trail,
      Paint()
        ..color = palette.route.withValues(alpha: lit ? .80 : .30)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    if (lit) {
      canvas.drawPath(
        trail,
        Paint()
          ..color = palette.onRoute.withValues(alpha: palette.dark ? .22 : .30)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintNodeGrounding(Canvas canvas, Offset center) {
    final radius = current ? 54.0 : 42.0;
    final glowColor = current
        ? palette.accent.withValues(alpha: palette.dark ? .20 : .26)
        : completed
        ? palette.route.withValues(alpha: palette.dark ? .14 : .11)
        : palette.ink.withValues(alpha: palette.dark ? .10 : .05);
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [glowColor, Colors.transparent])
            .createShader(rect),
    );
  }

  void _paintBiomeAccents(Canvas canvas, Size size, double here, double mid) {
    final position = index % (chapterSize + 1);
    final onRight = here < size.width / 2;
    final sideX = onRight ? size.width * .78 : size.width * .22;
    final secondaryX = onRight ? size.width * .16 : size.width * .84;
    final jitter = math.sin(index * 1.73) * 10;
    final y = mid + math.cos(index * 1.37) * 16;

    final primary = palette.route.withValues(alpha: palette.dark ? .14 : .11);
    final soft = palette.covered.withValues(alpha: palette.dark ? .22 : .32);
    final accent = palette.accent.withValues(alpha: palette.dark ? .24 : .22);

    if (position % 2 == 0) {
      switch (biome) {
        case BiomeKind.forest:
          // Layered fern / foliage cluster + mossy stepping stone.
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(sideX + jitter, y + 8),
              width: 44,
              height: 18,
            ),
            Paint()..color = soft,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(sideX + jitter - 10, y - 4),
              width: 24,
              height: 12,
            ),
            Paint()..color = primary,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(sideX + jitter + 11, y - 2),
              width: 20,
              height: 10,
            ),
            Paint()..color = primary,
          );
          if (position % 4 == 0) {
            canvas.drawCircle(
              Offset(sideX + jitter + 4, y - 10),
              2.6,
              Paint()..color = accent,
            );
          }
        case BiomeKind.ocean:
          // Gentle wave ripples & tide pebbles.
          final wavePaint = Paint()
            ..color = primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round;
          final wx = sideX + jitter;
          final wave = Path()
            ..moveTo(wx - 20, y)
            ..quadraticBezierTo(wx - 10, y - 6, wx, y)
            ..quadraticBezierTo(wx + 10, y + 6, wx + 20, y);
          canvas.drawPath(wave, wavePaint);
          canvas.drawCircle(
            Offset(wx - 14, y + 12),
            3.2,
            Paint()..color = soft,
          );
          canvas.drawCircle(
            Offset(wx + 12, y - 11),
            2.2,
            Paint()..color = accent,
          );
        case BiomeKind.winter:
          // Soft snowdrift & crystalline 6-point snowflake.
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(sideX + jitter, y + 10),
              width: 48,
              height: 14,
            ),
            Paint()..color = soft,
          );
          final sx = sideX + jitter + (onRight ? -8 : 8);
          final sy = y - 10;
          final flakePaint = Paint()
            ..color = primary
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round;
          for (var a = 0; a < 3; a++) {
            final angle = a * math.pi / 3;
            final dx = math.cos(angle) * 7;
            final dy = math.sin(angle) * 7;
            canvas.drawLine(
              Offset(sx - dx, sy - dy),
              Offset(sx + dx, sy + dy),
              flakePaint,
            );
          }
        case BiomeKind.desert:
          // Layered dune contour & sun-warmed stone.
          final dx = sideX + jitter;
          final dune = Path()
            ..moveTo(dx - 24, y + 10)
            ..quadraticBezierTo(dx, y - 8, dx + 24, y + 10)
            ..close();
          canvas.drawPath(dune, Paint()..color = soft);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(dx + 10, y + 12),
              width: 14,
              height: 7,
            ),
            Paint()..color = primary,
          );
          if (position % 4 == 0) {
            canvas.drawCircle(
              Offset(dx - 12, y - 8),
              2.5,
              Paint()..color = accent,
            );
          }
      }
    }

    // Subtle starlight / ambient motes on dark themes or every 3rd slot.
    if (palette.dark || position % 3 == 1) {
      final starCenter = Offset(secondaryX - jitter * .5, mid - 20);
      canvas.drawCircle(
        starCenter,
        palette.dark ? 2.0 : 1.6,
        Paint()
          ..color = palette.particleColor.withValues(
            alpha: palette.dark ? .32 : .18,
          ),
      );
      if (palette.dark && position % 2 == 1) {
        canvas.drawCircle(
          Offset(sideX - jitter * .4, mid + 24),
          1.4,
          Paint()..color = palette.accent.withValues(alpha: .28),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_JourneyLine oldDelegate) =>
      oldDelegate.index != index ||
      oldDelegate.palette != palette ||
      oldDelegate.biome != biome ||
      oldDelegate.lit != lit ||
      oldDelegate.current != current ||
      oldDelegate.completed != completed ||
      oldDelegate.highContrast != highContrast;
}

class _ChestStop extends StatelessWidget {
  const _ChestStop(this.chapter, this.palette, this.theme);
  final int chapter;
  final BoardPalette palette;
  final PathwiseTheme theme;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final claimed = model.chapterClaimed(chapter);
    final ready = model.chapterReady(chapter);
    final remaining = chapterSize - model.chapterClears(chapter);
    final biomePath = biomeAssetPath(biomeForTheme(theme));
    final scrimLeft = palette.surface.withValues(
      alpha: palette.dark ? .92 : .94,
    );
    final scrimRight = palette.surface.withValues(
      alpha: palette.dark ? .48 : .54,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GameTokens.cardRadius),
          boxShadow: [
            BoxShadow(
              color: ready
                  ? palette.route.withValues(alpha: .28)
                  : Colors.black.withValues(alpha: palette.dark ? .28 : .10),
              blurRadius: ready ? 16 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: palette.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GameTokens.cardRadius),
            side: BorderSide(
              color: ready ? palette.route : palette.cardEdge,
              width: ready ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: ready ? () => _showChapterReward(context, chapter) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  biomePath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [palette.cardTop, palette.cardBottom],
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [scrimLeft, scrimRight],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              (ready ? palette.accent : palette.route)
                                  .withValues(alpha: ready ? .36 : .14),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Center(
                          child: GameArt(
                            claimed ? ArtKind.treasureOpen : ArtKind.treasure,
                            palette: palette,
                            size: 52,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chapterName(chapter),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              claimed
                                  ? 'Treasure claimed'
                                  : ready
                                  ? 'Treasure ready'
                                  : remaining == 0
                                  ? 'Chapter complete'
                                  : '$remaining puzzles to treasure',
                              style: TextStyle(
                                color: ready ? palette.route : palette.mutedInk,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (ready)
                        ActionPill(
                          label: 'Open',
                          tone: ActionTone.primary,
                          onTap: () => _showChapterReward(context, chapter),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showChapterTreasures(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final model = context.watch<AppModel>();
        final palette = BoardPalette.palettes[model.theme]!;
        final pending = model.pendingChapterChests;
        return SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: pending.length + 1,
            itemBuilder: (context, index) => index == 0
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Chapter treasures',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GameCard(
                      onTap: () =>
                          _showChapterReward(context, pending[index - 1]),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          GameArt(ArtKind.treasure, palette: palette, size: 38),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              chapterName(pending[index - 1]),
                              style: TextStyle(
                                color: palette.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          ActionPill(
                            label: 'Open',
                            tone: ActionTone.primary,
                            onTap: () =>
                                _showChapterReward(context, pending[index - 1]),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );

Future<void> _showChapterReward(BuildContext context, int chapter) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ChapterRewardDialog(chapter: chapter),
    );

class _ChapterRewardDialog extends StatefulWidget {
  const _ChapterRewardDialog({required this.chapter});
  final int chapter;

  @override
  State<_ChapterRewardDialog> createState() => _ChapterRewardDialogState();
}

class _ChapterRewardDialogState extends State<_ChapterRewardDialog> {
  bool _opened = false;
  bool _claiming = false;

  Future<void> _claim() async {
    if (_claiming) return;
    final model = context.read<AppModel>();
    setState(() {
      _claiming = true;
      _opened = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final claimed = await model.claimChapter(widget.chapter);
    if (mounted && claimed) {
      Navigator.pop(context);
    } else if (mounted) {
      setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final ready = model.chapterReady(widget.chapter) && !model.storageError;

    return AlertDialog(
      icon: Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                palette.route.withValues(alpha: .26),
                Colors.transparent,
              ],
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: GameArt(
              _opened ? ArtKind.treasureOpen : ArtKind.treasure,
              key: ValueKey(_opened),
              palette: palette,
              size: 74,
            ),
          ),
        ),
      ),
      title: Text(
        chapterName(widget.chapter),
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RewardChip(
                palette: palette,
                art: ArtKind.coin,
                label: '$chapterRewardCoins coins',
              ),
              const SizedBox(width: 8),
              _RewardChip(
                palette: palette,
                art: ArtKind.hint,
                label: '$chapterRewardHints hint',
              ),
            ],
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(180, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: ready && !_claiming ? _claim : null,
          child: const Text(
            'Claim treasure',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({
    required this.palette,
    required this.art,
    required this.label,
  });

  final BoardPalette palette;
  final ArtKind art;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: palette.quiet,
      borderRadius: BorderRadius.circular(GameTokens.pillRadius),
      border: Border.all(color: palette.cardEdge),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GameArt(art, palette: palette, size: 18),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: palette.ink,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

class _JumpDialog extends StatefulWidget {
  const _JumpDialog();
  @override
  State<_JumpDialog> createState() => _JumpDialogState();
}

class _JumpDialogState extends State<_JumpDialog> {
  int? _level;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Jump to level'),
    content: TextField(
      autofocus: true,
      keyboardType: TextInputType.number,
      onChanged: (value) => setState(() => _level = int.tryParse(value)),
      decoration: const InputDecoration(labelText: 'Level number'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: (_level ?? 0) > 0
            ? () => Navigator.pop(context, _level)
            : null,
        child: const Text('Go'),
      ),
    ],
  );
}
