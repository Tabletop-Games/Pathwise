import '../model/app_model.dart';
import '../model/economy.dart';
import '../model/progression.dart';

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
  int get freezes => model.streak.freezes;
  bool get freezeFull => model.streak.freezes >= economy.maxFreezes;
  int get freezePrice => economy.freezePrice;
  int get maxFreezes => economy.maxFreezes;
  int get streakInterval => economy.streakInterval;
  int get weeklyBonus =>
      economy.streakBonus + model.progression.effect(Research.specialist);

  int get weeklyProgress => count > 0 && count % streakInterval == 0
      ? streakInterval
      : count % streakInterval;

  List<({int days, ({int coins, int hints}) reward, bool reached})>
  get milestones => [
    for (final entry in EconomyRules.milestones.entries)
      (days: entry.key, reward: entry.value, reached: count >= entry.key),
  ];

  Future<FreezePurchaseResult> buyFreeze() async {
    if (freezeFull) return const FreezePurchaseUnavailable();
    if (model.coinBalance < economy.freezePrice) {
      return FreezeInsufficientCoins(economy.freezePrice - model.coinBalance);
    }
    final ok = await model.buyFreeze();
    return ok ? const FreezePurchased() : const FreezePurchaseUnavailable();
  }
}
