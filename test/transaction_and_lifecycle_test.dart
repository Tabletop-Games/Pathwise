import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/cloud/cloud_save_format.dart';
import '../lib/cloud/cloud_save_provider.dart';
import '../lib/cloud/cloud_sync_service.dart';
import '../lib/cloud/key_value_store.dart';
import '../lib/logic/connectivity_service.dart';
import '../lib/logic/game_state_storage.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/progression.dart';
import '../lib/views/connection_view.dart';

class _FailingStorage extends GameStateStorage {
  bool fail = false;

  @override
  Future<Map<String, dynamic>> load() async => {};

  @override
  Future<void> save(String payload) async {
    if (fail) throw StateError('disk full');
  }
}

void main() {
  test(
    'AppModel rolls back async ad/purchase mutations when flush fails',
    () async {
      final storage = _FailingStorage();
      final model = AppModel(storage: storage, snapshot: {});
      storage.fail = true;

      expect(await model.grantAdBonus('ad-1'), isFalse);
      expect(model.coinBalance, economy.starterCoins);
      expect(model.adsToday, 0);

      expect(await model.grantHintAd('hint-1'), isFalse);
      expect(model.hintsRemaining, economy.starterHints);
      expect(model.hintAdsToday, 0);

      expect(await model.grantBoostAd(Boost.doubleTen, 'boost-1'), isFalse);
      expect(model.progression.inventory[Boost.doubleTen.name] ?? 0, 0);

      expect(
        await model.applyVerifiedPurchase('grant-1', coins: 500, themes: true),
        isFalse,
      );
      expect(model.coinBalance, economy.starterCoins);
      expect(model.hasThemePass, isFalse);

      // Recover storage and verify retries succeed without duplicate blocks.
      storage.fail = false;
      expect(await model.flush(), isTrue);
      expect(await model.grantAdBonus('ad-1'), isTrue);
      expect(model.coinBalance, economy.starterCoins + economy.rewardedAdCoins);
      model.dispose();
    },
  );

  test(
    'AppModel flush passes an independent snapshot copy to onPersisted',
    () async {
      final storage = _FailingStorage();
      Map<String, dynamic>? captured;
      final model = AppModel(
        storage: storage,
        snapshot: {},
        onPersisted: (snap) => captured = snap,
      );
      await model.flush();
      expect(captured, isNotNull);
      captured!['hintBalance'] = 9999;
      expect(model.hintsRemaining, economy.starterHints);
      model.dispose();
    },
  );

  test(
    'CloudSyncService does not mark synced when apply returns false',
    () async {
      final store = MemoryKeyValueStore();
      final cloud = FakeCloudSaves(store: store, key: 'cloud');
      await cloud.switchAccount('player-1');
      final remotePayload = AppModel(
        storage: _FailingStorage(),
        snapshot: {},
      ).snapshotMap();
      remotePayload['hintBalance'] = 42;
      await cloud.commit(
        'pathwise-progress-v1',
        CloudEnvelope.wrap(remotePayload, revision: 1, savedAt: 1000).encode(),
        'test',
      );

      final local = AppModel(
        storage: _FailingStorage(),
        snapshot: {},
      ).snapshotMap();
      final sync = CloudSyncService(
        provider: cloud,
        store: store,
        prefix: 'test',
        snapshot: () => local,
        apply: (_) async => false,
        isOnline: () => true,
      );
      await sync.start();
      expect(await sync.syncNow(), isFalse);
      expect(sync.status, CloudSyncStatus.error);
      expect(sync.lastSynced, isNull);
      sync.dispose();
    },
  );

  test('combine keeps the higher schemaVersion', () {
    final merged = combine(
      {'schemaVersion': 16, 'ledger': []},
      {
        'schemaVersion': 12,
        'attempts': {'a': 1},
      },
    );
    expect(merged['schemaVersion'], 16);
  });

  test(
    'ConnectivityService retry queues follow-up check if already checking',
    () async {
      var calls = 0;
      final service = ConnectivityService(
        probe: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return calls >= 2;
        },
      );
      final first = service.check();
      await service.retry();
      await first;
      expect(calls, greaterThanOrEqualTo(2));
      expect(service.online, isTrue);
      service.dispose();
    },
  );

  testWidgets('ConnectionGate shows again on a second offline period', (
    tester,
  ) async {
    var online = false;
    var now = DateTime.utc(2026, 11, 27);
    final connectivity = ConnectivityService(
      probe: () async => online,
      now: () => now,
      confirmDelay: const Duration(seconds: 4),
    );
    final model = AppModel(storage: _FailingStorage(), snapshot: {});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: model),
          ChangeNotifierProvider.value(value: connectivity),
        ],
        child: MaterialApp(
          home: ConnectionGate(
            connectivity: connectivity,
            child: const Scaffold(body: Text('Home')),
          ),
        ),
      ),
    );

    // First offline period (2 failed probes >= 4s apart).
    await connectivity.check();
    now = now.add(const Duration(seconds: 5));
    await connectivity.check();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionPane), findsOneWidget);

    // Back online -> hides overlay and resets period flag.
    online = true;
    await connectivity.check();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionPane), findsNothing);

    // Second offline period -> shows overlay again.
    online = false;
    await connectivity.check();
    now = now.add(const Duration(seconds: 5));
    await connectivity.check();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionPane), findsOneWidget);

    connectivity.dispose();
    model.dispose();
  });
}
