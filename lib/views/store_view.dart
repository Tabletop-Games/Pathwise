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
      null => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final billing = context.watch<BillingService>();
    final ads = context.watch<AdService>();
    final colors = Theme.of(context).colorScheme;
    final palette = BoardPalette.palettes[model.theme]!;
    final coinProducts = billing.products
        .where((p) => consumable(p.id))
        .toList();
    final upgrades = billing.products.where((p) => !consumable(p.id)).toList();
    final recommended = recommendedCoinPack(widget.coinShortfall);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _category = 2),
            icon: const Icon(Icons.toll_rounded),
            label: Text('${model.coinBalance}'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Themes')),
                          ButtonSegment(value: 1, label: Text('Tips')),
                          ButtonSegment(value: 2, label: Text('Coins')),
                          ButtonSegment(value: 3, label: Text('Upgrades')),
                        ],
                        selected: {_category},
                        onSelectionChanged: (v) =>
                            setState(() => _category = v.first),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _category,
                    children: [
                      _themesGrid(model),
                      _tipsGrid(model, palette),
                      ListView(
                        key: const PageStorageKey('store-coins'),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (widget.coinShortfall > 0)
                            Text(
                              'You need ${widget.coinShortfall} more coins.',
                            ),
                          if (billing.enabled && coinProducts.isNotEmpty)
                            _section(
                              title: 'Coin Packs',
                              child: Column(
                                children: [
                                  for (final product in coinProducts)
                                    Card(
                                      color: product.id == recommended
                                          ? colors.secondaryContainer
                                          : null,
                                      child: _productTile(
                                        context,
                                        model,
                                        billing,
                                        product,
                                        highlight: product.id == recommended,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (ads.enabled)
                            _section(
                              title: 'Earn Coins',
                              child: _earnCoins(context, model, ads),
                            ),
                          if (!billing.enabled && !ads.enabled)
                            const Text(
                              'Coin purchases and ad rewards are currently unavailable.',
                            ),
                        ],
                      ),
                      ListView(
                        key: const PageStorageKey('store-upgrades'),
                        padding: const EdgeInsets.all(16),
                        children: [
                          _section(
                            title: 'Permanent Upgrades',
                            subtitle: 'One-time purchases, not subscriptions.',
                            child: Column(
                              children: [
                                if (upgrades.isEmpty)
                                  const Text(
                                    'Purchases are currently unavailable.',
                                  ),
                                for (final product in upgrades)
                                  _productTile(
                                    context,
                                    model,
                                    billing,
                                    product,
                                  ),
                              ],
                            ),
                          ),
                          if (billing.enabled)
                            _section(
                              title: 'Purchase Management',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (billing.message case final message?)
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(message),
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: billing.buying
                                            ? null
                                            : billing.restore,
                                        child: const Text('Restore Purchases'),
                                      ),
                                      TextButton(
                                        onPressed: billing.buying
                                            ? null
                                            : billing.refreshCatalog,
                                        child: const Text('Refresh Prices'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _themesGrid(AppModel model) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final width = (constraints.maxWidth - 48) / 3;
      return GridView.builder(
        key: const PageStorageKey('store-themes'),
        padding: const EdgeInsets.all(12),
        itemCount: PathwiseTheme.values.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: width + 92 + (textScale > 1.2 ? 30 : 0),
        ),
        itemBuilder: (context, index) {
          final theme = PathwiseTheme.values[index];
          final candidate = BoardPalette.palettes[theme]!;
          final owned = model.ownsTheme(theme);
          return Card(
            key: ValueKey('theme-card-${theme.name}'),
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _themePreview(model, theme),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: _miniBoard(candidate, model.equippedTip),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    theme.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _compactAction(
                  model.theme == theme
                      ? 'Equipped'
                      : owned
                      ? 'Apply'
                      : '${economy.themePrice(theme)} coins',
                  model.theme == theme
                      ? null
                      : () => owned
                            ? model.setTheme(theme)
                            : _buyTheme(model, theme),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _miniBoard(BoardPalette palette, PathTip tip) => DecoratedBox(
    decoration: BoxDecoration(
      color: palette.canvas,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.arrow_back, size: 9, color: palette.ink),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  'Level 1',
                  style: TextStyle(
                    fontSize: 8,
                    color: palette.ink,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                ),
              ),
              Icon(Icons.timer_outlined, size: 9, color: palette.ink),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Center(
              child: LevelOneBoardPreview(palette: palette, tip: tip),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tipsGrid(AppModel model, BoardPalette palette) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560 ? 4 : 3;
      final width = (constraints.maxWidth - 24 - (columns - 1) * 8) / columns;
      final large = MediaQuery.textScalerOf(context).scale(1) > 1.2;
      return GridView.builder(
        key: const PageStorageKey('store-tips'),
        padding: const EdgeInsets.all(12),
        itemCount: PathTip.values.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: width + 78 + (large ? 30 : 0),
        ),
        itemBuilder: (context, index) {
          final tip = PathTip.values[index];
          final owned = model.ownsTip(tip);
          return Card(
            key: ValueKey('tip-card-${tip.name}'),
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _tipPreview(model, tip),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: TipArtwork(tip: tip, palette: palette),
                    ),
                  ),
                ),
                Text(tip.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                _compactAction(
                  model.equippedTip == tip
                      ? 'Equipped'
                      : owned
                      ? 'Apply'
                      : '${tip.price} coins',
                  _busy || model.equippedTip == tip
                      ? null
                      : () =>
                            owned ? _equipTip(model, tip) : _buyTip(model, tip),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _compactAction(String label, VoidCallback? action) => SizedBox(
    height: 48,
    child: FilledButton.tonal(
      onPressed: action,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.endsWith(' coins')) ...[
              const Icon(Icons.toll_rounded, size: 15),
              const SizedBox(width: 3),
            ],
            Text(label, maxLines: 1),
          ],
        ),
      ),
    ),
  );

  Future<void> _themePreview(AppModel model, PathwiseTheme theme) async {
    final palette = BoardPalette.palettes[theme]!;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: palette.canvas,
          statusBarIconBrightness: palette.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarColor: palette.canvas,
          systemNavigationBarIconBrightness: palette.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Theme(
          data: palette.theme,
          child: Builder(
            builder: (ctx) => AlertDialog(
              backgroundColor: palette.canvas,
              title: Text(theme.label),
              content: SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Level 1',
                            style: palette.theme.textTheme.titleMedium,
                          ),
                          const Text('0:15'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LevelOneBoardPreview(
                        palette: palette,
                        tip: model.equippedTip,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        children: [
                          OutlinedButton(
                            onPressed: null,
                            child: const Text('Undo'),
                          ),
                          OutlinedButton(
                            onPressed: null,
                            child: const Text('Clear'),
                          ),
                          FilledButton(
                            onPressed: null,
                            child: const Text('Hint'),
                          ),
                        ],
                      ),
                      if (model.earnedTheme(theme) &&
                          economy.themePrice(theme) >= 4500)
                        ShareResultButton(
                          result: ShareResult.cosmetic(theme.label),
                          label: 'Share Theme Discovery',
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _tipPreview(AppModel model, PathTip tip) async {
    var direction = 0;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(tip.label),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 250,
                  child: LevelOneBoardPreview(
                    tip: tip,
                    palette: BoardPalette.palettes[model.theme]!,
                    directionOverride: direction,
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (final pair in [
                      (3, 'Up'),
                      (0, 'Right'),
                      (1, 'Down'),
                      (2, 'Left'),
                    ])
                      TextButton(
                        onPressed: () => update(() => direction = pair.$1),
                        child: Text(pair.$2),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Unlock ${theme.label}?'),
        content: Text('Spend $price coins to own and equip this theme.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text('Unlock · $price'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) model.unlockTheme(theme);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Unlock ${tip.label}?'),
        content: Text('Spend ${tip.price} coins to own this tip.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text('Unlock · ${tip.price}'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    final result = await model.buyTip(tip);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save this purchase.')),
      );
  }

  Future<void> _equipTip(AppModel model, PathTip tip) async {
    setState(() => _busy = true);
    final result = await model.equipTip(tip);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to apply this tip.')),
      );
  }

  Widget _earnCoins(
    BuildContext context,
    AppModel model,
    AdService ads,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Rewarded video · +${economy.rewardedAdCoins} coins'),
        subtitle: Text(
          model.canEarnAdBonus
              ? '${model.adsToday} of ${economy.rewardedAdsPerDay} watched · milestone at ${economy.coinAdMilestone} earns ${economy.coinAdMilestoneBonus} bonus coins'
              : 'Come back after the daily limit resets.',
        ),
        trailing: FilledButton(
          onPressed: !model.canEarnAdBonus
              ? null
              : ads.videoReady
              ? () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ads.watchVideo(
                    (id) async {
                      final milestone =
                          model.adsToday + 1 == economy.coinAdMilestone;
                      final saved = await model.grantAdBonus(id);
                      if (saved && messenger.mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              milestone
                                  ? 'Bonus unlocked! +${economy.coinAdMilestoneBonus} bonus coins'
                                  : '+${economy.rewardedAdCoins} coins added',
                            ),
                          ),
                        );
                      }
                      return saved;
                    },
                    canPresent: () =>
                        context.mounted &&
                        ModalRoute.isCurrentOf(context) == true &&
                        model.canEarnAdBonus,
                  );
                }
              : () => ads.prepare(
                  canPresent: () =>
                      context.mounted &&
                      ModalRoute.isCurrentOf(context) == true,
                ),
          child: Text(ads.videoReady ? 'Watch' : 'Load'),
        ),
      ),
      Text(
        'Milestone progress: ${model.adsToday.clamp(0, economy.coinAdMilestone)} / ${economy.coinAdMilestone}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 4),
      Text(
        'At the milestone: +${economy.coinAdMilestoneBonus} bonus coins.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _productTile(
    BuildContext context,
    AppModel model,
    BillingService billing,
    ProductDetails product, {
    bool highlight = false,
  }) {
    final owned = switch (product.id) {
      themePassProduct => model.hasThemePass,
      removeAdsProduct => model.adFree,
      premiumProduct => model.premium,
      _ => false,
    };
    final description = switch (product.id) {
      themePassProduct => 'Unlocks all current and future themes.',
      removeAdsProduct =>
        'Removes automatic ads and banners. Optional rewarded ads remain.',
      premiumProduct => 'Lifetime access with a one-time coin bonus.',
      _ => '${storeProducts[product.id]?.coins ?? 0} coins',
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(storeProducts[product.id]?.label ?? product.title),
      subtitle: Text(description),
      trailing: FilledButton.tonal(
        onPressed: owned || billing.buying || model.storageError
            ? null
            : () => billing.buy(product),
        child: Text(owned ? 'Owned' : product.price),
      ),
      selected: highlight,
    );
  }

  Widget _section({
    Key? key,
    required String title,
    String? subtitle,
    required Widget child,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    ),
  );
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
