import '../model/app_model.dart';
import '../model/economy.dart';

sealed class FreezePurchaseResult {
  const FreezePurchaseResult();
}

final class FreezePurchased extends FreezePurchaseResult {
  const FreezePurchased();
}

final class FreezeInsufficientCoins extends FreezePurchaseResult {
  const FreezeInsufficientCoins(this.shortfall);
  final int shortfall;
}

final class FreezePurchaseUnavailable extends FreezePurchaseResult {
  const FreezePurchaseUnavailable();
}

/// Presentation logic for Play Streak and Streak Freeze purchases.
class StreakViewModel {
  StreakViewModel(this.model);

  final AppModel model;

  int get count => model.streak.count;
  bool get freezeFull => model.streak.freezes >= economy.maxFreezes;
  int get freezePrice => economy.freezePrice;

  Future<FreezePurchaseResult> buyFreeze() async {
    if (freezeFull) return const FreezePurchaseUnavailable();
    if (model.coinBalance < economy.freezePrice) {
      return FreezeInsufficientCoins(economy.freezePrice - model.coinBalance);
    }
    final ok = await model.buyFreeze();
    return ok ? const FreezePurchased() : const FreezePurchaseUnavailable();
  }
}
