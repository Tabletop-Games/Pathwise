import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/expedition.dart';
import 'trail_record_storage.dart';

/// A single versioned snapshot keeps completion records and resume data in sync.
class GameStateStorage {
  GameStateStorage([this._injected, this._trailStorage]);

  final TrailRecordStorage? _trailStorage;
  final _inMemoryTrails = <Trail, TrailRecord>{};

  Future<TrailRecord?> readTrail(Trail trail) async => _trailStorage == null
      ? _inMemoryTrails[trail]
      : _trailStorage.read(trail);

  Future<TrailRecord> mergeTrail(Trail trail, TrailRecord candidate) async {
    if (_trailStorage != null) return _trailStorage.merge(trail, candidate);
    final record = _inMemoryTrails.putIfAbsent(trail, TrailRecord.new);
    record.merge(candidate);
    return record;
  }

  final SharedPreferencesAsync? _injected;
  late final _preferences = _injected ?? SharedPreferencesAsync();
  static const schemaVersion = 6;
  static const _key = 'pathwise.save.v1';
  bool _loaded = false;

  Future<Map<String, dynamic>> load() async {
    final snapshot = await _preferences.getString(_key);
    if (snapshot == null) {
      _loaded = true;
      return {};
    }
    final decoded = jsonDecode(snapshot);
    if (decoded is! Map<String, dynamic> ||
        (decoded['schemaVersion'] != null &&
            decoded['schemaVersion'] != 1 &&
            decoded['schemaVersion'] != 2 &&
            decoded['schemaVersion'] != 3 &&
            decoded['schemaVersion'] != 4 &&
            decoded['schemaVersion'] != 5 &&
            decoded['schemaVersion'] != schemaVersion)) {
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
