import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cloud_save_format.dart';
import 'cloud_save_provider.dart';
import 'key_value_store.dart';

/// Shown on the Settings screen and in the sync-conflict dialog.
enum CloudSyncStatus {
  unsupported,
  signedOut,
  idle,
  syncing,
  waitingForNetwork,
  conflict,
  damaged,
  error,
}

/// Both copies, summarised, for the player's decision.
final class SyncChoice {
  const SyncChoice({
    required this.device,
    required this.cloud,
    required this.remote,
  });
  final SaveSummary device;
  final SaveSummary cloud;
  final CloudEnvelope remote;
}

typedef SnapshotSource = Map<String, dynamic> Function();
typedef ApplySnapshot = Future<void> Function(Map<String, dynamic> payload);

/// Keeps the device save and the Play Games saved game in step.
///
/// Guarantees:
/// * One pass runs at a time. Passes are serialized.
/// * Uploads carry a revision. A concurrent cloud write is detected by the
///   provider and the pass re-plans against the newer copy.
/// * The last agreed state is persisted, so a pass interrupted by process
///   death re-runs safely: nothing is double-applied because planning compares
///   digests, not history.
/// * Whatever a pass replaces on this device is first saved as a backup.
/// * Economy that differs on both sides is never merged automatically; the
///   player chooses.
///
/// These guarantees are the best a client-managed save can give. It is not a
/// transactional ledger. See docs/cloud-saves.md.
class CloudSyncService extends ChangeNotifier {
  CloudSyncService({
    required CloudSaveProvider provider,
    required KeyValueStore store,
    required String prefix,
    required SnapshotSource snapshot,
    required ApplySnapshot apply,
    required bool Function() isOnline,
    this.saveName = 'pathwise-progress-v1',
    this.providerName = 'Google Play Games',
    DateTime Function()? now,
    this.debounce = const Duration(seconds: 20),
    this.urgentDelay = const Duration(seconds: 2),
    this.retryDelays = const [
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ],
  }) : _provider = provider,
       _store = store,
       _prefix = prefix,
       _snapshot = snapshot,
       _apply = apply,
       _isOnline = isOnline,
       _now = now ?? DateTime.now;

  final CloudSaveProvider _provider;
  final KeyValueStore _store;
  final String _prefix;
  final SnapshotSource _snapshot;
  final ApplySnapshot _apply;
  final bool Function() _isOnline;
  final DateTime Function() _now;
  final String saveName;

  /// Shown to the player, for example "Google Play Games".
  final String providerName;
  final Duration debounce;
  final Duration urgentDelay;
  final List<Duration> retryDelays;

  CloudSyncStatus _status = CloudSyncStatus.signedOut;
  CloudSyncStatus get status => _status;
  bool _signedIn = false;
  bool get signedIn => _signedIn;
  DateTime? _lastSynced;
  DateTime? get lastSynced => _lastSynced;
  String? _message;
  String? get message => _message;
  SyncChoice? _choice;
  SyncChoice? get choice => _choice;
  bool _hasBackup = false;
  bool get hasBackup => _hasBackup;

  CloudBase? _base;
  Timer? _timer;
  int _retry = 0;
  bool _disposed = false;
  Future<void> _lane = Future<void>.value();

  String get _baseKey => '$_prefix.base.v1';
  String get _syncedKey => '$_prefix.synced.v1';
  String get _backupKey => '$_prefix.backup.v1';
  String get _optOutKey => '$_prefix.optout.v1';

  /// Set by "Stop cloud sync on this device". Play Games has no sign-out call,
  /// so the app keeps its own switch until the player signs in again.
  bool _optedOut = false;
  bool get optedOut => _optedOut;

  /// Purchases of consumables require a recoverable account and a successful
  /// sync that is not waiting on a player decision.
  bool get readyForConsumablePurchase =>
      _signedIn &&
      _status == CloudSyncStatus.idle &&
      _lastSynced != null &&
      _choice == null;

