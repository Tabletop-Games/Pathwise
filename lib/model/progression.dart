import 'dart:math';

import 'time_attack.dart';

enum Research {
  magnet('Coin Magnet', 'Level coins', 70, 10, 2),
  golden('Golden Route', 'Hint-free clear coins', 100, 8, 2),
  fortune('Daily Fortune', 'Daily clear coins', 100, 8, 4),
  mastery('Milestone Mastery', 'Achievement coins', 180, 6, 5),
  hunter('Treasure Hunter', 'Crate interval reduction', 120, 8, 4),
  lucky('Lucky Crates', 'Crate coins', 130, 8, 3),
  rare('Rare Discovery', 'Rare chance percentage points', 180, 6, 1),
  collector('Crate Collector', 'Unopened crate slots', 90, 6, 1),
  efficiency('Boost Efficiency', 'Boost duration percent', 160, 8, 5),
  savings('Smart Savings', 'Consumable discount percent', 140, 6, 3),
  momentum('Momentum', 'Coins every fifth first clear', 150, 8, 4),
  specialist('Daily Specialist', 'Seven-day streak coins', 210, 6, 8),
  legendaryCache('Legendary Cache', 'Legendary crate coins', 360, 5, 15),
  salvage(
    'Rare Salvage',
    'Additional coins in each rare crate',
    180,
    10,
    8,
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
    legendaryCache => lucky,
    salvage => rare,
    tuning => efficiency,
    procurement => savings,
    scout => hunter,
    discovery => legendaryCache,
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

typedef Crate = ({String id, CrateRarity rarity, int coins});

final class Progression {
  Progression(Map<String, dynamic> data)
    : ranks = Map<String, int>.from(data['ranks'] as Map? ?? {}),
      inventory = Map<String, int>.from(data['inventory'] as Map? ?? {}),
      active = Map<String, int>.from(data['active'] as Map? ?? {}),
      serial = data['serial'] as int? ?? 0,
      crateWait = (data['crateWait'] as int? ?? 45000).clamp(0, 150000),
      legendary = data['legendary'] as int? ?? 0 {
    if (ranks.remove('expedition') case final rank?) {
      ranks.putIfAbsent(Research.legendaryCache.name, () => rank);
    }
    final saved =
        data['crates'] as List? ??
        [if (data['crate'] case final Map crate) crate];
    for (final row in saved.whereType<Map>()) {
      final id = row['id'];
      final coins = row['coins'];
      final rarity = CrateRarity.values
          .where((r) => r.name == row['rarity'])
          .firstOrNull;
      if (id is String &&
          coins is int &&
          coins > 0 &&
          rarity != null &&
          !crates.any((item) => item.id == id)) {
        crates.add((id: id, rarity: rarity, coins: coins));
      }
    }
    for (final stamp in (data['crateDrops'] as List? ?? []).whereType<List>()) {
      if (stamp.length == 2 && stamp[0] is int && stamp[1] is int) {
        crateDrops.add((boot: stamp[0] as int, milliseconds: stamp[1] as int));
      }
    }
  }

  final Map<String, int> ranks, inventory, active;
  final crates = <Crate>[];
  final crateDrops = <BootTime>[];
  int serial, crateWait, legendary;

  int get crateCapacity => 1 + effect(Research.collector);
  void accrueCrateTime(int elapsed) {
    crateWait = max(0, crateWait - max(0, elapsed));
  }

  void migrateCrates(
    Map<String, dynamic> data,
    BootTime? now,
    Object? savedBoot,
    String day,
  ) {
    if (data.containsKey('crates') || now == null) return;
    final due = data['nextCrate'];
    if (savedBoot == now.boot && due is int && due > 0) {
      crateWait = (due - now.milliseconds).clamp(0, 150000);
    }
    if (data['crateDay'] == day && data['crateCount'] is int) {
      crateDrops.addAll(
        List.filled((data['crateCount'] as int).clamp(0, 6), now),
      );
    }
  }

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

  bool considerCrate(BootTime now, int Function() roll) {
    if (crateWait > 0 || crates.length >= crateCapacity) return false;
    crateDrops.removeWhere((stamp) {
      if (now.boot < stamp.boot) return false;
      final elapsed = now.boot == stamp.boot
          ? now.milliseconds - stamp.milliseconds
          : now.milliseconds;
      return elapsed >= const Duration(hours: 24).inMilliseconds;
    });
    if (crateDrops.length >= 6) return false;
    final draw = RangeError.checkValueInInterval(roll(), 0, 99);
    final odds = crateOdds(now.milliseconds);
    var ceiling = 0;
    final index = odds.indexWhere((value) {
      ceiling += value;
      return draw < ceiling;
    });
    final rarity = CrateRarity.values[index];
    final coins =
        (rarity.coins +
            effect(Research.lucky) +
            (rarity == CrateRarity.rare ? effect(Research.salvage) : 0) +
            (rarity == CrateRarity.legendary
                ? effect(Research.legendaryCache)
                : 0)) *
        (remaining(Boost.crateValue, now.milliseconds) > 0 ? 2 : 1);
    crates.add((id: 'crate/${serial++}', rarity: rarity, coins: coins));
    crateWait =
        (150 - effect(Research.hunter) - effect(Research.scout)) *
        (remaining(Boost.crateFrequency, now.milliseconds) > 0 ? 500 : 1000);
    crateDrops.add(now);
    return true;
  }

  Map<String, Object?> toJson() => {
    'ranks': ranks,
    'inventory': inventory,
    'active': active,
    'serial': serial,
    'crateWait': crateWait,
    'crateDrops': [
      for (final drop in crateDrops) [drop.boot, drop.milliseconds],
    ],
    'legendary': legendary,
    'crates': [
      for (final item in crates)
        {'id': item.id, 'rarity': item.rarity.name, 'coins': item.coins},
    ],
  };
}
