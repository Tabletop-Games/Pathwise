import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/haptic_service.dart';
import '../logic/play_games.dart';
import '../logic/social_sharing.dart';
import '../logic/sound_service.dart';
import '../logic/star_rating.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/journey.dart';
import '../model/user_preferences.dart';
import '../ui/art/control_art.dart';
import '../ui/art/game_assets.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
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
      appBar: model.complete && !timed
          ? null
          : AppBar(
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  id.title,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
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
                    onPressed: () =>
                        _confirmAttackAction(context, model, false),
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                  IconButton(
                    tooltip: 'Restart Time Attack',
                    onPressed: () => _confirmAttackAction(context, model, true),
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
                ],
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: timed
                        ? model.attackRemaining
                        : model.elapsed,
                    builder: (context, value, child) => Semantics(
                      label: timed ? 'Time remaining' : 'Elapsed time',
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 16,
                              color: palette.muted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatTime(
                                timed
                                    ? value + const Duration(milliseconds: 999)
                                    : value,
                              ),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      body: AtmosphericBackdrop(
        child: SafeArea(
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
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
                              if (model.activeStarThresholds
                                  case final thresholds?) ...[
                                _StarDepletionBar(
                                  model: model,
                                  thresholds: thresholds,
                                  palette: palette,
                                ),
                                const SizedBox(height: 14),
                              ],
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
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color.lerp(
                                    palette.surface,
                                    palette.canvas,
                                    .45,
                                  ),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: palette.cardEdge),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: palette.dark ? .30 : .10,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: SizedBox(
                                    width: side - 12,
                                    height: side - 12,
                                    child: PuzzleBoard(
                                      key: ObjectKey(board),
                                      model: model,
                                      puzzle: board,
                                      palette: palette,
                                      tipStyle: model.equippedTip,
                                    ),
                                  ),
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
                  const Positioned.fill(
                    child: AtmosphericBackdrop(child: SizedBox.expand()),
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

class _AttemptStarsRow extends StatelessWidget {
  const _AttemptStarsRow({
    required this.stars,
    required this.previousBest,
    required this.isFirstClear,
    required this.palette,
  });

  final int stars;
  final int previousBest;
  final bool isFirstClear;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final improved = !isFirstClear && stars > previousBest;
    final highContrast =
        palette == BoardPalette.palettes[PathwiseTheme.signal] ||
        MediaQuery.highContrastOf(context);
    return Semantics(
      label: '$stars of 3 stars',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                TweenAnimationBuilder<double>(
                  key: ValueKey('completion-star-$i-$stars'),
                  tween: Tween(begin: reduced ? 1.0 : 0.4, end: 1.0),
                  duration: reduced
                      ? Duration.zero
                      : Duration(milliseconds: 220 + i * 70),
                  curve: Curves.easeOutBack,
                  onEnd: i < stars
                      ? () {
                          try {
                            final model = context.read<AppModel?>();
                            model?.haptic.trigger(HapticEvent.starReveal);
                            model?.sound.play(
                              SoundEvent.starReveal,
                              starIndex: i + 1,
                            );
                          } on ProviderNotFoundException {
                            // Isolated widget tests may omit AppModel.
                          }
                        }
                      : null,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: RatingStar(
                      earned: i < stars,
                      size: 34,
                      highContrast: highContrast,
                      palette: palette,
                    ),
                  ),
                ),
            ],
          ),
          if (!isFirstClear) ...[
            const SizedBox(height: 4),
            Text(
              improved
                  ? 'Improved! Best: $stars/3 ★'
                  : 'Best: $previousBest/3 ★',
              style: TextStyle(
                color: improved ? palette.route : palette.mutedInk,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ],
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
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: Column(
          children: [
            if (model.chapterCompletedThisVisit && id.mode == PlayMode.levels)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 76,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          biomeAssetPath(biomeForTheme(model.theme)),
                          fit: BoxFit.cover,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: .15),
                                Colors.black.withValues(alpha: .45),
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: GameArt(
                            ArtKind.treasureOpen,
                            palette: palette,
                            size: 56,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Text(
              model.chapterCompletedThisVisit && id.mode == PlayMode.levels
                  ? '${chapterName(chapterFor(id.level))} complete'
                  : id.checkpoint != null
                  ? 'Checkpoint complete'
                  : id.mode == PlayMode.levels
                  ? 'Level complete!'
                  : 'Daily complete!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            if (id.mode == PlayMode.levels) ...[
              const SizedBox(height: 6),
              _AttemptStarsRow(
                stars: model.attemptStars,
                previousBest: model.previousAttemptBestStars,
                isFirstClear: model.firstCampaignClear,
                palette: palette,
              ),
              const SizedBox(height: 4),
            ],
            if (levelCoins > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: RewardAmount(levelCoins + bonusCoins, size: 48),
              ),
            if (bonusCoins > 0)
              Text(
                'Video bonus · +$bonusCoins coins',
                style: TextStyle(
                  color: palette.route,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            if (milestoneCoins > 0)
              Text(
                '+$milestoneCoins milestone coins',
                style: TextStyle(
                  color: palette.mutedInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: palette.muted),
                  const SizedBox(width: 4),
                  Text(
                    formatTime(model.elapsed.value),
                    style: TextStyle(
                      color: palette.mutedInk,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
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
                  onSkip: () {
                    model.skipLatestDiscovery();
                    if (next == null) {
                      Navigator.pop(context);
                    } else {
                      _openNextLevel(context, model, next);
                    }
                  },
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
                        size: 136,
                      ),
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
            if (model.firstCampaignClear &&
                model.latestDiscovery == null &&
                id.mode == PlayMode.levels) ...[
              const SizedBox(height: 8),
              CompletionBonus(model, key: ValueKey(id.level)),
            ],
            const SizedBox(height: 12),
            if (next != null)
              SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GameTokens.cardRadius),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [palette.buttonTop, palette.buttonBottom],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: palette.dark ? .35 : .18,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          GameTokens.cardRadius,
                        ),
                      ),
                    ),
                    onPressed: () => _openNextLevel(context, model, next),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      id.checkpoint == null ? 'Next level' : 'Next checkpoint',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
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
                              model.onlineReady &&
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
    final enabled = !model.complete && !model.storageError;
    return _ControlButton(
      icon: ControlGlyph.hint,
      label: 'Hint · ${model.hintsRemaining} left',
      onPressed: enabled
          ? () {
              // Keep button visually stable while drawing; ignore tap safely.
              if (model.isDrawing) return;
              if (model.hintsRemaining > 0) {
                if (model.canHint) model.hint();
              } else {
                showHintShop(context, model);
              }
            }
          : null,
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
                color: primary && enabled ? null : fill,
                gradient: primary && enabled
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [p.buttonTop, p.buttonBottom],
                      )
                    : null,
                borderRadius: BorderRadius.circular(GameTokens.pillRadius),
                border: primary && enabled
                    ? null
                    : Border.all(color: p.cardEdge),
                boxShadow: primary && enabled
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .16),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
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

/// Maps elapsed milliseconds to the horizontal star depletion track `[0.0..1.0]`.
///
/// The three stars sit evenly at `0.16` (1★), `0.50` (2★), and `0.84` (3★)
/// with outer track padding so stars never touch the track endpoints.
@visibleForTesting
double starDepletionProgress(int elapsedMs, StarThresholds thresholds) {
  const x1 = 0.16;
  const x2 = 0.50;
  const x3 = 0.84;
  const tailMs = 2000;
  if (elapsedMs <= 0) return 1.0;
  if (elapsedMs < thresholds.threeStarMs) {
    final span = math.max(1, thresholds.threeStarMs);
    return (1.0 - (elapsedMs / span) * (1.0 - x3)).clamp(x3, 1.0);
  }
  if (elapsedMs <= thresholds.twoStarMs) {
    final span = math.max(1, thresholds.twoStarMs - thresholds.threeStarMs);
    return (x3 - ((elapsedMs - thresholds.threeStarMs) / span) * (x3 - x2))
        .clamp(x2, x3);
  }
  if (elapsedMs <= thresholds.oneStarMs) {
    final span = math.max(1, thresholds.oneStarMs - thresholds.twoStarMs);
    return (x2 - ((elapsedMs - thresholds.twoStarMs) / span) * (x2 - x1)).clamp(
      x1,
      x2,
    );
  }
  final pastOne = elapsedMs - thresholds.oneStarMs;
  if (pastOne >= tailMs) return 0.0;
  return (x1 * (1.0 - pastOne / tailMs)).clamp(0.0, x1);
}

/// Time-based horizontal star depletion bar rendered directly above controls.
class _StarDepletionBar extends StatefulWidget {
  const _StarDepletionBar({
    required this.model,
    required this.thresholds,
    required this.palette,
  });

  final AppModel model;
  final StarThresholds thresholds;
  final BoardPalette palette;

  @override
  State<_StarDepletionBar> createState() => _StarDepletionBarState();
}

class _StarDepletionBarState extends State<_StarDepletionBar>
    with SingleTickerProviderStateMixin {
  static const _starPositions = [0.16, 0.50, 0.84];

  late final AnimationController _controller;
  late final ValueNotifier<double> _progressNotifier;
  double _fromProgress = 1.0;
  double _toProgress = 1.0;
  int _activeStars = 3;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_onAnimate);
    final initialMs = widget.model.elapsed.value.inMilliseconds;
    _toProgress = starDepletionProgress(initialMs, widget.thresholds);
    _fromProgress = _toProgress;
    _progressNotifier = ValueNotifier<double>(_toProgress);
    _activeStars = widget.thresholds.rate(initialMs);
    widget.model.elapsed.addListener(_onElapsedChanged);
    widget.model.addListener(_onModelChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion && _controller.isAnimating) {
      _controller.stop();
      _fromProgress = _toProgress;
      _progressNotifier.value = _toProgress;
    }
  }

  @override
  void didUpdateWidget(covariant _StarDepletionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.elapsed.removeListener(_onElapsedChanged);
      oldWidget.model.removeListener(_onModelChanged);
      widget.model.elapsed.addListener(_onElapsedChanged);
      widget.model.addListener(_onModelChanged);
    }
    if (oldWidget.model != widget.model ||
        oldWidget.thresholds != widget.thresholds) {
      _snapToCurrent();
    }
  }

  @override
  void dispose() {
    widget.model.elapsed.removeListener(_onElapsedChanged);
    widget.model.removeListener(_onModelChanged);
    _controller.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  void _snapToCurrent() {
    _controller.stop();
    final ms = widget.model.elapsed.value.inMilliseconds;
    final progress = starDepletionProgress(ms, widget.thresholds);
    _fromProgress = progress;
    _toProgress = progress;
    _progressNotifier.value = progress;
    final stars = widget.thresholds.rate(ms);
    if (stars != _activeStars && mounted) {
      setState(() => _activeStars = stars);
    }
  }

  void _onAnimate() {
    _progressNotifier.value =
        _fromProgress + (_toProgress - _fromProgress) * _controller.value;
  }

  void _onElapsedChanged() {
    final ms = widget.model.elapsed.value.inMilliseconds;
    final nextProgress = starDepletionProgress(ms, widget.thresholds);
    final stars = widget.thresholds.rate(ms);
    if (stars != _activeStars && mounted) {
      setState(() => _activeStars = stars);
    }
    if (_reducedMotion || widget.model.complete) {
      _controller.stop();
      _fromProgress = nextProgress;
      _toProgress = nextProgress;
      _progressNotifier.value = nextProgress;
      return;
    }
    if ((nextProgress - _toProgress).abs() > 1e-6) {
      _fromProgress = _progressNotifier.value;
      _toProgress = nextProgress;
      _controller.forward(from: 0);
    }
  }

  void _onModelChanged() {
    if (widget.model.complete) {
      _snapToCurrent();
    }
  }

  @override
  Widget build(BuildContext context) {
    const trackHeight = 7.0;
    const starSize = 22.0;
    const barHeight = 26.0;
    final highContrast =
        widget.palette == BoardPalette.palettes[PathwiseTheme.signal] ||
        MediaQuery.highContrastOf(context);

    return Semantics(
      label: '$_activeStars of 3 stars available',
      excludeSemantics: true,
      child: SizedBox(
        height: barHeight,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size(width, barHeight),
                  painter: _StarDepletionTrackPainter(
                    progressListenable: _progressNotifier,
                    trackColor: widget.palette.track,
                    fillColor: widget.palette.route,
                    trackHeight: trackHeight,
                  ),
                ),
                for (var i = 0; i < 3; i++)
                  Positioned(
                    left: width * _starPositions[i] - starSize / 2,
                    top: (barHeight - starSize) / 2,
                    child: AnimatedScale(
                      scale: i < _activeStars ? 1.0 : 0.88,
                      duration: _reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: RatingStar(
                        earned: i < _activeStars,
                        size: starSize,
                        highContrast: highContrast,
                        palette: widget.palette,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StarDepletionTrackPainter extends CustomPainter {
  _StarDepletionTrackPainter({
    required this.progressListenable,
    required this.trackColor,
    required this.fillColor,
    required this.trackHeight,
  }) : super(repaint: progressListenable);

  final ValueListenable<double> progressListenable;
  final Color trackColor;
  final Color fillColor;
  final double trackHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - trackHeight) / 2;
    final radius = Radius.circular(trackHeight / 2);
    final trackRect = Rect.fromLTWH(0, top, size.width, trackHeight);
    final trackRRect = RRect.fromRectAndRadius(trackRect, radius);

    canvas.drawRRect(trackRRect, Paint()..color = trackColor);

    final progress = progressListenable.value.clamp(0.0, 1.0);
    if (progress <= 0) return;

    canvas.save();
    canvas.clipRRect(trackRRect);
    final fillWidth = (size.width * progress).clamp(0.0, size.width);
    final fillRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, fillWidth, trackHeight),
      radius,
    );
    canvas.drawRRect(fillRRect, Paint()..color = fillColor);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StarDepletionTrackPainter oldDelegate) =>
      oldDelegate.trackColor != trackColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.trackHeight != trackHeight;
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
                  if (PlayGames.timeAttackBoard(run.minutes) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(
                        child: ActionPill(
                          label: 'Submit to Play Games',
                          icon: Icons.leaderboard_outlined,
                          onTap: () async {
                            final signedIn =
                                await PlayGames.isSignedIn() ||
                                await PlayGames.signIn();
                            final posted =
                                signedIn &&
                                await PlayGames.submitTimeAttackScore(
                                  run.minutes,
                                  run.score,
                                );
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
