import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/billing_service.dart';
import '../model/app_model.dart';
import '../model/economy.dart';
import 'wallet_view.dart';

enum StoreSection { premium, upgrades, coinPacks, earnCoins }

class StoreView extends StatefulWidget {
  const StoreView({super.key, this.section, this.coinShortfall = 0});
  final StoreSection? section;
  final int coinShortfall;

  @override
  State<StoreView> createState() => _StoreViewState();
}

class _StoreViewState extends State<StoreView> {
  final _premiumKey = GlobalKey();
  final _upgradeKey = GlobalKey();
  final _packsKey = GlobalKey();
  final _earnKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = switch (widget.section) {
        StoreSection.premium => _premiumKey,
        StoreSection.upgrades => _upgradeKey,
        StoreSection.coinPacks => _packsKey,
        StoreSection.earnCoins => _earnKey,
        null => null,
      };
      if (target?.currentContext case final targetContext?) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 280),
          alignment: .05,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final billing = context.watch<BillingService>();
    final ads = context.watch<AdService>();
    final coinProducts = billing.products
        .where((product) => consumable(product.id))
        .toList();
    final premiumProducts = billing.products
        .where((product) => !consumable(product.id))
        .toList();
    final recommended = recommendedCoinPack(widget.coinShortfall);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push<void>(MaterialPageRoute(builder: (_) => const WalletView())),
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
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (premiumProducts.isNotEmpty)
                  _section(
                    key: _premiumKey,
                    title: 'Pathwise Premium',
                    subtitle: 'A one-time purchase. Not a subscription.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Remove automatic advertisements and banners. Unlock all current and future themes, receive ${economy.premiumBonus} coins once, and keep optional rewarded ads.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        for (final product in premiumProducts.where(
                          (product) => product.id == premiumProduct,
                        ))
                          _productTile(context, model, billing, product),
                      ],
                    ),
                  ),
                if (premiumProducts.any(
                  (product) => product.id != premiumProduct,
                ))
                  _section(
                    key: _upgradeKey,
                    title: 'Permanent Upgrades',
                    child: Column(
                      children: [
                        for (final product in premiumProducts.where(
                          (product) => product.id != premiumProduct,
                        ))
                          _productTile(context, model, billing, product),
                      ],
                    ),
                  ),
                if (billing.enabled && coinProducts.isNotEmpty)
                  _section(
                    key: _packsKey,
                    title: 'Coin Packs',
                    subtitle: widget.coinShortfall > 0
                        ? 'You need ${widget.coinShortfall} more coins.'
                        : null,
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
                    key: _earnKey,
                    title: 'Earn Coins',
                    subtitle: model.canEarnAdBonus
                        ? '${model.adsToday} of ${economy.rewardedAdsPerDay} daily ads used · ${economy.rewardedAdsPerDay - model.adsToday} remaining'
                        : 'Daily ad limit reached',
                    child: _earnCoins(context, model, ads),
                  ),
                if (billing.enabled)
                  _section(
                    title: 'Purchase Management',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (billing.message case final message?)
                          Semantics(liveRegion: true, child: Text(message)),
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
                if (!billing.enabled && !ads.enabled)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Coin purchases and ad rewards are currently unavailable. You can keep playing offline.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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
