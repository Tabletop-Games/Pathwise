import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/expedition.dart';
import '../model/user_preferences.dart';
import 'main_menu_view.dart';
import 'puzzle_view.dart';

class ExpeditionView extends StatefulWidget {
  const ExpeditionView({super.key});

  @override
  State<ExpeditionView> createState() => _ExpeditionViewState();
}

class _ExpeditionViewState extends State<ExpeditionView> {
  Trail? _selected;
  Trail? _recordTrail;
  Future<TrailRecord?>? _record;

  Future<void> _chooseTrail(AppModel model, Trail current) async {
    var input = '';
    final trail = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final number = int.tryParse(input);
          final valid = number != null && model.trailUnlocked(Trail(number));
          return AlertDialog(
            title: const Text('Find a trail'),
            content: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Trail number',
                hintText: '1 to ${model.currentTrail.number}',
              ),
              onChanged: (text) => update(() => input = text.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(context, number) : null,
                child: const Text('Show trail'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted && trail != null && trail != current.number) {
      setState(() => _selected = Trail(trail));
    }
  }

  Future<void> _play(BuildContext context, AppModel model, Trail trail) async {
    if (model.expeditionSaving) return;
    if (model.expedition?.active != true &&
        !await model.startExpedition(trail)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This expedition could not be saved.')),
        );
      }
      return;
    }
    final puzzle = model.expeditionPuzzle;
    if (context.mounted && puzzle != null) {
      setState(() => _selected = null);
      await openPuzzle(context, puzzle);
    }
  }

  Future<void> _end(BuildContext context, AppModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this run?'),
        content: const Text(
          'This records an abandoned run. Trail coins already earned stay in your balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End run'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await model.abandonExpedition();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final palette = BoardPalette.palettes[model.theme]!;
    final run = model.expedition;
    final active = run?.active == true ? run : null;
    final trail = active?.trail ?? _selected ?? model.currentTrail;
    if (_recordTrail != trail) {
      _recordTrail = trail;
      _record = model.loadTrailRecord(trail);
    }
    final milestone = economy.nextExpeditionMilestone(
      model.currentTrail.number,
    );
    final next = model.currentTrail.next;
    final accent = [
      palette.route,
      palette.covered,
      palette.accent,
      palette.tile,
      palette.route,
    ][trail.biome];
    final onAccent = switch (trail.biome) {
      0 || 4 => palette.onRoute,
      2 => palette.onAccent,
      _ => palette.ink,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expedition'),
        actions: [
          if (active == null)
            IconButton(
              tooltip: 'Find a trail',
              onPressed: () => _chooseTrail(model, trail),
              icon: const Icon(Icons.search_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.terrain_rounded, color: onAccent, size: 36),
                        const SizedBox(height: 8),
                        Text(
                          'Trail ${trail.number} · ${trail.title}',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: onAccent,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${trail.difficultyLabel} · ${model.trailsQualified} qualified\nNext milestone: Trail $milestone\nSolve 10 stages and earn any 2 of 4 field marks. Assistance only affects the mark. Your run is saved when you leave.',
                          style: TextStyle(color: onAccent),
                        ),
                      ],
                    ),
                  ),
                ),
                if (run != null && !run.active) ...[
                  const SizedBox(height: 16),
                  ExpeditionSummary(run: run),
                ],
                if (active == null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Previous trail',
                        onPressed: trail.number > 1
                            ? () => setState(
                                () => _selected = Trail(trail.number - 1),
                              )
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next unlocked trail',
                        onPressed: trail.number < model.currentTrail.number
                            ? () => setState(() => _selected = trail.next)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                      if (trail != model.currentTrail)
                        TextButton(
                          onPressed: () => setState(() => _selected = null),
                          child: const Text('Current trail'),
                        ),
                    ],
                  ),
                ],
                FutureBuilder<TrailRecord?>(
                  future: _record,
                  builder: (context, snapshot) => _TrailCard(
                    trail: trail,
                    palette: palette,
                    run: active,
                    record:
                        model.trailRecord(trail) ??
                        (snapshot.connectionState == ConnectionState.done
                            ? snapshot.data
                            : null),
                    claimed: (stage) => model.trailRewardClaimed(trail, stage),
                    play: !model.expeditionSaving
                        ? () => _play(context, model, trail)
                        : null,
                    end: () => _end(context, model),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: Text('Ahead · Trail ${next.number} · ${next.title}'),
                  subtitle: Text(
                    'Qualify on Trail ${model.currentTrail.number} to unlock.',
                  ),
                ),
                if (model.expeditionHistory.length > 1) ...[
                  const SizedBox(height: 14),
                  ExpansionTile(
                    title: const Text('Recent runs'),
                    children: [
                      for (final past in model.expeditionHistory.reversed.take(
                        5,
                      ))
                        ListTile(
                          title: Text(
                            '${past.trail.title} · ${_outcome(past)}',
                          ),
                          subtitle: Text(
                            '${past.stage}/${Trail.stages} stages · ${past.marks.length}/4 marks',
                          ),
                          trailing: Text(
                            formatTime(
                              Duration(milliseconds: past.milliseconds),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (model.storageError)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Progress couldn’t be saved.'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailCard extends StatelessWidget {
  const _TrailCard({
    required this.trail,
    required this.palette,
    required this.run,
    required this.record,
    required this.play,
    required this.claimed,
    required this.end,
  });
  final Trail trail;
  final BoardPalette palette;
  final ExpeditionRun? run;
  final TrailRecord? record;
  final VoidCallback? play;
  final bool Function(int) claimed;
  final VoidCallback end;

  @override
  Widget build(BuildContext context) => Card(
    color: palette.surface,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trail.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            record?.fastest != null
                ? 'Best qualifying time ${formatTime(Duration(milliseconds: record!.fastest!))}'
                : 'First qualifying run earns ${economy.expeditionReward(trail.number, Trail.stages, qualified: true)} coins.',
          ),
          if (record case final best?)
            Text('Furthest ${best.deepest}/10 · Best marks ${best.marks}/4'),
          ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var stage = 0; stage < Trail.stages; stage++)
                  _Waypoint(
                    trail: trail,
                    stage: stage,
                    run: run,
                    palette: palette,
                    claimed: claimed(stage + 1),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            for (final objective in trail.objectives.entries)
              Text('Stage ${objective.key + 1} · ${objective.value.label}'),
            if (run != null)
              Text(
                '${run!.marks.length} of 4 marks · ${run!.marks.length >= Trail.requiredMarks ? 'Marks secured' : 'Two needed to qualify'}',
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final (icon, label) in [
                  (Icons.diamond_outlined, 'Field mark'),
                  (Icons.star_rounded, 'Coin milestone'),
                  (Icons.check_rounded, 'Claimed'),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: palette.muted, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(color: palette.muted),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: play,
                  child: Text(
                    run == null
                        ? 'Start ${trail.title}'
                        : 'Resume stage ${run!.stage + 1}',
                  ),
                ),
                if (run != null)
                  TextButton(onPressed: end, child: const Text('End run')),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _Waypoint extends StatelessWidget {
  const _Waypoint({
    required this.trail,
    required this.stage,
    required this.run,
    required this.palette,
    required this.claimed,
  });
  final Trail trail;
  final bool claimed;
  final int stage;
  final ExpeditionRun? run;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    final mark = trail.objectives[stage];
    final reward = economy.expeditionReward(
      trail.number,
      stage + 1,
      qualified: true,
    );
    final milestone = reward > 0;
    final current = run?.stage == stage;
    final cleared = stage < (run?.stage ?? 0);
    final scaled = MediaQuery.textScalerOf(context).scale(14);
    final label =
        'Stage ${stage + 1}'
        '${mark == null ? '' : ', ${mark.label}'}'
        '${milestone
            ? claimed
                  ? ', coins already claimed'
                  : ', $reward coins on first ${stage == Trail.stages - 1 ? 'qualification' : 'clear'}'
            : ''}'
        '${current
            ? ', current'
            : cleared
            ? ', cleared'
            : ''}';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Container(
          width: 12 + scaled * 2,
          height: 34 + scaled,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: current
                ? palette.route
                : cleared
                ? palette.covered
                : palette.tile,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${stage + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: current ? palette.onRoute : palette.ink,
                ),
              ),
              if (mark != null || milestone)
                Icon(
                  mark != null
                      ? Icons.diamond_outlined
                      : claimed
                      ? Icons.check_rounded
                      : Icons.star_rounded,
                  size: 13,
                  color: current ? palette.onRoute : palette.ink,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _outcome(ExpeditionRun run) => switch (run.outcome) {
  ExpeditionOutcome.active => 'In progress',
  ExpeditionOutcome.qualified => 'Trail qualified',
  ExpeditionOutcome.missedMarks => 'Qualification missed',
  ExpeditionOutcome.abandoned => 'Run abandoned',
};

class ExpeditionSummary extends StatelessWidget {
  const ExpeditionSummary({required this.run, super.key});
  final ExpeditionRun run;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_outcome(run), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(
            'Trail ${run.trail.number} · ${run.trail.title} · ${run.stage}/10 stages · ${run.marks.length}/4 marks',
          ),
          Text(
            '${formatTime(Duration(milliseconds: run.milliseconds))} active · ${run.coins} coins earned',
          ),
          if (run.outcome == ExpeditionOutcome.missedMarks)
            const Text(
              'Earn at least two field marks to qualify on your next run.',
            ),
          if (run.outcome == ExpeditionOutcome.qualified)
            for (final theme in PathwiseTheme.values.where(
              (theme) => theme.expeditionTrail == run.trail.number,
            ))
              Text('${theme.label} is available in the Vault.'),
          if (run.milestoneCoins > 0)
            Text(
              'Trail ${run.trail.number} milestone · +${run.milestoneCoins} coins',
            ),
        ],
      ),
    ),
  );
}
