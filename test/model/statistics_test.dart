import 'package:flutter_test/flutter_test.dart';

import '../../lib/model/app_model.dart';
import '../../lib/model/economy.dart';
import '../../lib/viewmodels/statistics_viewmodel.dart';
import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Statistics & Achievements', () {
    test('empty, replay, and large campaign states compute accurately', () {
      final empty = AppModel(storage: MemoryStorage(), snapshot: {});
      final emptySummary = StatisticsSummary.fromModel(empty);
      expect(emptySummary.totalSolved, 0);
      expect(emptySummary.totalStars, 0);
      expect(emptySummary.unlockedAchievements, 0);
      expect(emptySummary.achievements.length, Achievement.values.length);
      empty.dispose();

      // Replay updates best stars without duplicating level count.
      final replay = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'results': {
            'levels/1': {'milliseconds': 15000, 'hints': 0, 'stars': 2},
            'levels/2': {'milliseconds': 10000, 'hints': 0, 'stars': 3},
            'levels/3': {'milliseconds': 90000, 'hints': 1, 'stars': 0},
          },
        },
      );
      final replaySummary = StatisticsSummary.fromModel(replay);
      expect(replaySummary.levelsSolved, 3);
      expect(replaySummary.totalStars, 5);
      expect(replaySummary.threeStar, 1);
      expect(replaySummary.twoStar, 1);
      expect(replaySummary.oneStar, 0);
      expect(replaySummary.zeroStar, 1);
      replay.dispose();

      // Large campaign (1500 levels) aggregates cleanly without lag.
      final largeResults = <String, dynamic>{
        for (var i = 1; i <= 1500; i++)
          'levels/$i': {
            'milliseconds': 12000,
            'hints': 0,
            'unassisted': true,
            'stars': i % 4,
          },
      };
      final large = AppModel(
        storage: MemoryStorage(),
        snapshot: {'results': largeResults},
      );
      final largeSummary = StatisticsSummary.fromModel(large);
      expect(largeSummary.levelsSolved, 1500);
      expect(
        largeSummary.threeStar +
            largeSummary.twoStar +
            largeSummary.oneStar +
            largeSummary.zeroStar,
        1500,
      );
      large.dispose();
    });
  });
}
