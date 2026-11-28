import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/cloud/cloud_save_format.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/game_state.dart';

import '../support/fixtures.dart';

AppModel _model(MemoryStorage storage, Map<String, dynamic> snapshot) =>
    AppModel(
      storage: storage,
      snapshot: snapshot,
      loader: (_) async => fixture(),
      bootTime: () => (boot: 1, milliseconds: 100),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Star rewards, replay and cloud sync', () {
    test(
      'first clear applies boost to (base + stars) and keeps research additive',
      () async {
        final storage = MemoryStorage();
        final model = _model(storage, {
          'progressionBoot': 1,
          'progression': {
            'ranks': {'magnet': 2}, // +2 additive
            'active': {'tripleFifteen': 100000}, // 3x boost
          },
        });
        await model.open(const PuzzleId.level(1));
        complete(model); // ~0ms -> 3 stars
        expect(model.attemptStars, 3);
        expect(model.starsFor(const PuzzleId.level(1)), 3);
        // (5 + 3) * 3 + 2 (magnet) + 0 (golden) = 26, plus Trailhead achievement (20) = 46
        expect(model.completionCoins, 26);
        expect(model.earnedStarCoins, 9);
        expect(model.highestUnlocked, 2);
        model.dispose();
      },
    );

    test('zero-star completion still unlocks the next level', () async {
      final model = _model(MemoryStorage(), {});
      await model.open(const PuzzleId.level(1));
      model.addElapsedForTest(const Duration(seconds: 95));
      complete(model);
      expect(model.attemptStars, 0);
      expect(model.starsFor(const PuzzleId.level(1)), 0);
      expect(model.highestUnlocked, 2);
      model.dispose();
    });

    test(
      'replay awards only newly earned stars, idempotently across cloud sync',
      () async {
        final storage = MemoryStorage();
        final model = _model(storage, {
          'progressionBoot': 1,
          'progression': {
            'active': {'doubleTen': 100000}, // 2x boost
          },
        });
        await model.open(const PuzzleId.level(1));
        model.addElapsedForTest(
          const Duration(seconds: 25),
        ); // 1 star on 1.0-1.25x
        complete(model);
        final afterFirst = model.coinBalance;
        final firstStars = model.starsFor(const PuzzleId.level(1))!;
        expect(firstStars, inInclusiveRange(1, 2));

        // Replay faster -> 3 stars
        await model.open(const PuzzleId.level(1), replay: true);
        complete(model);
        expect(model.attemptStars, 3);
        expect(model.starsFor(const PuzzleId.level(1)), 3);
        final deltaStars = 3 - firstStars;
        expect(model.coinBalance, afterFirst + deltaStars * 2);

        // Further 3-star replay grants 0 coins
        final afterImprove = model.coinBalance;
        await model.open(const PuzzleId.level(1), replay: true);
        complete(model);
        expect(model.coinBalance, afterImprove);
        expect(model.earnedStarCoins, 0);

        // Cloud round-trip preserves stars and idempotency
        await model.flush();
        final wrapped = CloudEnvelope.wrap(
          await storage.load(),
          revision: 1,
          savedAt: 1,
        );
        final restored = _model(
          storage,
          CloudEnvelope.decode(wrapped.encode()).payload,
        );
        expect(restored.starsFor(const PuzzleId.level(1)), 3);
        await restored.open(const PuzzleId.level(1), replay: true);
        complete(restored);
        expect(restored.coinBalance, afterImprove);
        model.dispose();
        restored.dispose();
      },
    );
  });
}
