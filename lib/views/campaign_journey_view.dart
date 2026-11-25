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
  double get _extent =>
      MediaQuery.textScalerOf(context).scale(1) > 1.35 ? 176 : 138;

  static int _slotForLevel(int level) => level - 1 + chapterFor(level);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll ??= ScrollController(
      initialScrollOffset:
          _slotForLevel(context.read<AppModel>().highestUnlocked) * _extent,
    );
  }

  void _jump(int slot) => _scroll!.jumpTo(slot * _extent);

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey'),
        actions: [
          IconButton(
            tooltip: 'Current level',
            icon: const Icon(Icons.my_location),
            onPressed: () => _jump(_slotForLevel(model.highestUnlocked)),
          ),
          IconButton(
            tooltip: 'Jump to level',
            icon: const Icon(Icons.explore_outlined),
            onPressed: () async {
              final level = await showDialog<int>(
                context: context,
                builder: (_) => const _JumpDialog(),
              );
              if (mounted && level != null) _jump(_slotForLevel(level));
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
                    child: ListView.builder(
                      key: const PageStorageKey('campaign-journey'),
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
                          painter: _JourneyLine(index, palette, lit: playable),
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
    final diameter = current ? 66.0 : 58.0;
    final fill = current
        ? palette.route
        : completed
        ? palette.surface
        : playable
        ? palette.cardTop
        : palette.quiet;
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
                  color: current ? null : fill,
                  gradient: current
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [palette.buttonTop, palette.buttonBottom],
                        )
                      : null,
                  border: Border.all(color: border, width: current ? 3 : 2),
                  boxShadow: current
                      ? [
                          BoxShadow(
                            color: palette.route.withValues(alpha: .42),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ]
                      : completed
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
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
          if (solveTime != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(GameTokens.pillRadius),
                border: Border.all(color: palette.cardEdge),
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
  const _JourneyLine(this.index, this.palette, {required this.lit});
  final int index;
  final BoardPalette palette;
  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int level) => size.width * (.5 + _nodeX(level) * .32);
    final mid = size.height / 2;
    final here = x(index);
    final from = (here + x(index + 1)) / 2;
    final to = (here + x(index - 1)) / 2;
    final chapter = index ~/ (chapterSize + 1);
    final position = index % (chapterSize + 1);
    if (position % 4 == 1 &&
        palette != BoardPalette.palettes[PathwiseTheme.signal] &&
        palette != BoardPalette.palettes[PathwiseTheme.amoledCarbon]) {
      final across = here < size.width / 2
          ? size.width * .77
          : size.width * .23;
      final tint = palette.route.withValues(alpha: .10);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(across, mid),
          width: size.width * .22,
          height: 18 + chapter % 5 * 4,
        ),
        Paint()..color = tint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(across + size.width * .04, mid - 16),
          width: size.width * .13,
          height: 10,
        ),
        Paint()..color = tint,
      );
    }
    final trail = Path()
      ..moveTo(from, 0)
      ..cubicTo(from, mid * .7, here, mid * .64, here, mid);
    if (index > 0) {
      trail.cubicTo(here, mid * 1.36, to, mid * 1.3, to, size.height);
    }
    // Layered glowing path: wide soft outer glow, mid halo, crisp core.
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
        ..color = palette.route.withValues(alpha: lit ? .78 : .30)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_JourneyLine oldDelegate) =>
      oldDelegate.index != index ||
      oldDelegate.palette != palette ||
      oldDelegate.lit != lit;
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
      alpha: palette.dark ? .90 : .92,
    );
    final scrimRight = palette.surface.withValues(
      alpha: palette.dark ? .46 : .52,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    GameArt(
                      claimed ? ArtKind.treasureOpen : ArtKind.treasure,
                      palette: palette,
                      size: 54,
                    ),
                    const SizedBox(width: 14),
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
