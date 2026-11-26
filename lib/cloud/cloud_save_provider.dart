import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'key_value_store.dart';

/// The Play Games account or the service is unavailable right now. Sync keeps
/// the device copy and retries with backoff.
final class CloudUnavailable implements Exception {
  const CloudUnavailable([this.reason = 'unavailable']);
  final String reason;
  @override
  String toString() => 'CloudUnavailable: $reason';
}

/// Sign-in was rejected or failed for a reason other than cancellation.
final class CloudAuthFailed implements Exception {
  const CloudAuthFailed();
}

/// Result of reading the saved game. Either [bytes] (null when none exists) or
/// a conflict between this device's last write and another device's write.
final class CloudFetch {
  const CloudFetch({
    this.bytes,
    this.conflictId,
    this.conflictRemote,
    this.conflictLocal,
  });

  final List<int>? bytes;
  final String? conflictId;
  final List<int>? conflictRemote;
  final List<int>? conflictLocal;

  bool get conflict => conflictId != null;
}

/// Result of writing the saved game. A conflict means another device wrote
/// after this device read; nothing was written.
final class CloudCommit {
  const CloudCommit.committed()
    : committed = true,
      conflictId = null,
      conflictRemote = null;
  const CloudCommit.conflict(this.conflictId, this.conflictRemote)
    : committed = false;

  final bool committed;
  final String? conflictId;
  final List<int>? conflictRemote;
}

/// Account and saved-game operations. The sync service depends only on this.
abstract interface class CloudSaveProvider {
  /// False on platforms without Play Games Saved Games.
  bool get supported;

  /// Stable account identifier, or null when signed out.
  Future<String?> currentAccount();

  /// Explicit sign-in. Returns the account identifier, or null on cancel.
  Future<String?> signIn();

  Future<void> signOut();

  Future<CloudFetch> fetch(String name);

  Future<CloudCommit> commit(String name, List<int> bytes, String description);

  /// Resolves a conflict by writing [bytes] as the saved game.
  Future<void> resolve(String conflictId, List<int> bytes);
}

/// Play Games Services Saved Games through the Android bridge in
/// `CloudSaveChannel.java`. Only Android is supported; iOS uses
/// [UnsupportedCloudSaves].
class PlayGamesCloudSaves implements CloudSaveProvider {
  PlayGamesCloudSaves({
    MethodChannel? channel,
    Duration? timeout,
    bool enabled = false,
  }) : _channel =
           channel ?? const MethodChannel('games.tabletop.pathwise/cloud'),
       _timeout = timeout ?? const Duration(seconds: 25),
       _enabled = enabled;

  final MethodChannel _channel;
  final Duration _timeout;
  final bool _enabled;

  @override
  bool get supported =>
      defaultTargetPlatform == TargetPlatform.android && _enabled;

  Future<Map<Object?, Object?>> _call(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!supported) throw const CloudUnavailable('unsupported');
    try {
      final result = await _channel
          .invokeMapMethod<Object?, Object?>(method, args)
          .timeout(_timeout);
      return result ?? const {};
    } on PlatformException catch (error) {
      if (error.code == 'auth_failed') throw const CloudAuthFailed();
      throw CloudUnavailable(error.code);
    } on MissingPluginException {
      throw const CloudUnavailable('unsupported');
    } on TimeoutException {
      throw const CloudUnavailable('timeout');
    }
  }

  static List<int>? _bytes(Object? value) => value is Uint8List ? value : null;

  @override
  Future<String?> currentAccount() async {
    if (!supported) return null;
    final status = await _call('status');
    return status['signedIn'] == true ? status['playerId'] as String? : null;
  }

  @override
  Future<String?> signIn() async {
    final result = await _call('signIn');
    return result['signedIn'] == true ? result['playerId'] as String? : null;
  }

  @override
  Future<void> signOut() async {
    if (!supported) return;
    await _call('signOut');
  }

  @override
  Future<CloudFetch> fetch(String name) async {
    final result = await _call('fetch', {'name': name});
    if (result['conflictId'] is String) {
      return CloudFetch(
        conflictId: result['conflictId'] as String,
        conflictRemote: _bytes(result['conflictRemote']) ?? const [],
        conflictLocal: _bytes(result['conflictLocal']) ?? const [],
      );
    }
    return CloudFetch(bytes: _bytes(result['bytes']));
  }

  @override
  Future<CloudCommit> commit(
    String name,
    List<int> bytes,
    String description,
  ) async {
    final result = await _call('commit', {
      'name': name,
      'bytes': Uint8List.fromList(bytes),
      'description': description,
    });
    if (result['committed'] == true) return const CloudCommit.committed();
    return CloudCommit.conflict(
      result['conflictId'] as String,
      _bytes(result['conflictRemote']) ?? const [],
    );
  }

  @override
  Future<void> resolve(String conflictId, List<int> bytes) async {
    await _call('resolve', {
      'conflictId': conflictId,
      'bytes': Uint8List.fromList(bytes),
    });
  }
}

