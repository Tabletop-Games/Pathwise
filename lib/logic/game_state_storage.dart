import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single versioned snapshot keeps completion records and resume data in sync.
class GameStateStorage {
  GameStateStorage([this._injected]);

  final SharedPreferencesAsync? _injected;
  late final _preferences = _injected ?? SharedPreferencesAsync();
  static const schemaVersion = 16;
  static const _key = kDebugMode
      ? 'pathwise.debug.save.v1'
      : 'pathwise.save.v1';
  bool _loaded = false;

  Future<Map<String, dynamic>> load() async {
    final snapshot = await _preferences.getString(_key);
    if (snapshot == null) {
      _loaded = true;
      return {};
    }
    final decoded = jsonDecode(snapshot);
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported saved progress');
    }
    _loaded = true;
    return decoded;
  }

  void protect() => _loaded = false;

  Future<void> save(String snapshot) async {
    // A failed startup read must not overwrite existing progress.
    if (!_loaded) throw StateError('Local progress is unavailable');
    await _preferences.setString(_key, snapshot);
  }
}
