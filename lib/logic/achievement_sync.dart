import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../model/native_achievements.dart';
import 'play_games.dart';

abstract interface class AchievementSyncTarget implements Listenable {
  Map<AchievementMetric, int> get achievementCounters;
  int get achievementRevision;
  bool get isDrawing;
  bool get achievementProgressNeedsOwner;
  bool achievementsBelongToOtherAccount(String account);
  Future<bool> bindAchievementProgress(String account);
  Future<bool> confirmAchievements(String account, Map<String, int> progress);
}

typedef RemoteAchievement = ({int steps, int total, bool unlocked});
typedef RemoteAchievementState = ({
  String player,
  Map<String, RemoteAchievement> progress,
});
typedef AchievementUpdate = ({String id, int? steps});

class PlayAchievementGateway {
  const PlayAchievementGateway();

  Future<bool> authenticated() async =>
      await PlayGames.call<bool>('status') == true;
  Future<bool> signIn() async => await PlayGames.call<bool>('signIn') == true;
  Future<bool> openAchievements() async =>
      await PlayGames.call<bool>('achievements') == true;

  Future<RemoteAchievementState?> load() async {
    final response = await PlayGames.call<Map<Object?, Object?>>(
      'loadAchievements',
    );
    if (response == null || response['player'] is! String) return null;
    final entries = response['progress'];
    if (entries is! Map) return null;
    return (
      player: response['player'] as String,
      progress: {
        for (final row in entries.entries)
          if (row.key is String)
            if (row.value case [
              final int steps,
              final int total,
              final bool unlocked,
            ])
              row.key as String: (
                steps: steps,
                total: total,
                unlocked: unlocked,
              ),
      },
    );
  }

  Future<bool> update(String player, AchievementUpdate update) async =>
      await PlayGames.call<bool>('updateAchievement', {
        'player': player,
        'id': update.id,
        if (update.steps case final steps?) 'steps': '$steps',
      }) ==
      true;
}

enum AchievementSyncStatus {
  disabled,
  waiting,
  syncing,
  confirmed,
  unavailable,
}

enum NativeAchievementScreen { opened, signInUnavailable, unavailable }

class AchievementSync extends ChangeNotifier {
  AchievementSync(
    this.model, {
    PlayAchievementGateway gateway = const PlayAchievementGateway(),
    Map<String, String>? ids,
    bool enabled = PlayGames.enabled,
    this.isConnected,
  }) : _gateway = gateway,
       ids = _validateIds(ids ?? PlayGames.achievements),
       status = enabled
           ? AchievementSyncStatus.waiting
           : AchievementSyncStatus.disabled {
    if (enabled) {
      _seen = _desired();
      model.addListener(_onProgress);
    }
  }

