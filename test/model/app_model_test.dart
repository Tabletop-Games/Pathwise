import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/logic/game_state_storage.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/game_state.dart';
import '../../lib/model/user_preferences.dart';
import '../../lib/logic/ad_frequency.dart';
import '../../lib/logic/ad_service.dart';
import '../../lib/model/economy.dart';
import '../support/fixtures.dart' show MemoryStorage, complete, fixture;

AppModel app(
  MemoryStorage store, {
  Map<String, dynamic> data = const {},
  int Function()? now,
}) => AppModel(
  storage: store,
  snapshot: data,
  loader: (_) async => fixture(),
  bootTime: () => (boot: 5, milliseconds: now?.call() ?? 0),
)..setHaptics(false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryStorage store;
  late DateTime now;
  setUp(() {
    store = MemoryStorage();
    now = DateTime(2026, 11, 22);
  });

  Future<AppModel> launch() async => AppModel(
    storage: store,
    snapshot: await store.load(),
    today: () => now,
    loader: (_) async => fixture(),
  )..setHaptics(false);

  test(
    'unfinished routes, undo history, hints and appearance survive a restart',
    () async {
      final id = const PuzzleId.level(1);
      final app = await launch();
      app.setTheme(PathwiseTheme.blackwater);
      await app.open(id);
      app.begin(0);
      app.step(1);
      app.step(2);
      app.end();
      app.hint();
      app.close();
      await app.flush();
      app.dispose();

      final restored = await launch();
      expect(restored.theme, PathwiseTheme.blackwater);
      expect(restored.hasAttempt(id), true);
      await restored.open(id);
      expect(restored.path, [0, 1, 2]);
      expect(restored.hintCell, 5);
      expect(restored.hintsUsed, 1);
      restored.undo();
      expect(restored.path, [0]);
      restored.close();
      await restored.flush();
      restored.dispose();
    },
  );

  test('result and daily streak persist once per puzzle', () async {
    final app = await launch();
    final yesterday = app.daily;
    await app.open(yesterday);
    complete(app);
    final finishTime = app.elapsed.value;
    expect(app.complete, true);
    expect(app.solved, 1);
    expect(app.dailyStreak, 1);
    await app.open(app.daily);
    expect(app.complete, true);
    expect(app.solved, 1);
    expect(app.elapsed.value.inMilliseconds, finishTime.inMilliseconds);
    now = DateTime(2026, 11, 23);
    expect(app.daily.key, 'daily/2026-11-23');
    expect(app.dailyStreak, 1);
    await app.open(app.daily);
    complete(app);
    expect(app.dailyStreak, 2);

    await app.flush();
    app.close();
    await app.flush();
    app.dispose();

    final restored = await launch();
    expect(restored.solved, 2);
    expect(restored.unassisted, 2);
    expect(restored.dailyStreak, 2);
    now = DateTime(2026, 11, 25);
    expect(restored.dailyStreak, 0);
    expect(restored.best(PlayMode.daily), isNotNull);
    await restored.flush();
    restored.dispose();
  });

  test(
    'background finalizes the active stroke and failed writes recover',
    () async {
      final app = await launch();
      await app.open(const PuzzleId.level(1));
      app.begin(0);
      app.step(1);
      store.fail = true;
      app.setForeground(false);
      await app.flush();
      expect(app.storageError, true);
      expect(app.canUndo, true);
      final time = app.elapsed.value;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(app.elapsed.value, time);
      store.fail = false;
      await app.flush();
      expect(app.storageError, false);
      app.dispose();
    },
  );

  test(
    'a stale isolate response cannot overwrite the current puzzle',
    () async {
      final pending = <Completer<VerifiedPuzzle>>[];
      final app = AppModel(
        storage: store,
        snapshot: {'highestUnlocked': 2},
        loader: (_) {
          final completion = Completer<VerifiedPuzzle>();
          pending.add(completion);
          return completion.future;
        },
      );
      final first = app.open(const PuzzleId.level(1));
      final second = app.open(const PuzzleId.level(2));
      pending[1].complete(fixture());
      await second;
      pending[0].complete(VerifiedPuzzle(Puzzle(2, [0, 1]), [0, 2, 3, 1]));
      await first;
      expect(app.activeId!.value, 2);
      expect(app.puzzle!.size, 3);
      app.close();
      await app.flush();
      app.dispose();
    },
  );

  test(
    'a saved game keeps verified ownership, balance and the equipped theme',
    () async {
      final store = MemoryStorage();
      final v2 = app(
        store,
        data: {
          'themePass': true,
          'ownedThemes': ['warmWalnut'],
          'preferences': {'theme': 'warmWalnut'},
          'ledger': [
            {
              'id': 'existing-coin',
              'label': 'Existing coins',
              'amount': 90,
              'at': '2026-11-22T00:00:00Z',
            },
          ],
          'results': {
            'levels/4': {'milliseconds': 1500, 'hints': 2},
          },
        },
      );
      await v2.open(const PuzzleId.level(4), replay: true);
      expect(v2.hintsRemaining, 0);
      expect(v2.hasThemePass, isTrue);
      expect(v2.adFree, isFalse);
      expect(v2.ownedThemes, 23);
      expect(v2.theme.label, 'Warm Walnut');
      expect(v2.coinBalance, 90);
      await v2.flush();
      expect(
        (await store.load())['schemaVersion'],
        GameStateStorage.schemaVersion,
      );
      v2.dispose();
    },
  );
}
