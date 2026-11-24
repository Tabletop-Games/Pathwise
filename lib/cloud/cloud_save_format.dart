import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Versioned envelope stored in a Play Games Saved Game. The payload is the
/// same snapshot map the app keeps on the device, so both copies share one
/// schema and one migration path.
const cloudSaveFormat = 'pathwise-cloud';
const cloudSaveVersion = 1;

/// Saved Games allow several megabytes per snapshot. Refuse to upload anything
/// near that size so a write cannot fail half way through a sync.
const cloudSaveMaxBytes = 2 * 1024 * 1024;

/// Keys that are device-local or safe to merge when economy matches.
/// Everything else belongs to the economy unit: coins, hints, purchases,
/// rewards, results, streaks and achievements. Economy state is never merged
/// automatically, because a merge can duplicate or lose coins.
const progressKeys = <String>{
  'schemaVersion',
  'levelOneDemoSeen',
  'mechanicTutorials',
  'attempts',
  'playMilliseconds',
  'attackMinutes',
  'preferences',
  'economyActivity',
  'lastAutomaticAd',
  'billingProfile',
  'progressionBoot',
  'attack',
};

/// Crate timers change every few seconds during play. They are not economy.
const _volatileProgressionKeys = {'crateWait'};

final class CorruptSave implements Exception {
  const CorruptSave(this.reason);
  final String reason;
  @override
  String toString() => 'CorruptSave: $reason';
}

/// JSON with sorted keys, so equal maps always produce equal text.
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return [for (final item in value) _sorted(item)];
  return value;
}

String digestOf(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

/// Digest of the economy unit only. Two saves with equal economy digests
/// agree on every coin, purchase, reward and result.
String economyDigest(Map<String, dynamic> payload) {
  final economy = <String, dynamic>{};
  for (final entry in payload.entries) {
    if (progressKeys.contains(entry.key)) continue;
    if (entry.key == 'progression' && entry.value is Map) {
      final progression = Map<String, dynamic>.from(entry.value as Map);
      progression.removeWhere((key, _) => _volatileProgressionKeys.contains(key));
      economy[entry.key] = progression;
    } else {
      economy[entry.key] = entry.value;
    }
  }
  return digestOf(economy);
}

/// Signed-in player's record. `economy` and `payloadDigest` let a device tell
/// whether a remote save differs from its last synced state without parsing
/// both copies.
final class CloudEnvelope {
  const CloudEnvelope({
    required this.revision,
    required this.savedAt,
    required this.economy,
    required this.payloadDigest,
    required this.payload,
  });

  factory CloudEnvelope.wrap(
    Map<String, dynamic> payload, {
    required int revision,
    required int savedAt,
  }) => CloudEnvelope(
    revision: revision,
    savedAt: savedAt,
    economy: economyDigest(payload),
    payloadDigest: digestOf(payload),
    payload: payload,
  );

  final int revision;
  final int savedAt;
  final String economy;
  final String payloadDigest;
  final Map<String, dynamic> payload;

  List<int> encode() => utf8.encode(
    canonicalJson({
      'format': cloudSaveFormat,
      'version': cloudSaveVersion,
      'revision': revision,
      'savedAt': savedAt,
      'economy': economy,
      'payloadDigest': payloadDigest,
      'payload': payload,
    }),
  );

  /// Throws [CorruptSave] for anything that is not exactly what [encode] writes.
  static CloudEnvelope decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > cloudSaveMaxBytes) {
      throw const CorruptSave('empty or oversized');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const CorruptSave('not JSON');
    }
    if (decoded is! Map ||
        decoded['format'] != cloudSaveFormat ||
        decoded['version'] != cloudSaveVersion) {
      throw const CorruptSave('unknown format or version');
    }
    final revision = decoded['revision'];
    final savedAt = decoded['savedAt'];
    final economy = decoded['economy'];
    final digest = decoded['payloadDigest'];
    final payload = decoded['payload'];
    if (revision is! int ||
        revision < 1 ||
        savedAt is! int ||
        economy is! String ||
        digest is! String ||
        payload is! Map) {
      throw const CorruptSave('missing fields');
    }
    final typed = Map<String, dynamic>.from(payload);
    if (digestOf(typed) != digest) throw const CorruptSave('digest mismatch');
    if (economyDigest(typed) != economy) {
      throw const CorruptSave('economy digest mismatch');
    }
    return CloudEnvelope(
      revision: revision,
      savedAt: savedAt,
      economy: economy,
      payloadDigest: digest,
      payload: typed,
    );
  }
}

/// Merges progress keys of two saves whose economy is identical. Local values
/// win except where a union or maximum is always safe.
Map<String, dynamic> mergeProgress(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  final result = Map<String, dynamic>.from(local);
  Map<String, dynamic> map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  result['mechanicTutorials'] = {
    ...map(remote['mechanicTutorials']),
    ...map(local['mechanicTutorials']),
  };
  result['attempts'] = {...map(remote['attempts']), ...map(local['attempts'])};
  result['levelOneDemoSeen'] =
      local['levelOneDemoSeen'] == true || remote['levelOneDemoSeen'] == true;
  final localTime = local['playMilliseconds'];
  final remoteTime = remote['playMilliseconds'];
  if (localTime is int && remoteTime is int) {
    result['playMilliseconds'] = localTime > remoteTime ? localTime : remoteTime;
  }
  return result;
}

