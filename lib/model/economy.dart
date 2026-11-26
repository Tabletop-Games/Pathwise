import 'game_state.dart';
import 'user_preferences.dart';

/// Stable cosmetic identifiers with rarity-tiered Economy 2.0 pricing.
enum PathTip {
  classic('Classic', 0),
  arrow('Arrow', 120),
  crystal('Crystal', 120),
  star('Star', 120),
  cat('Cat', 120),
  dog('Dog', 120),
  rabbit('Rabbit', 120),
  fox('Fox', 250),
  panda('Panda', 250),
  frog('Frog', 250),
  penguin('Penguin', 250),
  turtle('Turtle', 250),
  bee('Bee', 250),
  ghost('Ghost', 500),
  robot('Robot', 500),
  ufo('UFO', 500),
  flame('Flame', 500),
  rocket('Rocket', 500),
  dragon('Dragon', 900),
  phoenix('Phoenix', 900);

  const PathTip(this.label, this.price);
  final String label;
  final int price;

  static PathTip? fromId(Object? id) {
    for (final tip in values) {
      if (tip.name == id) return tip;
    }
    return null;
  }
}

const economy = EconomyRules();

class EconomyRules {
  const EconomyRules();

  int get starterCoins => 50;
  int get streakBonus => 25;
  int get streakInterval => 7;
  static const automaticAdGap = Duration(minutes: 3);
  Duration get afterRewardedGap => const Duration(minutes: 1);
  int get exitsPerInterstitial => 5;
  int get premiumBonus => 1000;
  int get rewardedAdCoins => 20;
  int get rewardedAdsPerDay => 6;
  int get starterHints => 3;
  int get hintPrice => 40;
  int get hintAdsPerDay => 5;
  int get coinAdMilestone => 4;
  int get coinAdMilestoneBonus => 40;
  int get doubleBoostAdsPerDay => 3;
  int get wheelAdsPerDay => 6;
  int get cratesPerWindow => 8;
  int attackReward(int solves) =>
      solves < 2 ? 0 : (solves < 8 ? solves : 8) * 3;
  int get freezePrice => 150;
  int get maxFreezes => 2;
  static const milestones = <int, ({int coins, int hints})>{
    1: (coins: 20, hints: 0),
    3: (coins: 50, hints: 0),
    7: (coins: 100, hints: 1),
    14: (coins: 200, hints: 1),
    30: (coins: 400, hints: 2),
    60: (coins: 600, hints: 2),
    100: (coins: 1000, hints: 3),
    150: (coins: 1200, hints: 3),
    200: (coins: 1500, hints: 3),
  };
  int clearReward(PlayMode mode) => switch (mode) {
    PlayMode.levels => 5,
    PlayMode.daily => 10,
    PlayMode.attack => 0,
  };

  /// Centralized Economy 2.0 campaign first-clear payout:
  /// timed boosts multiply `(baseReward + stars)`; research bonuses are additive.
  int campaignClearCoins({
    required int multiplier,
    required int magnetBonus,
    required int goldenBonus,
    required int momentumBonus,
    int stars = 0,
  }) =>
      (clearReward(PlayMode.levels) + stars) * multiplier +
      magnetBonus +
      goldenBonus +
      momentumBonus;

  /// Centralized Economy 2.0 daily challenge first-clear payout:
  /// timed boosts multiply only the base reward; research bonuses are additive.
  int dailyClearCoins({
    required int multiplier,
    required int fortuneBonus,
    required int goldenBonus,
  }) => clearReward(PlayMode.daily) * multiplier + fortuneBonus + goldenBonus;

  /// Post-completion rewarded video bonus on campaign first clears.
  /// Eligible base includes the newly earned star bonus without compounding
  /// timed boosts or permanent research.
  int completionBonusCoins(int multiplier, {int stars = 0}) =>
      (clearReward(PlayMode.levels) + stars) * (multiplier - 1);

  String tipRarity(PathTip tip) => switch (tip.price) {
    <= 0 => 'Starter',
    <= 120 => 'Common',
    <= 250 => 'Uncommon',
    <= 500 => 'Rare',
    _ => 'Epic',
  };

