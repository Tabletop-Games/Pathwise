import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/economy_activity.dart';
import '../model/progression.dart';
import 'share_view.dart';

class ProgressionEntrances extends StatelessWidget {
  const ProgressionEntrances({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final researched = Research.values
        .where((item) => model.progression.rank(item) > 0)
        .length;
    final owned = Boost.values.fold(
      0,
      (sum, item) => sum + (model.progression.inventory[item.name] ?? 0),
    );
    final active = Boost.values
        .where(
          (boost) =>
              model.progression.remaining(boost, model.progressionTime) > 0,
        )
        .length;
    Widget entry({required bool boosts}) {
      return _Panel(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => ProgressionView(boosts: boosts)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  boosts ? Icons.bolt_rounded : Icons.hub_outlined,
                  color: boosts
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  boosts ? 'Boosts' : 'Research',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  boosts
                      ? (active > 0
                            ? '$active active · $owned in reserve'
                            : owned == 0
                            ? 'Timed effects'
                            : '$owned in reserve')
                      : (researched == 0
                            ? 'Permanent upgrades'
                            : researched == 1
                            ? '1 upgrade begun'
                            : '$researched upgrades begun'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 295 ||
            MediaQuery.textScalerOf(context).scale(16) > 22) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              entry(boosts: false),
              const SizedBox(height: 8),
              entry(boosts: true),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: entry(boosts: false)),
              const SizedBox(width: 10),
              Expanded(child: entry(boosts: true)),
            ],
          ),
        );
      },
    );
  }
}

enum _ResearchBranch {
  income('Coin rewards', Icons.toll_outlined, [
    Research.magnet,
    Research.golden,
    Research.fortune,
    Research.mastery,
    Research.momentum,
    Research.specialist,
  ]),
  supplies('Supply crates', Icons.inventory_2_outlined, [
    Research.hunter,
    Research.collector,
    Research.scout,
  ]),
  efficiency('Efficiency', Icons.tune_rounded, [
    Research.efficiency,
    Research.savings,
    Research.tuning,
    Research.procurement,
  ]);

  const _ResearchBranch(this.title, this.icon, this.items);
  final String title;
  final IconData icon;
  final List<Research> items;
}

class ProgressionView extends StatefulWidget {
  const ProgressionView({this.boosts = false, super.key});
  final bool boosts;

  @override
  State<ProgressionView> createState() => _ProgressionViewState();
}

class _ProgressionViewState extends State<ProgressionView> {
  Timer? _tick;
  var _branch = _ResearchBranch.income;

