import 'dart:math';

enum Research {
  magnet('Coin Magnet', 'Level coins', 70, 10, 2),
  golden('Golden Route', 'Hint-free clear coins', 100, 8, 2),
  fortune('Daily Fortune', 'Daily clear coins', 100, 8, 4),
  mastery('Milestone Mastery', 'Achievement coins', 180, 6, 5),
  hunter('Treasure Hunter', 'Crate interval reduction', 120, 8, 4),
  lucky('Lucky Crates', 'Crate coins', 130, 8, 3),
  rare('Rare Discovery', 'Rare chance percentage points', 180, 6, 1),
  collector('Crate Collector', 'Collection seconds', 90, 6, 8),
  efficiency('Boost Efficiency', 'Boost duration percent', 160, 8, 5),
  savings('Smart Savings', 'Consumable discount percent', 140, 6, 3),
  momentum('Momentum', 'Coins every fifth first clear', 150, 8, 4),
  specialist('Daily Specialist', 'Seven-day streak coins', 210, 6, 8),
  expedition('Legendary Cache', 'Legendary crate coins', 360, 5, 15),
  trailYield(
    'Trail Dividend',
    'Coins on first trail qualification',
    260,
    10,
    5,
    true,
  ),
  salvage(
    'Rare Salvage',
    'Additional coins in each rare crate',
    180,
    10,
    8,
    true,
  ),
  fieldwork(
    'Fieldwork',
    'Additional coins per daily objective',
    210,
    10,
    2,
    true,
  ),
  tuning('Boost Tuning', 'Boost duration percentage points', 190, 8, 4, true),
  procurement(
    'Contract Supply',
    'Boost price discount percentage points',
    160,
    8,
    2,
    true,
  ),
  scout(
    'Supply Routes',
    'Seconds removed from crate cooldowns',
    200,
    8,
    3,
    true,
  ),
  discovery(
    'Legendary Discovery',
    'Legendary chance percentage points',
    240,
    4,
    1,
    true,
  );

  const Research(
    this.title,
    this.benefit,
    this.base,
    this.limit,
    this.increment, [
    this.advanced = false,
  ]);
  final String title, benefit;
  final int base, limit, increment;
  final bool advanced;
  int effectAt(int rank) {
    final owned = rank < 0
        ? 0
        : rank > limit
        ? limit
        : rank;
    final extra = owned > 8 ? 2 * (owned - 8) : 0;
    return (owned + extra) * increment;
  }

  Research? get prerequisite => switch (this) {
    expedition => lucky,
    trailYield => momentum,
    salvage => rare,
    fieldwork => specialist,
    tuning => efficiency,
    procurement => savings,
    scout => hunter,
    discovery => expedition,
    _ => null,
  };
  int price(int rank) {
    RangeError.checkValueInInterval(rank, 0, limit - 1);
    return advanced
        ? base * [1, 3, 7, 16, 38, 80, 150, 260, 420, 600][rank]
        : base * (rank + 2) * (rank + 3) ~/ 6;
  }
}

enum Boost {
  doubleTen('2× coins', 10, 35, 2),
  doubleFifteen('2× coins', 15, 50, 2),
  doubleThirty('2× coins', 30, 90, 2),
  doubleSixty('2× coins', 60, 195, 2),
  trailProvisions('50% more first-qualification base coins', 20, 12, 1),
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
  int effect(Research item) => item.effectAt(rank(item));
  int discount(int price) =>
      (price * (100 - effect(Research.savings) - effect(Research.procurement)) +
          99) ~/
      100;
  int get refillPrice => 16;
  bool unlocked(Research item) =>
      item.prerequisite == null || rank(item.prerequisite!) >= 3;
  int get durationBonus =>
      effect(Research.efficiency) + effect(Research.tuning);
  int trailQualification(int base, int now) {
    final boosted = remaining(Boost.trailProvisions, now) > 0;
    return base + (boosted ? base ~/ 2 : 0) + effect(Research.trailYield);
  }

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
    active[boost.name] = now + boost.minutes * 600 * (100 + durationBonus);
  }

  List<int> crateOdds(int now) {
    final bonus =
        effect(Research.rare) + (remaining(Boost.crateRarity, now) > 0 ? 8 : 0);
    final legendary = effect(Research.discovery);
    return [75 - bonus - legendary, 18, 6 + bonus, 1 + legendary];
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
            (rarity == CrateRarity.rare ? effect(Research.salvage) : 0) +
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
        (150 - effect(Research.hunter) - effect(Research.scout)) *
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
