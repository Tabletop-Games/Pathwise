import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/economy_activity.dart';
import '../model/progression.dart';
import '../ui/art/game_assets.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'components/economy_navigation.dart';
import 'store_view.dart';

enum _ProgressionTab {
  research('Research'),
  boosts('Boosts');

  const _ProgressionTab(this.label);
  final String label;
}

enum _ResearchBranch {
  income(
    'Coins',
    'Permanent boosts to puzzle, streak, and milestone coin payouts.',
    'assets/art/resources/coin_stack_2.webp',
    ArtKind.coinStack2,
    [
      Research.magnet,
      Research.golden,
      Research.fortune,
      Research.mastery,
      Research.momentum,
      Research.specialist,
    ],
  ),
  supplies(
    'Crates',
    'Increase falling supply crate frequency and reward capacity.',
    'assets/art/resources/crate.webp',
    ArtKind.crate,
    [Research.hunter, Research.collector, Research.scout],
  ),
  efficiency(
    'Efficiency',
    'Extend boost timers and reduce upgrade and boost costs.',
    'assets/art/ui/boost.webp',
    ArtKind.bolt,
    [
      Research.efficiency,
      Research.savings,
      Research.tuning,
      Research.procurement,
    ],
  );

  const _ResearchBranch(
    this.title,
    this.summary,
    this.assetPath,
    this.fallbackArt,
    this.items,
  );
  final String title;
  final String summary;
  final String assetPath;
  final ArtKind fallbackArt;
  final List<Research> items;
}

String _researchAssetPath(Research item) => switch (item) {
  Research.magnet => 'assets/art/resources/coin.webp',
  Research.golden => 'assets/art/resources/coin_stack_2.webp',
  Research.fortune => 'assets/art/ui/wheel_ticket.webp',
  Research.mastery => 'assets/art/ui/achievement.webp',
  Research.momentum => 'assets/art/ui/flame.webp',
  Research.specialist => 'assets/art/resources/coin_stack_3.webp',
  Research.hunter => 'assets/art/resources/crate.webp',
  Research.collector => 'assets/art/resources/chest_open.webp',
  Research.scout => 'assets/art/ui/compass.webp',
  Research.efficiency => 'assets/art/ui/timer.webp',
  Research.savings => 'assets/art/resources/coin_stack_1.webp',
  Research.tuning => 'assets/art/ui/boost.webp',
  Research.procurement => 'assets/art/resources/hint.webp',
};

String _compactDuration(int ms) {
  final totalSeconds = (ms / 1000).round();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
  }
  if (minutes > 0) {
    return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
  }
  return '${seconds}s';
}

String _formatEffect(Research item, int value) => switch (item) {
  Research.magnet ||
  Research.golden ||
  Research.fortune ||
  Research.mastery ||
  Research.momentum ||
  Research.specialist => '+$value coins',
  Research.hunter || Research.scout => '-${value}s',
  Research.collector => '+${value}s',
  Research.efficiency ||
  Research.savings ||
  Research.tuning ||
  Research.procurement => '+$value%',
};

String _researchEffectText(Research item, int rank, bool mastered) {
  final current = item.effectAt(rank);
  if (mastered) return _formatEffect(item, current);
  final next = item.effectAt(rank + 1);
  return switch (item) {
    Research.magnet ||
    Research.golden ||
    Research.fortune ||
    Research.mastery ||
    Research.momentum ||
    Research.specialist => '+$current → +$next coins',
    _ => '${_formatEffect(item, current)} → ${_formatEffect(item, next)}',
  };
}

class ProgressionView extends StatefulWidget {
  const ProgressionView({this.boosts = false, super.key});
  final bool boosts;

  @override
  State<ProgressionView> createState() => _ProgressionViewState();
}

