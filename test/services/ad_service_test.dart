import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// The plugin's codec is needed to deliver simulated native SDK events.
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';

import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/model/app_model.dart';
import '../support/fixtures.dart';

final day = DateTime(2026, 11, 22);

AppModel create(MemoryStorage store, [Map<String, dynamic> saved = const {}]) =>
    AppModel(
      storage: store,
      snapshot: saved,
      today: () => day,
      loader: (_) async => fixture(),
    )..setHaptics(false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final sdk = instanceManager.channel;
  final ump = MethodChannel(
    'plugins.flutter.io/google_mobile_ads/ump',
    StandardMethodCodec(UserMessagingCodec()),
  );
  const clock = MethodChannel('com.shenmareparas.pathwise/clock');
  const testPublisher = 'ca-app-pub-3940256099942544';
  late AdService ads;
  late List<int> rewarded;
  late List<String> loadedUnits;
  late List<int> shown;
  late bool online;
  late bool consentAllowed;
  late bool initFails;

  Future<void> event(
    int adId,
    String name, [
    Map<String, Object> data = const {},
  ]) async {
    await messenger.handlePlatformMessage(
      sdk.name,
      sdk.codec.encodeMethodCall(
        MethodCall('onAdEvent', {'adId': adId, 'eventName': name, ...data}),
      ),
      (_) {},
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    ads = AdService(testAds: true);
    rewarded = [];
    loadedUnits = [];
    shown = [];
    online = true;
    consentAllowed = true;
    initFails = false;
    messenger.setMockMethodCallHandler(ump, (call) async {
      return switch (call.method) {
        'ConsentInformation#getPrivacyOptionsRequirementStatus' => 0,
        'ConsentInformation#canRequestAds' => consentAllowed,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(clock, (_) async => online);
    messenger.setMockMethodCallHandler(sdk, (call) async {
      if (call.method == 'MobileAds#initialize') {
        if (initFails) throw PlatformException(code: 'unavailable');
        return InitializationStatus({});
      }
      if (call.method == 'loadRewardedAd' ||
          call.method == 'loadInterstitialAd') {
        loadedUnits.add(call.arguments['adUnitId'] as String);
        if (call.method == 'loadRewardedAd') {
          rewarded.add(call.arguments['adId'] as int);
        }
      }
      if (call.method == 'showAdWithoutView') {
        shown.add(call.arguments['adId'] as int);
      }
      return null;
    });
  });

  tearDown(() {
    ads.dispose();
    messenger.setMockMethodCallHandler(ump, null);
    messenger.setMockMethodCallHandler(clock, null);
    messenger.setMockMethodCallHandler(sdk, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android config has five distinct production units and serving off', () {
    final config = jsonDecode(
      File('config/production.example.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(config['PATHWISE_ADS_ENABLED'], 'false');
    expect(config['PATHWISE_ADS_CONSENT_CONFIGURED'], 'false');
    expect(
      config['PATHWISE_ADMOB_APP_ID'],
      'ca-app-pub-7623640820680894~1301071315',
    );
    const units = {
      'BANNER': '4968536352',
      'INTERSTITIAL': '2620293351',
      'REWARDED': '2665806648',
      'EXTRA_HINT': '7594699697',
      'WHEEL': '2222953515',
    };
    for (final MapEntry(:key, :value) in units.entries) {
      final id = config['PATHWISE_ADMOB_$key'] as String;
      expect(id, 'ca-app-pub-7623640820680894/$value');
      expect(AdService.validAdUnit(id), isTrue);
    }
  });

  test(
    'debug never loads production units without explicit test mode',
    () async {
      final production = AdService(testAds: false);
      addTearDown(production.dispose);
      await production.prepare(canPresent: () => true);
      expect(production.enabled, isFalse);
      expect(production.canLoadBanner, isFalse);
      expect(loadedUnits, isEmpty);
    },
  );

  test('all Android debug placements use official Google test IDs', () async {
    await ads.prepare(canPresent: () => true);
    expect(ads.bannerUnit, '$testPublisher/9214589741');
    expect(loadedUnits, [
      '$testPublisher/1033173712',
      ...List.filled(5, '$testPublisher/5224354917'),
    ]);
  });

  test(
    'each rewarded placement grants once only after its SDK callback',
    () async {
      await ads.prepare(canPresent: () => true);
      final initialAds = rewarded.toList();
      final receiptIds = <String>{};
      for (final placement in RewardPlacement.values) {
        final id = initialAds[placement.index];
        await event(id, 'onAdLoaded');
        var grants = 0;
        final grant = Completer<bool>();
        expect(
          await ads.watchVideo((receipt) {
            grants++;
            receiptIds.add(receipt);
            return grant.future;
          }, placement: placement),
          isTrue,
        );
        expect(shown.last, id);
        expect(grants, 0);
        final earned = {'rewardItem': RewardItem(1, 'test')};
        await event(id, 'onRewardedAdUserEarnedReward', earned);
        await event(id, 'onRewardedAdUserEarnedReward', earned);
        expect(grants, 1);
        grant.complete(true);
        await event(id, 'onAdDismissedFullScreenContent');
      }
      expect(receiptIds, hasLength(RewardPlacement.values.length));
    },
  );

  test('no fill, offline and dismissed video grant nothing', () async {
    await ads.prepare(canPresent: () => true);
    final coins = rewarded[RewardPlacement.coins.index];
    final hint = rewarded[RewardPlacement.hint.index];
    var grants = 0;
    Future<bool> grant(String _) async {
      grants++;
      return true;
    }

    await event(coins, 'onAdFailedToLoad', {
      'loadAdError': LoadAdError(3, 'test', 'No fill', null),
    });
    expect(await ads.watchVideo(grant), isFalse);
    await event(hint, 'onAdLoaded');
    online = false;
    expect(
      await ads.watchVideo(grant, placement: RewardPlacement.hint),
      isFalse,
    );
    expect(shown, isEmpty);
    online = true;
    expect(
      await ads.watchVideo(grant, placement: RewardPlacement.hint),
      isTrue,
    );
    await event(hint, 'onAdDismissedFullScreenContent');
    expect(grants, 0);
  });

  test(
    'UMP denial and failed initialization keep all ad loads blocked',
    () async {
      consentAllowed = false;
      await ads.prepare(canPresent: () => true);
      expect(ads.canLoadBanner, isFalse);
      expect(loadedUnits, isEmpty);
      consentAllowed = true;
      initFails = true;
      await ads.prepare(canPresent: () => true);
      expect(ads.canLoadBanner, isFalse);
      expect(loadedUnits, isEmpty);
      initFails = false;
      await ads.prepare(canPresent: () => true);
      expect(ads.canLoadBanner, isTrue);
      expect(loadedUnits, hasLength(6));
    },
  );

  test('optional ads are disabled by default and video ids and daily caps are enforced', () async {
    final ads = AdService();
    expect(ads.enabled, isFalse);
    expect(ads.videoReady, isFalse);
    await ads.prepare(canPresent: () => true);
    ads.afterCompletedExit(canPresent: true);
    expect(
      AdService.validAdUnit('ca-app-pub-3940256099942544/1033173712'),
      isFalse,
    );
    ads.dispose();

    final model = create(MemoryStorage());
    expect(await model.grantAdBonus('first'), isTrue);
    expect(await model.grantAdBonus('first'), isFalse);
    expect(await model.grantAdBonus('second'), isTrue);
    expect(await model.grantAdBonus('third'), isTrue);
    expect(await model.grantAdBonus('fourth'), isTrue);
    expect(model.coinBalance, 170);
    expect(await model.grantAdBonus('fifth'), isTrue);
    expect(await model.grantAdBonus('sixth'), isTrue);
    expect(await model.grantAdBonus('seventh'), isFalse);
    expect(model.coinBalance, 210);
    model.dispose();
  });
}