  Future<void> start() async {
    _base = await _loadBase();
    _lastSynced = await _loadSynced();
    _hasBackup = (await _store.getString(_backupKey)) != null;
    _optedOut = (await _store.getString(_optOutKey)) == '1';
    if (!_provider.supported) {
      _set(CloudSyncStatus.unsupported);
      return;
    }
    if (_optedOut) {
      _signedIn = false;
      _set(CloudSyncStatus.signedOut);
      return;
    }
    try {
      _signedIn = await _provider.currentAccount() != null;
    } on CloudUnavailable {
      _signedIn = false;
    }
    _set(_signedIn ? CloudSyncStatus.idle : CloudSyncStatus.signedOut);
    if (_signedIn) scheduleSync(urgent: true);
  }

  /// Called after every persisted local change. Economy changes sync quickly;
  /// progress such as an unfinished route waits for the debounce window.
  void localChanged(Map<String, dynamic> payload) {
    if (_disposed || !_provider.supported || !_signedIn || _optedOut) return;
    final economyChanged =
        _base == null || economyDigest(payload) != _base!.economy;
    scheduleSync(urgent: economyChanged);
  }

  void scheduleSync({required bool urgent}) {
    if (_disposed || !_provider.supported) return;
    _timer?.cancel();
    _timer = Timer(urgent ? urgentDelay : debounce, () => unawaited(syncNow()));
  }

