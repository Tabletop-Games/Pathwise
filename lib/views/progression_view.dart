import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy_activity.dart';
import '../model/progression.dart';
import '../ui/art/medallion_art.dart';
import '../ui/art/research_art.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'components/economy_navigation.dart';
import 'store_view.dart';

enum _ResearchBranch {
  income('Coins', [
    Research.magnet,
    Research.golden,
    Research.fortune,
    Research.mastery,
    Research.momentum,
    Research.specialist,
  ]),
  supplies('Crates', [Research.hunter, Research.collector, Research.scout]),
  efficiency('Efficiency', [
    Research.efficiency,
    Research.savings,
    Research.tuning,
    Research.procurement,
  ]);

  const _ResearchBranch(this.title, this.items);
  final String title;
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
    final palette = BoardPalette.palettes[model.theme]!;
    final progression = model.progression;
    final now = model.progressionTime;
    final multipliers = Boost.values.where(
      (item) =>
          item.multiplier > 1 &&
          (item.availableToBuy ||
              (progression.inventory[item.name] ?? 0) > 0 ||
              progression.remaining(item, now) > 0),
    );
    final supplies = Boost.values.where(
      (item) =>
          item.multiplier == 1 &&
          ((progression.inventory[item.name] ?? 0) > 0 ||
              progression.remaining(item, now) > 0),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(palette),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          titleSpacing: 0,
          title: Text(
            widget.boosts ? 'Boosts' : 'Research',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
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
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: widget.boosts
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Temporary coin multipliers',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide =
                                constraints.maxWidth >= 350 &&
                                MediaQuery.textScalerOf(context).scale(16) <=
                                    19;
                            final width = wide
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                for (final boost in [
                                  ...multipliers,
                                  ...supplies,
                                ])
                                  SizedBox(
                                    width: width,
                                    child: _boost(model, boost, now),
                                  ),
                              ],
                            );
                          },
                        ),
                        if (multipliers.isEmpty && supplies.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Column(
                              children: [
                                GameArt(
                                  ArtKind.bolt,
                                  palette: palette,
                                  size: 72,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No boosts yet',
                                  style: TextStyle(
                                    color: palette.mutedInk,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                          child: GameSegmented<_ResearchBranch>(
                            selected: _branch,
                            onChanged: (value) =>
                                setState(() => _branch = value),
                            segments: [
                              for (final branch in _ResearchBranch.values)
                                (value: branch, label: branch.title),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            key: PageStorageKey('research-${_branch.name}'),
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            children: [
                              for (final item in _branch.items)
                                _research(model, item),
                            ],
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

  Widget _research(AppModel model, Research item) {
    final progress = model.progression;
    final rank = progress.rank(item);
    final mastered = rank == item.limit;
    final unlocked = progress.unlocked(item);
    final price = mastered ? 0 : item.price(rank);
    final shortfall = price - model.coinBalance;
    final palette = BoardPalette.palettes[model.theme]!;
    final Widget action;
    if (mastered) {
      action = ActionPill(
        label: 'Share',
        semanticLabel: 'Share ${item.title} milestone',
        onTap: () => const ShareDestinationService().open(
          ShareResult.research(item.title, item.limit),
          ShareDestination.android,
        ),
      );
    } else if (!unlocked) {
      action = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 104),
        child: Semantics(
          label: 'Requires ${item.prerequisite!.title} rank 3',
          excludeSemantics: true,
          child: InfoChip(
            icon: GameArt(ArtKind.lock, palette: palette, size: 16),
            label: '${item.prerequisite!.title} 3',
          ),
        ),
      );
    } else {
      action = PricePill(
        price: price,
        affordable: shortfall <= 0,
        semanticLabel: 'Upgrade ${item.title} for $price coins',
        onTap: model.storageError
            ? null
            : () {
                if (shortfall > 0) {
                  showInsufficientCoins(
                    context,
                    itemName: item.title,
                    requiredCoins: price,
                    currentBalance: model.coinBalance,
                  );
                } else if (model.research(item)) {
                  _feedback('${item.title} reached rank ${rank + 1}');
                }
              },
      );
    }
    final effect = mastered
        ? '+${item.effectAt(rank)}'
        : '+${item.effectAt(rank)} → +${item.effectAt(rank + 1)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Padding(
        key: ValueKey('research-${item.name}'),
        padding: const EdgeInsets.all(14),
        child: Opacity(
          opacity: unlocked ? 1 : .62,
          child: Row(
            children: [
              ResearchArtwork(item, palette: palette),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.benefit,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.mutedInk, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      effect,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: GameBar(value: rank / item.limit)),
                        const SizedBox(width: 8),
                        Semantics(
                          label: mastered
                              ? 'Mastered'
                              : 'Rank $rank of ${item.limit}',
                          excludeSemantics: true,
                          child: Text(
                            '$rank/${item.limit}',
                            style: TextStyle(
                              color: palette.mutedInk,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              action,
            ],
          ),
        ),
      ),
    );
  }

  Widget _boost(AppModel model, Boost boost, int now) {
    final progress = model.progression;
    final palette = BoardPalette.palettes[model.theme]!;
    final inventory = progress.inventory[boost.name] ?? 0;
    final remaining = progress.remaining(boost, now);
    final duration = boost.minutes * 600 * (100 + progress.durationBonus);
    final price = progress.discount(boost.price);
    final canActivate = !model.storageError && progress.canActivate(boost, now);
    final multiplier = boost.multiplier > 1;
    final watch =
        (boost == Boost.doubleTen || boost == Boost.tripleFifteen) &&
        context.watch<AdService>().enabled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Padding(
        key: ValueKey('boost-${boost.name}'),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (multiplier)
                  BoostArtwork(boost, palette: palette, size: 42)
                else
                  GameArt(ArtKind.crate, palette: palette, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        multiplier ? '${boost.multiplier}×' : 'Supply relay',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: multiplier ? 26 : 18,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Text(_duration(duration)),
                          if (inventory > 0) Text('$inventory ready'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (remaining > 0) ...[
              const SizedBox(height: 12),
              Text('${boost.multiplier}× active'),
              Text(
                '${_duration(remaining)} left',
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
              const SizedBox(height: 6),
              GameBar(value: remaining / duration),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (watch)
                  ActionPill(
                    label: 'Watch',
                    icon: Icons.play_arrow_rounded,
                    semanticLabel: 'Watch a video for one boost',
                    onTap: model.canEarnBoostAd(boost)
                        ? () async {
                            final ads = context.read<AdService>();
                            bool current() =>
                                mounted &&
                                ModalRoute.isCurrentOf(context) == true;
                            if (!ads.readyFor(RewardPlacement.boost)) {
                              await ads.prepare(canPresent: current);
                            }
                            if (!current()) return;
                            final shown = await ads.watchVideo(
                              (event) => model.grantBoostAd(boost, event),
                              placement: RewardPlacement.boost,
                              canPresent: () =>
                                  current() && model.canEarnBoostAd(boost),
                            );
                            if (!shown && current()) {
                              _feedback('Video unavailable');
                            }
                          }
                        : null,
                  ),
                if (boost.availableToBuy)
                  PricePill(
                    price: price,
                    affordable: model.coinBalance >= price,
                    semanticLabel: 'Buy ${boost.title} for $price coins',
                    onTap: model.storageError
                        ? null
                        : () {
                            if (model.coinBalance < price) {
                              showInsufficientCoins(
                                context,
                                itemName: boost.title,
                                requiredCoins: price,
                                currentBalance: model.coinBalance,
                              );
                            } else if (model.buyBoost(boost)) {
                              _feedback('Added to your boost reserve');
                            }
                          },
                  ),
                if (inventory > 0 && remaining <= 0)
                  ActionPill(
                    label: 'Activate',
                    tone: ActionTone.primary,
                    onTap: canActivate
                        ? () {
                            if (model.activateBoost(boost)) {
                              _feedback(
                                'Boost active for ${_duration(duration)}',
                              );
                            }
                          }
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
