import 'dart:convert';

import '../../lib/cloud/key_value_store.dart';
import '../../lib/logic/game_state_storage.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/game_state.dart';

/// Shared fixtures for the test suite: an in-memory save, a tiny certified
/// board, and helpers that finish it.

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

AppModel journeyModel(MemoryStorage storage, Map<String, dynamic> snapshot) =>
    AppModel(
      storage: storage,
      snapshot: snapshot,
      loader: (_) async => fixture(),
      bootTime: () => (boot: 1, milliseconds: 100),
    );

Future<void> clear(AppModel model, int level, {bool replay = false}) async {
  await model.open(PuzzleId.level(level), replay: replay);
  complete(model);
  await model.flush();
}


/// In-memory [KeyValueStore] with the same contract as the preferences store.
class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
