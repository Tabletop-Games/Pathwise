import 'dart:convert';

import 'time_attack.dart';

const fortuneWindowMs = 24 * 60 * 60 * 1000;

final class FortunePrize {
  const FortunePrize(this.id, this.label, this.weight, this.coins);
  final String id, label;
  final int weight, coins;
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
          ),
        ),
      ) {
    if (prizes.length != segmentCount ||
        prizes.fold(0, (sum, prize) => sum + prize.weight) != 100 ||
        prizes.map((prize) => prize.id).toSet().length != prizes.length ||
        prizes.any((prize) => prize.weight <= 0 || prize.coins <= 0)) {
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

  static const segmentCount = 6;
  static const segmentTurns = 1 / segmentCount;

  double center(FortunePrize prize) {
    final index = prizes.indexWhere((item) => item.id == prize.id);
    if (index < 0) throw ArgumentError.value(prize.id);
    return (index + .5) * segmentTurns;
  }

  double destination(double current, FortunePrize prize, {int rotations = 5}) =>
      current + rotations + ((1 - center(prize) - current) % 1);

  FortunePrize atPointer(double rotation) =>
      prizes[(((-rotation) % 1) * segmentCount).floor() % segmentCount];
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
