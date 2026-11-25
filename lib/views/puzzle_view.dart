import 'dart:async';
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
import '../model/journey.dart';
import '../ui/art/control_art.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import '../ui/journey_art.dart';
import 'components/ad_banner.dart';
import 'components/economy_navigation.dart';
import 'components/puzzle_board.dart';
import 'falling_crate.dart';
import 'journey_rewards.dart';
import 'mechanic_tutorial_view.dart';
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
    if (model.pendingMechanicTutorials.isNotEmpty) {
      return MechanicTutorialView(
        key: ValueKey(model.pendingMechanicTutorials.first.id),
        mechanic: model.pendingMechanicTutorials.first,
        onAcknowledge: (skipped) => model.acknowledgeMechanic(
          model.pendingMechanicTutorials.first,
          skipped: skipped,
        ),
      );
    }
    final timed = id.mode == PlayMode.attack;
    final attackFinished = timed && model.attack?.finished == true;
    if (attackFinished && puzzle == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Time Attack')),
        body: SafeArea(child: _AttackResults(model: model)),
      );
    }
    return Scaffold(
      bottomNavigationBar: timed || model.complete ? null : const AdBanner(),
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
                  final extraHeader =
                      (timed ? 28.0 : 0.0) +
                      (id.layoutLabel != null ? 22.0 : 0.0) +
                      (id.mode == PlayMode.daily && id.checkpoint == null
                          ? 26.0
                          : 0.0);
                  final reservedVertical = 176.0 + extraHeader;
                  final side = math.min(
                    math.min(constraints.maxWidth - 32, 490.0),
                    math.max(200.0, constraints.maxHeight - reservedVertical),
                  );
                  final verticalSpace =
                      constraints.maxHeight - side - reservedVertical;
                  final topInset = verticalSpace > 0
                      ? (verticalSpace * .22).clamp(8.0, 36.0)
                      : 8.0;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, topInset, 16, 18),
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
                            _BoardProgress(
                              checkpoint: model.complete
                                  ? board.checkpoints.length
                                  : model.nextCheckpoint,
                              checkpoints: board.checkpoints.length,
                              tiles: model.path.length,
                              area: board.area,
                              palette: palette,
                            ),
                            const SizedBox(height: 14),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _ControlButton(
                                    icon: ControlGlyph.undo,
                                    label: 'Undo',
                                    onPressed: model.canUndo
                                        ? model.undo
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  _ControlButton(
                                    icon: ControlGlyph.clear,
                                    label: 'Clear',
                                    onPressed: model.canClear
                                        ? model.clear
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  _HintAction(model: model),
                                ],
                              ),
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
                                tipStyle: model.equippedTip,
                              ),
                            ),
                            if (model.hintCell != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    model.correctedByHint
                                        ? 'Route corrected'
                                        : 'Follow the highlight',
                                    style: TextStyle(
                                      color: palette.mutedInk,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(height: 8),
                            BoardRulesButton(puzzle: board, palette: palette),
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
                Positioned.fill(child: ModalBarrier(color: palette.canvas)),
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
              if (!timed)
                if (model.fallingCrate case final crate?)
                  Positioned.fill(
                    key: ValueKey(crate.id),
                    child: FallingCrate(crate: crate),
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
  final accepted = await showGameDialog<bool>(
    context,
    builder: (dialog) => GameDialog(
      art: GameArt(ArtKind.levels, palette: dialog.palette, size: 56),
      title: 'Restart puzzle?',
      body: 'This clears your route. Your hint balance stays the same.',
      actions: [
        ActionPill(
          label: 'Keep playing',
          onTap: () => Navigator.pop(dialog, false),
        ),
        ActionPill(
          label: 'Restart',
          tone: ActionTone.primary,
          onTap: () => Navigator.pop(dialog, true),
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
  final accepted = await showGameDialog<bool>(
    context,
    builder: (dialog) => GameDialog(
      art: GameArt(ArtKind.timer, palette: dialog.palette, size: 56),
      title: restart ? 'Restart Time Attack?' : 'Stop Time Attack?',
      body: 'This run’s score and rewards will be discarded.',
      actions: [
        ActionPill(
          label: 'Keep playing',
          onTap: () => Navigator.pop(dialog, false),
        ),
        ActionPill(
          label: restart ? 'Restart' : 'Stop',
          tone: ActionTone.primary,
          onTap: () => Navigator.pop(dialog, true),
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

  void _openNextLevel(BuildContext context, AppModel model, PuzzleId next) {
    final ads = context.read<AdService>();
    final shouldCheckInterstitial =
        id.mode == PlayMode.levels && model.completedThisVisit && !model.adFree;
    unawaited(model.open(next));
    if (shouldCheckInterstitial && context.mounted) {
      bool canPresent() =>
          context.mounted &&
          !model.adFree &&
          !model.complete &&
          ModalRoute.isCurrentOf(context) == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      unawaited(
        ads.afterCompletedExit(
          canPresent: canPresent(),
          stillPresent: canPresent,
        ),
      );
      if (canPresent()) unawaited(ads.prepare(canPresent: canPresent));
    }
  }

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
    final levelCoins = model.firstCampaignClear && id.mode == PlayMode.levels
        ? model.completionCoins
        : model.lastReward;
    final milestoneCoins = model.lastReward - levelCoins;
    final bonusCoins = model.completionBonusCoins;
    final hints = result?.hints ?? model.hintsUsed;
    final duration = Duration(
      milliseconds: result?.milliseconds ?? model.elapsed.value.inMilliseconds,
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
        child: Column(
          children: [
            if (model.chapterCompletedThisVisit && id.mode == PlayMode.levels)
              JourneyArt(palette, chapter: chapterFor(id.level), height: 90)
            else
              GameArt(ArtKind.check, palette: palette, size: 42),
            Text(
              model.chapterCompletedThisVisit && id.mode == PlayMode.levels
                  ? '${chapterName(chapterFor(id.level))} complete'
                  : id.checkpoint != null
                  ? 'Checkpoint complete'
                  : id.mode == PlayMode.levels
                  ? 'Level complete!'
                  : 'Daily complete!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('${formatTime(duration)} · $hints hints'),
            if (levelCoins > 0)
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 4),
                child: RewardAmount(levelCoins + bonusCoins, size: 46),
              ),
            if (bonusCoins > 0) Text('Video bonus · +$bonusCoins coins'),
            if (milestoneCoins > 0) Text('+$milestoneCoins milestone coins'),
            if (model.firstCampaignClear && id.mode == PlayMode.levels) ...[
              const SizedBox(height: 10),
              if (model.latestDiscovery case final discovery?) ...[
                Text(
                  'New discovery!',
                  style: TextStyle(
                    color: palette.route,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                DiscoveryRow(
                  discovery,
                  reveal: true,
                  onClaimLater: next == null || !model.onlineReady
                      ? () => Navigator.pop(context)
                      : () => _openNextLevel(context, model, next),
                  key: ValueKey(discovery.number),
                ),
              ] else ...[
                TweenAnimationBuilder<double>(
                  key: ValueKey(
                    'discovery-${id.level}-${model.discoveryPercent}',
                  ),
                  tween: Tween(
                    begin:
                        (model.discoveryStartPercent ??
                            model.discoveryPercent) /
                        100,
                    end: model.discoveryPercent / 100,
                  ),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) => Column(
                    children: [
                      ProgressiveDiscoveryArt(
                        item: model.upcomingDiscoveryItem,
                        palette: palette,
                        progress: progress,
                        size: 84,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mystery discovery · ${(progress * 100).round()}%',
                        style: TextStyle(
                          color: palette.mutedInk,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 14),
            if (next != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        GameTokens.cardRadius,
                      ),
                    ),
                  ),
                  onPressed: model.onlineReady
                      ? () => _openNextLevel(context, model, next)
                      : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(
                    id.checkpoint == null ? 'Next level' : 'Next checkpoint',
                  ),
                ),
              ),
            if (next != null && !model.onlineReady)
              const Text('Reconnect to play the next puzzle.'),
            const SizedBox(height: 8),
            if (model.firstCampaignClear &&
                model.latestDiscovery == null &&
                id.mode == PlayMode.levels)
              CompletionBonus(model, key: ValueKey(id.level)),
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
  final shortfall = economy.hintPrice - model.coinBalance;
  var busy = false;
  var unavailable = false;
  final action = await showGameDialog<String>(
    context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, refresh) {
        bool current() =>
            dialog.mounted && ModalRoute.isCurrentOf(dialog) == true;
        final canEarn = model.canEarnHintAd;
        final p = dialog.palette;
        final watchLabel = !ads.enabled
            ? 'Unavailable'
            : !canEarn
            ? 'Daily limit'
            : busy
            ? 'Preparing…'
            : unavailable
            ? 'Retry'
            : 'Watch';
        Widget option(Widget art, Widget action) => GameCard(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(children: [art, const Spacer(), action]),
        );
        Widget plusOne(ArtKind kind) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GameArt(kind, palette: p, size: 36),
            const SizedBox(width: 8),
            Semantics(
              label: 'One hint',
              excludeSemantics: true,
              child: Text(
                '+1',
                style: TextStyle(
                  color: p.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GameArt(ArtKind.hint, palette: p, size: 26),
          ],
        );
        return GameDialog(
          art: GameArt(ArtKind.hint, palette: p, size: 64),
          title: 'Get a hint',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                plusOne(ArtKind.video),
                ActionPill(
                  key: const ValueKey('hint-watch'),
                  label: watchLabel,
                  tone: ActionTone.primary,
                  semanticLabel: 'Watch a video for one hint. $watchLabel',
                  onTap: !ads.enabled || !canEarn || busy
                      ? null
                      : () async {
                          refresh(() {
                            busy = true;
                            unavailable = false;
                          });
                          if (!ads.readyFor(RewardPlacement.hint) &&
                              await ads.isOnline() &&
                              current()) {
                            await ads.prepare(canPresent: current);
                          }
                          if (!current()) return;
                          final shown = await ads.watchVideo(
                            model.grantHintAd,
                            placement: RewardPlacement.hint,
                            canPresent: () => current() && model.canEarnHintAd,
                            waitForReward: true,
                          );
                          if (!current()) return;
                          if (shown) {
                            Navigator.pop(dialog);
                          } else {
                            refresh(() {
                              busy = false;
                              unavailable = true;
                            });
                          }
                        },
                ),
              ),
              if (unavailable)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Ad unavailable. Try again shortly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.mutedInk, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 8),
              option(
                plusOne(ArtKind.coin),
                PricePill(
                  key: const ValueKey('hint-buy'),
                  price: economy.hintPrice,
                  affordable: shortfall <= 0,
                  semanticLabel: shortfall > 0
                      ? 'Buy a hint for ${economy.hintPrice} coins. $shortfall more coins needed'
                      : 'Buy a hint for ${economy.hintPrice} coins',
                  onTap: busy
                      ? null
                      : () => Navigator.pop(
                          dialog,
                          shortfall > 0 ? 'insufficient' : 'coins',
                        ),
                ),
              ),
            ],
          ),
          actions: [
            ActionPill(label: 'Close', onTap: () => Navigator.pop(dialog)),
          ],
        );
      },
    ),
  );
  if (!context.mounted) return;
  if (action == 'coins') await model.buyHint();
  if (action == 'insufficient') {
    await showInsufficientCoins(
      context,
      itemName: 'A hint',
      requiredCoins: economy.hintPrice,
      currentBalance: model.coinBalance,
    );
  }
}

class _HintAction extends StatelessWidget {
  const _HintAction({required this.model});
  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final onTap = model.canHint
        ? model.hint
        : model.hintsRemaining == 0 && !model.complete && !model.storageError
        ? () => showHintShop(context, model)
        : null;
    return _ControlButton(
      icon: ControlGlyph.hint,
      label: 'Hint · ${model.hintsRemaining} left',
      onPressed: onTap,
      primary: true,
    );
  }
}

/// A compact board control. Hint is the one tinted action.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final ControlGlyph icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null;
    final fill = primary && enabled ? p.route : p.quiet;
    final ink = !enabled
        ? p.mutedInk.withValues(alpha: .6)
        : primary
        ? p.onRoute
        : p.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: InkResponse(
        onTap: onPressed,
        radius: 32,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: GameTokens.minTouch),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(GameTokens.pillRadius),
                border: primary && enabled
                    ? null
                    : Border.all(color: p.cardEdge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTheme(
                    data: IconThemeData(color: ink),
                    child: PathIcon(icon, size: 18),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Checkpoint pips and a single tile bar replace the two text lines.
class _BoardProgress extends StatelessWidget {
  const _BoardProgress({
    required this.checkpoint,
    required this.checkpoints,
    required this.tiles,
    required this.area,
    required this.palette,
  });

  final int checkpoint, checkpoints, tiles, area;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Checkpoint $checkpoint of $checkpoints, $tiles of $area tiles',
    excludeSemantics: true,
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$checkpoint/$checkpoints',
              style: TextStyle(
                color: palette.ink,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            Text(
              '$tiles/$area',
              style: TextStyle(color: palette.mutedInk, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 6),
        GameBar(value: tiles / area, height: 6),
      ],
    ),
  );
}

class _AttackResults extends StatelessWidget {
  const _AttackResults({required this.model});
  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final run = model.attack!;
    final p = BoardPalette.palettes[model.theme]!;
    Widget stat(ArtKind art, String value, String label) => Semantics(
      label: '$label, $value',
      excludeSemantics: true,
      child: GameCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            GameArt(art, palette: p, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: p.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GameCard(
            padding: EdgeInsets.zero,
            child: ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              children: [
                Center(child: GameArt(ArtKind.timer, palette: p, size: 64)),
                const SizedBox(height: 6),
                Text(
                  'Time’s up',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Semantics(
                  label: 'Score ${run.score}',
                  excludeSemantics: true,
                  child: Text(
                    '${run.score}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (run.record)
                      InfoChip(
                        icon: GameArt(ArtKind.trophy, palette: p, size: 16),
                        label: 'New personal best',
                      ),
                    if (model.recentStreakDay case final day?)
                      InfoChip(
                        icon: GameArt(ArtKind.flame, palette: p, size: 16),
                        label: '$day-day streak',
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, box) {
                    final width = (box.maxWidth - 8) / 2;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tile in [
                          stat(
                            ArtKind.check,
                            '${run.clears.length}',
                            'Puzzles completed',
                          ),
                          stat(ArtKind.coin, '+${run.coins}', 'Coins earned'),
                          stat(
                            ArtKind.timer,
                            formatTime(Duration(milliseconds: run.average)),
                            'Average puzzle',
                          ),
                          stat(
                            ArtKind.bolt,
                            formatTime(Duration(milliseconds: run.fastest)),
                            'Fastest puzzle',
                          ),
                          stat(
                            ArtKind.trophy,
                            '${run.previousBest}',
                            'Previous best',
                          ),
                        ])
                          SizedBox(width: width, child: tile),
                      ],
                    );
                  },
                ),
                AchievementCelebration(model),
                if (run.canRank && PlayGames.enabled)
                  if (PlayGames.timeAttackBoard(run.minutes) case final board?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(
                        child: ActionPill(
                          label: 'Submit to Play Games',
                          icon: Icons.leaderboard_outlined,
                          onTap: () async {
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
                        ),
                      ),
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
                const SizedBox(height: 8),
                Center(
                  child: ActionPill(
                    label: 'Replay',
                    tone: ActionTone.primary,
                    onTap: model.openAttack,
                  ),
                ),
                Center(
                  child: ActionPill(
                    label: 'Return to home',
                    onTap: () => Navigator.pop(context),
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
