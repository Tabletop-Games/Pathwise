import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/logic/game_state_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Widget tests run in debug mode, which uses the debug save key.
const _debugKey = 'pathwise.debug.save.v1';

void main() {
  late SharedPreferencesAsync preferences;
  late GameStateStorage storage;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    storage = GameStateStorage(preferences);
  });

  test('a fresh install loads an empty save and may write', () async {
    expect(await storage.load(), isEmpty);
    await storage.save(
      jsonEncode({'schemaVersion': GameStateStorage.schemaVersion}),
    );
    expect(await preferences.getString(_debugKey), isNotNull);
  });

  test('a current-schema save round-trips unchanged', () async {
    final snapshot = {
      'schemaVersion': GameStateStorage.schemaVersion,
      'hintBalance': 3,
      'ownedTips': ['classic'],
    };
    await storage.load();
    await storage.save(jsonEncode(snapshot));
    expect(await GameStateStorage(preferences).load(), snapshot);
  });

  test('only the current schema version is readable', () async {
    for (final version in [
      null,
      0,
      GameStateStorage.schemaVersion - 1,
      GameStateStorage.schemaVersion + 1,
    ]) {
      await preferences.setString(
        _debugKey,
        jsonEncode({'schemaVersion': version, 'hintBalance': 9}),
      );
      await expectLater(
        GameStateStorage(preferences).load(),
        throwsFormatException,
        reason: 'schema $version',
      );
    }
  });

  test('a non-object save is rejected', () async {
    await preferences.setString(_debugKey, jsonEncode([1, 2, 3]));
    await expectLater(storage.load(), throwsFormatException);
  });

  test('nothing may overwrite a save that has not been read', () async {
    await preferences.setString(_debugKey, '{"schemaVersion":99}');
    await expectLater(storage.load(), throwsFormatException);
    storage.protect();
    expect(() => storage.save('{}'), throwsStateError);
    expect(await preferences.getString(_debugKey), '{"schemaVersion":99}');
  });

  test('saving before the first load is refused', () {
    expect(() => storage.save('{}'), throwsStateError);
  });
}
