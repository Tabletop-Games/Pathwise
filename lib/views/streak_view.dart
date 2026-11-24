import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/play_streak.dart';
import 'components/economy_navigation.dart';

class StreakView extends StatelessWidget {
  const StreakView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final streak = model.streak;
    final next = EconomyRules.milestones.entries
        .where((entry) => entry.key > streak.count)
        .firstOrNull;
    final today = PlayStreak.calendarDate(model.todayKey);
    return Scaffold(
      appBar: AppBar(title: const Text('Daily streak')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            Text(
              '${streak.count} days',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text(
              'Longest: ${streak.longest} days',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 8,
              children: [
                for (var index = 6; index >= 0; index--)
                  Builder(
                    builder: (context) {
                      final day = today.subtract(Duration(days: index));
                      final status = streak.days[dayKey(day)];
                      return Column(
                        children: [
                          Text(
                            MaterialLocalizations.of(context)
                                .formatDecimal(day.day),
                          ),
                          Icon(switch (status) {
                            'played' => Icons.check_circle_outline,
                            'protected' => Icons.ac_unit,
                            _ => Icons.circle_outlined,
                          }, semanticLabel: status ?? 'No qualifying puzzle'),
                        ],
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (next != null)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text('Day ${next.key}'),
                subtitle: Text(
                  '${next.value.coins} coins · ${next.value.hints} hints',
                ),
              ),
            ListTile(
              leading: const Icon(Icons.ac_unit),
              title: const Text('Streak Freeze'),
              subtitle: Text(
                '${streak.freezes} of ${economy.maxFreezes} owned',
              ),
            ),
            FilledButton.icon(
              onPressed:
                  model.storageError || streak.freezes >= economy.maxFreezes
                  ? null
                  : () {
                      if (model.coinBalance < economy.freezePrice) {
                        showInsufficientCoins(
                          context,
                          itemName: 'Streak Freeze',
                          requiredCoins: economy.freezePrice,
                          currentBalance: model.coinBalance,
                        );
                      } else {
                        model.buyFreeze();
                      }
                    },
              icon: const Icon(Icons.toll_rounded),
              label: Text('Buy Freeze · ${economy.freezePrice} coins'),
            ),
          ],
        ),
      ),
    );
  }
}
