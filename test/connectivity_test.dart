import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/connectivity_service.dart';
import '../lib/model/app_model.dart';
import '../lib/model/game_state.dart';
import '../lib/model/progression.dart';
import '../lib/model/user_preferences.dart';
import 'app_model_test.dart' show MemoryStorage, fixture;

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

  group('gameplay requires a connection', () {
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
        snapshot: const {},
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

    test('no puzzle starts while the connection is unknown or down', () async {
      await model.open(const PuzzleId.level(1));
      expect(model.activeId, isNull);
      await goOnline();
      await model.open(const PuzzleId.level(1));
      expect(model.activeId, const PuzzleId.level(1));
    });

    test('losing the connection keeps the route, refuses input and resumes in place', () async {
      await goOnline();
      await model.open(const PuzzleId.level(1));
      model.begin(0);
      model.step(1);
      model.step(2);
      model.end();
      expect(model.path, [0, 1, 2]);

      await goOffline();
      expect(model.path, [0, 1, 2], reason: 'the route is kept');
      expect(model.isDrawing, isFalse, reason: 'the stroke is finished');
      expect(model.begin(2), isFalse);
      model.step(5);
      expect(model.path, [0, 1, 2]);
      await model.open(const PuzzleId.level(2));
      expect(model.activeId, const PuzzleId.level(1), reason: 'no new puzzle');

      await goOnline();
      expect(model.begin(2), isTrue);
      model.step(5);
      model.end();
      expect(model.path, [0, 1, 2, 5]);
    });

    test('the unfinished route is saved while offline', () async {
      await goOnline();
      await model.open(const PuzzleId.level(1));
      model.begin(0);
      model.step(1);
      model.end();
      await goOffline();
      await model.flush();
      expect(store.value, contains('"path":[0,1]'));
    });

    test('an offline player cannot buy or claim anything', () async {
      await goOnline();
      expect(model.coinBalance, 50);
      await goOffline();
      expect(model.unlockTheme(PathwiseTheme.forestMint), isFalse);
      expect(model.research(Research.magnet), isFalse);
      expect(await model.buyHint(), isFalse);
    });
  });
}
