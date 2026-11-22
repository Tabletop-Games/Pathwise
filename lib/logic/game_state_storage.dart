import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A single versioned snapshot keeps completion records and resume data in sync.
class GameStateStorage {
  GameStateStorage([this._injected]);

  final SharedPreferencesAsync? _injected;
  late final _preferences = _injected ?? SharedPreferencesAsync();
  static const _key = 'pathwise.save.v1';
  bool _loaded = false;

  Future<Map<String, dynamic>> load() async {
    final snapshot = await _preferences.getString(_key);
    _loaded = true;
    if (snapshot == null) return {};
    try {
      final decoded = jsonDecode(snapshot);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> save(String snapshot) async {
    // A failed startup read must not overwrite existing progress.
    if (!_loaded) throw StateError('Local progress is unavailable');
    await _preferences.setString(_key, snapshot);
  }
}