/// Platforms without Saved Games. Sign-in is never offered and no saves sync.
class UnsupportedCloudSaves implements CloudSaveProvider {
  const UnsupportedCloudSaves();

  @override
  bool get supported => false;
  @override
  Future<String?> currentAccount() async => null;
  @override
  Future<String?> signIn() async => null;
  @override
  Future<void> signOut() async {}
  @override
  Future<CloudFetch> fetch(String name) =>
      Future.error(const CloudUnavailable('unsupported'));
  @override
  Future<CloudCommit> commit(
    String name,
    List<int> bytes,
    String description,
  ) => Future.error(const CloudUnavailable('unsupported'));
  @override
  Future<void> resolve(String conflictId, List<int> bytes) =>
      Future.error(const CloudUnavailable('unsupported'));
}

/// Local stand-in for Saved Games. Debug builds use it because the debug
/// package has no Play Games project. Tests use it with simulated failures.
/// State persists in [store], so the fake survives restarts like the cloud.
class FakeCloudSaves implements CloudSaveProvider {
  FakeCloudSaves({required KeyValueStore store, required String key})
    : _store = store,
      _key = key;

  final KeyValueStore _store;
  final String _key;
  bool loaded = false;
  String? account;
  final _saves = <String, List<int>>{};
  final _conflicts = <String, (String, List<int>)>{};
  int _conflictSerial = 0;

  /// Failure injection for tests.
  bool offline = false;
  int failNextCommits = 0;
  int failNextFetches = 0;
  int conflictsNextCommits = 0;

  @override
  bool get supported => true;

  Future<void> _load() async {
    if (loaded) return;
    final text = await _store.getString(_key);
    loaded = true;
    if (text == null) return;
    final data = jsonDecode(text) as Map<String, dynamic>;
    account = data['account'] as String?;
    for (final entry in (data['saves'] as Map? ?? {}).entries) {
      _saves[entry.key as String] = base64Decode(entry.value as String);
    }
  }

  Future<void> _save() => _store.setString(
    _key,
    jsonEncode({
      'account': account,
      'saves': {
        for (final entry in _saves.entries)
          entry.key: base64Encode(entry.value),
      },
    }),
  );

  /// Each account has its own saved games, as in Play Games.
  String _slot(String name) => '${account ?? ''}::$name';

  void _checkOnline() {
    if (offline) throw const CloudUnavailable('offline');
  }

  @override
  Future<String?> currentAccount() async {
    await _load();
    return account;
  }

  @override
  Future<String?> signIn() async {
    await _load();
    _checkOnline();
    account ??= 'fake-player-1';
    await _save();
    return account;
  }

  @override
  Future<void> signOut() async {
    await _load();
    account = null;
    await _save();
  }

  /// Signs in as [id] without going through the Play Games UI (tests only).
  Future<void> switchAccount(String? id) async {
    await _load();
    account = id;
    await _save();
  }

  /// Simulates another device writing the save for the current account.
  Future<void> externalWrite(String name, List<int> bytes) async {
    await _load();
    _saves[_slot(name)] = List<int>.of(bytes);
    await _save();
  }

  /// The save currently in the cloud for the current account, for assertions.
  Future<List<int>?> stored(String name) async {
    await _load();
    return _saves[_slot(name)];
  }

  @override
  Future<CloudFetch> fetch(String name) async {
    await _load();
    _checkOnline();
    if (failNextFetches > 0) {
      failNextFetches--;
      throw const CloudUnavailable('fetch failed');
    }
    final bytes = _saves[_slot(name)];
    return CloudFetch(bytes: bytes == null ? null : List<int>.of(bytes));
  }

  @override
  Future<CloudCommit> commit(
    String name,
    List<int> bytes,
    String description,
  ) async {
    await _load();
    _checkOnline();
    if (failNextCommits > 0) {
      failNextCommits--;
      throw const CloudUnavailable('commit failed');
    }
    if (conflictsNextCommits > 0) {
      conflictsNextCommits--;
      final id = 'conflict-${_conflictSerial++}';
      final remote = List<int>.of(_saves[_slot(name)] ?? const []);
      _conflicts[id] = (_slot(name), remote);
      return CloudCommit.conflict(id, remote);
    }
    _saves[_slot(name)] = List<int>.of(bytes);
    await _save();
    return const CloudCommit.committed();
  }

  @override
  Future<void> resolve(String conflictId, List<int> bytes) async {
    await _load();
    _checkOnline();
    final conflict = _conflicts.remove(conflictId);
    if (conflict == null) throw const CloudUnavailable('unknown conflict');
    _saves[conflict.$1] = List<int>.of(bytes);
    await _save();
  }
}
