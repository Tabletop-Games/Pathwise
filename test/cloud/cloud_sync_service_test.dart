import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/cloud/cloud_save_format.dart';
import 'package:pathwise/cloud/cloud_save_provider.dart';
import 'package:pathwise/cloud/cloud_sync_service.dart';
import 'package:pathwise/logic/game_state_storage.dart';
import 'package:pathwise/model/app_model.dart';

import '../support/fixtures.dart';

const _name = 'pathwise-progress-v1';

Map<String, dynamic> save({
  int coins = 50,
  List<String> levels = const [],
  Map<String, dynamic> tutorials = const {},
}) => {
  'schemaVersion': 13,
  'ledger': [
    {
      'id': 'starter',
      'label': 'Welcome coins',
      'amount': 50,
      'at': '2026-11-22T00:00:00Z',
    },
    if (coins != 50)
      {
        'id': 'x',
        'label': 'x',
        'amount': coins - 50,
        'at': '2026-11-22T00:00:00Z',
      },
  ],
  'hintBalance': 3,
  'results': {
    for (final level in levels)
      level: {'ms': 1000, 'hints': 0, 'unassisted': true},
  },
  'highestUnlocked': 1,
  'ownedThemes': <String>[],
  'progression': {'ranks': <String, int>{}, 'crateWait': 45000},
  'mechanicTutorials': tutorials,
  'attempts': <String, dynamic>{},
  'playMilliseconds': 0,
  'preferences': {'haptics': true},
  'economyActivity': {'counts': <String, int>{}},
};

/// One installation: its own local cache and sync service, sharing a cloud.
class Device {
  Device(
    this.cloud, {
    this.urgentDelay = const Duration(hours: 1),
    bool online = true,
    MemoryKeyValueStore? sharedStore,
  }) : store = sharedStore ?? MemoryKeyValueStore(),
       _online = online {
    service = CloudSyncService(
      provider: cloud,
      store: store,
      prefix: 'test',
      snapshot: () => local,
      apply: (payload) async {
        applied.add(payload);
        local = payload;
        return true;
      },
      isOnline: () => _online,
      now: () => DateTime.utc(2026, 11, 24, 12),
      debounce: const Duration(hours: 1),
      urgentDelay: urgentDelay,
      retryDelays: const [Duration(hours: 1)],
    );
  }

  final FakeCloudSaves cloud;
  final MemoryKeyValueStore store;
  final Duration urgentDelay;
  final applied = <Map<String, dynamic>>[];
  late final CloudSyncService service;
  Map<String, dynamic> local = save();
  bool _online;