/// Economy taken from [economyFrom]; progress keys merged from [progressFrom].
Map<String, dynamic> combine(
  Map<String, dynamic> economyFrom,
  Map<String, dynamic> progressFrom,
) {
  final result = Map<String, dynamic>.from(economyFrom);
  for (final key in progressKeys) {
    if (progressFrom.containsKey(key)) result[key] = progressFrom[key];
  }
  return result;
}

/// A device that has only its welcome coins, no completed puzzles and no
/// unfinished attempt has nothing to lose when a cloud save is adopted.
bool isFreshSave(Map<String, dynamic> payload) {
  final results = payload['results'];
  final attempts = payload['attempts'];
  final ledger = payload['ledger'];
  final onlyWelcome = ledger is! List ||
      ledger.every((row) => row is Map && row['id'] == 'starter');
  return onlyWelcome &&
      (results is! Map || results.isEmpty) &&
      (attempts is! Map || attempts.isEmpty);
}

/// Human-readable facts about a save for the conflict dialog. No identifiers.
final class SaveSummary {
  const SaveSummary({
    required this.coins,
    required this.hints,
    required this.levelsSolved,
    required this.highestLevel,
    required this.savedAt,
  });

  factory SaveSummary.of(Map<String, dynamic> payload, int savedAt) {
    final ledger = payload['ledger'];
    var coins = payload['archivedCoins'] is int
        ? payload['archivedCoins'] as int
        : 0;
    if (ledger is List) {
      for (final row in ledger) {
        if (row is Map && row['amount'] is int) coins += row['amount'] as int;
      }
    }
    final results = payload['results'];
    var levels = 0;
    if (results is Map) {
      levels = results.keys.where((key) => key.toString().startsWith('levels/')).length;
    }
    return SaveSummary(
      coins: coins,
      hints: payload['hintBalance'] is int ? payload['hintBalance'] as int : 0,
      levelsSolved: levels,
      highestLevel: payload['highestUnlocked'] is int
          ? payload['highestUnlocked'] as int
          : 1,
      savedAt: savedAt,
    );
  }

  final int coins;
  final int hints;
  final int levelsSolved;
  final int highestLevel;
  final int savedAt;
}

/// Sync state last agreed with the cloud. Stored on the device.
final class CloudBase {
  const CloudBase({
    required this.revision,
    required this.economy,
    required this.payloadDigest,
    required this.account,
  });

  factory CloudBase.fromJson(Map<String, dynamic> json) => CloudBase(
    revision: json['revision'] as int,
    economy: json['economy'] as String,
    payloadDigest: json['payloadDigest'] as String,
    account: json['account'] as String,
  );

  final int revision;
  final String economy;
  final String payloadDigest;
  final String account;

  Map<String, Object> toJson() => {
    'revision': revision,
    'economy': economy,
    'payloadDigest': payloadDigest,
    'account': account,
  };
}

/// What a sync pass should do. Planning is pure, so every rule is tested
/// without Play Games.
sealed class SyncPlan {
  const SyncPlan();
}

/// Nothing to do: the device and cloud already agree.
final class PlanNone extends SyncPlan {
  const PlanNone();
}

/// Write [payload] to the cloud. The device is already correct.
final class PlanUpload extends SyncPlan {
  const PlanUpload(this.payload);
  final Map<String, dynamic> payload;
}

/// Make [payload] the device state, then upload it when [upload] is true.
final class PlanApply extends SyncPlan {
  const PlanApply(this.payload, {required this.upload});
  final Map<String, dynamic> payload;
  final bool upload;
}

/// Economy differs on both sides since the last sync. The player decides.
final class PlanAskUser extends SyncPlan {
  const PlanAskUser();
}

/// Decides how to reconcile [local] with the [remote] save.
///
/// [base] is the state this device last agreed with the cloud, or null when
/// there is none (first sign-in, or a different account). [remote] is null
/// when no cloud save exists.
SyncPlan planSync({
  required CloudBase? base,
  required Map<String, dynamic> local,
  required CloudEnvelope? remote,
}) {
  final localDigest = digestOf(local);
  final localDirty = base == null || localDigest != base.payloadDigest;
  if (remote == null) return PlanUpload(local);

  // Cloud unchanged since our last sync.
  if (base != null && remote.revision == base.revision) {
    return localDirty ? PlanUpload(local) : const PlanNone();
  }
  // Cloud changed elsewhere and this device has nothing unsynced.
  if (base != null && !localDirty) {
    return PlanApply(remote.payload, upload: false);
  }

  final localEconomy = economyDigest(local);
  // Both sides agree on economy, so only progress differs.
  if (localEconomy == remote.economy) {
    return PlanApply(mergeProgress(local, remote.payload), upload: true);
  }
  // Nothing to lose: first sign-in on a new device.
  if (base == null && isFreshSave(local)) {
    return PlanApply(remote.payload, upload: false);
  }
  // Only this device changed economy: keep it, take the cloud's progress.
  if (base != null && remote.economy == base.economy) {
    return PlanApply(
      combine(local, mergeProgress(local, remote.payload)),
      upload: true,
    );
  }
  // Only the cloud changed economy: take it, keep this device's progress.
  if (base != null && localEconomy == base.economy) {
    return PlanApply(
      combine(remote.payload, mergeProgress(local, remote.payload)),
      upload: true,
    );
  }
  return const PlanAskUser();
}
