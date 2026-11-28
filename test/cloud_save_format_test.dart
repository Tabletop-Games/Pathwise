import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/cloud/cloud_save_format.dart';

Map<String, dynamic> save({
  int coins = 50,
  Map<String, dynamic> results = const {},
  Map<String, dynamic> tutorials = const {},
  Map<String, dynamic> attempts = const {},
  int playMs = 0,
  int crateWait = 45000,
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
        'id': 'other',
        'label': 'Other',
        'amount': coins - 50,
        'at': '2026-11-22T00:00:00Z',
      },
  ],
  'hintBalance': 3,
  'results': results,
  'highestUnlocked': 1,
  'ownedThemes': <String>[],
  'progression': {'ranks': <String, int>{}, 'crateWait': crateWait},
  'mechanicTutorials': tutorials,
  'attempts': attempts,
  'playMilliseconds': playMs,
  'preferences': {'haptics': true},
  'economyActivity': {'counts': {}},
};

void main() {
  group('envelope', () {
    test('round-trips and keeps revision and economy digest', () {
      final envelope = CloudEnvelope.wrap(save(), revision: 3, savedAt: 1000);
      final decoded = CloudEnvelope.decode(envelope.encode());
      expect(decoded.revision, 3);
      expect(decoded.savedAt, 1000);
      expect(decoded.economy, economyDigest(save()));
      expect(decoded.payload, save());
    });

    test('compresses and restores a six-digit campaign history', () {
      final payload = save(
        results: {
          for (var level = 1; level <= 100000; level++)
            'levels/$level': {'ms': level + 800, 'hints': level % 4},
        },
      );
      expect(
        utf8.encode(jsonEncode(payload)).length,
        greaterThan(cloudSaveMaxBytes),
      );
      final envelope = CloudEnvelope.wrap(payload, revision: 3, savedAt: 1000);
      final bytes = envelope.encode();
      expect(bytes.take(2), [0x1f, 0x8b]);
      expect(bytes.length, lessThan(cloudSaveMaxBytes));
      final restored = CloudEnvelope.decode(bytes);
      expect(restored.payloadDigest, envelope.payloadDigest);
      expect(restored.payload['results']['levels/100000'], {
        'ms': 100800,
        'hints': 0,
      });
    });

    test('only the current format and version are readable', () {
      List<int> envelope(Object version, {String format = cloudSaveFormat}) {
        final payload = save();
        return utf8.encode(
          jsonEncode({
            'format': format,
            'version': version,
            'revision': 2,
            'savedAt': 100,
            'economy': economyDigest(payload),
            'payloadDigest': digestOf(payload),
            'payload': payload,
          }),
        );
      }

      expect(CloudEnvelope.decode(envelope(cloudSaveVersion)).revision, 2);
      for (final version in [0, 1, cloudSaveVersion - 1, cloudSaveVersion + 1]) {
        expect(
          () => CloudEnvelope.decode(envelope(version)),
          throwsA(isA<CorruptSave>()),
          reason: 'version $version',
        );
      }
      expect(
        () => CloudEnvelope.decode(envelope(cloudSaveVersion, format: 'other')),
        throwsA(isA<CorruptSave>()),
      );
    });

    test('cosmetic ownership belongs to the economy conflict unit', () {
      expect(
        economyDigest({
          ...save(),
          'ownedTips': ['classic', 'crystal'],
        }),
        isNot(
          economyDigest({
            ...save(),
            'ownedTips': ['classic'],
          }),
        ),
      );
    });

    test('rejects tampered payloads, wrong formats and empty data', () {
      final bytes = CloudEnvelope.wrap(
        save(),
        revision: 1,
        savedAt: 1,
      ).encode();
      final text = utf8.decode(bytes);
      final tampered = utf8.encode(
        text.replaceFirst('"hintBalance":3', '"hintBalance":300'),
      );
      expect(() => CloudEnvelope.decode(tampered), throwsA(isA<CorruptSave>()));
      expect(
        () =>
            CloudEnvelope.decode(utf8.encode('{"format":"other","version":1}')),
        throwsA(isA<CorruptSave>()),
      );
      expect(() => CloudEnvelope.decode(const []), throwsA(isA<CorruptSave>()));
      expect(
        () => CloudEnvelope.decode(utf8.encode('not json')),
        throwsA(isA<CorruptSave>()),
      );
      expect(
        () => CloudEnvelope.decode(List.filled(cloudSaveMaxBytes + 1, 32)),
        throwsA(isA<CorruptSave>()),
      );
    });

    test('digests ignore key order and volatile crate timers', () {
      final reordered = {
        for (final key in save().keys.toList().reversed) key: save()[key],
      };
      expect(digestOf(reordered), digestOf(save()));
      expect(
        economyDigest(save(crateWait: 1000)),
        economyDigest(save(crateWait: 9000)),
      );
      expect(
        digestOf(save(crateWait: 1000)),
        isNot(digestOf(save(crateWait: 9000))),
      );
    });

    test('progress-only changes do not change the economy digest', () {
      final base = economyDigest(save());
      expect(economyDigest(save(tutorials: {'walls': 'completed'})), base);
      expect(economyDigest(save(playMs: 5000)), base);
      expect(
        economyDigest(
          save(
            attempts: {
              'levels/1': {
                'path': [0],
              },
            },
          ),
        ),
        base,
      );
      expect(economyDigest(save(coins: 60)), isNot(base));
      expect(
        economyDigest(
          save(
            results: {
              'levels/1': {'ms': 5},
            },
          ),
        ),
        isNot(base),
      );
    });
  });

  group('merge', () {
    test('unions tutorials and attempts and keeps the longer play time', () {
      final local = save(
        tutorials: {'walls': 'completed'},
        playMs: 100,
        attempts: {'levels/2': 'a'},
      );
      final remote = save(
        tutorials: {'ice': 'skipped'},
        playMs: 900,
        attempts: {'levels/3': 'b'},
      );
      final merged = mergeProgress(local, remote);
      expect(merged['mechanicTutorials'], {
        'ice': 'skipped',
        'walls': 'completed',
      });
      expect(merged['attempts'], {'levels/2': 'a', 'levels/3': 'b'});
      expect(merged['playMilliseconds'], 900);
      expect(economyDigest(merged), economyDigest(local));
    });

    test('combine takes economy from one copy and progress from the merge', () {
      final local = save(coins: 80, tutorials: {'walls': 'completed'});
      final remote = save(coins: 60, tutorials: {'ice': 'completed'});
      final combined = combine(remote, mergeProgress(local, remote));
      expect(combined['ledger'], remote['ledger']);
      expect(combined['mechanicTutorials'], {
        'ice': 'completed',
        'walls': 'completed',
      });
    });

    test('summaries are human readable facts', () {
      final summary = SaveSummary.of(
        save(coins: 120, results: {'levels/1': {}, 'daily/2026-11-22': {}}),
        42,
      );
      expect(summary.coins, 120);
      expect(summary.levelsSolved, 1);
      expect(summary.hints, 3);
      expect(summary.savedAt, 42);
    });
  });

  group('planSync', () {
    CloudBase baseOf(
      Map<String, dynamic> payload, {
      int revision = 1,
      String account = 'a',
    }) => CloudBase(
      revision: revision,
      economy: economyDigest(payload),
      payloadDigest: digestOf(payload),
      account: account,
    );

    CloudEnvelope remoteOf(Map<String, dynamic> payload, {int revision = 1}) =>
        CloudEnvelope.wrap(payload, revision: revision, savedAt: 1);

    test('no cloud save uploads the device save, even when fresh', () {
      expect(
        planSync(base: null, local: save(), remote: null),
        isA<PlanUpload>(),
      );
    });

    test('unchanged cloud and clean device do nothing', () {
      final local = save();
      final plan = planSync(
        base: baseOf(local),
        local: local,
        remote: remoteOf(local),
      );
      expect(plan, isA<PlanNone>());
    });

    test('unchanged cloud and local changes upload', () {
      final base = save();
      final local = save(coins: 80);
      final plan = planSync(
        base: baseOf(base),
        local: local,
        remote: remoteOf(base),
      );
      expect(plan, isA<PlanUpload>());
    });

    test('cloud changed elsewhere and device is clean adopts the cloud', () {
      final base = save();
      final cloud = save(coins: 90);
      final plan = planSync(
        base: baseOf(base),
        local: base,
        remote: remoteOf(cloud, revision: 2),
      );
      expect(plan, isA<PlanApply>());
      expect((plan as PlanApply).payload, cloud);
      expect(plan.upload, isFalse);
    });

    test('same economy on both sides merges progress without asking', () {
      final base = save();
      final local = save(tutorials: {'walls': 'completed'});
      final cloud = save(tutorials: {'ice': 'completed'});
      final plan = planSync(
        base: baseOf(base),
        local: local,
        remote: remoteOf(cloud, revision: 2),
      );
      expect(plan, isA<PlanApply>());
      final applied = (plan as PlanApply).payload;
      expect(applied['mechanicTutorials'], {
        'ice': 'completed',
        'walls': 'completed',
      });
      expect(plan.upload, isTrue);
    });

    test('only the device changed economy: keep the device coins', () {
      final base = save();
      final local = save(coins: 80);
      final cloud = save(tutorials: {'ice': 'completed'});
      final plan = planSync(
        base: baseOf(base),
        local: local,
        remote: remoteOf(cloud, revision: 2),
      );
      expect(plan, isA<PlanApply>());
      expect((plan as PlanApply).payload['ledger'], local['ledger']);
      expect(plan.payload['mechanicTutorials'], {'ice': 'completed'});
    });

    test('only the cloud changed economy: take the cloud coins', () {
      final base = save();
      final local = save(tutorials: {'walls': 'completed'});
      final cloud = save(coins: 90);
      final plan = planSync(
        base: baseOf(base),
        local: local,
        remote: remoteOf(cloud, revision: 2),
      );
      expect(plan, isA<PlanApply>());
      expect((plan as PlanApply).payload['ledger'], cloud['ledger']);
      expect(plan.payload['mechanicTutorials'], {'walls': 'completed'});
    });

    test('economy changed on both sides asks the player', () {
      final base = save();
      final local = save(coins: 80);
      final cloud = save(coins: 90);
      expect(
        planSync(
          base: baseOf(base),
          local: local,
          remote: remoteOf(cloud, revision: 2),
        ),
        isA<PlanAskUser>(),
      );
    });

    test('first sign-in on a fresh device adopts the cloud save', () {
      final fresh = save();
      final cloud = save(coins: 120, results: {'levels/1': {}});
      final plan = planSync(base: null, local: fresh, remote: remoteOf(cloud));
      expect(plan, isA<PlanApply>());
      expect((plan as PlanApply).upload, isFalse);
    });

    test(
      'first sign-in on a used device with different economy asks the player',
      () {
        final used = save(coins: 80, results: {'levels/1': {}});
        final cloud = save(
          coins: 120,
          results: {'levels/1': {}, 'levels/2': {}},
        );
        expect(
          planSync(base: null, local: used, remote: remoteOf(cloud)),
          isA<PlanAskUser>(),
        );
      },
    );

    test('identical saves on first sign-in merge without a prompt', () {
      final same = save(results: {'levels/1': {}});
      expect(
        planSync(base: null, local: same, remote: remoteOf(same)),
        isA<PlanApply>(),
      );
    });
  });
}