class _ProgressionViewState extends State<ProgressionView> {
  late _ProgressionTab _tab;
  var _branch = _ResearchBranch.income;
  var _recordedResearchActivity = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.boosts ? _ProgressionTab.boosts : _ProgressionTab.research;
    if (_tab == _ProgressionTab.research) {
      _scheduleResearchActivity();
    }
  }

  void _scheduleResearchActivity() {
    if (_recordedResearchActivity) return;
    _recordedResearchActivity = true;
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

  void _selectTab(_ProgressionTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (tab == _ProgressionTab.research) {
      _scheduleResearchActivity();
    }
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
    final active = Boost.values
        .where((boost) => progression.remaining(boost, now) > 0)
        .toList();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(palette),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          titleSpacing: 0,
          title: const Text(
            'Upgrades',
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
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: GameSegmented<_ProgressionTab>(
                        selected: _tab,
                        onChanged: _selectTab,
                        segments: [
                          for (final tab in _ProgressionTab.values)
                            (value: tab, label: tab.label),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _tab == _ProgressionTab.boosts
                          ? _boostsBody(model, palette, active, now)
                          : _researchBody(model, palette),
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

  Widget _researchBody(AppModel model, BoardPalette palette) {
    final tier1 = _branch.items.where((item) => !item.advanced).toList();
    final tier2 = _branch.items.where((item) => item.advanced).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _researchHeader(model, palette),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: GameSegmented<_ResearchBranch>(
            selected: _branch,
            onChanged: (value) => setState(() => _branch = value),
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
              if (tier1.isNotEmpty) ...[
                _researchSectionHeader('Tier 1 · Foundations', palette),
                for (final item in tier1) _research(model, item),
              ],
              if (tier2.isNotEmpty) ...[
                if (tier1.isNotEmpty) const SizedBox(height: 6),
                _researchSectionHeader('Tier 2 · Advanced Contracts', palette),
                for (final item in tier2) _research(model, item),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _researchSectionHeader(String title, BoardPalette palette) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: palette.mutedInk,
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: palette.cardEdge),
      ],
    ),
  );

  Widget _boostsBody(
    AppModel model,
    BoardPalette palette,
    List<Boost> active,
    int now,
  ) {
    Widget buildList(BuildContext context) {
      final progress = model.progression;
      final currentNow = model.progressionTime;
      final currentActive = [
        for (final boost in Boost.values)
          if (progress.remaining(boost, currentNow) > 0) boost,
      ];
      final owned = Boost.values
          .where((boost) => (progress.inventory[boost.name] ?? 0) > 0)
          .toList();
      final adsEnabled = context.watch<AdService>().enabled;

      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
        children: [
          if (currentActive.isNotEmpty)
            _activeBoostStrip(model, palette, currentActive, currentNow),
          _boostSectionHeader('Your inventory', palette),
          if (owned.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Text(
                'No boosts in your inventory',
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
            ),
          for (final boost in owned)
            _boostRow(
              key: ValueKey('boost-inventory-${boost.name}'),
              boost: boost,
              palette: palette,
              details: _boostDetails(progress, boost),
              quantity: progress.inventory[boost.name],
              actions: [
                ActionPill(
                  label: 'Activate',
                  semanticLabel: 'Activate ${boost.title}',
                  tone: ActionTone.primary,
                  onTap:
                      !model.storageError &&
                          progress.canActivate(boost, currentNow)
                      ? () => model.activateBoost(boost)
                      : null,
                ),
              ],
            ),
          const SizedBox(height: 10),
          _boostSectionHeader('Boost Shop', palette),
          for (final boost in Boost.values.where(
            (boost) => boost.availableToBuy,
          ))
            _boostRow(
              key: ValueKey('boost-shop-${boost.name}'),
              boost: boost,
              palette: palette,
              details: _boostDetails(progress, boost),
              actions: [
                if (adsEnabled &&
                    (boost == Boost.doubleTen || boost == Boost.tripleFifteen))
                  _boostVideoAction(model, boost),
                _boostPurchaseAction(model, boost),
              ],
            ),
        ],
      );
    }

    if (active.isEmpty) return buildList(context);
    return _ActiveBoostTicker(builder: buildList);
  }

  Widget _boostSectionHeader(String title, BoardPalette palette) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: TextStyle(
          color: palette.ink,
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
    ),
  );

  Widget _activeBoostStrip(
    AppModel model,
    BoardPalette palette,
    List<Boost> active,
    int now,
  ) {
    final progress = model.progression;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GameCard(
        selected: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GameArt(ArtKind.bolt, palette: palette, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Active boosts',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.route,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            for (final boost in active) ...[
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final remaining = progress.remaining(boost, now);
                  final totalDuration = progress.boostDurationMs(boost);
                  return Row(
                    children: [
                      _boostArtworkBadge(boost, palette, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 2,
                              children: [
                                Text(
                                  boost.multiplier > 1
                                      ? '${boost.multiplier}× ${boost.title}'
                                      : boost.title,
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  '${_duration(remaining)} left',
                                  style: TextStyle(
                                    color: palette.route,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            GameBar(
                              value: remaining / totalDuration,
                              height: 5,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _researchHeader(AppModel model, BoardPalette palette) {
    final progress = model.progression;
    var earnedRanks = 0;
    var totalRanks = 0;
    Research? masteredItem;
    for (final item in _branch.items) {
      final r = progress.rank(item);
      earnedRanks += r;
      totalRanks += item.limit;
      if (r == item.limit) {
        masteredItem = item;
      }
    }
    return GameCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.quiet,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.cardEdge),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: SizedBox.square(
                dimension: 42,
                child: Image.asset(
                  _branch.assetPath,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      GameArt(_branch.fallbackArt, palette: palette, size: 42),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_branch.title} lab',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    InfoChip(
                      icon: GameArt(ArtKind.trophy, palette: palette, size: 14),
                      label: '$earnedRanks of $totalRanks',
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _branch.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.mutedInk, fontSize: 12),
                ),
              ],
            ),
          ),
          if (masteredItem != null)
            IconButton(
              icon: Icon(Icons.share_outlined, color: palette.mutedInk),
              tooltip: 'Share ${masteredItem.title} milestone',
              onPressed: () => const ShareDestinationService().open(
                ShareResult.research(masteredItem!.title, masteredItem.limit),
                ShareDestination.android,
              ),
            ),
        ],
      ),
    );
  }

  Widget _researchArtworkBadge(Research item, BoardPalette palette) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: palette.quiet,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.cardEdge),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox.square(
            dimension: 38,
            child: Image.asset(
              _researchAssetPath(item),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  GameArt(ArtKind.research, palette: palette, size: 38),
            ),
          ),
        ),
      );

  Widget _boostArtworkBadge(
    Boost boost,
    BoardPalette palette, {
    double size = 56,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: boost.multiplier >= 3
          ? Color.lerp(palette.quiet, palette.accent, .16)
          : palette.quiet,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: boost.multiplier >= 3
            ? palette.accent.withValues(alpha: .5)
            : palette.cardEdge,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox.square(
        dimension: size - 12,
        child: Image.asset(
          boostAssetPath(boost),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => boost.multiplier > 1
              ? GameArt(ArtKind.bolt, palette: palette, size: size - 12)
              : GameArt(ArtKind.crate, palette: palette, size: size - 12),
        ),
      ),
    ),
  );

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
      action = const ActionPill(label: 'MAX', tone: ActionTone.selected);
    } else if (!unlocked) {
      action = Semantics(
        label: 'Requires ${item.prerequisite!.title} rank 3',
        excludeSemantics: true,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: palette.quiet,
            borderRadius: BorderRadius.circular(GameTokens.pillRadius),
            border: Border.all(color: palette.cardEdge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GameArt(ArtKind.lock, palette: palette, size: 15),
              const SizedBox(width: 5),
              Text(
                'Locked',
                style: TextStyle(
                  color: palette.mutedInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
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
    final effect = _researchEffectText(item, rank, mastered);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GameCard(
        key: ValueKey('research-${item.name}'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _researchArtworkBadge(item, palette),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unlocked ? palette.ink : palette.mutedInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.benefit,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.mutedInk, fontSize: 12),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        effect,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unlocked ? palette.route : palette.mutedInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                action,
              ],
            ),
            if (!unlocked && item.prerequisite != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  GameArt(ArtKind.lock, palette: palette, size: 13),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Requires ${item.prerequisite!.title} rank 3',
                      style: TextStyle(
                        color: palette.mutedInk,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: GameBar(value: rank / item.limit, height: 7)),
                const SizedBox(width: 8),
                Semantics(
                  label: mastered ? 'Mastered' : 'Rank $rank of ${item.limit}',
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
    );
  }

  String _boostDetails(Progression progress, Boost boost) {
    final duration = progress.boostDurationMs(boost);
    final effect = boost == Boost.crateFrequency
        ? '2× crate drop rate'
        : '${boost.multiplier}×';
    return '$effect · ${_compactDuration(duration)}';
  }

  Widget _boostRow({
    required Key key,
    required Boost boost,
    required BoardPalette palette,
    required String details,
    required List<Widget> actions,
    int? quantity,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GameCard(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < (actions.length == 2 ? 300 : 245) ||
                  MediaQuery.textScalerOf(context).scale(14) > 18;
              final description = Row(
                children: [
                  _boostArtworkBadge(boost, palette, size: 42),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          boost.title,
                          style: TextStyle(
                            color: palette.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          details,
                          style: TextStyle(
                            color: palette.mutedInk,
                            fontSize: 12,
                          ),
                        ),
                        if (quantity != null)
                          Text(
                            '$quantity owned',
                            style: TextStyle(
                              color: palette.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
              final actionGroup = Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 4,
                children: actions,
              );
              if (stacked) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [description, actionGroup],
                );
              }
              return Row(
                children: [
                  Expanded(child: description),
                  const SizedBox(width: 8),
                  actionGroup,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _boostPurchaseAction(AppModel model, Boost boost) {
    final price = model.progression.discount(boost.price);
    return PricePill(
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
              } else {
                model.buyBoost(boost);
              }
            },
    );
  }

  Widget _boostVideoAction(AppModel model, Boost boost) {
    final adLimit = boost == Boost.doubleTen ? economy.doubleBoostAdsPerDay : 1;
    final adsUsed = model.boostAdsToday(boost);
    final adsLeft = (adLimit - adsUsed).clamp(0, adLimit);
    final milestoneLocked =
        boost == Boost.tripleFifteen &&
        model.adsToday < economy.coinAdMilestone;
    return ActionPill(
      label: adsLeft == 0
          ? 'Daily limit'
          : milestoneLocked
          ? 'Video locked'
          : 'Watch · $adsLeft/$adLimit',
      icon: adsLeft == 0
          ? Icons.schedule_rounded
          : milestoneLocked
          ? Icons.lock_outline_rounded
          : Icons.play_arrow_rounded,
      semanticLabel: adsLeft == 0
          ? 'Daily video limit reached for ${boost.title}'
          : milestoneLocked
          ? 'Watch ${economy.coinAdMilestone} coin videos today to unlock a video for ${boost.title}'
          : 'Watch a video for one ${boost.title}',
      onTap: model.canEarnBoostAd(boost)
          ? () async {
              final ads = context.read<AdService>();
              bool current() =>
                  mounted && ModalRoute.isCurrentOf(context) == true;
              if (!ads.readyFor(RewardPlacement.boost)) {
                await ads.prepare(canPresent: current);
              }
              if (!current()) return;
              final shown = await ads.watchVideo(
                (event) => model.grantBoostAd(boost, event),
                placement: RewardPlacement.boost,
                canPresent: () => current() && model.canEarnBoostAd(boost),
              );
              if (!shown && current()) _feedback('Video unavailable');
            }
          : null,
    );
  }
}

class _ActiveBoostTicker extends StatefulWidget {
  const _ActiveBoostTicker({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_ActiveBoostTicker> createState() => _ActiveBoostTickerState();
}

class _ActiveBoostTickerState extends State<_ActiveBoostTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
