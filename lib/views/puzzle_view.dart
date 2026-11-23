import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import 'components/ad_banner.dart';
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
    final timed = id.mode == PlayMode.attack;
    if (timed && model.attack?.finished == true)
      return _AttackResults(model: model);
    return Scaffold(
      bottomNavigationBar: const AdBanner(),
      appBar: AppBar(
        title: Text(
          id.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 18),
            child: ValueListenableBuilder<Duration>(
              valueListenable: timed ? model.attackRemaining : model.elapsed,
              builder: (context, value, child) => Semantics(
                label: timed ? 'Time remaining' : 'Elapsed time',
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      formatTime(
                        timed
                            ? value + const Duration(milliseconds: 999)
                            : value,
                      ),
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
                        if (timed)
                          Text(
                            '${model.attack!.clears.length} solved · ${model.attack!.score} points',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
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
                            _HintAction(model: model),
                          ],
                        ),
                        _CrateTray(model: model),
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
                          child: model.complete && !timed
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
                                        ? model.correctedByHint
                                              ? 'Route corrected. Follow the highlighted tile.'
                                              : 'Trace to the highlighted tile.'
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

class _HintAction extends StatelessWidget {
  const _HintAction({required this.model});
  final AppModel model;

  Future<void> _reward(BuildContext context, {required bool refill}) async {
    final ads = context.read<AdService>();
    final id = model.activeId;
    final placement = refill ? RewardPlacement.refill : RewardPlacement.hint;
    bool current() =>
        context.mounted &&
        model.activeId == id &&
        ModalRoute.isCurrentOf(context) == true;
    if (ads.enabled && !ads.readyFor(placement))
      await ads.prepare(canPresent: current);
    if (!current()) return;
    final shown = await ads.watchVideo(
      refill
          ? model.grantTankRefill
          : (event) => model.grantRewardedHint(id!.key, event),
      placement: placement,
      canPresent: () =>
          current() &&
          (refill ? model.canRefillTank : model.canRequestExtraHint),
    );
    if (!shown && current())
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rewarded video unavailable. No reward was added.'),
        ),
      );
  }

  Future<void> _extraHint(BuildContext context) async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Extra hint'),
        content: const Text(
          'You’ve used your three standard hints for this puzzle. Watch one video to reveal another hint.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Watch ad · 1 hint'),
          ),
        ],
      ),
    );
    if (consent == true && context.mounted) {
      await _reward(context, refill: false);
    }
  }

  Future<void> _refill(BuildContext context) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Refill hint tank'),
        content: const Text(
          'Restore the shared tank to 3/3. Refilling keeps this puzzle’s hint count.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'ad'),
            child: const Text('Watch ad'),
          ),
          FilledButton(
            onPressed: model.coinBalance >= model.refillPrice
                ? () => Navigator.pop(dialog, 'coins')
                : null,
            child: Text('Spend ${model.refillPrice} coins'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'ad') await _reward(context, refill: true);
    if (action == 'coins') model.buyTankRefill();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.tonalIcon(
        onPressed: model.canHint
            ? model.hint
            : model.canRequestExtraHint
            ? () => _extraHint(context)
            : model.freeHints > 0 &&
                  model.hintTank == 0 &&
                  model.canRefillTank &&
                  !model.complete
            ? () => _refill(context)
            : null,
        icon: const Icon(Icons.lightbulb_outline_rounded),
        label: Text(
          model.freeHints > 0
              ? model.hintTank > 0
                    ? 'Hint · ${model.freeHints} left'
                    : 'Refill hints'
              : model.extraHints > 0
              ? 'Use extra hint'
              : 'Watch ad · 1 hint',
        ),
      ),
      TextButton(
        onPressed: model.canRefillTank && !model.complete
            ? () => _refill(context)
            : null,
        child: Semantics(
          label: 'Hint tank ${model.hintTank} of 3',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var slot = 0; slot < 3; slot++)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(
                    slot < model.hintTank
                        ? Icons.circle
                        : Icons.circle_outlined,
                    size: 9,
                  ),
                ),
              const SizedBox(width: 4),
              Text('${model.hintTank}/3'),
            ],
          ),
        ),
      ),
    ],
  );
}

class _AttackResults extends StatelessWidget {
  const _AttackResults({required this.model});
  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final run = model.attack!;
    return Scaffold(
      appBar: AppBar(title: const Text('Time Attack')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(
                  Icons.timer_off_outlined,
                  size: 58,
                  color: Theme.of(context).colorScheme.primary,
                ),
                Text(
                  'Time’s up',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                if (run.record)
                  const Center(child: Chip(label: Text('New personal best'))),
                ListTile(
                  title: const Text('Puzzles completed'),
                  trailing: Text('${run.clears.length}'),
                ),
                ListTile(
                  title: const Text('Score'),
                  trailing: Text('${run.score}'),
                ),
                ListTile(
                  title: const Text('Average puzzle'),
                  trailing: Text(
                    formatTime(Duration(milliseconds: run.average)),
                  ),
                ),
                ListTile(
                  title: const Text('Fastest puzzle'),
                  trailing: Text(
                    formatTime(Duration(milliseconds: run.fastest)),
                  ),
                ),
                ListTile(
                  title: const Text('Previous best'),
                  trailing: Text('${run.previousBest}'),
                ),
                ListTile(
                  title: const Text('Coins earned'),
                  trailing: Text('${run.coins}'),
                ),
                FilledButton(
                  onPressed: model.openAttack,
                  child: const Text('Replay'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Return to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CrateTray extends StatefulWidget {
  const _CrateTray({required this.model});
  final AppModel model;

  @override
  State<_CrateTray> createState() => _CrateTrayState();
}

class _CrateTrayState extends State<_CrateTray> {
  int? _collected;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (model.activeId?.mode == PlayMode.attack) return const SizedBox.shrink();
    final crate = model.supplyCrate;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 42,
      child: ClipRect(
        child: Center(
          child: AnimatedSwitcher(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 450),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween(begin: const Offset(0, -1.3), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                  ),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: model.complete
                ? const SizedBox.shrink()
                : _collected != null
                ? Semantics(
                    liveRegion: true,
                    child: Text('Supply crate opened · +$_collected coins'),
                  )
                : crate == null
                ? const SizedBox.shrink()
                : TextButton.icon(
                    key: ValueKey(crate.id),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(
                      '${crate.rarity.name[0].toUpperCase()}${crate.rarity.name.substring(1)} supply crate',
                    ),
                    onPressed: () {
                      if (!model.claimCrate(crate.id)) return;
                      setState(() => _collected = crate.coins);
                      Future<void>.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _collected = null);
                      });
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
