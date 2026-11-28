import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/billing_service.dart';
import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/user_preferences.dart';
import '../ui/game_art.dart';
import '../ui/game_ui.dart';
import 'components/economy_navigation.dart';
import 'components/puzzle_board.dart';
import 'components/tip_art.dart';
import 'share_view.dart';

enum StoreSection {
  themes,
  tips,
  coins,
  premium,
  upgrades,
  coinPacks,
  earnCoins,
}

/// Coin packs in display order, with the illustration that matches their size.
const coinPackOrder = <(String, ArtKind)>[
  ('pathwise_coins_500', ArtKind.coinStack1),
  ('pathwise_coins_1250', ArtKind.coinStack2),
  ('pathwise_coins_3000', ArtKind.coinStack3),
  ('pathwise_coins_7500', ArtKind.coinStack4),
  ('pathwise_coins_18000', ArtKind.coinStack5),
];

class StoreView extends StatefulWidget {
  const StoreView({super.key, this.section, this.coinShortfall = 0});
  final StoreSection? section;
  final int coinShortfall;
  @override
  State<StoreView> createState() => _StoreViewState();
}

class _StoreViewState extends State<StoreView> {
  late int _category;
  bool _busy = false;
  bool _watching = false;
  late final List<ScrollController> _tabScrolls = List.generate(
    4,
    (_) => ScrollController(),
  );

  @override
  void initState() {
    super.initState();
    _category = switch (widget.section) {
      StoreSection.themes => 0,
      StoreSection.tips => 1,
      StoreSection.coins ||
      StoreSection.coinPacks ||
      StoreSection.earnCoins => 2,
      StoreSection.upgrades || StoreSection.premium => 3,
      null => context.read<AppModel>().lastStoreCategory,
    };
    context.read<AppModel>().lastStoreCategory = _category;
  }

