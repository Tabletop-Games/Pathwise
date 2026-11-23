import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/economy_activity.dart';
import '../model/field_notes.dart';

class FieldNotesView extends StatelessWidget {
  const FieldNotesView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final day = model.fieldNotesDay;
    final notes = model.notes;
    final week = FieldNotes.weekFor(day);
    return Scaffold(
      appBar: AppBar(title: const Text('Field Notes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Daily objectives',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Three objectives rotate at 00:00 UTC. Collect completed rewards before the next day.',
            ),
            for (final goal in FieldNotes.goals(day))
              _Objective(
                title: goal.title,
                count: notes.count(goal, day),
                target: goal.target,
                coins: model.dailyNoteCoins,
                ready: notes.claimable(goal, day),
                claimed: notes.wasClaimed(goal, day),
                claim: () => model.claimFieldNote(goal),
              ),
            const SizedBox(height: 16),
            Text(
              'Weekly objective',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            _Objective(
              title: 'Puzzle clears this week',
              count: week == notes.week ? notes.weekly : 0,
              target: FieldNotes.weeklyTarget,
              coins: FieldNotes.weeklyCoins,
              ready: notes.claimable(null, day),
              claimed: notes.wasClaimed(null, day),
              claim: () => model.claimFieldNote(null),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('Economy activity'),
              subtitle: const Text('Anonymous counters stored on this device'),
              children: [
                for (final event in EconomyEvent.values)
                  if (model.activity.counts[event.name] case final total?)
                    ListTile(
                      title: Text(event.label),
                      trailing: Text('$total'),
                    ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: jsonEncode(model.activity.toJson())),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Economy counters copied.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Copy anonymous counters'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Objective extends StatelessWidget {
  const _Objective({
    required this.title,
    required this.count,
    required this.target,
    required this.coins,
    required this.ready,
    required this.claimed,
    required this.claim,
  });
  final String title;
  final int count, target, coins;
  final bool ready, claimed;
  final VoidCallback claim;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text('$count / $target · $coins coins'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (count / target).clamp(0, 1)),
          if (claimed)
            const Text('Collected')
          else if (ready)
            TextButton(onPressed: claim, child: const Text('Collect')),
        ],
      ),
    ),
  );
}
