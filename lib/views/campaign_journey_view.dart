import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import '../model/journey.dart';
import '../model/user_preferences.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import '../ui/journey_art.dart';
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
      body: SafeArea(
        child: Column(
          children: [
            if (model.pendingChapterChests.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.card_giftcard_outlined),
                label: Text('Treasures · ${model.pendingChapterChests.length}'),
                onPressed: () => showChapterTreasures(context),
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
                        return _ChestStop(chapter, palette);
                      }
                      final level = chapter * chapterSize + position + 1;
                      final id = PuzzleId.level(level);
                      final result = model.result(id);
                      final playable = model.canPlayLevel(level);
                      final current = level == model.highestUnlocked;
                      return CustomPaint(
                        painter: _JourneyLine(index, palette),
                        child: Align(
                          alignment: Alignment(_nodeX(index), 0),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Semantics(
                              button: playable,
                              label: 'Level $level',
                              child: OutlinedButton.icon(
                                key: ValueKey('journey-level-$level'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: current
                                      ? palette.route
                                      : palette.surface,
                                  disabledForegroundColor: palette.mutedInk,
                                  disabledBackgroundColor: palette.surface,
                                  foregroundColor: current
                                      ? palette.onRoute
                                      : palette.ink,
                                  minimumSize: const Size(84, 50),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                ),
                                onPressed: playable
                                    ? () => openPuzzle(
                                        context,
                                        id,
                                        replay:
                                            result != null &&
                                            !model.hasAttempt(id),
                                      )
                                    : null,
                                icon: Icon(
                                  result != null
                                      ? Icons.replay_rounded
                                      : playable
                                      ? Icons.play_arrow_rounded
                                      : Icons.lock_outline,
                                  size: 19,
                                ),
                                label: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('$level'),
                                    if (result != null)
                                      Text(
                                        formatTime(
                                          Duration(
                                            milliseconds: result.milliseconds,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
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
    );
  }
}

double _nodeX(int index) => math.sin(index * .91) * .63;

class _JourneyLine extends CustomPainter {
  const _JourneyLine(this.index, this.palette);
  final int index;
  final BoardPalette palette;

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
      final tint = palette.route.withValues(alpha: .11);
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
    canvas.drawPath(
      trail,
      Paint()
        ..color = palette.route.withValues(alpha: .38)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_JourneyLine oldDelegate) =>
      oldDelegate.index != index || oldDelegate.palette != palette;
}

class _ChestStop extends StatelessWidget {
  const _ChestStop(this.chapter, this.palette);
  final int chapter;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final claimed = model.chapterClaimed(chapter);
    final ready = model.chapterReady(chapter);
    final remaining = chapterSize - model.chapterClears(chapter);
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: .55,
            child: JourneyArt(palette, chapter: chapter),
          ),
        ),
        ListTile(
          title: Text(
            chapterName(chapter),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            claimed
                ? 'Treasure claimed'
                : ready
                ? 'Treasure ready'
                : remaining == 0
                ? 'Chapter complete'
                : '$remaining puzzles to treasure',
          ),
          leading: GameArt(
            claimed ? ArtKind.treasureOpen : ArtKind.treasure,
            palette: palette,
            size: 42,
          ),
          trailing: ready ? const Icon(Icons.chevron_right) : null,
          onTap: ready ? () => _showChapterReward(context, chapter) : null,
        ),
      ],
    );
  }
}

Future<void> showChapterTreasures(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final model = context.watch<AppModel>();
        final pending = model.pendingChapterChests;
        return SafeArea(
          child: ListView.builder(
            itemCount: pending.length + 1,
            itemBuilder: (context, index) => index == 0
                ? const ListTile(title: Text('Chapter treasures'))
                : ListTile(
                    title: Text(chapterName(pending[index - 1])),
                    trailing: const Icon(Icons.card_giftcard_outlined),
                    onTap: () =>
                        _showChapterReward(context, pending[index - 1]),
                  ),
          ),
        );
      },
    );

Future<void> _showChapterReward(BuildContext context, int chapter) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final model = context.watch<AppModel>();
        return AlertDialog(
          icon: GameArt(
            ArtKind.treasureOpen,
            palette: BoardPalette.palettes[model.theme]!,
            size: 62,
          ),
          title: Text(chapterName(chapter)),
          content: const Text(
            '$chapterRewardCoins coins · $chapterRewardHints hint',
          ),
          actions: [
            FilledButton(
              onPressed: !model.chapterReady(chapter) || model.storageError
                  ? null
                  : () async {
                      if (await model.claimChapter(chapter) && context.mounted)
                        Navigator.pop(context);
                    },
              child: const Text('Claim treasure'),
            ),
          ],
        );
      },
    );

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