  @override
  void dispose() {
    for (final controller in _tabScrolls) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectCategory(int value) {
    context.read<AppModel>().lastStoreCategory = value;
    if (value == _category) {
      final controller = _tabScrolls[value];
      if (!controller.hasClients || controller.offset <= 0) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.jumpTo(0);
      } else {
        controller.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    setState(() => _category = value);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final billing = context.watch<BillingService>();
    final ads = context.watch<AdService>();
    final palette = BoardPalette.palettes[model.theme]!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(palette),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          titleSpacing: 0,
          title: const Text(
            'Store',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
          ),
          actions: [
            BalanceChip(
              coins: model.coinBalance,
              onTap: () => setState(() => _category = 2),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: AtmosphericBackdrop(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                      child: GameSegmented<int>(
                        selected: _category,
                        onChanged: _selectCategory,
                        segments: const [
                          (value: 0, label: 'Themes'),
                          (value: 1, label: 'Tips'),
                          (value: 2, label: 'Coins'),
                          (value: 3, label: 'Upgrades'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _category,
                        children: [
                          _themesGrid(model),
                          _tipsGrid(model, palette),
                          _coinsTab(model, billing, ads, palette),
                          _upgradesTab(model, billing, palette),
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

  // ---- Themes ---------------------------------------------------------------

  Widget _themesGrid(AppModel model) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final columns = constraints.maxWidth >= 560 ? 4 : 3;
      final width = (constraints.maxWidth - 24 - (columns - 1) * 8) / columns;
      final themes = List<PathwiseTheme>.of(PathwiseTheme.values)
        ..sort((a, b) {
          final byPrice = economy
              .themePrice(a)
              .compareTo(economy.themePrice(b));
          if (byPrice != 0) return byPrice;
          final aOwned = model.ownsTheme(a) ? 0 : 1;
          final bOwned = model.ownsTheme(b) ? 0 : 1;
          final byOwned = aOwned.compareTo(bOwned);
          if (byOwned != 0) return byOwned;
          return a.label.compareTo(b.label);
        });
      return GridView.builder(
        key: const PageStorageKey('store-themes'),
        controller: _tabScrolls[0],
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: themes.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: width + 74 + (textScale > 1.2 ? 28 : 0),
        ),
        itemBuilder: (context, index) {
          final theme = themes[index];
          final candidate = BoardPalette.palettes[theme]!;
          final owned = model.ownsTheme(theme);
          final equipped = model.theme == theme;
          return GameCard(
            key: ValueKey('theme-card-${theme.name}'),
            selected: equipped,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Column(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Preview ${theme.label}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _themePreview(model, theme),
                      child: _thumb(candidate, model.equippedTip),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  theme.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                _cosmeticAction(
                  equipped: equipped,
                  owned: owned,
                  price: economy.themePrice(theme),
                  name: theme.label,
                  onApply: () => model.setTheme(theme),
                  onBuy: () => _buyTheme(model, theme),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  /// Board-only thumbnail. It shows the candidate theme's real Level 1 board
  /// and no invented controls.
  Widget _thumb(BoardPalette candidate, PathTip tip) => DecoratedBox(
    decoration: BoxDecoration(
      color: candidate.canvas,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Center(
        child: LevelOneBoardPreview(palette: candidate, tip: tip),
      ),
    ),
  );

  /// One action per card: price while locked, Apply while owned, Equipped
  /// while active. Only the price is visually loud.
  Widget _cosmeticAction({
    required bool equipped,
    required bool owned,
    required int price,
    required String name,
    required VoidCallback onApply,
    required VoidCallback? onBuy,
  }) {
    if (equipped) {
      return ActionPill(
        label: 'Equipped',
        icon: Icons.check_rounded,
        tone: ActionTone.selected,
        semanticLabel: '$name equipped',
      );
    }
    if (owned) {
      return ActionPill(
        label: 'Apply',
        onTap: _busy ? null : onApply,
        semanticLabel: 'Apply $name',
      );
    }
    return PricePill(
      price: price,
      onTap: _busy ? null : onBuy,
      semanticLabel: 'Unlock $name for $price coins',
    );
  }

  // ---- Tips -----------------------------------------------------------------

  Widget _tipsGrid(AppModel model, BoardPalette palette) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560 ? 4 : 3;
      final width = (constraints.maxWidth - 24 - (columns - 1) * 8) / columns;
      final large = MediaQuery.textScalerOf(context).scale(1) > 1.2;
      return GridView.builder(
        key: const PageStorageKey('store-tips'),
        controller: _tabScrolls[1],
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: PathTip.values.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: width + 72 + (large ? 28 : 0),
        ),
        itemBuilder: (context, index) {
          final tip = PathTip.values[index];
          final equipped = model.equippedTip == tip;
          return GameCard(
            key: ValueKey('tip-card-${tip.name}'),
            selected: equipped,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Column(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Preview ${tip.label}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _tipPreview(model, tip),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.quiet,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Center(
                            child: TipArtwork(tip: tip, palette: palette),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                _cosmeticAction(
                  equipped: equipped,
                  owned: model.ownsTip(tip),
                  price: tip.price,
                  name: tip.label,
                  onApply: () => _equipTip(model, tip),
                  onBuy: () => _buyTip(model, tip),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  // ---- Coins ----------------------------------------------------------------

  Widget _coinsTab(
    AppModel model,
    BillingService billing,
    AdService ads,
    BoardPalette palette,
  ) {
    final recommended = recommendedCoinPack(widget.coinShortfall);
    return ListView(
      key: const PageStorageKey('store-coins'),
      controller: _tabScrolls[2],
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        if (widget.coinShortfall > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ShortfallBanner(shortfall: widget.coinShortfall),
          ),
        _freeCoinsCard(model, ads, palette),
        const SizedBox(height: 14),
        const _SectionLabel('Coin packs'),
        if (!billing.enabled)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _Unavailable('Purchases are unavailable on this build.'),
          )
        else if (billing.products.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Unavailable(
              'Prices are loading.',
              action: billing.buying
                  ? null
                  : ('Refresh', billing.refreshCatalog),
            ),
          )
        else
          const SizedBox(height: 8),
        _packGrid(model, billing, recommended),
        if (billing.message case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget _freeCoinsCard(AppModel model, AdService ads, BoardPalette palette) {
    final canEarn = model.canEarnAdBonus;
    final milestone = economy.coinAdMilestone;
    final watched = model.adsToday;
    final bonus = model.nextCoinVideoEarnsMilestone;
    final reward =
        economy.rewardedAdCoins + (bonus ? economy.coinAdMilestoneBonus : 0);
    final claimed = model.coinMilestoneClaimed;
    final highContrast = _isSignalPalette(palette);
    final String label;
    final VoidCallback? action;
    if (!ads.enabled) {
      label = 'Unavailable';
      action = null;
    } else if (!canEarn) {
      label = 'Back tomorrow';
      action = null;
    } else if (_watching) {
      label = 'Working…';
      action = null;
    } else if (ads.videoReady) {
      label = 'Watch video';
      action = () => _watchCoinVideo(model, ads);
    } else {
      label = 'Load video';
      action = () => _prepareVideo(ads);
    }
    return _accentHighlightCard(
      palette: palette,
      highlight: true,
      child: GameCard(
        key: const ValueKey('free-coins'),
        padding: const EdgeInsets.all(16),
        color: highContrast
            ? palette.cardTop
            : Color.lerp(
                palette.card,
                palette.accent,
                palette.dark ? .12 : .16,
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _SectionLabel('Free coins'),
                const Spacer(),
                Semantics(
                  label:
                      '$watched of ${economy.rewardedAdsPerDay} videos today',
                  excludeSemantics: true,
                  child: InfoChip(
                    icon: Icon(
                      Icons.play_circle_outline_rounded,
                      size: 16,
                      color: palette.ink,
                    ),
                    label: '$watched/${economy.rewardedAdsPerDay}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                GameArt(
                  bonus ? ArtKind.coinStack3 : ArtKind.coinStack2,
                  palette: palette,
                  size: 72,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RewardAmount(reward, size: 38),
                      if (!canEarn) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Come back tomorrow',
                          style: TextStyle(
                            color: palette.mutedInk,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ] else if (bonus) ...[
                        const SizedBox(height: 6),
                        Semantics(
                          label:
                              '${economy.rewardedAdCoins} reward plus ${economy.coinAdMilestoneBonus} bonus',
                          excludeSemantics: true,
                          child: Row(
                            children: [
                              GameArt(ArtKind.gift, palette: palette, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                '${economy.rewardedAdCoins} + ${economy.coinAdMilestoneBonus} bonus',
                                style: TextStyle(
                                  color: palette.mutedInk,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ProgressPips(
                      done: claimed
                          ? milestone
                          : watched.clamp(0, milestone - 1),
                      total: milestone,
                      finalReward: !claimed,
                      semanticLabel: claimed
                          ? 'Bonus claimed'
                          : '$watched of $milestone videos for a ${economy.coinAdMilestoneBonus} coin bonus',
                    ),
                  ),
                ),
                ActionPill(
                  label: label,
                  tone: action == null ? ActionTone.quiet : ActionTone.primary,
                  icon: action != null && ads.videoReady
                      ? Icons.play_arrow_rounded
                      : null,
                  onTap: action,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _prepareVideo(AdService ads) async {
    setState(() => _watching = true);
    try {
      await ads.prepare(
        canPresent: () => mounted && ModalRoute.isCurrentOf(context) == true,
      );
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  Future<void> _watchCoinVideo(AppModel model, AdService ads) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _watching = true);
    try {
      await ads.watchVideo(
        (id) async {
          final milestone = model.nextCoinVideoEarnsMilestone;
          final saved = await model.grantAdBonus(id);
          if (saved && messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  milestone
                      ? '+${economy.rewardedAdCoins + economy.coinAdMilestoneBonus}'
                      : '+${economy.rewardedAdCoins}',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return saved;
        },
        canPresent: () =>
            mounted &&
            ModalRoute.isCurrentOf(context) == true &&
            model.canEarnAdBonus,
      );
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  Widget _packGrid(
    AppModel model,
    BillingService billing,
    String? recommended,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: coinPackOrder.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 158,
      ),
      itemBuilder: (context, index) {
        final (id, art) = coinPackOrder[index];
        final entry = storeProducts[id]!;
        final tier = entry.label.split(' · ').first;
        return _PackCard(
          key: ValueKey('pack-$id'),
          tier: tier,
          coins: entry.coins,
          art: art,
          product: billing.products.where((p) => p.id == id).firstOrNull,
          highlight: id == recommended,
          enabled: billing.enabled && !billing.buying && !model.storageError,
          onBuy: (product) => billing.buy(product),
        );
      },
    );
  }

  // ---- Upgrades -------------------------------------------------------------

  Widget _upgradesTab(
    AppModel model,
    BillingService billing,
    BoardPalette palette,
  ) {
    ProductDetails? details(String id) =>
        billing.products.where((p) => p.id == id).firstOrNull;
    final buyable = billing.enabled && !billing.buying && !model.storageError;
    return ListView(
      key: const PageStorageKey('store-upgrades'),
      controller: _tabScrolls[3],
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        _UpgradeCard(
          key: const ValueKey('upgrade-premium'),
          art: ArtKind.crown,
          title: 'Premium',
          featured: true,
          owned: model.premium,
          product: details(premiumProduct),
          enabled: buyable,
          chips: [
            (ArtKind.brush, 'All current & future themes'),
            (ArtKind.noAds, 'No banners or exit ads'),
            (ArtKind.coin, '+${_formatCoins(economy.premiumBonus)} coins'),
            (ArtKind.video, 'Optional reward videos stay'),
          ],
          onBuy: billing.buy,
        ),
        const SizedBox(height: 10),
        _UpgradeCard(
          key: const ValueKey('upgrade-themes'),
          art: ArtKind.brush,
          title: 'Themes Forever',
          owned: model.hasThemePass,
          product: details(themePassProduct),
          enabled: buyable,
          chips: const [
            (ArtKind.brush, 'Current & future themes'),
            (null, 'Excludes path tips'),
          ],
          onBuy: billing.buy,
        ),
        const SizedBox(height: 10),
        _UpgradeCard(
          key: const ValueKey('upgrade-ads'),
          art: ArtKind.noAds,
          title: 'Remove Ads',
          owned: model.adFree,
          product: details(removeAdsProduct),
          enabled: buyable,
          chips: const [
            (ArtKind.noAds, 'No banner or exit ads'),
            (ArtKind.video, 'Optional reward videos stay'),
          ],
          onBuy: billing.buy,
        ),
        const SizedBox(height: 14),
        if (!billing.enabled)
          const _Unavailable('Purchases are unavailable on this build.')
        else if (billing.products.isEmpty)
          _Unavailable(
            'Prices are loading.',
            action: billing.buying ? null : ('Refresh', billing.refreshCatalog),
          ),
        if (billing.enabled)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: billing.buying ? null : billing.restore,
                child: const Text('Restore purchases'),
              ),
              TextButton(
                onPressed: billing.buying ? null : billing.refreshCatalog,
                child: const Text('Refresh prices'),
              ),
              TextButton(onPressed: _showTerms, child: const Text('Details')),
            ],
          )
        else
          Center(
            child: TextButton(
              onPressed: _showTerms,
              child: const Text('Details'),
            ),
          ),
        if (billing.message case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  /// Purchase terms stay one tap away. They are not repeated on every card.
  Future<void> _showTerms() => showGameDialog<void>(
    context,
    builder: (dialog) => GameDialog(
      title: 'Upgrade details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in [
            'One-time purchases, not subscriptions.',
            'Remove Ads removes automatic ads and banners. Optional rewarded videos remain available.',
            'Themes Forever unlocks every current and future theme. It does not include tips.',
            'Premium includes Themes Forever and Remove Ads, plus a one-time ${economy.premiumBonus} coin bonus.',
            'Use Restore purchases to recover permanent upgrades on a new device.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                line,
                style: TextStyle(color: dialog.palette.ink, fontSize: 14),
              ),
            ),
        ],
      ),
      actions: [ActionPill(label: 'Close', onTap: () => Navigator.pop(dialog))],
    ),
  );

  // ---- Previews and purchases ----------------------------------------------

  Future<void> _themePreview(AppModel model, PathwiseTheme theme) async {
    final candidate = BoardPalette.palettes[theme]!;
    final owned = model.ownsTheme(theme);
    await showDialog<void>(
      context: context,
      builder: (dialog) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayFor(candidate),
        child: Theme(
          data: candidate.theme,
          child: Builder(
            builder: (ctx) => GameDialog(
              title: theme.label,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: candidate.canvas,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: LevelOneBoardPreview(
                        palette: candidate,
                        tip: model.equippedTip,
                      ),
                    ),
                  ),
                  if (model.earnedTheme(theme) &&
                      economy.themePrice(theme) >= 4500)
                    ShareResultButton(
                      result: ShareResult.cosmetic(theme.label),
                      label: 'Share Theme Discovery',
                    ),
                ],
              ),
              actions: [
                ActionPill(label: 'Close', onTap: () => Navigator.pop(dialog)),
                if (model.theme != theme)
                  if (owned)
                    ActionPill(
                      label: 'Apply',
                      tone: ActionTone.primary,
                      onTap: () {
                        model.setTheme(theme);
                        Navigator.pop(dialog);
                      },
                    )
                  else
                    PricePill(
                      price: economy.themePrice(theme),
                      onTap: () {
                        Navigator.pop(dialog);
                        _buyTheme(model, theme);
                      },
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _tipPreview(AppModel model, PathTip tip) async {
    final palette = BoardPalette.palettes[model.theme]!;
    await showDialog<void>(
      context: context,
      builder: (dialog) => GameDialog(
        title: tip.label,
        child: SizedBox(
          width: 250,
          child: LevelOneBoardPreview(tip: tip, palette: palette),
        ),
        actions: [
          ActionPill(label: 'Close', onTap: () => Navigator.pop(dialog)),
          if (model.equippedTip != tip)
            if (model.ownsTip(tip))
              ActionPill(
                label: 'Apply',
                tone: ActionTone.primary,
                onTap: () {
                  Navigator.pop(dialog);
                  _equipTip(model, tip);
                },
              )
            else
              PricePill(
                price: tip.price,
                onTap: () {
                  Navigator.pop(dialog);
                  _buyTip(model, tip);
                },
              ),
        ],
      ),
    );
  }

  Future<bool> _confirmUnlock({
    required String name,
    required int price,
    required Widget art,
  }) async {
    final confirm = await showGameDialog<bool>(
      context,
      builder: (dialog) => GameDialog(
        art: art,
        title: name,
        actions: [
          ActionPill(
            label: 'Not now',
            onTap: () => Navigator.pop(dialog, false),
          ),
          PricePill(
            price: price,
            semanticLabel: 'Unlock $name for $price coins',
            onTap: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    );
    return confirm == true && mounted;
  }

  Future<void> _buyTheme(AppModel model, PathwiseTheme theme) async {
    final price = economy.themePrice(theme);
    if (model.coinBalance < price) {
      await showInsufficientCoins(
        context,
        itemName: theme.label,
        requiredCoins: price,
        currentBalance: model.coinBalance,
      );
      return;
    }
    final candidate = BoardPalette.palettes[theme]!;
    final yes = await _confirmUnlock(
      name: theme.label,
      price: price,
      art: SizedBox(width: 96, child: _thumb(candidate, model.equippedTip)),
    );
    if (yes) model.unlockTheme(theme);
  }

  Future<void> _buyTip(AppModel model, PathTip tip) async {
    if (model.coinBalance < tip.price) {
      await showInsufficientCoins(
        context,
        itemName: tip.label,
        requiredCoins: tip.price,
        currentBalance: model.coinBalance,
      );
      return;
    }
    final palette = BoardPalette.palettes[model.theme]!;
    final yes = await _confirmUnlock(
      name: tip.label,
      price: tip.price,
      art: SizedBox(
        width: 96,
        child: TipArtwork(tip: tip, palette: palette),
      ),
    );
    if (!yes) return;
    setState(() => _busy = true);
    final result = await model.buyTip(tip);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t save this purchase. Try again.'),
        ),
      );
    }
  }

  Future<void> _equipTip(AppModel model, PathTip tip) async {
    setState(() => _busy = true);
    final result = await model.equipTip(tip);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t apply this tip. Try again.')),
      );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: context.palette.mutedInk,
      fontWeight: FontWeight.w800,
      fontSize: 13,
      letterSpacing: .4,
    ),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.text, {this.action});
  final String text;
  final (String, VoidCallback)? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.mutedInk, fontSize: 14),
        ),
        if (action case (final label, final callback))
          TextButton(onPressed: callback, child: Text(label)),
      ],
    ),
  );
}

class _ShortfallBanner extends StatelessWidget {
  const _ShortfallBanner({required this.shortfall});
  final int shortfall;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'You need $shortfall more coins',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: p.quiet,
          borderRadius: BorderRadius.circular(GameTokens.cardRadius),
          border: Border.all(color: p.cardEdge),
        ),
        child: Row(
          children: [
            const CoinMark(size: 22),
            const SizedBox(width: 8),
            Text(
              '$shortfall short',
              style: TextStyle(
                color: p.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isSignalPalette(BoardPalette p) =>
    p == BoardPalette.palettes[PathwiseTheme.signal];

Widget _accentHighlightCard({
  required BoardPalette palette,
  required bool highlight,
  required Widget child,
}) {
  if (!highlight || !_isSignalPalette(palette)) return child;
  return DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(GameTokens.cardRadius),
      border: Border.all(color: palette.accent, width: 2),
    ),
    child: child,
  );
}

String _formatCoins(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.tier,
    required this.coins,
    required this.art,
    required this.product,
    required this.enabled,
    required this.onBuy,
    this.highlight = false,
    super.key,
  });

  final String tier;
  final int coins;
  final ArtKind art;
  final ProductDetails? product;
  final bool highlight, enabled;
  final void Function(ProductDetails) onBuy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final details = product;
    final artSize = switch (art) {
      ArtKind.coinStack1 => 50.0,
      ArtKind.coinStack2 => 58.0,
      ArtKind.coinStack3 => 66.0,
      ArtKind.coinStack4 => 74.0,
      ArtKind.coinStack5 => 82.0,
      _ => 64.0,
    };
    return GameCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      selected: highlight,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: GameArt(art, palette: p, size: artSize),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tier,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.mutedInk,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CoinMark(size: 18),
              const SizedBox(width: 5),
              Text(
                _formatCoins(coins),
                style: TextStyle(
                  color: p.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (details == null)
            const ActionPill(label: 'Store unavailable', tone: ActionTone.quiet)
          else
            ActionPill(
              label: details.price,
              tone: enabled ? ActionTone.primary : ActionTone.quiet,
              onTap: enabled ? () => onBuy(details) : null,
              semanticLabel: 'Buy $coins coins for ${details.price}',
            ),
        ],
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({
    required this.art,
    required this.title,
    required this.owned,
    required this.product,
    required this.enabled,
    required this.chips,
    required this.onBuy,
    this.featured = false,
    super.key,
  });

  final ArtKind art;
  final String title;
  final bool owned, enabled, featured;
  final ProductDetails? product;
  final List<(ArtKind?, String)> chips;
  final void Function(ProductDetails) onBuy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final details = product;
    final highContrast = _isSignalPalette(p);
    return _accentHighlightCard(
      palette: p,
      highlight: featured,
      child: GameCard(
        padding: const EdgeInsets.all(14),
        selected: featured && !highContrast,
        color: featured
            ? (highContrast
                  ? p.cardTop
                  : Color.lerp(p.card, p.accent, p.dark ? .12 : .16))
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.quiet,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: GameArt(art, palette: p, size: featured ? 56 : 48),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: p.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: featured ? 21 : 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (owned)
                  const ActionPill(
                    label: 'Owned',
                    icon: Icons.check_rounded,
                    tone: ActionTone.selected,
                  )
                else if (details == null)
                  Flexible(
                    flex: 0,
                    child: Text(
                      'Unavailable',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: p.mutedInk,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  ActionPill(
                    label: details.price,
                    tone: enabled ? ActionTone.primary : ActionTone.quiet,
                    onTap: enabled ? () => onBuy(details) : null,
                    semanticLabel: 'Buy $title for ${details.price}',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (kind, label) in chips)
                  InfoChip(
                    icon: kind != null
                        ? GameArt(kind, palette: p, size: 16)
                        : Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: p.mutedInk,
                          ),
                    label: label,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String? recommendedCoinPack(int shortfall) {
  if (shortfall <= 0) return null;
  final packs =
      storeProducts.entries
          .where((entry) => entry.value.coins >= shortfall)
          .toList()
        ..sort((a, b) => a.value.coins.compareTo(b.value.coins));
  return packs.isEmpty ? null : packs.first.key;
}
