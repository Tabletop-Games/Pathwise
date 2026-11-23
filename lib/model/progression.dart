import 'dart:math';

enum Research {
  magnet('Coin Magnet', 'Level coins per rank', 70, 10, 2),
  golden('Golden Route', 'Hint-free clear coins per rank', 100, 8, 2),
  fortune('Daily Fortune', 'Daily clear coins per rank', 100, 8, 4),
  mastery('Milestone Mastery', 'Achievement coins per rank', 180, 6, 5),
  hunter('Treasure Hunter', 'Crate interval reduction per rank', 120, 8, 4),
  lucky('Lucky Crates', 'Crate coins per rank', 130, 8, 3),
  rare('Rare Discovery', 'Rare chance percentage points per rank', 180, 6, 1),
  collector('Crate Collector', 'Collection seconds per rank', 90, 6, 8),
  efficiency('Boost Efficiency', 'Boost duration percent per rank', 160, 8, 5),
  savings('Smart Savings', 'Consumable discount percent per rank', 140, 6, 3),
  momentum('Momentum', 'Coins every fifth first clear per rank', 150, 8, 4),
  specialist('Daily Specialist', 'Seven-day streak coins per rank', 210, 6, 8),
  expedition('Expedition', 'Legendary crate coins per rank', 360, 5, 15);

  const Research(
    this.title,
    this.benefit,
    this.base,
    this.limit,
    this.increment,
  );
  final String title, benefit;
  final int base, limit, increment;
  int price(int rank) => base * (rank + 2) * (rank + 3) ~/ 6;
}

enum Boost {
  doubleTen('2× coins', 10, 35, 2),
  doubleFifteen('2× coins', 15, 50, 2),
  doubleThirty('2× coins', 30, 90, 2),
  tripleFifteen('3× coins', 15, 110, 3),
  quadrupleTen('4× coins', 10, 120, 4),
  crateFrequency('Twice as many crate opportunities', 15, 35, 1),
  crateValue('Double crate coins', 15, 55, 1),
  crateRarity('More rare crates', 15, 40, 1);

  const Boost(this.title, this.minutes, this.price, this.multiplier);
  final String title;
  final int minutes, price, multiplier;
  String get slot => multiplier > 1 ? 'coins' : name;
}

enum CrateRarity {
  common(12),
  uncommon(25),
  rare(55),
  legendary(150);

  const CrateRarity(this.coins);
  final int coins;
}

typedef Crate = ({String id, CrateRarity rarity, int coins, int deadline});

final class Progression {
  Progression(Map<String, dynamic> data)
    : ranks = Map<String, int>.from(data['ranks'] as Map? ?? {}),
      inventory = Map<String, int>.from(data['inventory'] as Map? ?? {}),
      active = Map<String, int>.from(data['active'] as Map? ?? {}),
      serial = data['serial'] as int? ?? 0,
      nextCrate = data['nextCrate'] as int? ?? 0,
      crateCount = data['crateCount'] as int? ?? 0,
      crateDay = data['crateDay'] as String? ?? '',
      legendary = data['legendary'] as int? ?? 0 {
    if (data['crate'] case final Map saved) {
      crate = (
        id: saved['id'] as String,
        rarity: CrateRarity.values.byName(saved['rarity'] as String),
        coins: saved['coins'] as int,
        deadline: saved['deadline'] as int,
      );
    }
  }

  final Map<String, int> ranks, inventory, active;
  int serial, nextCrate, crateCount, legendary;
  String crateDay;
  Crate? crate;

  int rank(Research item) => (ranks[item.name] ?? 0).clamp(0, item.limit);
  int effect(Research item) => rank(item) * item.increment;
  int discount(int price) =>
      (price * (100 - effect(Research.savings)) + 99) ~/ 100;
  int get refillPrice => discount(16);
  bool unlocked(Research item) =>
      item != Research.expedition || rank(Research.lucky) >= 3;
  int remaining(Boost boost, int now) =>
      max(0, (active[boost.name] ?? 0) - now);
  bool canActivate(Boost boost, int now) =>
      (inventory[boost.name] ?? 0) > 0 &&
      !Boost.values.any(
        (other) => other.slot == boost.slot && remaining(other, now) > 0,
      );
  int multiplier(int now) => Boost.values.fold(
    1,
    (value, boost) =>
        remaining(boost, now) > 0 ? max(value, boost.multiplier) : value,
  );

  void activate(Boost boost, int now) {
    inventory[boost.name] = inventory[boost.name]! - 1;
    active[boost.name] =
        now + boost.minutes * 600 * (100 + effect(Research.efficiency));
  }

  List<int> crateOdds(int now) {
    final bonus =
        effect(Research.rare) + (remaining(Boost.crateRarity, now) > 0 ? 8 : 0);
    return [75 - bonus, 18, 6 + bonus, 1];
  }

  bool considerCrate(int now, String day, int roll) {
    if (crateDay != day) {
      crateDay = day;
      crateCount = 0;
    }
    final existing = crate;
    if (existing != null && existing.deadline > now) return false;
    crate = null;
    if (crateCount >= 6 || now < nextCrate) return false;
    if (nextCrate == 0) {
      nextCrate = now + 45000;
      return false;
    }
    final odds = crateOdds(now);
    var ceiling = 0;
    final index = odds.indexWhere((value) {
      ceiling += value;
      return roll < ceiling;
    });
    final rarity = CrateRarity.values[index];
    final coins =
        (rarity.coins +
            effect(Research.lucky) +
            (rarity == CrateRarity.legendary
                ? effect(Research.expedition)
                : 0)) *
        (remaining(Boost.crateValue, now) > 0 ? 2 : 1);
    crate = (
      id: 'crate/${serial++}',
      rarity: rarity,
      coins: coins,
      deadline: now + (24 + effect(Research.collector)) * 1000,
    );
    nextCrate =
        now +
        (150 - effect(Research.hunter)) *
            (remaining(Boost.crateFrequency, now) > 0 ? 500 : 1000);
    crateCount++;
    return true;
  }

  Map<String, Object?> toJson() => {
    'ranks': ranks,
    'inventory': inventory,
    'active': active,
    'serial': serial,
    'nextCrate': nextCrate,
    'crateDay': crateDay,
    'crateCount': crateCount,
    'legendary': legendary,
    if (crate case final item?)
      'crate': {
        'id': item.id,
        'rarity': item.rarity.name,
        'coins': item.coins,
        'deadline': item.deadline,
      },
  };
}
