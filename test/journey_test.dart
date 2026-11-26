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
          normal +
          (economy.clearReward(PlayMode.levels) + 3) * (multiplier - 1);
      expect(model.coinBalance, expected);
      final restored = journeyModel(storage, await storage.load());
      await clear(restored, 1, replay: true);
      expect(restored.coinBalance, expected);
      expect(restored.canMultiplyCompletion, isFalse);
      model.dispose();
      restored.dispose();
    });
  }

  test('legacy clears stay prospective, mystery reward is deterministic and idempotent', () async {
    final storage = MemoryStorage();
    final model = journeyModel(storage, {
      'results': {
        'levels/30': {'milliseconds': 1000, 'hints': 0},
      },
      'themePass': true,
    });
    expect(model.discoveryPercent, 0);
    final cycle1Item = model.upcomingDiscoveryItem;
    for (var level = 1; level <= 10; level++) {
      await clear(model, level);
      expect(model.discoveryPercent, level % 10 * 10);
    }
    final offer1 = model.latestDiscovery;
    expect(offer1, isNotNull);
    expect(offer1!.item, cycle1Item);
    expect(await model.claimMysteryReward(offer1), isTrue);
    expect(await model.claimMysteryReward(offer1), isFalse);
    final wrapped = CloudEnvelope.wrap(
      await storage.load(),
      revision: 1,
      savedAt: 1,
    );
    final restored = journeyModel(
      storage,
      CloudEnvelope.decode(wrapped.encode()).payload,
    );
    expect(await restored.claimMysteryReward(offer1), isFalse);
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

  test('six-digit chapter clears restore multiple pending chests', () async {
    final store = MemoryStorage();
    final model = journeyModel(store, {
      'schemaVersion': 14,
      'results': {
        for (final end in [25, 100000, 100025])
          for (
            var level = end - 24;
            level <= (end == 25 ? end : end - 1);
            level++
          )
            'levels/$level': {'milliseconds': 1000, 'hints': 0},
      },
    });
    expect(model.highestUnlocked, 100025);
    expect(model.pendingChapterChests, isEmpty);
    expect(model.chapterReady(chapterFor(25)), false);
    expect(chapterEnd(chapterFor(100000)), 100000);
    expect(chapterName(chapterFor(100000)), isNot(chapterName(0)));
    await clear(model, 100000);
    await clear(model, 100025);
    expect(model.canPlayLevel(100026), true);
    expect(model.canPlayLevel(100027), false);
    final older = chapterFor(100000);
    final newer = chapterFor(100025);
    expect(model.pendingChapterChests, [older, newer]);
    final coins = model.coinBalance;
    final hints = model.hintsRemaining;
    final restored = journeyModel(store, await store.load());
    expect(restored.pendingChapterChests, [older, newer]);
    expect(await restored.claimChapter(older), true);
    expect(await restored.claimChapter(older), false);
    expect(restored.coinBalance, coins + chapterRewardCoins);
    expect(restored.hintsRemaining, hints + chapterRewardHints);
    final remote = CloudEnvelope.decode(
      CloudEnvelope.wrap(await store.load(), revision: 1, savedAt: 1).encode(),
    );
    final synced = journeyModel(store, remote.payload);
    expect(synced.highestUnlocked, 100026);
    expect(synced.chapterClaimed(older), true);
    expect(synced.pendingChapterChests, [newer]);
    await clear(synced, 100000, replay: true);
    expect(synced.chapterReady(older), false);
    synced.dispose();
    restored.dispose();
    model.dispose();
  });

  test(
    'exhausted owned catalogue falls back to coins or boosts and skip discards',
    () async {
      final model = journeyModel(MemoryStorage(), {
        'themePass': true,
        'ownedTips': PathTip.values.map((tip) => tip.name).toList(),
        'journey': {
          'clears': 9,
          'pending': {'1': 'tip/arrow'},
        },
      });
      await clear(model, 1);
      final offer = model.latestDiscovery!;
      expect(offer.isCoins || offer.isBoost, isTrue);
      model.skipLatestDiscovery();
      expect(model.latestDiscovery, isNull);
      expect(await model.claimMysteryReward(offer), isTrue);
      expect(await model.claimMysteryReward(offer), isFalse);
      model.dispose();
    },
  );
}
