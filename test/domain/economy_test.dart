import 'package:flutter_test/flutter_test.dart';

import '../../lib/model/economy.dart';
import '../../lib/model/progression.dart';

void main() {
  test(
    'Economy 2.0 does not compound research bonuses with timed boosts',
    () {
      expect(
        economy.campaignClearCoins(
          multiplier: 4,
          magnetBonus: 10,
          goldenBonus: 8,
          momentumBonus: 0,
        ),
        38,
      );
      expect(
        economy.campaignClearCoins(
          multiplier: 4,
          magnetBonus: 10,
          goldenBonus: 8,
          momentumBonus: 16,
        ),
        54,
      );
      expect(
        economy.dailyClearCoins(
          multiplier: 4,
          fortuneBonus: 16,
          goldenBonus: 8,
        ),
        64,
      );
    },
  );

  test('advanced cost and benefit bounds and single-slot boost caps hold', () {
    final progress = Progression({
      'ranks': {for (final item in Research.values) item.name: item.limit + 5},
      'inventory': {for (final boost in Boost.values) boost.name: 1},
    });
    for (final item in Research.values) {
      final costs = List.generate(item.limit, item.price);
      expect(costs, everyElement(greaterThan(0)));
      expect(costs.last, lessThan(200000));
      for (var i = 1; i < costs.length; i++) {
        expect(costs[i], greaterThan(costs[i - 1]));
        expect(item.effectAt(i + 1), greaterThan(item.effectAt(i)));
      }
      expect(progress.rank(item), item.limit);
      expect(() => item.price(item.limit), throwsRangeError);
    }
    expect(progress.durationBonus, 24);
    expect(progress.discount(100), 86);
    progress.activate(Boost.quadrupleTen, 1);
    expect(progress.canActivate(Boost.doubleTen, 2), false);
    expect(progress.multiplier(2), 4);
    expect(progress.multiplier(2), 4);
  });
}