  @override
  void initState() {
    super.initState();
    if (widget.boosts) {
      _tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final model = context.read<AppModel>();
        final open = Research.values.where(
          (item) =>
              model.progression.unlocked(item) &&
              model.progression.rank(item) < item.limit,
        );
        final affordable = open
            .where(
              (item) =>
                  item.price(model.progression.rank(item)) <= model.coinBalance,
            )
            .length;
        model.recordActivity(EconomyEvent.researchAffordable, affordable);
        model.recordActivity(
          EconomyEvent.researchUnavailable,
          open.length - affordable,
        );
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _duration(int milliseconds) {
    final seconds = (milliseconds + 999) ~/ 1000;
    return seconds % 60 == 0
        ? '${seconds ~/ 60} min'
        : '${seconds ~/ 60}m ${seconds % 60}s';
  }

  void _feedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final progression = model.progression;
    final now = model.progressionTime;
    final ranks = Research.values.fold(
      0,
      (total, item) => total + progression.rank(item),
    );
    final rankLimit = Research.values.fold(
      0,
      (total, item) => total + item.limit,
    );
    final owned = Boost.values.fold(
      0,
      (total, item) => total + (progression.inventory[item.name] ?? 0),
    );
    final active = Boost.values
        .where((boost) => progression.remaining(boost, now) > 0)
        .length;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: Text(widget.boosts ? 'Boosts' : 'Research'),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              children: [
                _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          widget.boosts
                              ? Icons.bolt_rounded
                              : Icons.hub_outlined,
                          color: widget.boosts
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.primary,
                          size: 35,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.boosts ? 'Boost reserve' : 'Research lab',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _Detail(
                          widget.boosts
                              ? '$owned ready to activate · $active active'
                              : '$ranks of $rankLimit ranks developed',
                        ),
                        if (!widget.boosts)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _Meter(ranks / rankLimit),
                          ),
                        const SizedBox(height: 12),
                        _Detail(
                          '${model.coinBalance} coins available',
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (widget.boosts) ...[
                  const _Heading('Coin multipliers'),
                  for (final boost in Boost.values.where(
                    (item) => item.multiplier > 1,
                  ))
                    _boost(model, boost, now),
                  const _Heading('Supply boosts'),
                  for (final boost in Boost.values.where(
                    (item) => item.multiplier == 1,
                  ))
                    _boost(model, boost, now),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final branch in _ResearchBranch.values)
                        ChoiceChip(
                          label: Text(branch.title),
                          avatar: Icon(
                            branch.icon,
                            size: 17,
                            color: _branch == branch
                                ? Theme.of(context).colorScheme.surface
                                : Theme.of(context).colorScheme.primary,
                          ),
                          labelStyle: TextStyle(
                            color: _branch == branch
                                ? Theme.of(context).colorScheme.surface
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          showCheckmark: false,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          selected: _branch == branch,
                          onSelected: (_) => setState(() => _branch = branch),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final item in _branch.items) _research(model, item),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _research(AppModel model, Research item) {
    final progress = model.progression;
    final rank = progress.rank(item);
    final mastered = rank == item.limit;
    final unlocked = progress.unlocked(item);
    final price = mastered ? 0 : item.price(rank);
    final shortfall = price - model.coinBalance;
    return _Upgrade(
      title: item.title,
      icon: _branch.icon,
      state: mastered ? 'Mastered' : 'Rank $rank / ${item.limit}',
      progress: rank / item.limit,
      effect: item.benefit,
      description: mastered
          ? 'Current benefit +${item.effectAt(rank)}'
          : 'Current +${item.effectAt(rank)} · Next +${item.effectAt(rank + 1)}',
      action: mastered
          ? _SecondaryAction(
              label: 'Share milestone',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ShareView(
                    result: ShareResult.research(item.title, item.limit),
                  ),
                ),
              ),
            )
          : unlocked
          ? _PrimaryAction(
              label: 'Upgrade · $price coins',
              onPressed: !model.storageError && shortfall <= 0
                  ? () {
                      if (model.research(item))
                        _feedback('${item.title} reached rank ${rank + 1}');
                    }
                  : null,
            )
          : null,
      availability: !unlocked
          ? 'Requires ${item.prerequisite!.title} rank 3'
          : shortfall > 0
          ? '$shortfall more coins needed'
          : null,
    );
  }

  Widget _boost(AppModel model, Boost boost, int now) {
    final progress = model.progression;
    final inventory = progress.inventory[boost.name] ?? 0;
    final remaining = progress.remaining(boost, now);
    final duration = boost.minutes * 600 * (100 + progress.durationBonus);
    final price = progress.discount(boost.price);
    final canActivate = !model.storageError && progress.canActivate(boost, now);
    return _Upgrade(
      title: switch (boost) {
        Boost.crateFrequency => 'Supply relay',
        _ => '${boost.multiplier}× coin boost',
      },
      icon: boost.multiplier > 1
          ? Icons.bolt_rounded
          : Icons.inventory_2_outlined,
      state: '${_duration(duration)} · $inventory owned',
      progress: remaining > 0 ? remaining / duration : null,
      effect: boost.title,
      description: remaining > 0
          ? '${_duration(remaining)} remaining'
          : boost.multiplier > 1
          ? 'Applies to eligible puzzle clear rewards'
          : 'Applies to new supply crate drops',
      availability: !canActivate && inventory > 0 && remaining == 0
          ? 'Another coin boost is active'
          : null,
      action: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _SecondaryAction(
            label: 'Buy · $price coins',
            onPressed: !model.storageError && model.coinBalance >= price
                ? () {
                    if (model.buyBoost(boost))
                      _feedback('Added to your boost reserve');
                  }
                : null,
          ),
          _PrimaryAction(
            label: 'Activate',
            onPressed: canActivate
                ? () {
                    if (model.activateBoost(boost))
                      _feedback('Boost active for ${_duration(duration)}');
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(20),
    child: child,
  );
}

class _Upgrade extends StatelessWidget {
  const _Upgrade({
    required this.title,
    required this.icon,
    required this.state,
    required this.effect,
    required this.description,
    this.progress,
    this.availability,
    this.action,
  });
  final String title, state, effect, description;
  final String? availability;
  final IconData icon;
  final double? progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _Detail(state, color: Theme.of(context).colorScheme.primary),
            if (progress case final value?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _Meter(value),
              ),
            _Detail(effect, color: Theme.of(context).colorScheme.onSurface),
            _Detail(description),
            if (availability case final detail?)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: _Detail(
                  detail,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 10), child: action!),
          ],
        ),
      ),
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
    ),
  );
}

class _Meter extends StatelessWidget {
  const _Meter(this.value);
  final double value;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.clamp(0.0, 1.0)),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    builder: (_, amount, _) => LinearProgressIndicator(
      value: amount,
      minHeight: 5,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.outlineVariant,
      borderRadius: BorderRadius.circular(5),
    ),
  );
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.surface,
      backgroundColor: Theme.of(context).colorScheme.primary,
      disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      disabledBackgroundColor: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.primary,
      disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}
