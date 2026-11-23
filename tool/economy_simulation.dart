import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import '../lib/model/progression.dart';
import '../lib/model/user_preferences.dart';

void main() {
  const crateCollectionRate = 0.7;
  const rarities = [75, 18, 6, 1];
  final crateValue = [
    for (var i = 0; i < rarities.length; i++)
      rarities[i] * CrateRarity.values[i].coins / 100,
  ].reduce((a, b) => a + b);
  final upgradeCost = Research.values
      .expand((item) => List.generate(item.limit, item.price))
      .reduce((a, b) => a + b);
  final theme = economy.themePrice(PathwiseTheme.forestMint);
  print('Base crate EV: ${crateValue.toStringAsFixed(2)} coins');
  print('Research ceiling: $upgradeCost coins');
  for (final profile in [
    (name: 'Casual, no ads', minutes: 15, levels: 4, ads: 0, paid: 0),
    (name: 'Average, no ads', minutes: 30, levels: 10, ads: 0, paid: 0),
    (name: 'Engaged, no ads', minutes: 60, levels: 25, ads: 0, paid: 0),
    (name: 'Average, rewarded ads', minutes: 30, levels: 10, ads: 3, paid: 0),
    (name: 'Average, Starter pack', minutes: 30, levels: 10, ads: 0, paid: 500),
  ]) {
    final offers = ((profile.minutes * 60 - 45) ~/ 150 + 1).clamp(0, 6);
    final crates = crateValue * offers * crateCollectionRate;
    final perSession =
        profile.levels * economy.clearReward(PlayMode.levels) +
        economy.clearReward(PlayMode.daily) +
        profile.ads * economy.rewardedAdCoins +
        crates;
    final income = perSession * 60 / profile.minutes;
    final starter =
        economy.starterCoins + Achievement.trailhead.coins + profile.paid;
    double minutesTo(int price) =>
        (price - starter).clamp(0, price) * 60 / income;
    print(
      '${profile.name}: ${income.toStringAsFixed(0)} coins/hour, '
      '${crates.toStringAsFixed(0)} crate coins/session, '
      '${minutesTo(Research.magnet.base).toStringAsFixed(1)} min to Magnet, '
      '${minutesTo(theme).toStringAsFixed(1)} min to first paid theme',
    );
  }
  for (final boost in Boost.values.where((item) => item.multiplier > 1)) {
    final bonus = (boost.multiplier - 1) * economy.clearReward(PlayMode.levels);
    print(
      '${boost.title}, ${boost.minutes}m: '
      '${(boost.price / bonus).ceil()} eligible clears to break even',
    );
  }
}
