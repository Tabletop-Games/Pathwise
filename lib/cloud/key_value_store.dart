import 'package:shared_preferences/shared_preferences.dart';

/// Small string store for sync bookkeeping and the local fake cloud. Keys are
/// the caller's responsibility; debug builds use `.debug` keys so they never
/// touch production data.
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class PreferencesKeyValueStore implements KeyValueStore {
  final _preferences = SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}
