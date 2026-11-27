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
import '../viewmodels/journey_viewmodel.dart';
import 'main_menu_view.dart';

part 'journey_landscape.dart';

/// A reverse, lazy route. Even distant level jumps require one offset
/// calculation and build only the rows around the destination.
class CampaignJourneyView extends StatefulWidget {
  const CampaignJourneyView({super.key});

  @override
  State<CampaignJourneyView> createState() => _CampaignJourneyViewState();
}

class _CampaignJourneyViewState extends State<CampaignJourneyView> {
  static const _slotsPerChapter = chapterSize + 2;

  ScrollController? _scroll;
  int? _lastFocusedLevel;
  double _extent = 72;

  @override
  void initState() {
    super.initState();
    GameAssetCache.instance.preloadBiomes();
  }

  // Keep subpixel precision in the scroll offset, including at large text sizes.
  static int _maxLevelForExtent(double extent) =>
      JourneyViewModel.maxLevelForExtent(
        extent,
        slotsPerChapter: _slotsPerChapter,
      );

  static int _slotForLevel(int level) => level + chapterFor(level) * 2;

  double _focusedOffset(int slot, double viewportHeight) =>
      math.max(0.0, (slot + 0.5) * _extent - viewportHeight * 0.34);

  void _focusLevel(int level) {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    final viewportHeight = scroll.position.viewportDimension;
    final target = _focusedOffset(
      _slotForLevel(math.min(level, _maxLevelForExtent(_extent))),
      viewportHeight,
    );
    if (MediaQuery.disableAnimationsOf(context) ||
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
    GameAssetCache.instance.evictJourneyAssets();
    super.dispose();
  }

  Future<void> _chooseChapter() async {
    final model = context.read<AppModel>();
    final reached = chapterFor(
      math.min(model.highestUnlocked, _maxLevelForExtent(_extent)),
    );
    final chapter = await showModalBottomSheet<int>(
      context: context,
      sheetAnimationStyle: _journeyAnimationStyle(context),
      isScrollControlled: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .7,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Chapters',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheet).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: reached + 2,
                  itemBuilder: (context, index) {
                    final chapter = reached + 1 - index;
                    final start = chapter * chapterSize + 1;
                    final unlocked = model.canPlayLevel(start);
                    return ListTile(
                      key: ValueKey('journey-chapter-choice-$chapter'),
                      enabled: unlocked,
                      leading: Icon(
                        unlocked ? Icons.terrain_rounded : Icons.lock_outline,
                      ),
                      title: Text(
                        chapterName(chapter),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Levels $start–${chapterEnd(chapter)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: unlocked
                          ? () => Navigator.pop(sheet, chapter)
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && chapter != null) _focusLevel(chapter * chapterSize + 1);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final highContrast =
        model.theme == PathwiseTheme.signal ||
        model.theme == PathwiseTheme.amoledCarbon ||
        MediaQuery.highContrastOf(context);
    final highest = model.highestUnlocked;
    final treasureCount = model.pendingChapterChests.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey'),
        actions: [
          IconButton(
            tooltip: 'Current level',
            icon: const Icon(Icons.my_location),
            onPressed: () => _focusLevel(model.highestUnlocked),
          ),
          IconButton(
            tooltip: 'Chapters',
            icon: const Icon(Icons.map_outlined),
            onPressed: _chooseChapter,
          ),
          IconButton(
            tooltip: 'Jump to level',
            icon: const Icon(Icons.explore_outlined),
            onPressed: () async {
              final level = await showDialog<int>(
                context: context,
                animationStyle: _journeyAnimationStyle(context),
                builder: (_) =>
                    _JumpDialog(maximumLevel: _maxLevelForExtent(_extent)),
              );
              if (mounted && level != null) _focusLevel(level);
            },
          ),
        ],
      ),
      body: Material(
        color: palette.canvas,
        child: SafeArea(
          child: Column(
            children: [
              if (treasureCount > 0)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 550),
                  child: ListTile(
                    minTileHeight: 56,
                    leading: GameArt(
                      ArtKind.treasure,
                      palette: palette,
                      size: 34,
                    ),
                    title: Text('Treasures · $treasureCount'),
                    trailing: Text(
                      'Claim',
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    onTap: () => showChapterTreasures(context),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 550),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final oldExtent = _extent;
                        final scaler = MediaQuery.textScalerOf(context);
                        _extent = 72 + math.max(0.0, scaler.scale(16) - 16) * 3;
                        final refocus =
                            _lastFocusedLevel != null &&
                            _lastFocusedLevel != highest;
                        _lastFocusedLevel = highest;
                        final previousOffset = _scroll?.hasClients == true
                            ? _scroll!.offset
                            : null;
                        _scroll ??= ScrollController(
                          initialScrollOffset: _focusedOffset(
                            _slotForLevel(
                              math.min(highest, _maxLevelForExtent(_extent)),
                            ),
                            constraints.maxHeight,
                          ),
                        );
                        if (refocus ||
                            (previousOffset != null && oldExtent != _extent)) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            if (refocus) {
                              _focusLevel(highest);
                            } else if (_scroll!.hasClients) {
                              _scroll!.jumpTo(
                                previousOffset! * _extent / oldExtent,
                              );
                            }
                          });
                        }
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _JourneyWorldPainter(
                                    scroll: _scroll!,
                                    extent: _extent,
                                    palette: palette,
                                    highContrast: highContrast,
                                    highestUnlocked: highest,
                                  ),
                                ),
                              ),
                            ),
                            ListView.builder(
                              padding: EdgeInsets.zero,
                              reverse: true,
                              itemExtent: _extent,
                              controller: _scroll,
                              itemBuilder: (context, index) => _buildStop(
                                context,
                                model,
                                palette,
                                highContrast,
                                index,
                              ),
                            ),
                          ],
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

  Widget _buildStop(
    BuildContext context,
    AppModel model,
    BoardPalette palette,
    bool highContrast,
    int index,
  ) {
    final chapter = index ~/ _slotsPerChapter;
    final position = index % _slotsPerChapter;
    final first = chapter * chapterSize + 1;
    final level = chapter * chapterSize + position;
    final isHeader = position == 0;
    final isTreasure = position == chapterSize + 1;
    final stopX = _routeX(index);
    final unlocked = model.canPlayLevel(
      isHeader
          ? first
          : isTreasure
          ? chapterEnd(chapter)
          : level,
    );

    if (isHeader) {
      return _ChapterHeaderStop(chapter: chapter, palette: palette);
    }
    if (isTreasure) {
      return _ChestStop(chapter, palette);
    }
    final id = PuzzleId.level(level);
    final result = model.result(id);
    return _JourneyNode(
      level: level,
      palette: palette,
      x: stopX,
      playable: unlocked,
      current: level == model.highestUnlocked,
      stars: result == null ? null : model.starsFor(id),
      onTap: unlocked
          ? () => openPuzzle(
              context,
              id,
              replay: result != null && !model.hasAttempt(id),
            )
          : () {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      'Clear Level ${model.highestUnlocked} first to unlock Level $level',
                    ),
                  ),
                );
            },
    );
  }
}