  static Map<String, String> _validateIds(Map<String, String> ids) {
    final counts = <String, int>{};
    for (final id in ids.values) {
      counts.update(id, (value) => value + 1, ifAbsent: () => 1);
    }
    return Map.unmodifiable({
      for (final item in nativeAchievements)
        if (ids[item.id] case final id?)
          if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) &&
              !id.startsWith('REPLACE_') &&
              counts[id] == 1)
            item.id: id,
    });
  }

  final AchievementSyncTarget model;
  final Map<String, String> ids;
  final PlayAchievementGateway _gateway;
  final bool Function()? isConnected;
  AchievementSyncStatus status;
  Map<String, int> _confirmed = const {};
  Map<String, int> _seen = const {};
  Timer? _debounce, _retry;
  Future<void>? _flight;
  bool _active = false, _disposed = false;
  bool accountMismatch = false;
  int _generation = 0;
  int _revision = -1;

  int confirmedSteps(NativeAchievement item) => _confirmed[item.id] ?? 0;
  bool confirmed(NativeAchievement item) => confirmedSteps(item) >= item.target;
  int get configuredCount => ids.length;
  bool get enabled => status != AchievementSyncStatus.disabled;

  Future<NativeAchievementScreen> openNative() async {
    if (!enabled) return NativeAchievementScreen.unavailable;
    if (!await _gateway.authenticated() && !await _gateway.signIn()) {
      return NativeAchievementScreen.signInUnavailable;
    }
    unawaited(refresh(accountMayHaveChanged: true));
    return await _gateway.openAchievements()
        ? NativeAchievementScreen.opened
        : NativeAchievementScreen.unavailable;
  }

  Map<String, int> _desired() {
    final counters = model.achievementCounters;
    return {
      for (final item in nativeAchievements)
        if (ids.containsKey(item.id)) item.id: item.progress(counters),
    };
  }

  void _onProgress() {
    if (!_active || ids.isEmpty || _revision == model.achievementRevision)
      return;
    _revision = model.achievementRevision;
    final desired = _desired();
    if (mapEquals(_seen, desired)) return;
    _seen = desired;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), refresh);
  }

  void foreground(bool active) {
    if (status == AchievementSyncStatus.disabled ||
        ids.isEmpty ||
        _active == active)
      return;
    _active = active;
    _generation++;
    _debounce?.cancel();
    _retry?.cancel();
    _confirmed = const {};
    accountMismatch = false;
    if (!active) {
      status = AchievementSyncStatus.waiting;
      notifyListeners();
      return;
    }
    _seen = _desired();
    unawaited(refresh());
    _retry = Timer.periodic(const Duration(seconds: 45), (_) => refresh());
  }

  Future<void> refresh({bool accountMayHaveChanged = false}) async {
    if (_disposed ||
        !_active ||
        ids.isEmpty ||
        model.isDrawing ||
        isConnected?.call() == false) {
      return;
    }
    if (accountMayHaveChanged) {
      _generation++;
      _confirmed = const {};
      accountMismatch = false;
      status = AchievementSyncStatus.waiting;
      notifyListeners();
      await _flight;
      if (_disposed || !_active) return;
    }
    final existing = _flight;
    if (existing != null) return existing;
    final generation = _generation;
    final requested = _desired();
    final future = _reconcile(generation);
    _flight = future;
    try {
      await future;
    } finally {
      _flight = null;
      if (_active &&
          !_disposed &&
          (generation != _generation || !mapEquals(requested, _desired()))) {
        _seen = _desired();
        unawaited(refresh());
      }
    }
  }

  bool _current(int generation) =>
      !_disposed && _active && _generation == generation;

  Future<void> _reconcile(int generation) async {
    status = AchievementSyncStatus.syncing;
    notifyListeners();
    final remote = await _gateway.load();
    if (!_current(generation)) return;
    if (remote == null) {
      _confirmed = const {};
      accountMismatch = false;
      status = AchievementSyncStatus.unavailable;
      notifyListeners();
      return;
    }

    final account = sha256.convert(utf8.encode(remote.player)).toString();
    accountMismatch = model.achievementsBelongToOtherAccount(account);
    final desired = _desired();
    final changes = <AchievementUpdate>[];
    final supported = <NativeAchievement, String>{};
    for (final item in nativeAchievements) {
      final id = ids[item.id];
      final value = remote.progress[id];
      if (id == null ||
          value == null ||
          value.total != (item.incremental ? item.target : 0)) {
        continue;
      }
      supported[item] = id;
      final target = desired[item.id] ?? 0;
      if (value.unlocked || target == 0 || target <= value.steps) continue;
      if ((!item.incremental || item.hidden) && target != item.target) {
        continue;
      }
      changes.add((id: id, steps: item.incremental ? target : null));
    }

    final needsBinding =
        model.achievementProgressNeedsOwner &&
        supported.keys.any((item) => (desired[item.id] ?? 0) > 0);
    final bound = !needsBinding || await model.bindAchievementProgress(account);
    final ready =
        !accountMismatch &&
        !model.isDrawing &&
        bound &&
        (needsBinding || changes.isNotEmpty);
    var verified = remote;
    if (changes.isNotEmpty &&
        ready &&
        _current(generation) &&
        !model.isDrawing) {
      await Future.wait(
        changes.map((change) => _gateway.update(remote.player, change)),
      );
      if (!_current(generation)) return;
      final updated = await _gateway.load();
      if (!_current(generation)) return;
      if (updated == null || updated.player != remote.player) {
        _confirmed = const {};
        accountMismatch = false;
        status = AchievementSyncStatus.unavailable;
        notifyListeners();
        return;
      }
      verified = updated;
    }
    if (!_current(generation)) return;

    _confirmed = {
      for (final entry in supported.entries)
        if (verified.progress[entry.value] case final value?)
          entry.key.id: value.unlocked
              ? entry.key.target
              : value.steps.clamp(0, entry.key.target - 1),
    };
    await model.confirmAchievements(account, _confirmed);
    if (!_current(generation)) return;
    status = AchievementSyncStatus.confirmed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    model.removeListener(_onProgress);
    _debounce?.cancel();
    _retry?.cancel();
    super.dispose();
  }
}
