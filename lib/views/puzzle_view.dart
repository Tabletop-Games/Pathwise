import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import 'components/brand_mark.dart';
import 'components/puzzle_board.dart';

String formatTime(Duration value) {
  final minutes = value.inMinutes;
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class PuzzleView extends StatelessWidget {
  const PuzzleView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final id = model.activeId;
    if (id == null) return const SizedBox.shrink();
    final palette = BoardPalette.palettes[model.theme]!;
    final puzzle = model.puzzle;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          id.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 18),
            child: ValueListenableBuilder<Duration>(
              valueListenable: model.elapsed,
              builder: (context, value, child) => Semantics(
                label: 'Elapsed time',
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      formatTime(value),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch ((model.loading, model.loadError, puzzle)) {
          (true, _, _) => const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Preparing puzzle',
            ),
          ),
          (_, final String message, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => model.open(id),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
          (_, _, null) => const SizedBox.shrink(),
          (_, _, final board?) => LayoutBuilder(
            builder: (context, constraints) {
              final side = math.min(
                math.min(constraints.maxWidth - 32, 490.0),
                math.max(200.0, constraints.maxHeight - 270),
              );
              return Center(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 490),
                    child: Column(
                      children: [
                        if (id.mode == PlayMode.daily)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '${id.value}',
                              style: TextStyle(color: palette.muted),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.complete
                                    ? 'Full route'
                                    : 'Checkpoint ${model.nextCheckpoint} of ${board.checkpoints.length}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${model.path.length} / ${board.area} tiles',
                              style: TextStyle(color: palette.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: model.path.length / board.area,
                            minHeight: 5,
                            color: palette.route,
                            backgroundColor: palette.tile,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 3,
                          children: [
                            OutlinedButton.icon(
                              onPressed: model.canUndo ? model.undo : null,
                              icon: const Icon(Icons.undo_rounded),
                              label: const Text('Undo'),
                            ),
                            OutlinedButton.icon(
                              onPressed: model.canClear ? model.clear : null,
                              icon: const Icon(Icons.restart_alt_rounded),
                              label: const Text('Clear'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: model.canHint ? model.hint : null,
                              icon: const Icon(Icons.lightbulb_outline_rounded),
                              label: const Text('Hint'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: side,
                          height: side,
                          child: PuzzleBoard(
                            key: ObjectKey(board),
                            model: model,
                            puzzle: board,
                            palette: palette,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 360),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween(
                                    begin: .96,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: model.complete
                              ? _Completion(
                                  model: model,
                                  id: id,
                                  palette: palette,
                                )
                              : Padding(
                                  key: const ValueKey('instruction'),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    model.hintCell != null
                                        ? 'Trace to the highlighted tile.'
                                        : model.path.length == 1
                                        ? 'Start at 1. Visit the numbers in order and fill every tile.'
                                        : 'Drag from the tip to extend. Tap the trail to backtrack.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: palette.muted),
                                  ),
                                ),
                        ),
                        if (model.storageError)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('Progress couldn’t be saved.'),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        },
      ),
    );
  }
}

class _Completion extends StatelessWidget {
  const _Completion({
    required this.model,
    required this.id,
    required this.palette,
  });

  final AppModel model;
  final PuzzleId id;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final next = switch (id.mode) {
      PlayMode.levels when model.canPlayLevel(id.level + 1) => PuzzleId.level(
        id.level + 1,
      ),
      PlayMode.endless => model.endless,
      _ => null,
    };
    final best =
        model.result(id)?.milliseconds ?? model.elapsed.value.inMilliseconds;
    final hints = model.hintsUsed;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Row(
              children: [
                BrandMark(background: palette.accent, ink: palette.onAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route complete',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${formatTime(model.elapsed.value)} · $hints ${hints == 1 ? 'hint' : 'hints'}',
                        style: TextStyle(color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 13,
              runSpacing: 6,
              children: [
                Text(
                  '${model.newBest ? 'New best' : 'Personal best'} ${formatTime(Duration(milliseconds: best))}',
                ),
                Text(
                  model.lastReward > 0
                      ? '+${model.lastReward} coins'
                      : '0 coins earned',
                ),
                Text('Balance ${model.coinBalance}'),
                if (id.mode == PlayMode.levels)
                  Text('Level ${model.highestUnlocked} unlocked'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (next != null)
                  FilledButton(
                    onPressed: () => model.open(next),
                    child: Text(
                      id.mode == PlayMode.levels ? 'Next level' : 'Next puzzle',
                    ),
                  ),
                if (id.mode != PlayMode.endless)
                  OutlinedButton(
                    onPressed: () => model.open(id, replay: true),
                    child: const Text('Replay'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    id.mode == PlayMode.levels ? 'Return to Levels' : 'Back',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