  int themePrice(PathwiseTheme theme) => switch (theme) {
    PathwiseTheme.field ||
    PathwiseTheme.blackwater ||
    PathwiseTheme.terracotta ||
    PathwiseTheme.signal => 0,
    PathwiseTheme.forestMint || PathwiseTheme.warmWalnut => 90,
    PathwiseTheme.glacier || PathwiseTheme.midnightSlate => 140,
    PathwiseTheme.oceanicBreeze || PathwiseTheme.royalVelvet => 220,
    PathwiseTheme.chalk || PathwiseTheme.amoledCarbon => 500,
    PathwiseTheme.canyon => 4500,
    PathwiseTheme.tidal => 12000,
    PathwiseTheme.parchment || PathwiseTheme.violet => 500,
    PathwiseTheme.koi || PathwiseTheme.crt => 1000,
    PathwiseTheme.neon => 30000,
    PathwiseTheme.gilded => 60000,
    PathwiseTheme.basinGold => 1000,
    PathwiseTheme.copperSky => 4500,
    PathwiseTheme.highPass => 12000,
  };
}

enum Achievement {
  trailhead('Trailhead', 'Complete a level', 20),
  trailblazer('Trailblazer', 'Complete 12 levels', 40),
  pathfinder('Pathfinder', 'Complete 50 levels', 80),
  dailyHabit('Daily habit', 'Reach a 3-day streak', 25),
  weeklyRitual('Weekly ritual', 'Reach a 7-day streak', 45),
  unaided('Unaided', 'Solve 10 puzzles without hints', 35),
  collector('Collector', 'Own 6 themes', 30),
  timeTrial('Time trial', 'Solve 3 puzzles in one Time Attack', 25),
  twentyFive('Surveyor', 'Clear 25 levels', 50),
  hundred('Cartographer', 'Clear 100 levels', 100),
  fiveHundred('Navigator', 'Clear 500 levels', 250),
  thousand('Trail legend', 'Clear 1,000 levels', 500),
  researcher('Applied research', 'Buy 10 research ranks', 50),
  legendaryCrate('Legendary supply', 'Collect a legendary crate', 60);

  const Achievement(this.title, this.description, this.coins);
  final String title;
  final String description;
  final int coins;
}

final class CoinTransaction {
  const CoinTransaction(this.id, this.label, this.amount, this.date);

  final String id;
  final String label;
  final int amount;
  final DateTime date;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'amount': amount,
    'at': date.toUtc().toIso8601String(),
  };
}

/// Stable event IDs make retries idempotent. Archived credits remain part of the balance.
final class Wallet {
  Wallet(Object? saved, DateTime now, {int archivedCoins = 0})
    : _earned = archivedCoins,
      _archivedCoins = archivedCoins {
    if (saved is List) {
      for (final row in saved) {
        if (row is! Map)
          throw const FormatException('Invalid coin transaction');
        final id = row['id'];
        final label = row['label'];
        final amount = row['amount'];
        final at = row['at'];
        if (id is! String ||
            label is! String ||
            amount is! int ||
            at is! String) {
          throw const FormatException('Invalid coin transaction');
        }
        final date = DateTime.tryParse(at);
        if (date == null || !add(id, label, amount, date)) {
          throw const FormatException('Invalid coin ledger');
        }
      }
    } else if (saved == null) {
      add('starter', 'Welcome coins', economy.starterCoins, now);
    } else {
      throw const FormatException('Invalid coin ledger');
    }
  }

  final _history = <String, CoinTransaction>{};
  int _earned;
  int _archivedCoins;
  int get archivedCoins => _archivedCoins;
  final _recentRewardIds = <String>[];
  int _spent = 0;
  int get earned => _earned;
  int get spent => _spent;
  int get balance => earned - spent;
  Iterable<CoinTransaction> get history => _history.values;
  bool contains(String id) => _history.containsKey(id);
  int amountOf(String id) => _history[id]?.amount ?? 0;

  bool add(String id, String label, int amount, DateTime date) {
    if (contains(id) || balance + amount < 0 || amount == 0) return false;
    _history[id] = CoinTransaction(id, label, amount, date);
    if ((id.startsWith('trail/') ||
            id.startsWith('wheel/') ||
            id.startsWith('notes/')) &&
        amount > 0) {
      _recentRewardIds.add(id);
      if (_recentRewardIds.length > 32) {
        final removed = _history.remove(_recentRewardIds.removeAt(0))!;
        _archivedCoins += removed.amount;
      }
    }
    if (amount > 0) {
      _earned += amount;
    } else {
      _spent -= amount;
    }
    return true;
  }

  List<Map<String, Object>> toJson() => [
    for (final transaction in history) transaction.toJson(),
  ];
}
