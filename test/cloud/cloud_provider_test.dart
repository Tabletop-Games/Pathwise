import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/cloud/cloud_save_provider.dart';
import '../../lib/cloud/key_value_store.dart';
import '../../lib/main.dart' show cloudProviderFor;
import '../../lib/model/app_model.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/product_catalog.dart';
import '../support/fixtures.dart' show MemoryStorage;

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
}