  /// Runs one serialized pass. Returns true when the device and cloud agree.
  Future<bool> syncNow() {
    final result = _lane.then((_) => _run());
    _lane = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Required before a consumable purchase: sign in, then sync successfully.
  Future<bool> prepareForPurchase() async {
    if (!_signedIn) return false;
    final synced = await syncNow();
    return synced && _choice == null;
  }

  Future<void> signIn() async {
    if (!_provider.supported) return;
    _optedOut = false;
    await _store.remove(_optOutKey);
    _set(CloudSyncStatus.syncing);
    try {
      final account = await _provider.signIn();
      _signedIn = account != null;
      if (!_signedIn) {
        _message = null;
        _set(CloudSyncStatus.signedOut);
        return;
      }
      _message = null;
      await syncNow();
    } on CloudAuthFailed {
      _message = 'Google Play Games sign-in did not complete. Try again.';
      _set(CloudSyncStatus.error);
    } on CloudUnavailable {
      _message = 'Google Play Games is unavailable right now.';
      _set(CloudSyncStatus.error);
    }
  }

  /// Stops syncing on this device. The device copy stays. The next sign-in
  /// compares it with that account's cloud save and asks before replacing it.
  Future<void> signOut() async {
    _timer?.cancel();
    _optedOut = true;
    await _store.setString(_optOutKey, '1');
    await _provider.signOut();
    _signedIn = false;
    _choice = null;
    _message = null;
    _base = null;
    await _store.remove(_baseKey);
    _set(CloudSyncStatus.signedOut);
  }

  /// Applies the player's choice after a conflict.
  Future<void> resolveChoice({required bool keepDevice}) async {
    final choice = _choice;
    if (choice == null) return;
    await _lock(() async {
      if (keepDevice) {
        // The cloud copy is about to be overwritten. Keep it on the device.
        await _backup(choice.remote.encode());
        final rev = _nextRevision(choice.remote);
        final committed = await _writeCloud(_snapshot(), rev);
        if (committed) {
          _choice = null;
          _markSynced(rev, _snapshot(), await _accountKey());
        }
      } else {
        await _adoptRemote(choice.remote);
        _choice = null;
      }
      _set(CloudSyncStatus.idle);
    });
  }

  /// Replaces this device's save with the cloud save, after backing up.
  Future<void> restoreFromCloud() => _lock(() async {
    final fetch = await _provider.fetch(saveName);
    final remote = _decodeOrNull(fetch.bytes);
    if (remote == null) {
      _message = 'There is no cloud save for this account yet.';
      _set(CloudSyncStatus.idle);
      return;
    }
    await _adoptRemote(remote);
    _set(CloudSyncStatus.idle);
  });

  /// Restores the device copy that the last replacement backed up.
  Future<void> restoreBackup() => _lock(() async {
    final text = await _store.getString(_backupKey);
    if (text == null) return;
    final envelope = CloudEnvelope.decode(base64Decode(text));
    await _apply(envelope.payload);
    _hasBackup = false;
    await _store.remove(_backupKey);
    scheduleSync(urgent: true);
  });

  /// Used only after the cloud save could not be read. Writes this device's
  /// save over the unreadable one.
  Future<void> replaceDamagedCloudSave() => _lock(() async {
    final rev = (_base?.revision ?? 0) + 1;
    if (await _writeCloud(_snapshot(), rev)) {
      _markSynced(rev, _snapshot(), await _accountKey());
      _set(CloudSyncStatus.idle);
    }
  });

  Future<T> _lock<T>(Future<T> Function() task) {
    final result = _lane.then((_) => task());
    _lane = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> _run() async {
    if (_disposed || !_provider.supported) return false;
    if (_optedOut) {
      _set(CloudSyncStatus.signedOut);
      return false;
    }
    if (!_isOnline()) {
      _set(CloudSyncStatus.waitingForNetwork);
      _scheduleRetry();
      return false;
    }
    _timer?.cancel();
    _set(CloudSyncStatus.syncing);
    try {
      final account = await _provider.currentAccount();
      _signedIn = account != null;
      if (account == null) {
        _set(CloudSyncStatus.signedOut);
        return false;
      }
      final accountKey = digestOf(account);
      var base = _base;
      if (base != null && base.account != accountKey) base = null;
      _base = base;

      for (var attempt = 0; attempt < 3; attempt++) {
        final fetch = await _provider.fetch(saveName);
        if (fetch.conflict) {
          // Another device wrote while this one was reading. Keep the device's
          // view as a backup, then let the cloud's copy win and re-plan.
          await _backup(fetch.conflictLocal ?? const []);
          await _provider.resolve(
            fetch.conflictId!,
            fetch.conflictRemote ?? const [],
          );
          continue;
        }
        final CloudEnvelope? remote;
        try {
          remote = _decodeOrNull(fetch.bytes);
        } on CorruptSave {
          _message =
              'Your cloud save could not be read. Your device copy is safe.';
          _set(CloudSyncStatus.damaged);
          return false;
        }
        final local = _snapshot();
        final plan = planSync(base: _base, local: local, remote: remote);
        switch (plan) {
          case PlanNone():
            _markSynced(_base!.revision, local, accountKey);
            return _finish();
          case PlanUpload(:final payload):
            final rev = _nextRevision(remote);
            if (await _writeCloud(payload, rev)) {
              _markSynced(rev, payload, accountKey);
              return _finish();
            }
          case PlanApply(:final payload, :final upload):
            if (!_sameSave(local, payload)) {
              await _backupIfReplacing(local, payload);
              await _apply(payload);
            }
            final after = _snapshot();
            if (upload) {
              final rev = _nextRevision(remote);
              if (await _writeCloud(after, rev)) {
                _markSynced(rev, after, accountKey);
                return _finish();
              }
            } else if (remote != null) {
              _markSynced(remote.revision, after, accountKey);
              return _finish();
            }
          case PlanAskUser():
            if (remote == null) {
              throw StateError('a player choice needs a cloud save');
            }
            _choice = SyncChoice(
              device: SaveSummary.of(local, _now().millisecondsSinceEpoch),
              cloud: SaveSummary.of(remote.payload, remote.savedAt),
              remote: remote,
            );
            _message = 'Your device and the cloud have different progress.';
            _set(CloudSyncStatus.conflict);
            return false;
        }
      }
      _message = 'Cloud sync is busy. It will try again.';
      _set(CloudSyncStatus.error);
      _scheduleRetry();
      return false;
    } on CloudAuthFailed {
      _message =
          'Sign in to Google Play Games again to keep your progress synced.';
      _set(CloudSyncStatus.error);
      _signedIn = false;
      return false;
    } on CloudUnavailable catch (error) {
      _message = error.reason == 'offline' || error.reason == 'timeout'
          ? 'Could not reach Google Play Games. Your progress is saved on this device.'
          : 'Cloud sync failed. Your progress is saved on this device.';
      _set(
        _isOnline() ? CloudSyncStatus.error : CloudSyncStatus.waitingForNetwork,
      );
      _scheduleRetry();
      return false;
    }
  }

  bool _finish() {
    _retry = 0;
    _message = null;
    _set(CloudSyncStatus.idle);
    return true;
  }

  int _nextRevision(CloudEnvelope? remote) {
    final baseRevision = _base?.revision ?? 0;
    final cloudRevision = remote?.revision ?? 0;
    return (baseRevision > cloudRevision ? baseRevision : cloudRevision) + 1;
  }

  Future<bool> _writeCloud(Map<String, dynamic> payload, int revision) async {
    final envelope = CloudEnvelope.wrap(
      payload,
      revision: revision,
      savedAt: _now().millisecondsSinceEpoch,
    );
    final bytes = envelope.encode();
    if (bytes.length > cloudSaveMaxBytes) {
      _message = 'Your progress is too large to sync.';
      _set(CloudSyncStatus.error);
      return false;
    }
    final result = await _provider.commit(saveName, bytes, 'Pathwise progress');
    if (result.committed) return true;
    // Another device wrote between our read and this write. Keep the cloud's
    // copy and let the next attempt plan against it.
    await _provider.resolve(
      result.conflictId!,
      result.conflictRemote ?? const [],
    );
    return false;
  }

  Future<void> _adoptRemote(CloudEnvelope remote) async {
    final local = _snapshot();
    if (!_sameSave(local, remote.payload)) {
      await _backupIfReplacing(local, remote.payload);
      await _apply(remote.payload);
    }
    _markSynced(remote.revision, _snapshot(), await _accountKey());
  }

  Future<void> _backupIfReplacing(
    Map<String, dynamic> local,
    Map<String, dynamic> incoming,
  ) async {
    if (isFreshSave(local)) return;
    if (economyDigest(local) == economyDigest(incoming) &&
        digestOf(local) == digestOf(incoming)) {
      return;
    }
    await _backup(
      CloudEnvelope.wrap(
        local,
        // The envelope needs a positive revision. Backups are never uploaded.
        revision: _base?.revision ?? 1,
        savedAt: _now().millisecondsSinceEpoch,
      ).encode(),
    );
  }

  Future<void> _backup(List<int> bytes) async {
    if (bytes.isEmpty) return;
    await _store.setString(_backupKey, base64Encode(bytes));
    _hasBackup = true;
  }

  bool _sameSave(Map<String, dynamic> a, Map<String, dynamic> b) =>
      digestOf(a) == digestOf(b);

  void _markSynced(int revision, Map<String, dynamic> payload, String account) {
    final base = CloudBase(
      revision: revision,
      economy: economyDigest(payload),
      payloadDigest: digestOf(payload),
      account: account,
    );
    _base = base;
    _lastSynced = _now();
    unawaited(_store.setString(_baseKey, jsonEncode(base.toJson())));
    unawaited(
      _store.setString(
        _syncedKey,
        _lastSynced!.millisecondsSinceEpoch.toString(),
      ),
    );
  }

  Future<String> _accountKey() async {
    final account = await _provider.currentAccount();
    return digestOf(account ?? '');
  }

  void _scheduleRetry() {
    if (_disposed) return;
    final index = _retry.clamp(0, retryDelays.length - 1);
    _retry++;
    _timer?.cancel();
    _timer = Timer(retryDelays[index], () => unawaited(syncNow()));
  }

  CloudEnvelope? _decodeOrNull(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    return CloudEnvelope.decode(bytes);
  }

  Future<CloudBase?> _loadBase() async {
    final text = await _store.getString(_baseKey);
    if (text == null) return null;
    try {
      return CloudBase.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Future<DateTime?> _loadSynced() async {
    final text = await _store.getString(_syncedKey);
    final ms = text == null ? null : int.tryParse(text);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _set(CloudSyncStatus value) {
    if (_disposed) return;
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
