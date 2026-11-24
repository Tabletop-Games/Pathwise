import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import '../lib/model/journey.dart';

void main() {
  final base = economy.clearReward(PlayMode.levels);
  for (final (label, clears, normalPerClear, fraction, exhausted) in [
    ('Casual, no ads', 3, 5, 0.0, false),
    ('Casual, occasional ads', 3, 5, .20, false),
    ('Regular', 10, 5, .30, false),
    ('Dedicated', 25, 5, .35, false),
    ('Active boost', 10, 10, .30, false),
    ('Substantial research', 10, 21, .30, false),
    ('Premium', 10, 5, .10, false),
    ('Catalogue exhausted', 10, 5, .30, true),
  ]) {
    var previousEnd = 0.0;
    var extraMultiplier = 0.0;
    for (final (end, multiplier) in multiplierRegions) {
      extraMultiplier += (end - previousEnd) * (multiplier - 1);
      previousEnd = end;
    }
    final normal = normalPerClear * clears;
    final videos = clears * .9 * fraction;
    final bonus = videos * base * extraMultiplier;
    final discoveries = clears / discoveryInterval;
    final claims = discoveries * fraction;
    final fallback = exhausted ? claims * discoveryFallbackCoins : 0.0;
    final total = normal + bonus + fallback;
    print(
      '$label: ${normal.toStringAsFixed(1)} → ${total.toStringAsFixed(1)} coins/day; '
      '+${bonus.toStringAsFixed(1)} multiplier; +${fallback.toStringAsFixed(1)} fallback; '
      '${(exhausted ? 0 : claims).toStringAsFixed(2)} cosmetics/day; '
      '${(videos + claims).toStringAsFixed(1)} videos/day; '
      '${(100 / total).toStringAsFixed(1)} days per 100 coins',
    );
  }
}
