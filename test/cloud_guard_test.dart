import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/cloud/cloud_save_provider.dart';
import '../lib/cloud/key_value_store.dart';
import '../lib/main.dart' show cloudProviderFor;
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/product_catalog.dart';
import 'app_model_test.dart' show MemoryStorage;

void main() {
  group('save provider selection', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test(
      'debug builds without Play Games use a local fake, never Play Games',
      () {
        expect(kDebugMode, isTrue, reason: 'widget tests run in debug mode');
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        expect(cloudProviderFor(MemoryKeyValueStore()), isA<FakeCloudSaves>());
      },
    );

    test('iOS gets the unsupported provider and no sign-in', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final provider = cloudProviderFor(MemoryKeyValueStore());
      expect(provider, isA<UnsupportedCloudSaves>());
      expect(provider.supported, isFalse);
      expect(await provider.signIn(), isNull);
      expect(
        provider.fetch('pathwise-progress-v1'),
        throwsA(isA<CloudUnavailable>()),
      );
    });

    test('the Play Games provider is inert until it is configured', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final provider = PlayGamesCloudSaves();
      expect(
        provider.supported,
        isFalse,
        reason: 'PATHWISE_GAMES_ENABLED is not set in tests',
      );
      expect(await provider.currentAccount(), isNull);
    });

    test('fake saves survive a restart through their store', () async {
      final store = MemoryKeyValueStore();
      final first = FakeCloudSaves(store: store, key: 'debug-cloud');
      await first.switchAccount('tester');
      await first.externalWrite('pathwise-progress-v1', [7, 8]);

      final restarted = FakeCloudSaves(store: store, key: 'debug-cloud');
      expect(await restarted.currentAccount(), 'tester');
      expect(await restarted.stored('pathwise-progress-v1'), [7, 8]);
    });
  });

  group('economy guards', () {
    late AppModel model;
    late DateTime today;

    setUp(() {
      today = DateTime(2026, 11, 22);
      model = AppModel(
        storage: MemoryStorage(),
        snapshot: const {},
        today: () => today,
        bootTime: () => (boot: 1, milliseconds: 1000),
      );
    });

    tearDown(() => model.dispose());

    test(
      'permanent entitlements follow Google Play ownership, not the save',
      () async {
        await model.applyVerifiedPurchase(
          'grant-ads',
          coins: 0,
          themes: false,
          removeAds: true,
        );
        expect(model.adFree, isTrue);

        model.reconcileOwnedProducts({});
        expect(
          model.adFree,
          isFalse,
          reason: 'a refund removes the entitlement',
        );

        model.reconcileOwnedProducts({removeAdsProduct});
        expect(model.adFree, isTrue);
        expect(
          model.hasThemePass,
          isFalse,
          reason: 'Remove Ads grants no themes',
        );
      },
    );

    test(
      'Premium grants its one-time bonus once, even when restored again',
      () async {
        await model.applyVerifiedPurchase(
          'premium-grant',
          coins: 0,
          themes: true,
          bundle: true,
        );
        final afterFirst = model.coinBalance;
        await model.applyVerifiedPurchase(
          'premium-grant',
          coins: 0,
          themes: true,
          bundle: true,
        );
        expect(model.coinBalance, afterFirst);
        // The Theme Pass also unlocks the Collector achievement, paid once.
        expect(
          model.coinBalance,
          50 + economy.premiumBonus + Achievement.collector.coins,
        );
      },
    );

    test('a coin pack is credited once per purchase token', () async {
      await model.applyVerifiedPurchase(
        'token-hash',
        coins: 500,
        themes: false,
      );
      await model.applyVerifiedPurchase(
        'token-hash',
        coins: 500,
        themes: false,
      );
      expect(model.coinBalance, 550);
    });

    test('a rewarded video pays once per reward id', () async {
      expect(await model.grantAdBonus('video-1'), isTrue);
      expect(await model.grantAdBonus('video-1'), isFalse);
      expect(model.coinBalance, 50 + economy.rewardedAdCoins);
    });

    test('daily video limits hold within a day', () async {
      for (var i = 0; i < economy.rewardedAdsPerDay; i++) {
        expect(await model.grantAdBonus('ad-$i'), isTrue, reason: 'video $i');
      }
      expect(await model.grantAdBonus('ad-extra'), isFalse);
    });
  });
}
