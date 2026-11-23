import 'dart:convert';

import 'progression.dart';
import 'time_attack.dart';

const fortuneWindowMs = 24 * 60 * 60 * 1000;

final class FortunePrize {
  const FortunePrize(this.id, this.label, this.weight, this.coins, this.boost);
  final String id, label;
  final int weight, coins;
  final Boost? boost;
}

final class FortuneCatalog {
  FortuneCatalog(String json)
    : prizes = List.unmodifiable(
        (jsonDecode(json) as List).cast<Map>().map(
          (row) => FortunePrize(
            row['id'] as String,
            row['label'] as String,
            row['weight'] as int,
            row['coins'] as int,
            row['boost'] == null
                ? null
                : Boost.values.byName(row['boost'] as String),
          ),
        ),
      ) {
    if (prizes.fold(0, (sum, prize) => sum + prize.weight) != 100 ||
        prizes.map((prize) => prize.id).toSet().length != prizes.length ||
        prizes.any((prize) => prize.weight <= 0 || prize.coins < 0)) {
      throw const FormatException('Invalid Fortune Wheel catalog');
    }
  }

  final List<FortunePrize> prizes;

  FortunePrize pick(int roll) {
    RangeError.checkValueInInterval(roll, 0, 99);
    var end = 0;
    return prizes.firstWhere((prize) {
      end += prize.weight;
      return roll < end;
    });
  }

  double center(FortunePrize prize) {
    var start = 0;
    for (final item in prizes) {
      if (item.id == prize.id) return (start + item.weight / 2) / 100;
      start += item.weight;
    }
    throw ArgumentError.value(prize.id);
  }
}

final class FortuneStatus {
  FortuneStatus.fromJson(Map data)
    : now = data['now'] as int,
      stamps = List<int>.from(data['stamps'] as List),
      counts = Map<String, int>.from(data['counts'] as Map),
      last = data['last'] as String?,
      receipt = data['receipt'] as String? {
    if (stamps.length > 4 ||
        stamps.any((stamp) => stamp <= now - fortuneWindowMs || stamp > now) ||
        counts.values.any((count) => count < 0 || count > (1 << 40))) {
      throw const FormatException('Invalid verified wheel state');
    }
  }

  final int now;
  final List<int> stamps;
  final Map<String, int> counts;
  final String? last, receipt;

  int remaining(int elapsed) =>
      4 -
      stamps
          .where(
            (stamp) =>
                stamp >
                now + elapsed.clamp(0, fortuneWindowMs) - fortuneWindowMs,
          )
          .length;
}

int freeFortuneWait(BootTime? last, BootTime? now) {
  if (now == null) return -1;
  if (last == null) return 0;
  // A new boot's uptime is a conservative lower bound on time since a spin
  // in an earlier boot. This is independent of the wall clock.
  final elapsed = now.boot == last.boot
      ? now.milliseconds - last.milliseconds
      : now.milliseconds;
  return (fortuneWindowMs - elapsed).clamp(0, fortuneWindowMs);
}
