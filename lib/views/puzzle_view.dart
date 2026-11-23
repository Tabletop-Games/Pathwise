import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/play_games.dart';
import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import 'components/ad_banner.dart';
import 'components/puzzle_board.dart';
import 'falling_crate.dart';
import 'fortune_view.dart';
import 'share_view.dart';

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
    final attackFinished = timed && model.attack?.finished == true;
    if (attackFinished && puzzle == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Time Attack')),
        body: SafeArea(child: _AttackResults(model: model)),
      );
    }
    return Scaffold(
      bottomNavigationBar: timed ? null : const AdBanner(),
      appBar: AppBar(
        title: Text(
          id.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (kDebugMode && !timed && model.puzzle != null)
            IconButton(
              tooltip: 'Debug: drop crate',
              onPressed: model.forceCrateForDebug,
              icon: const Icon(Icons.bug_report_outlined),
            ),
          if (!timed && puzzle != null && !model.complete)
            PopupMenuButton<int>(
              tooltip: 'Puzzle options',
              onSelected: (_) => _confirmPuzzleRestart(context, model),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('Restart puzzle')),
              ],
            ),
          if (timed && !attackFinished) ...[
            IconButton(
              tooltip: 'Stop Time Attack',
              onPressed: () => _confirmAttackAction(context, model, false),
              icon: const Icon(Icons.stop_circle_outlined),
            ),
            IconButton(
              tooltip: 'Restart Time Attack',
              onPressed: () => _confirmAttackAction(context, model, true),
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          ],
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
          (_, _, final board?) => Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
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
                            if (id.layoutLabel case final label?)
                              Text(
                                label,
                                style: TextStyle(color: palette.muted),
                              ),
                            if (id.mode == PlayMode.daily &&
                                id.checkpoint == null)
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
                                  onPressed: model.canClear
                                      ? model.clear
                                      : null,
                                  icon: const Icon(Icons.restart_alt_rounded),
                                  label: const Text('Clear'),
                                ),
                                _HintAction(model: model),
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
                              child: Padding(
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
                            if (board.wall != null && board.portal != null)
                              TextButton.icon(
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (dialog) => AlertDialog(
                                    title: const Text('Mixed board rules'),
                                    content: const Text(
                                      'Walls block the path. Arrows direct exits. Collect the key to open its gate. '
                                      'The marked portal jumps to its ring. Ice slides one tile straight ahead.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialog),
                                        child: const Text('Done'),
                                      ),
                                    ],
                                  ),
                                ),
                                icon: const Icon(Icons.help_outline_rounded),
                                label: const Text('Board rules'),
                              )
                            else if (board.wall != null)
                              const Text('Walls block the route.')
                            else if (board.arrow != null)
                              const Text(
                                'Follow the arrow when leaving its tile.',
                              )
                            else if (board.gate != null)
                              const Text(
                                'Collect the key before entering its lock.',
                              )
                            else if (board.portal != null)
                              const Text(
                                'Enter the dotted portal to jump to its ring.',
                              )
                            else if (board.ice != null)
                              const Text('Ice slides one tile straight ahead.'),
                            if (model.endedEarly)
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                children: [
                                  Text(
                                    '${board.area - model.path.length} tiles left!',
                                  ),
                                  FilledButton(
                                    onPressed: model.canClear
                                        ? model.clear
                                        : null,
                                    child: const Text('Reset board'),
                                  ),
                                ],
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
              if (attackFinished) ...[
                const Positioned.fill(
                  child: ModalBarrier(color: Colors.black54),
                ),
                BlockSemantics(child: _AttackResults(model: model)),
              ],
              if (model.complete && !timed) ...[
                const Positioned.fill(
                  child: ModalBarrier(color: Colors.black54),
                ),
                if (model.completedThisVisit &&
                    !MediaQuery.disableAnimationsOf(context))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 680),
                        builder: (_, phase, _) => CustomPaint(
                          painter: _CompletionBurst(phase, palette),
                        ),
                      ),
                    ),
                  ),
                BlockSemantics(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: _Completion(
                          model: model,
                          id: id,
                          palette: palette,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (!timed && !model.complete)
                if (model.fallingCrate case final crate?)
                  Positioned.fill(
                    child: FallingCrate(key: ValueKey(crate.id), crate: crate),
                  ),
            ],
          ),
        },
      ),
    );
  }
}

class _CompletionBurst extends CustomPainter {
  const _CompletionBurst(this.phase, this.palette);

  final double phase;
  final BoardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (phase >= 1) return;
    final center = size.center(Offset.zero);
    final radius =
        size.shortestSide * (.24 + .26 * Curves.easeOut.transform(phase));
    final colors = [palette.route, palette.accent, palette.ink];
    final paint = Paint();
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi * 2 / 24;
      final distance = radius * (i.isEven ? 1 : .84);
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      paint.color = colors[i % colors.length].withValues(alpha: 1 - phase);
      canvas.drawCircle(point, i.isEven ? 3 : 2, paint);
    }
  }

  @override
  bool shouldRepaint(_CompletionBurst oldDelegate) =>
      phase != oldDelegate.phase || palette != oldDelegate.palette;
}

Future<void> _confirmPuzzleRestart(BuildContext context, AppModel model) async {
  final id = model.activeId;
  if (id == null) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Restart puzzle?'),
      content: const Text(
        'This clears your route. Your hint balance stays the same.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Keep playing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Restart'),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted && model.activeId == id) {
    await model.open(id, replay: true);
  }
}

