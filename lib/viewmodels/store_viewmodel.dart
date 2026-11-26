import 'package:in_app_purchase/in_app_purchase.dart';

import '../logic/ad_service.dart';
import '../logic/billing_service.dart';
import '../model/app_model.dart';
import '../model/economy.dart';
import '../model/user_preferences.dart';

sealed class StorePurchaseResult {
  const StorePurchaseResult();
}

final class StorePurchaseSuccess extends StorePurchaseResult {
  const StorePurchaseSuccess(this.message);
  final String message;
}

final class StoreInsufficientCoins extends StorePurchaseResult {
  const StoreInsufficientCoins({
    required this.itemName,
    required this.shortfall,
  });
  final String itemName;
  final int shortfall;
}

final class StorePurchaseFailed extends StorePurchaseResult {
  const StorePurchaseFailed(this.message);
  final String message;
}

final class StorePurchaseNoop extends StorePurchaseResult {
  const StorePurchaseNoop();
}

/// Presentation logic and transaction coordination for the unified Store.
class StoreViewModel {
  StoreViewModel({
    required this.model,
    required this.ads,
    required this.billing,
  });

  final AppModel model;
  final AdService ads;
  final BillingService billing;

  bool get coinOfferEnabled => ads.enabled;
  bool get canEarnAdBonus => model.canEarnAdBonus;
  bool get nextCoinVideoEarnsMilestone => model.nextCoinVideoEarnsMilestone;
  int get adsToday => model.adsToday;
  int get rewardedAdsPerDay => economy.rewardedAdsPerDay;
  int get coinAdMilestone => economy.coinAdMilestone;

  int get nextAdRewardAmount =>
      economy.rewardedAdCoins +
      (model.nextCoinVideoEarnsMilestone ? economy.coinAdMilestoneBonus : 0);

  bool get isCoinVideoReady => ads.videoReady;

  bool canShareTheme(PathwiseTheme theme) =>
      model.earnedTheme(theme) && economy.themePrice(theme) >= 4500;

  ProductDetails? productFor(String id) {
    for (final product in billing.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  static String packTierLabel(({String label, int coins, bool legacy}) entry) =>
      entry.label.split(' · ').first;

  static ({String label, int coins, bool legacy})? recommendedCoinPack(
    int shortfall,
  ) {
    final packs =
        storeProducts.values
            .where((product) => !product.legacy && product.coins > 0)
            .toList()
          ..sort((a, b) => a.coins.compareTo(b.coins));
    if (packs.isEmpty) return null;
    for (final pack in packs) {
      if (pack.coins >= shortfall) return pack;
    }
    return packs.last;
  }

  StorePurchaseResult buyTheme(PathwiseTheme theme) {
    if (model.ownsTheme(theme)) {
      model.setTheme(theme);
      return const StorePurchaseNoop();
    }
    final price = economy.themePrice(theme);
    if (model.coinBalance < price) {
      return StoreInsufficientCoins(
        itemName: theme.label,
        shortfall: price - model.coinBalance,
      );
    }
    if (model.unlockTheme(theme)) {
      return StorePurchaseSuccess('${theme.label} unlocked and equipped.');
    }
    return const StorePurchaseFailed(
      'Unable to unlock theme right now. Please try again.',
    );
  }

  Future<StorePurchaseResult> buyTip(PathTip tip) async {
    if (model.ownsTip(tip)) {
      await model.equipTip(tip);
      return const StorePurchaseNoop();
    }
    if (model.coinBalance < tip.price) {
      return StoreInsufficientCoins(
        itemName: tip.label,
        shortfall: tip.price - model.coinBalance,
      );
    }
    if (await model.buyTip(tip)) {
      await model.equipTip(tip);
      return StorePurchaseSuccess('${tip.label} unlocked and equipped.');
    }
    return const StorePurchaseFailed(
      'Unable to unlock tip right now. Please try again.',
    );
  }

  Future<void> equipTip(PathTip tip) => model.equipTip(tip);

  Future<StorePurchaseResult> watchCoinVideo({
    required bool Function() canPresent,
  }) async {
    if (!model.canEarnAdBonus) return const StorePurchaseNoop();
    if (!ads.videoReady) {
      await ads.prepare(canPresent: canPresent);
      return const StorePurchaseNoop();
    }
    final bonus = model.nextCoinVideoEarnsMilestone;
    var earned = 0;
    final shown = await ads.watchVideo((id) async {
      final ok = await model.grantAdBonus(id);
      if (ok) {
        earned =
            economy.rewardedAdCoins +
            (bonus ? economy.coinAdMilestoneBonus : 0);
      }
      return ok;
    }, canPresent: canPresent);
    if (shown && earned > 0) {
      return StorePurchaseSuccess(
        bonus
            ? 'Fourth video bonus: +$earned coins added.'
            : '+$earned coins added.',
      );
    }
    return const StorePurchaseNoop();
  }

  Future<void> buyPack(ProductDetails product) => billing.buy(product);

  Future<void> restorePurchases() => billing.restore();
}