class _JourneyNode extends StatelessWidget {
  const _JourneyNode({
    required this.level,
    required this.palette,
    required this.x,
    required this.playable,
    required this.current,
    required this.stars,
    required this.onTap,
  });

  final int level;
  final BoardPalette palette;
  final double x;
  final bool playable;
  final bool current;
  final int? stars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completed = stars != null;
    final stroke = current
        ? palette.onRoute
        : completed
        ? palette.route
        : palette.cardEdge;
    final fill = current
        ? palette.route
        : completed
        ? Color.lerp(palette.card, palette.route, palette.dark ? .20 : .14)!
        : playable
        ? palette.card
        : palette.quiet;
    final topColor = Color.lerp(fill, Colors.white, palette.dark ? .14 : .26)!;
    final skirtColor = Color.lerp(
      fill,
      Colors.black,
      palette.dark ? .38 : .26,
    )!;
    final ink = current
        ? palette.onRoute
        : playable
        ? palette.ink
        : palette.mutedInk;
    final semanticsLabel = current
        ? 'Level $level, current'
        : !playable
        ? 'Level $level, locked'
        : completed
        ? 'Level $level, completed, $stars of 3 stars'
        : 'Level $level';
    final textScale = MediaQuery.textScalerOf(context).scale(20);
    final width = math.max(
      current ? 78.0 : 70.0,
      math.min(130.0, textScale * (level.toString().length * .56 + 1.45)),
    );
    final height = math.max(current ? 66.0 : 58.0, textScale + 26);
    const goldStar = Color(0xFFE5A91A);
    final emptyStar = palette.mutedInk.withValues(alpha: .42);
    final highContrast =
        palette == BoardPalette.palettes[PathwiseTheme.signal] ||
        palette == BoardPalette.palettes[PathwiseTheme.amoledCarbon];
    final platformAsset = current
        ? 'assets/art/journey/iso_platform_current.png'
        : !playable
        ? 'assets/art/journey/iso_platform_locked.png'
        : 'assets/art/journey/iso_platform_completed.png';
    final numberInk = highContrast
        ? ink
        : current
        ? Colors.white
        : playable
        ? const Color(0xFF1F2A24)
        : const Color(0xFFF2F5F8);

