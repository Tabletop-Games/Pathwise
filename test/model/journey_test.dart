import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/cloud/cloud_save_format.dart';
import 'package:pathwise/logic/ad_frequency.dart';
import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/logic/billing_service.dart';
import 'package:pathwise/logic/connectivity_service.dart';
import 'package:pathwise/logic/game_controller.dart';
import 'package:pathwise/logic/game_state_storage.dart';
import 'package:pathwise/logic/puzzle.dart';
import 'package:pathwise/logic/tip_tracker.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/economy.dart';
import 'package:pathwise/model/game_state.dart';
import 'package:pathwise/model/journey.dart';
import 'package:pathwise/model/user_preferences.dart';
import 'package:pathwise/views/components/puzzle_board.dart';
import 'package:pathwise/views/journey_rewards.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

class _MemoryStorage extends GameStateStorage {
  String data = '{}';

  @override
  Future<Map<String, dynamic>> load() async =>
      Map<String, dynamic>.from(jsonDecode(data) as Map);

  @override
  Future<void> save(String snapshot) async {
    data = snapshot;
  }
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
      final expected = normal + model.completionCoins * (multiplier - 1);
      expect(model.coinBalance, expected);
      final restored = journeyModel(storage, await storage.load());
      await clear(restored, 1, replay: true);
      expect(restored.coinBalance, expected);
      expect(restored.canMultiplyCompletion, isFalse);
      model.dispose();
      restored.dispose();
    });
  }

  test('journey scroll extents keep every reachable level exact', () {
    final max = maxJourneyLevelForExtent(132.0);
    expect(max, greaterThan(1000000));
    expect(max % chapterSize, 0);
    expect(maxJourneyLevelForExtent(264.0), lessThan(max));
  });

  test('a mystery reward is deterministic and claims once', () async {
    final storage = MemoryStorage();
    final model = journeyModel(storage, {'themePass': true});
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
          'pending': {'1': 'tip/crystal'},
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

  test(
    'upcoming discovery persists across snapshot save and restore',
    () async {
      final storage = _MemoryStorage();
      final model = AppModel(
        storage: storage,
        snapshot: const {},
        connectivity: ConnectivityService(probe: () async => true),
        today: () => DateTime(2026, 11, 25),
        bootTime: () => (boot: 1, milliseconds: 1000),
      );

      final firstUpcoming = model.upcomingDiscoveryItem;
      expect(firstUpcoming, isNotEmpty);
      await model.flush();

      // Reload from storage and verify identical upcoming discovery item.
      final loadedSnapshot = await storage.load();
      final reloaded = AppModel(
        storage: storage,
        snapshot: loadedSnapshot,
        connectivity: ConnectivityService(probe: () async => true),
        today: () => DateTime(2026, 11, 25),
        bootTime: () => (boot: 1, milliseconds: 1000),
      );
      expect(reloaded.upcomingDiscoveryItem, firstUpcoming);

      model.dispose();
      reloaded.dispose();
    },
  );

  test('a saved journey restores its progress and replaces an invalid upcoming reward', () {
    AppModel launch(String upcoming) => AppModel(
      storage: _MemoryStorage(),
      snapshot: {
        'hintBalance': 7,
        'journey': {'clears': 14, 'upcoming': upcoming},
      },
      connectivity: ConnectivityService(probe: () async => true),
      today: () => DateTime(2026, 11, 25),
      bootTime: () => (boot: 1, milliseconds: 1000),
    );
    final valid = launch('tip/cat');
    expect(valid.hintsRemaining, 7);
    expect(valid.discoveryPercent, 40);
    expect(valid.upcomingDiscoveryItem, 'tip/cat');
    valid.dispose();
    final invalid = launch('tip/not-a-tip');
    expect(invalid.upcomingDiscoveryItem, isNot('tip/not-a-tip'));
    expect(invalid.upcomingDiscoveryItem, matches(RegExp(r'^[a-z]+/')));
    invalid.dispose();
  });
}
