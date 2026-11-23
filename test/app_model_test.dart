import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/game_state_storage.dart';
import '../lib/logic/puzzle.dart';
import '../lib/model/app_model.dart';
import '../lib/model/game_state.dart';
import '../lib/model/user_preferences.dart';

class MemoryStorage extends GameStateStorage {
  String? value;
  int writes = 0;
  bool fail = false;

  @override
  Future<Map<String, dynamic>> load() async =>
      value == null ? {} : jsonDecode(value!) as Map<String, dynamic>;

  @override
  Future<void> save(String snapshot) async {
    writes++;
    if (fail) throw StateError('Simulated write error');
    value = snapshot;
  }
}

VerifiedPuzzle fixture() =>
    VerifiedPuzzle(Puzzle(3, [0, 2, 4, 8]), [0, 1, 2, 5, 4, 3, 6, 7, 8]);

void complete(AppModel model) {
  final route = fixture().solution;
  model.begin(route.first);
  for (final cell in route.skip(1)) {
    model.step(cell);
  }
  model.end();
}

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
}
