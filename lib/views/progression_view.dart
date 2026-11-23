import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/social_sharing.dart';

import '../model/app_model.dart';
import '../model/economy_activity.dart';
import '../model/progression.dart';
import 'share_view.dart';

class ProgressionView extends StatefulWidget {
  const ProgressionView({this.boosts = false, super.key});
  final bool boosts;

  @override
  State<ProgressionView> createState() => _ProgressionViewState();
}

class _ProgressionViewState extends State<ProgressionView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (!widget.boosts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final model = context.read<AppModel>();
        final research = model.progression;
        final open = Research.values.where(
          (item) => research.unlocked(item) && research.rank(item) < item.limit,
        );
        final affordable = open
            .where(
              (item) => item.price(research.rank(item)) <= model.coinBalance,
            )
            .length;
        model.recordActivity(EconomyEvent.researchAffordable, affordable);
        model.recordActivity(
          EconomyEvent.researchUnavailable,
          open.length - affordable,
        );
      });
    }
    if (widget.boosts) {
      _tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final progression = model.progression;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.boosts ? 'Boosts' : 'Research'),
        actions: [
          Center(child: Text('${model.coinBalance} coins')),
          const SizedBox(width: 20),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 630),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: widget.boosts
                  ? [
                      for (final boost in Boost.values)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(13),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  boost.title,
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(
                                  '${boost.minutes} min · ${progression.inventory[boost.name] ?? 0} in inventory',
                                ),
                                if (progression.remaining(
                                      boost,
                                      model.progressionTime,
                                    )
                                    case final remaining when remaining > 0)
                                  Text(
                                    '${Duration(milliseconds: remaining).inMinutes}m ${Duration(milliseconds: remaining).inSeconds % 60}s active',
                                  ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed:
                                          model.coinBalance >=
                                              progression.discount(boost.price)
                                          ? () => model.buyBoost(boost)
                                          : null,
                                      child: Text(
                                        'Buy · ${progression.discount(boost.price)}',
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed:
                                          progression.canActivate(
                                            boost,
                                            model.progressionTime,
                                          )
                                          ? () => model.activateBoost(boost)
                                          : null,
                                      child: const Text('Activate'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ]
                  : [
                      for (final (index, item) in Research.values.indexed) ...[
                        if (const {0, 4, 8, 12, 13}.contains(index))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(5, 14, 0, 8),
                            child: Text(switch (index) {
                              0 => 'Coin production',
                              4 => 'Supply crates',
                              8 => 'Efficiency',
                              12 => 'Rare finds',
                              _ => 'Long-term specializations',
                            }, style: theme.textTheme.headlineSmall),
                          ),
                        Card(
                          child: ListTile(
                            leading: Icon(
                              index < 4
                                  ? Icons.toll
                                  : index < 8
                                  ? Icons.inventory_2_outlined
                                  : Icons.science_outlined,
                            ),
                            title: Text(item.title),
                            subtitle: Text(
                              'Rank ${progression.rank(item)} / ${item.limit}\n'
                              '${item.benefit} · +${progression.effect(item)}'
                              '${progression.rank(item) < item.limit ? ' → +${item.effectAt(progression.rank(item) + 1)}' : ''}'
                              '${!progression.unlocked(item) ? '\nRequires ${item.prerequisite!.title} rank 3' : ''}',
                            ),
                            trailing: progression.rank(item) >= item.limit
                                ? IconButton(
                                    tooltip: 'Share Research Milestone',
                                    icon: const Icon(Icons.share_outlined),
                                    onPressed: () =>
                                        Navigator.of(context).push<void>(
                                          MaterialPageRoute(
                                            builder: (_) => ShareView(
                                              result: ShareResult.research(
                                                item.title,
                                                item.limit,
                                              ),
                                            ),
                                          ),
                                        ),
                                  )
                                : OutlinedButton(
                                    onPressed:
                                        progression.unlocked(item) &&
                                            model.coinBalance >=
                                                item.price(
                                                  progression.rank(item),
                                                )
                                        ? () => model.research(item)
                                        : null,
                                    child: Text(
                                      progression.unlocked(item)
                                          ? '${item.price(progression.rank(item))} coins'
                                          : 'Locked',
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
