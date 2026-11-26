import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/play_streak.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import '../viewmodels/streak_viewmodel.dart';
import 'components/economy_navigation.dart';
import 'store_view.dart';

class StreakView extends StatelessWidget {
  const StreakView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final vm = StreakViewModel(model);
    final palette = BoardPalette.palettes[model.theme]!;
    final streak = model.streak;
    final next = EconomyRules.milestones.entries
        .where((entry) => entry.key > vm.count)
        .firstOrNull;
    final today = PlayStreak.calendarDate(model.todayKey);
    final freezeFull = model.storageError || vm.freezeFull;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(palette),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          titleSpacing: 0,
          title: const Text(
            'Daily streak',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
          ),
          actions: [
            BalanceChip(
              coins: model.coinBalance,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const StoreView(section: StoreSection.coins),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: AtmosphericBackdrop(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                      child: Column(
                        children: [
                          GameArt(ArtKind.flame, palette: palette, size: 84),
                          const SizedBox(height: 8),
                          Semantics(
                            label: '${streak.count} days',
                            excludeSemantics: true,
                            child: Text(
                              '${streak.count}',
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 56,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Semantics(
                            label: 'Longest: ${streak.longest} days',
                            excludeSemantics: true,
                            child: InfoChip(
                              icon: GameArt(
                                ArtKind.trophy,
                                palette: palette,
                                size: 16,
                              ),
                              label: '${streak.longest}',
                            ),
                          ),
                          const SizedBox(height: 18),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var index = 6; index >= 0; index--)
                                  _Day(
                                    day: today.subtract(Duration(days: index)),
                                    status:
                                        streak.days[dayKey(
                                          today.subtract(Duration(days: index)),
                                        )],
                                    palette: palette,
                                    today: index == 0,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 10),
                      GameCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            GameArt(
                              ArtKind.treasure,
                              palette: palette,
                              size: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Day ${next.key}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    next.key - streak.count == 1
                                        ? '1 day to next milestone'
                                        : '${next.key - streak.count} days to next milestone',
                                    style: TextStyle(
                                      color: palette.mutedInk,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  GameBar(value: streak.count / next.key),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                RewardAmount(next.value.coins, size: 22),
                                if (next.value.hints > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Semantics(
                                      label: '${next.value.hints} hints',
                                      excludeSemantics: true,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GameArt(
                                            ArtKind.hint,
                                            palette: palette,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '+${next.value.hints}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      Builder(
                        builder: (context) {
                          final progress =
                              streak.count % economy.streakInterval;
                          final daysToWeekly =
                              economy.streakInterval - progress;
                          return GameCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                GameArt(
                                  ArtKind.trophy,
                                  palette: palette,
                                  size: 48,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Steady streak',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        daysToWeekly == 1
                                            ? 'All milestones reached · 1 day to weekly bonus'
                                            : 'All milestones reached · $daysToWeekly days to weekly bonus',
                                        style: TextStyle(
                                          color: palette.mutedInk,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      GameBar(
                                        value:
                                            progress / economy.streakInterval,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                RewardAmount(economy.streakBonus, size: 22),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 10),
                    GameCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          GameArt(ArtKind.freeze, palette: palette, size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Streak Freeze',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Protects your streak if you miss a day. Holds up to ${economy.maxFreezes}.',
                                  style: TextStyle(
                                    color: palette.mutedInk,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Semantics(
                                  label:
                                      '${streak.freezes} of ${economy.maxFreezes} owned',
                                  excludeSemantics: true,
                                  child: ProgressPips(
                                    done: streak.freezes,
                                    total: economy.maxFreezes,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (freezeFull && !model.storageError)
                            const ActionPill(
                              label: 'Full',
                              tone: ActionTone.selected,
                            )
                          else
                            PricePill(
                              price: vm.freezePrice,
                              affordable: model.coinBalance >= vm.freezePrice,
                              semanticLabel:
                                  'Buy Streak Freeze for ${vm.freezePrice} coins',
                              onTap: freezeFull
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final outcome = await vm.buyFreeze();
                                      if (!context.mounted) return;
                                      switch (outcome) {
                                        case FreezeInsufficientCoins(
                                          :final shortfall,
                                        ):
                                          await showInsufficientCoins(
                                            context,
                                            itemName: 'Streak Freeze',
                                            requiredCoins:
                                                model.coinBalance + shortfall,
                                            currentBalance: model.coinBalance,
                                          );
                                        case FreezePurchased():
                                          if (messenger.mounted) {
                                            messenger.showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Streak Freeze added.',
                                                ),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        case FreezePurchaseUnavailable():
                                          if (messenger.mounted) {
                                            messenger.showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Couldn’t buy Streak Freeze. Try again.',
                                                ),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                      }
                                    },
                            ),
                        ],
                      ),
                    ),
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

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.status,
    required this.palette,
    required this.today,
  });

  final DateTime day;
  final String? status;
  final BoardPalette palette;
  final bool today;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final weekday = weekdays[day.weekday - 1];
    final label = switch (status) {
      'played' => 'Played',
      'protected' => 'Protected by a freeze',
      _ => 'No qualifying puzzle',
    };
    return Semantics(
      label: '${day.day}, $label',
      excludeSemantics: true,
      child: Container(
        width: 44,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: today ? palette.quiet : Colors.transparent,
          borderRadius: BorderRadius.circular(GameTokens.cardRadius),
          border: today ? Border.all(color: palette.route, width: 1.5) : null,
        ),
        child: Column(
          children: [
            Text(
              weekday,
              style: TextStyle(
                color: today ? palette.route : palette.mutedInk,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              MaterialLocalizations.of(context).formatDecimal(day.day),
              style: TextStyle(
                color: today ? palette.ink : palette.mutedInk,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            switch (status) {
              'played' => GameArt(ArtKind.check, palette: palette, size: 26),
              'protected' => GameArt(
                ArtKind.freeze,
                palette: palette,
                size: 26,
              ),
              _ => Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.cardEdge, width: 2),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }
}
