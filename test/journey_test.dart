import 'package:flutter_test/flutter_test.dart';

import '../lib/cloud/cloud_save_format.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import '../lib/model/journey.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

AppModel journeyModel(MemoryStorage storage, Map<String, dynamic> snapshot) =>
    AppModel(
      storage: storage,
      snapshot: snapshot,
      loader: (_) async => fixture(),
      bootTime: () => (boot: 1, milliseconds: 100),
    );

Future<void> clear(AppModel model, int level, {bool replay = false}) async {
  await model.open(PuzzleId.level(level), replay: replay);
  complete(model);
  await model.flush();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('track boundaries match visible region widths', () {
    expect(
      <double>[0, .24, .33, .45, .50, .55, .66, .76, 1].map(multiplierAt),
      [2, 2, 3, 3, 4, 4, 3, 3, 2],
    );
    expect(accessibleMultiplier, 3);
  });

  for (final multiplier in [2, 3, 4]) {
    test('$multiplier× adds only the base difference, once', () async {
      final storage = MemoryStorage();
      final model = journeyModel(storage, {
        'progressionBoot': 1,
        'progression': {
          'ranks': {'magnet': 2},
          'active': {'doubleTen': 100000},
        },
      });
      await clear(model, 1);
      expect(
        model.completionCoins,
        greaterThan(economy.clearReward(PlayMode.levels)),
      );
      final normal = model.coinBalance;
      model.selectCompletionMultiplier(multiplier);
      model.selectCompletionMultiplier(multiplier == 2 ? 4 : 2);
      expect(model.selectedMultiplier, multiplier);
      final callback = model.completionRewardCallback()!;
      expect(model.coinBalance, normal);
      if (multiplier == 4) model.close();
      expect(await callback('sdk'), isTrue);
      expect(await callback('duplicate'), isFalse);
      final expected =
          normal + economy.clearReward(PlayMode.levels) * (multiplier - 1);
      expect(model.coinBalance, expected);
      final restored = journeyModel(storage, await storage.load());
      await clear(restored, 1, replay: true);
      expect(restored.coinBalance, expected);
      expect(restored.canMultiplyCompletion, isFalse);
      model.dispose();
      restored.dispose();
    });
  }

  test('legacy clears stay prospective, discoveries survive restore and remain distinct', () async {
    final storage = MemoryStorage();
    final model = journeyModel(storage, {
      'results': {
        'levels/30': {'milliseconds': 1000, 'hints': 0},
      },
      'themePass': true,
    });
    expect(model.discoveryPercent, 0);
    for (var level = 1; level <= 20; level++) {
      await clear(model, level);
      expect(model.discoveryPercent, level % 10 * 10);
    }
    expect(model.pendingDiscoveries.map((d) => d.item), [
      'tip/arrow',
      'tip/crystal',
    ]);
    expect(model.ownsTip(PathTip.arrow), isFalse);
    final wrapped = CloudEnvelope.wrap(
      await storage.load(),
      revision: 1,
      savedAt: 1,
    );
    final restored = journeyModel(
      storage,
      CloudEnvelope.decode(wrapped.encode()).payload,
    );
    expect(restored.pendingDiscoveries.length, 2);
    expect(await restored.claimDiscovery(1), isTrue);
    expect(await restored.claimDiscovery(1), isFalse);
    expect(restored.ownsTip(PathTip.arrow), isTrue);
    expect(restored.equippedTip, PathTip.classic);
    model.dispose();
    restored.dispose();
  });

  test(
    'chapter requires all of its levels and replays award no discovery',
    () async {
      final model = journeyModel(MemoryStorage(), {
        'results': {
          for (var level = 1; level < 25; level++)
            'levels/$level': {'milliseconds': 1000, 'hints': 0},
        },
      });
      await clear(model, 25);
      expect(model.chapterCompletedThisVisit, isTrue);
      expect(model.discoveryPercent, 10);
      await clear(model, 25, replay: true);
      expect(model.chapterCompletedThisVisit, isFalse);
      expect(model.discoveryPercent, 10);
      model.dispose();
    },
  );

  test('exhausted owned catalogue falls back to coins once', () async {
    final model = journeyModel(MemoryStorage(), {
      'themePass': true,
      'ownedTips': PathTip.values.map((tip) => tip.name).toList(),
      'journey': {'clears': 9},
    });
    await clear(model, 1);
    expect(model.latestDiscovery?.item, Discovery.fallback);
    final before = model.coinBalance;
    expect(await model.claimDiscovery(1), isTrue);
    expect(await model.claimDiscovery(1), isFalse);
    expect(model.coinBalance, before + discoveryFallbackCoins);
    model.dispose();
  });
}
