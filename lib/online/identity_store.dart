import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The refresh credential is a server-issued secret. It proves possession of
/// this installation's device record; the player id alone proves nothing.
final class Identity {
  const Identity(this.playerId, this.refresh);
  final String playerId;
  final String refresh;
}

/// A command awaiting delivery. The operation id makes retries idempotent.
final class PendingCommand {
  const PendingCommand(this.op, this.type, this.args);
  final String op;
  final String type;
  final Map<String, Object?> args;

  Map<String, Object?> toJson() => {'op': op, 'type': type, 'args': args};

  static PendingCommand? tryParse(Object? value) {
    if (value is! Map) return null;
    final op = value['op'];
    final type = value['type'];
    final args = value['args'];
    if (op is! String || type is! String || args is! Map) return null;
    return PendingCommand(op, type, Map<String, Object?>.from(args));
  }
}

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

/// In-memory store for tests.
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

class IdentityStore {
  IdentityStore([KeyValueStore? store])
    : _preferences = store ?? PreferencesKeyValueStore();

  final KeyValueStore _preferences;
  static const _identityKey = kDebugMode
      ? 'pathwise.debug.identity.v1'
      : 'pathwise.identity.v1';
  static const _outboxKey = kDebugMode
      ? 'pathwise.debug.outbox.v1'
      : 'pathwise.outbox.v1';

  Future<Identity?> read() async {
    final text = await _preferences.getString(_identityKey);
    if (text == null) return null;
    try {
      final data = jsonDecode(text);
      if (data is Map &&
          data['player'] is String &&
          data['refresh'] is String) {
        return Identity(data['player'] as String, data['refresh'] as String);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> write(Identity identity) => _preferences.setString(
    _identityKey,
    jsonEncode({'player': identity.playerId, 'refresh': identity.refresh}),
  );

  Future<void> clear() async {
    await _preferences.remove(_identityKey);
    await _preferences.remove(_outboxKey);
  }

  Future<List<PendingCommand>> readOutbox() async {
    final text = await _preferences.getString(_outboxKey);
    if (text == null) return [];
    try {
      final data = jsonDecode(text);
      if (data is! List) return [];
      return [
        for (final row in data)
          if (PendingCommand.tryParse(row) case final command?) command,
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> writeOutbox(List<PendingCommand> commands) =>
      _preferences.setString(
        _outboxKey,
        jsonEncode([for (final command in commands) command.toJson()]),
      );
}
