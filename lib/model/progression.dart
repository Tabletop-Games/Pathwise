import 'dart:math';

import 'economy.dart';
import 'time_attack.dart';

enum Research {
  magnet('Coin Magnet', 'Level coins', 40, 10, 1),
  golden('Golden Route', 'Hint-free clear coins', 80, 8, 1),
  fortune('Daily Fortune', 'Daily clear coins', 90, 8, 2),
  mastery('Milestone Mastery', 'Achievement coins', 140, 6, 3),
  hunter('Treasure Hunter', 'Crate interval reduction', 100, 8, 3),
  collector(
    'Crate Collector',
    'Extra seconds to catch flying crates',
    80,
    9,
    1,
  ),
  efficiency('Boost Efficiency', 'Boost duration percent', 140, 8, 2),
  savings('Smart Savings', 'Consumable discount percent', 120, 6, 1),
  momentum('Momentum', 'Coins every fifth first clear', 120, 8, 2),
  specialist('Daily Specialist', 'Seven-day streak coins', 160, 6, 5),
  tuning('Boost Tuning', 'Boost duration percentage points', 180, 8, 1, true),
  procurement(
    'Contract Supply',
    'Boost price discount percentage points',
    160,
    8,
    1,
    true,
  ),
  scout(
    'Supply Routes',
    'Seconds removed from crate cooldowns',
    180,
    8,
    2,
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
    return owned * increment;
  }

  Research? get prerequisite => switch (this) {
    tuning => efficiency,
    procurement => savings,
    scout => hunter,
    _ => null,
  };
  int price(int rank) {
    RangeError.checkValueInInterval(rank, 0, limit - 1);
    return advanced
        ? base * [1, 2, 4, 7, 11, 16, 22, 30, 40, 52][rank]
        : base * (rank + 2) * (rank + 3) ~/ 6;
  }
}

enum Boost {
  doubleTen('Quick Charge', 5, 30, 2),
  doubleFifteen('Surge 15', 15, 36, 2),
  doubleThirty('Surge 30', 30, 72, 2),
  doubleSixty('Endurance', 15, 80, 2),
  tripleFifteen('Power Surge', 5, 65, 3),
  quadrupleTen('Royal Rush', 3, 75, 4),
  crateFrequency('Crate Radar', 15, 28, 1);

  const Boost(this.title, this.minutes, this.price, this.multiplier);
  final String title;
  final int minutes, price, multiplier;
  bool get availableToBuy =>
      this == doubleTen ||
      this == doubleSixty ||
      this == tripleFifteen ||
      this == quadrupleTen;
  String get slot => multiplier > 1 ? 'coins' : name;
  String get subtitle => switch (this) {
    doubleTen => 'Short 2× session sprint',
    doubleSixty => 'Best 2× value for longer play',
    tripleFifteen => 'High-yield 3× coin burst',
    quadrupleTen => 'Peak 4× speed-clear rush',
    crateFrequency => 'Twice as many crate drops',
    _ => '$multiplier× base campaign & daily coins',
  };
}

typedef Crate = ({String id, int coins});

const crateTopPrize = 90;

int crateCoins(int roll) =>
    switch (RangeError.checkValueInInterval(roll, 0, 99)) {
      < 35 => 20,
      < 65 => 35,
      < 85 => 55,
      < 95 => 75,
      _ => crateTopPrize,
    };

final class Progression {
  Progression(Map<String, dynamic> data)
    : ranks = Map<String, int>.from(data['ranks'] as Map? ?? {}),
      inventory = Map<String, int>.from(data['inventory'] as Map? ?? {}),
      active = Map<String, int>.from(data['active'] as Map? ?? {}),
      serial = data['serial'] as int? ?? 0,
      crateWait = (data['crateWait'] as int? ?? 45000).clamp(0, 150000),
      legendary = data['legendary'] as int? ?? 0 {
    for (final stamp in (data['crateDrops'] as List? ?? []).whereType<List>()) {
      if (stamp.length == 2 && stamp[0] is int && stamp[1] is int) {
        crateDrops.add((boot: stamp[0] as int, milliseconds: stamp[1] as int));
      }
    }
  }

  final Map<String, int> ranks, inventory, active;
  final crateDrops = <BootTime>[];
  int serial, crateWait, legendary;

  Duration get crateFlightTime =>
      Duration(seconds: 8 + effect(Research.collector));
  void accrueCrateTime(int elapsed) {
    crateWait = max(0, crateWait - max(0, elapsed));
  }

  void migrateCrates(
    Map<String, dynamic> data,
    BootTime? now,
    Object? savedBoot,
    String day,
  ) {
    if (data.containsKey('crateWait') || now == null) return;
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

  Crate? considerCrate(BootTime now, int Function() roll) {
    if (crateWait > 0) return null;
    crateDrops.removeWhere((stamp) {
      if (now.boot < stamp.boot) return false;
      final elapsed = now.boot == stamp.boot
          ? now.milliseconds - stamp.milliseconds
          : now.milliseconds;
      return elapsed >= const Duration(hours: 24).inMilliseconds;
    });
    if (crateDrops.length >= economy.cratesPerWindow) return null;
    final crate = (id: 'crate/${serial++}', coins: crateCoins(roll()));
    crateWait =
        (150 - effect(Research.hunter) - effect(Research.scout)) *
        (remaining(Boost.crateFrequency, now.milliseconds) > 0 ? 500 : 1000);
    crateDrops.add(now);
    return crate;
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
  };
}