    return LayoutBuilder(
      builder: (context, constraints) {
        final widthAvailable = constraints.maxWidth;
        final center = widthAvailable * x;
        final nodeWidth = math.min(
          width,
          2.0 * math.min(center, widthAvailable - center) - 12,
        );
        final labelOnRight = x <= .5;
        final labelInset = labelOnRight ? center : widthAvailable - center;
        final tagStart = labelInset + nodeWidth / 2 + 8;
        final shape = RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        );

        return Stack(
          children: [
            if (current && widthAvailable - tagStart > 20)
              Positioned(
                left: labelOnRight ? tagStart : null,
                right: labelOnRight ? null : tagStart,
                top: 0,
                bottom: 0,
                width: math.min(110.0, widthAvailable - tagStart - 6),
                child: Align(
                  alignment: labelOnRight
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: fill,
                        shape: StadiumBorder(
                          side: BorderSide(color: stroke, width: 1.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        child: Text(
                          'Current',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: center - nodeWidth / 2,
              top: (constraints.maxHeight - height) / 2 - (current ? 2 : 0),
              width: nodeWidth,
              height: height,
              child: Semantics(
                key: ValueKey('journey-level-$level'),
                button: true,
                label: semanticsLabel,
                hint: !playable ? 'Shows how to unlock this level' : null,
                excludeSemantics: true,
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (highContrast)
                      CustomPaint(
                        painter: _IsoPlatformPainter(
                          topColor: topColor,
                          bottomColor: fill,
                          skirtColor: skirtColor,
                          borderColor: stroke,
                          accentGlow: current ? palette.accent : null,
                          elevated: current,
                        ),
                      )
                    else
                      Image.asset(
                        platformAsset,
                        fit: BoxFit.fill,
                        cacheWidth: 256,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => CustomPaint(
                          painter: _IsoPlatformPainter(
                            topColor: topColor,
                            bottomColor: fill,
                            skirtColor: skirtColor,
                            borderColor: stroke,
                            accentGlow: current ? palette.accent : null,
                            elevated: current,
                          ),
                        ),
                      ),
                    Material(
                      type: MaterialType.transparency,
                      shape: shape,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onTap,
                        customBorder: shape,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (current)
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: numberInk,
                                  size: 14,
                                )
                              else if (!playable)
                                Icon(
                                  Icons.lock_outline_rounded,
                                  color: numberInk,
                                  size: 12,
                                ),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '$level',
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: numberInk,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                      height: 1.05,
                                    ),
                                  ),
                                ),
                              ),
                              if (completed)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var s = 0; s < 3; s++)
                                      Icon(
                                        s < stars!
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        size: 11,
                                        color: s < stars!
                                            ? goldStar
                                            : emptyStar,
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IsoPlatformPainter extends CustomPainter {
  const _IsoPlatformPainter({
    required this.topColor,
    required this.bottomColor,
    required this.skirtColor,
    required this.borderColor,
    required this.elevated,
    this.accentGlow,
  });

  final Color topColor;
  final Color bottomColor;
  final Color skirtColor;
  final Color borderColor;
  final Color? accentGlow;
  final bool elevated;

  @override
  void paint(Canvas canvas, Size size) {
    const skirtDepth = 5.5;
    final faceRect = Rect.fromLTWH(0, 0, size.width, size.height - skirtDepth);
    final faceRRect = RRect.fromRectAndRadius(
      faceRect,
      const Radius.circular(13),
    );
    final skirtRRect = RRect.fromRectAndRadius(
      faceRect.translate(0, skirtDepth),
      const Radius.circular(13),
    );

    // Soft ground shadow.
    canvas.drawRRect(
      skirtRRect.inflate(1.2).shift(const Offset(0, 2)),
      Paint()..color = Colors.black.withValues(alpha: elevated ? .36 : .24),
    );

    if (accentGlow != null) {
      canvas.drawRRect(
        faceRRect.inflate(2.5),
        Paint()
          ..color = accentGlow!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
    }

    // 2.5D extruded underside skirt.
    canvas.drawRRect(skirtRRect, Paint()..color = skirtColor);

    // Top platform face with subtle directional lighting.
    canvas.drawRRect(
      faceRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [topColor, bottomColor],
        ).createShader(faceRect),
    );

    // Crisp rim border.
    canvas.drawRRect(
      faceRRect.deflate(.6),
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = elevated ? 2.0 : 1.3,
    );
  }

  @override
  bool shouldRepaint(_IsoPlatformPainter old) =>
      old.topColor != topColor ||
      old.bottomColor != bottomColor ||
      old.skirtColor != skirtColor ||
      old.borderColor != borderColor ||
      old.accentGlow != accentGlow ||
      old.elevated != elevated;
}

class _ChapterHeaderStop extends StatelessWidget {
  const _ChapterHeaderStop({required this.chapter, required this.palette});

  final int chapter;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.cardEdge, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/art/journey/prop_signpost.webp',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.signpost_rounded, size: 22, color: palette.ink),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chapter ${chapter + 1} · ${chapterName(chapter)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      'Levels ${chapter * chapterSize + 1}–${chapterEnd(chapter)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.mutedInk,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        height: 1.15,
                      ),
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

class _ChestStop extends StatelessWidget {
  const _ChestStop(this.chapter, this.palette);
  final int chapter;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final model = context.read<AppModel>();
    final claimed = model.chapterClaimed(chapter);
    final ready = model.chapterReady(chapter);
    final clears = model.chapterClears(chapter);
    final status = claimed
        ? 'Treasure claimed'
        : ready
        ? 'Treasure ready'
        : '$clears / $chapterSize puzzles';

    void onTap() {
      if (ready) {
        _showChapterReward(context, chapter);
      } else {
        showDialog<void>(
          context: context,
          animationStyle: _journeyAnimationStyle(context),
          builder: (dialogContext) => GameDialog(
            title: '${chapterName(chapter)} chest',
            art: GameArt(
              claimed ? ArtKind.treasureOpen : ArtKind.treasure,
              palette: palette,
              size: 56,
            ),
            body: claimed
                ? 'You already claimed $chapterRewardCoins coins and $chapterRewardHints hint from this chapter.'
                : 'Complete all $chapterSize puzzles in Chapter ${chapter + 1} ($clears / $chapterSize) to unlock $chapterRewardCoins coins and $chapterRewardHints hint.',
            actions: [
              ActionPill(
                label: 'OK',
                tone: ActionTone.primary,
                onTap: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      }
    }

    return Center(
      child: Semantics(
        button: true,
        label: '${chapterName(chapter)}, $status',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .32),
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: palette.surface.withValues(alpha: .96),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: ready ? palette.route : palette.cardEdge,
                width: ready ? 2.2 : 1.4,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 5, 14, 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 46,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            bottom: 0,
                            child: Image.asset(
                              'assets/art/journey/iso_pedestal.png',
                              width: 46,
                              height: 36,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            child: GameArt(
                              claimed ? ArtKind.treasureOpen : ArtKind.treasure,
                              palette: palette,
                              size: 30,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ready ? palette.route : palette.ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              height: 1.15,
                            ),
                          ),
                          Text(
                            '$chapterRewardCoins coins · $chapterRewardHints hint',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.mutedInk,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ready) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.route,
                        size: 20,
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

AnimationStyle? _journeyAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null;

Future<void> showChapterTreasures(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: _journeyAnimationStyle(context),
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
      animationStyle: _journeyAnimationStyle(context),
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
  bool _claimed = false;

  Future<void> _claim() async {
    if (_claiming || _claimed) return;
    final model = context.read<AppModel>();
    setState(() {
      _claiming = true;
      _opened = true;
    });
    if (!MediaQuery.disableAnimationsOf(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
    final claimed = await model.claimChapter(widget.chapter);
    if (!mounted) return;
    setState(() {
      _claiming = false;
      _claimed = claimed;
      if (!claimed) _opened = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final ready = model.chapterReady(widget.chapter) && !model.storageError;

    return GameDialog(
      art: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              (_claimed ? palette.accent : palette.route).withValues(
                alpha: _claimed ? .34 : .26,
              ),
              Colors.transparent,
            ],
          ),
        ),
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: GameArt(
            _opened ? ArtKind.treasureOpen : ArtKind.treasure,
            key: ValueKey(_opened),
            palette: palette,
            size: 74,
          ),
        ),
      ),
      title: chapterName(widget.chapter),
      body: _claimed
          ? 'Chapter ${widget.chapter + 1} treasure claimed!'
          : 'Chapter ${widget.chapter + 1} treasure',
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _RewardChip(
            palette: palette,
            art: ArtKind.coin,
            label: '$chapterRewardCoins coins',
          ),
          _RewardChip(
            palette: palette,
            art: ArtKind.hint,
            label: '$chapterRewardHints hint',
          ),
        ],
      ),
      actions: [
        if (_claimed)
          ActionPill(
            label: 'Done',
            tone: ActionTone.primary,
            onTap: () => Navigator.pop(context),
          )
        else
          ActionPill(
            label: _claiming ? 'Opening...' : 'Claim treasure',
            tone: ActionTone.primary,
            onTap: ready && !_claiming ? _claim : null,
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
  const _JumpDialog({required this.maximumLevel});

  final int maximumLevel;

  @override
  State<_JumpDialog> createState() => _JumpDialogState();
}

class _JumpDialogState extends State<_JumpDialog> {
  String _input = '';

  int? get _level => int.tryParse(_input.trim(), radix: 10);

  bool get _valid => (_level ?? 0) > 0 && _level! <= widget.maximumLevel;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Jump to level'),
    content: TextField(
      autofocus: true,
      keyboardType: TextInputType.number,
      onChanged: (value) => setState(() => _input = value),
      onSubmitted: (_) {
        if (_valid) Navigator.pop(context, _level);
      },
      decoration: InputDecoration(
        labelText: 'Level number',
        errorText: _input.isNotEmpty && !_valid
            ? 'Enter a level from 1 to ${widget.maximumLevel}'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _valid ? () => Navigator.pop(context, _level) : null,
        child: const Text('Go'),
      ),
    ],
  );
}
