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
    'assets/art/resources/coin_stack_2.png',
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
    'assets/art/resources/crate.png',
    ArtKind.crate,
    [Research.hunter, Research.collector, Research.scout],
  ),
  efficiency(
    'Efficiency',
    'Extend boost timers and reduce upgrade and boost costs.',
    'assets/art/ui/boost.png',
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
  Research.magnet => 'assets/art/resources/coin.png',
  Research.golden => 'assets/art/resources/coin_stack_2.png',
  Research.fortune => 'assets/art/ui/wheel_ticket.png',
  Research.mastery => 'assets/art/ui/achievement.png',
  Research.momentum => 'assets/art/ui/flame.png',
  Research.specialist => 'assets/art/resources/coin_stack_3.png',
  Research.hunter => 'assets/art/resources/crate.png',
  Research.collector => 'assets/art/resources/chest_open.png',
  Research.scout => 'assets/art/ui/compass.png',
  Research.efficiency => 'assets/art/ui/timer.png',
  Research.savings => 'assets/art/resources/coin_stack_1.png',
  Research.tuning => 'assets/art/ui/boost.png',
  Research.procurement => 'assets/art/resources/hint.png',
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
  Timer? _tick;
  late _ProgressionTab _tab;
  var _branch = _ResearchBranch.income;
  var _recordedResearchActivity = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.boosts ? _ProgressionTab.boosts : _ProgressionTab.research;
    if (_tab == _ProgressionTab.boosts) {
      _startTick();
    } else {
      _scheduleResearchActivity();
    }
  }

  void _startTick() {
    _tick ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
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
    if (tab == _ProgressionTab.boosts) {
      _startTick();
    } else {
      _stopTick();
      _scheduleResearchActivity();
    }
  }

  @override
  void dispose() {
    _stopTick();
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
    final active = Boost.values
        .where((boost) => progression.remaining(boost, now) > 0)
        .toList();
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
            child: LayoutBuilder(
              builder: (context, viewport) {
                final availableWidth = viewport.maxWidth;
                final maxContentWidth =
                    _tab == _ProgressionTab.boosts && availableWidth >= 620
                    ? 760.0
                    : 620.0;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth),
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
                              ? _boostsBody(
                                  model,
                                  palette,
                                  active,
                                  [...multipliers, ...supplies],
                                  now,
                                  availableWidth,
                                )
                              : _researchBody(model, palette),
                        ),
                      ],
                    ),
                  ),
                );
              },
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
    List<Boost> allBoosts,
    int now,
    double screenWidth,
  ) {
    final twoColumn =
        screenWidth >= 620 && MediaQuery.textScalerOf(context).scale(16) <= 19;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
      children: [
        if (active.isNotEmpty) _activeBoostStrip(model, palette, active, now),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Coin boosts',
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Activate a boost or build your reserve',
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
            ],
          ),
        ),
        if (allBoosts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                GameArt(ArtKind.bolt, palette: palette, size: 72),
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
          )
        else if (!twoColumn)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final boost in allBoosts) _boost(model, boost, now),
            ],
          )
        else
          Column(
            children: [
              for (var i = 0; i < allBoosts.length; i += 2)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _boost(model, allBoosts[i], now)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: i + 1 < allBoosts.length
                            ? _boost(model, allBoosts[i + 1], now)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

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
                  final totalDuration =
                      boost.minutes * 600 * (100 + progress.durationBonus);
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
    final adLimit = boost == Boost.doubleTen ? economy.doubleBoostAdsPerDay : 1;
    final adsUsed = model.boostAdsToday(boost);
    final adsLeft = (adLimit - adsUsed).clamp(0, adLimit);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GameCard(
        key: ValueKey('boost-${boost.name}'),
        selected: remaining > 0,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _boostArtworkBadge(boost, palette, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: palette.route.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              multiplier
                                  ? '${boost.multiplier}× · ${_compactDuration(duration)}'
                                  : 'Crates · ${_compactDuration(duration)}',
                              style: TextStyle(
                                color: palette.route,
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: inventory > 0
                                  ? palette.route.withValues(alpha: .10)
                                  : palette.quiet,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: inventory > 0
                                    ? palette.route.withValues(alpha: .35)
                                    : palette.cardEdge,
                              ),
                            ),
                            child: Text(
                              '$inventory owned',
                              style: TextStyle(
                                color: inventory > 0
                                    ? palette.ink
                                    : palette.mutedInk,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        boost.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        boost.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.mutedInk,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (remaining > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Active · ${_duration(remaining)} left',
                style: TextStyle(
                  color: palette.route,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 5),
              GameBar(value: remaining / duration, height: 6),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (watch)
                  ActionPill(
                    label: adsLeft > 0
                        ? 'Watch · $adsLeft/$adLimit'
                        : 'Daily limit',
                    icon: adsLeft > 0
                        ? Icons.play_arrow_rounded
                        : Icons.schedule_rounded,
                    semanticLabel: adsLeft > 0
                        ? 'Watch a video for one ${boost.title}'
                        : 'Daily video limit reached for ${boost.title}',
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
                                'Boost active for ${_compactDuration(duration)}',
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