Future<void> _confirmAttackAction(
  BuildContext context,
  AppModel model,
  bool restart,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(restart ? 'Restart Time Attack?' : 'Stop Time Attack?'),
      content: const Text('This run’s score and rewards will be discarded.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep playing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(restart ? 'Restart' : 'Stop'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted || model.attack?.finished != false) {
    return;
  }
  if (restart) {
    await model.restartAttack();
  } else {
    model.stopAttack();
    Navigator.pop(context);
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
      PlayMode.daily when id.checkpoint != null => model.dailyCurrent(
        id.value as String,
      ),
      _ => null,
    };
    final result = model.result(id);
    final hints = result?.hints ?? model.hintsUsed;
    final duration = Duration(
      milliseconds: result?.milliseconds ?? model.elapsed.value.inMilliseconds,
    );
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
                Icon(
                  Icons.check_circle_rounded,
                  color: palette.accent,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        id.checkpoint != null
                            ? 'Checkpoint complete'
                            : id.mode == PlayMode.levels
                            ? 'Level complete!'
                            : 'Daily complete!',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${formatTime(duration)} · $hints ${hints == 1 ? 'hint' : 'hints'}',
                        style: TextStyle(color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (model.recentStreakDay case final day?)
              Chip(
                avatar: const Icon(Icons.local_fire_department_rounded),
                label: Text('$day-day streak'),
              ),
            if (model.lastReward > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.toll_rounded),
                    const SizedBox(width: 8),
                    Text(
                      '+${model.lastReward} coins',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            if (next != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  onPressed: () => model.open(next),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(
                    id.checkpoint == null ? 'Next level' : 'Next checkpoint',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            AchievementCelebration(model),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (id.mode == PlayMode.daily && id.checkpoint == null)
                  ShareResultButton(
                    result: ShareResult.daily(
                      id.value as String,
                      time: Duration(
                        milliseconds:
                            model.result(id)?.milliseconds ??
                            model.elapsed.value.inMilliseconds,
                      ),
                      hints: model.result(id)?.hints ?? hints,
                      newBest: model.newBest,
                    ),
                    label: 'Share Today’s Result',
                    prominent: true,
                  ),
                if (id.mode == PlayMode.levels &&
                    SharePromptPolicy.levelMilestone(id.level))
                  ShareResultButton(
                    result: ShareResult.level(
                      level: id.level,
                      total: model.levelsSolved,
                    ),
                    label: 'Share Level Milestone',
                  ),
                TextButton(
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

Future<void> showHintShop(BuildContext context, AppModel model) async {
  final ads = context.read<AdService>();
  final online = ads.enabled ? ads.isOnline() : Future<bool>.value(false);
  final action = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Need a hint?'),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('+1 hint · ${model.coinBalance} coins available'),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: online,
            builder: (context, snapshot) =>
                snapshot.data == true &&
                    ads.readyFor(RewardPlacement.hint) &&
                    model.canEarnHintAd
                ? FilledButton.icon(
                    onPressed: () => Navigator.pop(dialog, 'ad'),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Watch ad · +1 hint'),
                  )
                : Text(
                    model.canEarnHintAd
                        ? 'No ads available right now'
                        : 'Daily ad limit reached',
                  ),
          ),
          const SizedBox(height: 8),
          if (model.coinBalance < economy.hintPrice) ...[
            Text('Need ${economy.hintPrice - model.coinBalance} more coins'),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialog, 'vault'),
              icon: const Icon(Icons.toll_rounded),
              label: const Text('Get coins'),
            ),
            const Text('A hint costs 60 coins'),
          ] else
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(dialog, 'coins'),
              icon: const Icon(Icons.toll_rounded),
              label: const Text('60 coins · +1 hint'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (action == 'coins') await model.buyHint();
  if (action == 'vault') {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const FortuneView()));
  }
  if (action != 'ad') return;
  bool current() => context.mounted && ModalRoute.isCurrentOf(context) == true;
  if (!ads.readyFor(RewardPlacement.hint)) {
    await ads.prepare(canPresent: current);
  }
  if (!current()) return;
  final shown = await ads.watchVideo(
    model.grantHintAd,
    placement: RewardPlacement.hint,
    canPresent: () => current() && model.canEarnHintAd,
  );
  if (!shown && current()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Video unavailable. No hint was added.')),
    );
  }
}

class _HintAction extends StatelessWidget {
  const _HintAction({required this.model});
  final AppModel model;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: model.canHint
        ? model.hint
        : model.hintsRemaining == 0 && !model.complete && !model.storageError
        ? () => showHintShop(context, model)
        : null,
    icon: const Icon(Icons.lightbulb_outline_rounded),
    label: Text('Hint · ${model.hintsRemaining} left'),
  );
}

class _AttackResults extends StatelessWidget {
  const _AttackResults({required this.model});
  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final run = model.attack!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              padding: const EdgeInsets.all(16),
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
                if (model.recentStreakDay case final day?)
                  Center(
                    child: Chip(
                      avatar: const Icon(Icons.local_fire_department_rounded),
                      label: Text('$day-day streak'),
                    ),
                  ),
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
                AchievementCelebration(model),
                if (run.canRank && PlayGames.enabled)
                  if (PlayGames.timeAttackBoard(run.minutes) case final board?)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final signedIn =
                            await PlayGames.call<bool>('status') == true ||
                            await PlayGames.call<bool>('signIn') == true;
                        final posted =
                            signedIn &&
                            await PlayGames.call<bool>('submitScore', {
                                  'id': board,
                                  'score': '${run.score}',
                                }) ==
                                true;
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                posted
                                    ? 'Score submitted.'
                                    : 'Score submission unavailable.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: const Text('Submit to Play Games'),
                    ),
                ShareResultButton(
                  result: ShareResult.attack(
                    score: run.score,
                    puzzles: run.clears.length,
                    newBest: run.record,
                  ),
                  label: 'Share Your Score',
                  prominent: run.record,
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
