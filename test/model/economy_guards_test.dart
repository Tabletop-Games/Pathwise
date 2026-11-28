import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/economy.dart';
import 'package:pathwise/model/product_catalog.dart';

import '../support/fixtures.dart';

void main() {
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
