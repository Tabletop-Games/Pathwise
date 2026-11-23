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
    PlayMode.expedition || PlayMode.attack => 0,
  };
  int expeditionReward(int trail, int stages, {required bool qualified}) =>
      switch (stages) {
        3 || 6 => trail <= 3 ? 12 : 4,
        10 when qualified => trail <= 3 ? 36 : 20 + (trail ~/ 10).clamp(0, 12),
        _ => 0,
      };

  int expeditionMilestone(int trail) => switch (trail) {
    3 => 0, // Basin Gold is the existing reward.
    10 => 24,
    25 => 30,
    50 => 42,
    100 => 60,
    _ when trail > 100 && trail % 100 == 0 => 60,
    _ when trail > 100 && trail % 25 == 0 => 24,
    _ => 0,
  };
  int nextExpeditionMilestone(int trail) => switch (trail) {
    <= 3 => 3,
    <= 10 => 10,
    <= 25 => 25,
    <= 50 => 50,
    <= 100 => 100,
    _ => (trail ~/ 25 + (trail % 25 == 0 ? 0 : 1)) * 25,
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
    PathwiseTheme.basinGold ||
    PathwiseTheme.copperSky ||
    PathwiseTheme.highPass => 0,
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
  legendaryCrate('Legendary supply', 'Collect a legendary crate', 60),
  expeditionClear('Field guide', 'Qualify on an expedition trail', 30);

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

/// Stable event IDs make retries idempotent. The Expedition frontier proves
/// older trail credits are spent opportunities after they leave the ledger.
final class Wallet {
  Wallet(Object? saved, DateTime now, {int archivedTrailCoins = 0})
    : _earned = archivedTrailCoins,
      _archivedTrailCoins = archivedTrailCoins {
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
  int _archivedTrailCoins;
  int get archivedTrailCoins => _archivedTrailCoins;
  final _recentTrailIds = <String>[];
  int _spent = 0;
  int get earned => _earned;
  int get spent => _spent;
  int get balance => earned - spent;
  Iterable<CoinTransaction> get history => _history.values;
  bool contains(String id) => _history.containsKey(id);

  bool add(String id, String label, int amount, DateTime date) {
    if (contains(id) || balance + amount < 0 || amount == 0) return false;
    _history[id] = CoinTransaction(id, label, amount, date);
    if (id.startsWith('trail/') && amount > 0) {
      _recentTrailIds.add(id);
      if (_recentTrailIds.length > 32) {
        final removed = _history.remove(_recentTrailIds.removeAt(0))!;
        _archivedTrailCoins += removed.amount;
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