  void dispose() => service.dispose();
}

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
  late FakeCloudSaves cloud;
  final devices = <Device>[];

  Device device(Device Function() make) {
    final created = make();
    devices.add(created);
    return created;
  }

  setUp(() async {
    cloud = FakeCloudSaves(store: MemoryKeyValueStore(), key: 'cloud');
    await cloud.switchAccount('player-1');
  });

  tearDown(() {
    for (final item in devices) {
      item.dispose();
    }
    devices.clear();
  });

  test(
    'a signed-in device uploads its save and reports a successful sync',
    () async {
      final a = device(() => Device(cloud));
      a.local = save(coins: 80, levels: ['levels/1']);
      await a.service.start();
      expect(a.service.status, CloudSyncStatus.idle);
      expect(
        a.service.readyForConsumablePurchase,
        isFalse,
        reason: 'not synced yet',
      );

      expect(await a.service.syncNow(), isTrue);
      final stored = CloudEnvelope.decode((await cloud.stored(_name))!);
      expect(stored.revision, 1);
      expect(stored.payload, a.local);
      expect(a.service.readyForConsumablePurchase, isTrue);
      expect(a.service.lastSynced, isNotNull);
    },
  );

  test(
    'a signed-out device is not uploading and explains how to sign in',
    () async {
      await cloud.switchAccount(null);
      final a = device(() => Device(cloud));
      await a.service.start();
      expect(a.service.status, CloudSyncStatus.signedOut);
      expect(await a.service.syncNow(), isFalse);
      expect(await cloud.stored(_name), isNull);

      await a.service.signIn();
      expect(a.service.signedIn, isTrue);
      expect(a.service.status, CloudSyncStatus.idle);
      expect(await cloud.stored(_name), isNotNull);
    },
  );

  test('a fresh second device restores the cloud save on sign-in', () async {
    final a = device(() => Device(cloud));
    a.local = save(coins: 80, levels: ['levels/1']);
    await a.service.start();
    await a.service.syncNow();

    final b = device(() => Device(cloud));
    await b.service.start();
    expect(await b.service.syncNow(), isTrue);
    expect(b.local, a.local);
    expect(b.applied, hasLength(1));
    expect(
      b.service.hasBackup,
      isFalse,
      reason: 'a fresh device has nothing to back up',
    );
  });

  test('economy changed on both devices asks the player and changes nothing silently', () async {
    final a = device(() => Device(cloud));
    a.local = save(coins: 80, levels: ['levels/1']);
    await a.service.start();
    await a.service.syncNow();

    final b = device(() => Device(cloud));
    b.local = save(coins: 60, levels: ['levels/1']);
    await b.service.start();
    expect(await b.service.syncNow(), isFalse);
    expect(b.service.status, CloudSyncStatus.conflict);
    expect(b.service.choice, isNotNull);
    expect(
      b.local,
      save(coins: 60, levels: ['levels/1']),
      reason: 'not applied yet',
    );
    expect(b.service.readyForConsumablePurchase, isFalse);

    await b.service.resolveChoice(keepDevice: false);
    expect(b.local, a.local);
    expect(
      b.service.hasBackup,
      isTrue,
      reason: 'the replaced device save is kept',
    );
    expect(b.service.status, CloudSyncStatus.idle);

    await b.service.restoreBackup();
    expect(b.local, save(coins: 60, levels: ['levels/1']));
  });

  test('keeping this device overwrites the cloud and keeps the cloud copy as backup', () async {
    final a = device(() => Device(cloud));
    a.local = save(coins: 80, levels: ['levels/1']);
    await a.service.start();
    await a.service.syncNow();

    final b = device(() => Device(cloud));
    b.local = save(coins: 60, levels: ['levels/1']);
    await b.service.start();
    await b.service.syncNow();
    await b.service.resolveChoice(keepDevice: true);

    expect(CloudEnvelope.decode((await cloud.stored(_name))!).payload, b.local);
    expect(b.service.hasBackup, isTrue);
    expect(b.service.status, CloudSyncStatus.idle);
  });

  test(
    'an interrupted upload keeps the device save and succeeds on the next pass',
    () async {
      cloud.failNextCommits = 1;
      final a = device(() => Device(cloud));
      a.local = save(coins: 80, levels: ['levels/1']);
      await a.service.start();

      expect(await a.service.syncNow(), isFalse);
      expect(a.service.status, CloudSyncStatus.error);
      expect(a.local, save(coins: 80, levels: ['levels/1']));
      expect(await cloud.stored(_name), isNull);

      expect(await a.service.syncNow(), isTrue);
      expect(
        CloudEnvelope.decode((await cloud.stored(_name))!).payload,
        a.local,
      );
    },
  );

  test('a restart after an upload that was not recorded re-plans without double application', () async {
    final a = device(() => Device(cloud));
    a.local = save(coins: 80, levels: ['levels/1']);
    await a.service.start();
    await a.service.syncNow();
    final revision = CloudEnvelope.decode((await cloud.stored(_name))!)
        .revision;

    // Simulate a crash after the cloud write but before the local baseline was saved.
    a.store.values.clear();
    final restarted = device(() => Device(cloud));
    restarted.local = a.local;
    await restarted.service.start();
    expect(await restarted.service.syncNow(), isTrue);
    expect(CloudEnvelope.decode((await cloud.stored(_name))!).payload, a.local);
    expect(restarted.applied, isEmpty, reason: 'nothing needed to be applied');
    expect(
      CloudEnvelope.decode((await cloud.stored(_name))!).revision,
      greaterThanOrEqualTo(revision),
    );
  });

  test(
    'a write that loses a race is re-planned, never blindly overwritten',
    () async {
      final a = device(() => Device(cloud));
      a.local = save(coins: 80, levels: ['levels/1']);
      await a.service.start();
      cloud.conflictsNextCommits = 1;
      expect(await a.service.syncNow(), isTrue);
      expect(
        CloudEnvelope.decode((await cloud.stored(_name))!).payload,
        a.local,
      );
    },
  );

  test('an unreadable cloud save is reported and left alone until the player chooses', () async {
    await cloud.externalWrite(_name, [1, 2, 3]);
    final a = device(() => Device(cloud));
    a.local = save(coins: 80, levels: ['levels/1']);
    await a.service.start();
    expect(await a.service.syncNow(), isFalse);
    expect(a.service.status, CloudSyncStatus.damaged);
    expect(await cloud.stored(_name), [1, 2, 3]);

    await a.service.replaceDamagedCloudSave();
    expect(CloudEnvelope.decode((await cloud.stored(_name))!).payload, a.local);
    expect(a.service.status, CloudSyncStatus.idle);
  });

  test('offline passes make no cloud calls and keep the device save', () async {
    final a = device(() => Device(cloud, online: false));
    a.local = save(coins: 80, levels: ['levels/1']);
    await a.service.start();
    expect(await a.service.syncNow(), isFalse);
    expect(a.service.status, CloudSyncStatus.waitingForNetwork);
    expect(await cloud.stored(_name), isNull);
    expect(a.local, save(coins: 80, levels: ['levels/1']));
  });

  test(
    'switching accounts never replaces a used device save silently',
    () async {
      final a = device(() => Device(cloud));
      a.local = save(coins: 80, levels: ['levels/1']);
      await a.service.start();
      await a.service.syncNow();
      await a.service.signOut();
      expect(a.service.status, CloudSyncStatus.signedOut);
      expect(
        a.local,
        save(coins: 80, levels: ['levels/1']),
        reason: 'device copy stays',
      );

      await cloud.switchAccount('player-2');
      await cloud.externalWrite(
        _name,
        CloudEnvelope.wrap(
          save(coins: 200, levels: ['levels/1', 'levels/2']),
          revision: 4,
          savedAt: 1,
        ).encode(),
      );

      await a.service.signIn();
      expect(a.service.status, CloudSyncStatus.conflict);
      expect(a.local, save(coins: 80, levels: ['levels/1']));
    },
  );

  test(
    'concurrent sync requests run one after another and both report success',
    () async {
      final a = device(() => Device(cloud));
      a.local = save(coins: 80, levels: ['levels/1']);
      await a.service.start();
      final results = await Future.wait([
        a.service.syncNow(),
        a.service.syncNow(),
      ]);
      expect(results, [true, true]);
      expect(
        CloudEnvelope.decode((await cloud.stored(_name))!).payload,
        a.local,
      );
    },
  );

  test(
    'economy changes sync urgently while progress waits for the debounce',
    () async {
      final a = device(() => Device(cloud, urgentDelay: Duration.zero));
      a.local = save(coins: 80, levels: ['levels/1']);
      await a.service.start();
      await a.service.syncNow();
      final before = CloudEnvelope.decode((await cloud.stored(_name))!)
          .revision;

      // Progress-only change: a tutorial acknowledgement.
      a.local = save(
        coins: 80,
        levels: ['levels/1'],
        tutorials: {'walls': 'completed'},
      );
      a.service.localChanged(a.local);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        CloudEnvelope.decode((await cloud.stored(_name))!).revision,
        before,
      );

      // Economy change: a coin purchase.
      a.local = save(coins: 120, levels: ['levels/1']);
      a.service.localChanged(a.local);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        CloudEnvelope.decode((await cloud.stored(_name))!).revision,
        greaterThan(before),
      );
    },
  );

  test(
    'stopping sync survives a restart until the player signs in again',
    () async {
      final a = device(() => Device(cloud));
      a.local = save(coins: 80, levels: ['levels/1']);
      await a.service.start();
      await a.service.syncNow();
      await a.service.signOut();
      expect(a.service.optedOut, isTrue);
      expect(a.service.signedIn, isFalse);

      // The app restarts while the Play Games account is still on the device.
      final restarted = device(() => Device(cloud, sharedStore: a.store));
      restarted.local = a.local;
      await restarted.service.start();
      expect(restarted.service.status, CloudSyncStatus.signedOut);
      expect(await restarted.service.syncNow(), isFalse);
      expect(restarted.service.readyForConsumablePurchase, isFalse);

      await restarted.service.signIn();
      expect(restarted.service.optedOut, isFalse);
      expect(restarted.service.signedIn, isTrue);
      expect(restarted.service.status, CloudSyncStatus.idle);
    },
  );

  test(
    'restoring from cloud keeps a backup of the device save first',
    () async {
      final a = device(() => Device(cloud));
      a.local = save(coins: 80, levels: ['levels/1']);
      await a.service.start();
      await a.service.syncNow();

      a.local = save(coins: 10);
      await a.service.restoreFromCloud();
      expect(a.local, save(coins: 80, levels: ['levels/1']));
      expect(a.service.hasBackup, isTrue);
    },
  );

  test(
    'platforms without Saved Games never sync and cannot buy coins',
    () async {
      final unsupported = CloudSyncService(
        provider: const UnsupportedCloudSaves(),
        store: MemoryKeyValueStore(),
        prefix: 'unsupported',
        snapshot: () => save(),
        apply: (_) async => true,
        isOnline: () => true,
      );
      addTearDown(unsupported.dispose);
      await unsupported.start();
      expect(unsupported.status, CloudSyncStatus.unsupported);
      expect(await unsupported.syncNow(), isFalse);
      expect(await unsupported.prepareForPurchase(), isFalse);
      await unsupported.signIn();
      expect(unsupported.signedIn, isFalse);
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
}
