import 'package:flutter_test/flutter_test.dart';

import '../../lib/logic/connectivity_service.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/game_state.dart';
import '../../lib/model/progression.dart';
import '../../lib/model/user_preferences.dart';
import '../support/fixtures.dart';

void main() {
  group('ConnectivityService', () {
    late bool reachable;
    late DateTime clock;
    late ConnectivityService service;

    setUp(() {
      reachable = true;
      clock = DateTime(2026, 11, 24, 12);
      service = ConnectivityService(
        probe: () async => reachable,
        now: () => clock,
        interval: const Duration(hours: 1),
        confirmDelay: const Duration(seconds: 4),
      );
    });

    tearDown(() => service.dispose());

    test(
      'starts as checking and becomes online after a successful probe',
      () async {
        expect(service.state, ConnectivityState.checking);
        await service.start();
        expect(service.online, isTrue);
      },
    );

    test('an unreachable first probe reports offline straight away', () async {
      reachable = false;
      await service.start();
      expect(service.state, ConnectivityState.offline);
    });

    test('one dropped probe does not interrupt play', () async {
      await service.start();
      reachable = false;
      await service.check();
      expect(
        service.online,
        isTrue,
        reason: 'a single failure is not confirmed',
      );
      reachable = true;
      await service.check();
      expect(service.online, isTrue);
    });

    test(
      'two failures spaced by the confirmation delay report offline',
      () async {
        await service.start();
        reachable = false;
        await service.check();
        clock = clock.add(const Duration(seconds: 2));
        await service.check();
        expect(service.online, isTrue, reason: 'too soon to confirm');
        clock = clock.add(const Duration(seconds: 3));
        await service.check();
        expect(service.state, ConnectivityState.offline);
      },
    );

    test(
      'a successful probe brings the service back online and notifies',
      () async {
        await service.start();
        reachable = false;
        await service.check();
        clock = clock.add(const Duration(seconds: 10));
        await service.check();
        expect(service.state, ConnectivityState.offline);

        var notified = 0;
        service.addListener(() => notified++);
        reachable = true;
        await service.retry();
        expect(service.online, isTrue);
        expect(notified, 1);
      },
    );

    test('a probe that throws counts as unreachable', () async {
      final thrower = ConnectivityService(
        probe: () async => throw StateError('no route'),
        now: () => clock,
        interval: const Duration(hours: 1),
      );
      addTearDown(thrower.dispose);
      await thrower.start();
      expect(thrower.state, ConnectivityState.offline);
    });

    test('background pauses probing and foreground resumes it', () async {
      var probes = 0;
      final counting = ConnectivityService(
        probe: () async {
          probes++;
          return true;
        },
        interval: const Duration(hours: 1),
      );
      addTearDown(counting.dispose);
      await counting.start();
      expect(probes, 1);
      counting.setForeground(false);
      counting.setForeground(true);
      await Future<void>.delayed(Duration.zero);
      expect(probes, 2);
    });
  });

  group('offline-first gameplay works without a connection', () {
    late ConnectivityService connectivity;
    late bool reachable;
    late DateTime clock;
    late MemoryStorage store;
    late AppModel model;

    setUp(() {
      reachable = false;
      clock = DateTime(2026, 11, 22);
      connectivity = ConnectivityService(
        probe: () async => reachable,
        now: () => clock,
        interval: const Duration(hours: 1),
        confirmDelay: const Duration(seconds: 4),
      );
      store = MemoryStorage();
      model = AppModel(
        storage: store,
        snapshot: {
          'ledger': [
            {
              'id': 'starter',
              'label': 'Welcome',
              'amount': 200,
              'at': '2026-11-22T00:00:00Z',
            },
          ],
        },
        today: () => clock,
        loader: (_) async => fixture(),
        bootTime: () => (boot: 1, milliseconds: 100000),
        connectivity: connectivity,
      )..setHaptics(false);
    });

    tearDown(() {
      model.dispose();
      connectivity.dispose();
    });

    Future<void> goOnline() async {
      reachable = true;
      await connectivity.retry();
    }

    Future<void> goOffline() async {
      reachable = false;
      await connectivity.check();
      clock = clock.add(const Duration(seconds: 10));
      await connectivity.check();
    }

    test('puzzles start while connectivity is unknown or offline', () async {
      await model.open(const PuzzleId.level(1));
      expect(model.activeId, const PuzzleId.level(1));
      await goOnline();
      await model.open(const PuzzleId.level(1));
      expect(model.activeId, const PuzzleId.level(1));
    });

    test(
      'losing the connection does not interrupt the route or gameplay',
      () async {
        await goOnline();
        await model.open(const PuzzleId.level(1));
        model.begin(0);
        model.step(1);
        model.step(2);

        await goOffline();
        expect(model.path, [0, 1, 2], reason: 'the route is kept');
        expect(model.isDrawing, isTrue, reason: 'stroke is not interrupted');
        model.step(5);
        model.end();
        expect(model.path, [0, 1, 2, 5]);
      },
    );

    test('the unfinished route is saved while offline', () async {
      await goOffline();
      await model.open(const PuzzleId.level(1));
      model.begin(0);
      model.step(1);
      model.end();
      await model.flush();
      expect(store.value, contains('"path":[0,1]'));
    });

    test('an offline player can spend coins locally but cannot claim ad rewards', () async {
      await goOffline();
      expect(model.coinBalance, 200);
      final research = Research.magnet.price(0);
      expect(model.research(Research.magnet), isTrue);
      expect(model.coinBalance, 200 - research);
      expect(await model.buyHint(), isTrue);
      expect(model.coinBalance, 200 - research - economy.hintPrice);
      // What is left does not cover the theme, so the local purchase is refused
      // for lack of coins, not because the device is offline.
      expect(
        economy.themePrice(PathwiseTheme.forestMint),
        greaterThan(model.coinBalance),
      );
      expect(model.unlockTheme(PathwiseTheme.forestMint), isFalse);
      expect(await model.grantAdBonus('ad-1'), isFalse);
      expect(await model.grantHintAd('hint-ad-1'), isFalse);
    });
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
}
