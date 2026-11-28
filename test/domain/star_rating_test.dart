import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../lib/cloud/cloud_save_format.dart';
import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/puzzle_generator.dart';
import '../../lib/logic/star_rating.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/game_state.dart';
import '../../lib/ui/art/game_assets.dart';
import '../../lib/views/components/tip_art.dart';
import '../../lib/views/main_menu_view.dart';
import '../support/fixtures.dart' show MemoryStorage, complete, fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Star rating thresholds', () {
    test('baseline 1.0x boundary behavior is exact', () {
      const t = StarThresholds(
        threeStarMs: 10000,
        twoStarMs: 20000,
        oneStarMs: 30000,
        multiplier: 1.0,
      );
      expect(t.rate(0), 3);
      expect(t.rate(9999), 3);
      expect(t.rate(10000), 2);
      expect(t.rate(20000), 2);
      expect(t.rate(20001), 1);
      expect(t.rate(30000), 1);
      expect(t.rate(30001), 0);
      expect(t.rate(-1), 0);
    });

    test('difficulty scaling is deterministic, bounded, and replay-stable', () {
      final b1 = generatePuzzle(const PuzzleId.level(1).generation, level: 1);
      final b2 = generatePuzzle(const PuzzleId.level(1).generation, level: 1);
      final t1 = starThresholdsForBoard(b1);
      final t2 = starThresholdsForBoard(b2);
      expect(t1.multiplier, t2.multiplier);
      expect(t1.threeStarMs, t2.threeStarMs);
      expect(t1.twoStarMs, t2.twoStarMs);
      expect(t1.oneStarMs, t2.oneStarMs);

      final b350 = generatePuzzle(
        const PuzzleId.level(350).generation,
        level: 350,
      );
      final t350 = starThresholdsForBoard(b350);
      expect(t350.multiplier, inInclusiveRange(1.0, 4.0));
      expect(t350.threeStarMs, greaterThanOrEqualTo(t1.threeStarMs));
    });
  });
}
