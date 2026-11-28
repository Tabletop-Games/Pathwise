import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/cloud/cloud_save_format.dart';
import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/puzzle_generator.dart';
import '../lib/logic/star_rating.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import '../lib/ui/art/game_assets.dart';
import '../lib/views/components/tip_art.dart';
import '../lib/views/main_menu_view.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

AppModel _model(MemoryStorage storage, Map<String, dynamic> snapshot) =>
    AppModel(
      storage: storage,
      snapshot: snapshot,
      loader: (_) async => fixture(),
      bootTime: () => (boot: 1, milliseconds: 100),
    );

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

  group('Star rewards, replay, migration, and cloud sync', () {
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

  group('Cosmetic tip artwork & rendering specs', () {
    test(
      'Home banner uses classic.webp for Compass, never hero_robot.webp',
      () {
        expect(tipAssetPath(PathTip.classic), 'assets/art/tips/classic.webp');
        expect(tipAssetPath(PathTip.robot), 'assets/art/tips/robot.webp');
        for (final tip in PathTip.values) {
          expect(tipAssetPath(tip), 'assets/art/tips/${tip.name}.webp');
        }
      },
    );

    test('all tip specs are upright with positive scale', () {
      for (final tip in PathTip.values) {
        expect(tipSpecFor(tip).scale, greaterThan(0));
      }
      expect(PathTip.values.length, 19);
    });

    testWidgets(
      'Home screen renders Compass artwork when Compass is equipped',
      (tester) async {
        final model = _model(MemoryStorage(), {});
        final ads = AdService();
        final billing = BillingService(persist: (_) async => true);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppModel>.value(value: model),
              ChangeNotifierProvider<AdService>.value(value: ads),
              ChangeNotifierProvider<BillingService>.value(value: billing),
            ],
            child: const MaterialApp(home: MainMenuView()),
          ),
        );
        await tester.pump();
        final images = tester
            .widgetList<Image>(find.byType(Image))
            .map((w) => w.image)
            .whereType<AssetImage>()
            .map((a) => a.assetName)
            .toList();
        expect(images, contains('assets/art/tips/classic.webp'));
        expect(images, isNot(contains('assets/art/tips/hero_robot.webp')));
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        ads.dispose();
        billing.dispose();
      },
    );
  });
}
