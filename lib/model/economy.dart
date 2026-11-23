import 'game_state.dart';
import 'user_preferences.dart';

const economy = EconomyRules();

class EconomyRules {
  const EconomyRules();

  int get starterCoins => 40;
  int get streakBonus => 35;
  int get streakInterval => 7;
  Duration get automaticAdGap => const Duration(minutes: 4);
  Duration get afterRewardedGap => const Duration(minutes: 1);
  int get exitsPerInterstitial => 5;
  int get premiumBonus => 1000;
  int get rewardedAdCoins => 8;
  int get rewardedAdsPerDay => 3;
  int clearReward(PlayMode mode) => switch (mode) {
    PlayMode.levels => 12,
    PlayMode.daily => 24,
    PlayMode.endless || PlayMode.attack => 0,
  };
  int themePrice(PathwiseTheme theme) => switch (theme) {
    PathwiseTheme.field ||
    PathwiseTheme.blackwater ||
    PathwiseTheme.terracotta => 0,
    PathwiseTheme.forestMint || PathwiseTheme.warmWalnut => 110,
    PathwiseTheme.glacier || PathwiseTheme.midnightSlate => 160,
    PathwiseTheme.oceanicBreeze || PathwiseTheme.royalVelvet => 220,
    PathwiseTheme.chalk || PathwiseTheme.amoledCarbon => 500,
    PathwiseTheme.canyon || PathwiseTheme.tidal => 1000,
    PathwiseTheme.parchment ||
    PathwiseTheme.violet ||
    PathwiseTheme.signal => 500,
    PathwiseTheme.koi || PathwiseTheme.crt => 1000,
    PathwiseTheme.neon || PathwiseTheme.gilded => 1500,
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

/// Currency is an append-only ledger. Stable event IDs make retries idempotent.
final class Wallet {
  Wallet(Object? saved, DateTime now) {
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
  int _earned = 0;
  int _spent = 0;
  int get earned => _earned;
  int get spent => _spent;
  int get balance => earned - spent;
  Iterable<CoinTransaction> get history => _history.values;
  bool contains(String id) => _history.containsKey(id);

  bool add(String id, String label, int amount, DateTime date) {
    if (contains(id) || balance + amount < 0 || amount == 0) return false;
    _history[id] = CoinTransaction(id, label, amount, date);
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
