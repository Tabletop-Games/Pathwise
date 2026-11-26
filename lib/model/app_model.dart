import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../logic/connectivity_service.dart';
import '../logic/game_controller.dart';
import '../logic/game_state_storage.dart';
import '../logic/haptic_service.dart';
import '../logic/mechanic_tutorials.dart';
import '../logic/puzzle.dart';
import '../logic/puzzle_generator.dart';
import '../logic/star_rating.dart';
import 'economy.dart';
import 'economy_activity.dart';
import 'fortune.dart';
import 'game_state.dart';
import 'journey.dart';
import 'native_achievements.dart';
import 'play_streak.dart';
import 'product_catalog.dart';
import 'progression.dart';
import 'time_attack.dart';
import 'user_preferences.dart';

typedef PuzzleLoader = Future<VerifiedPuzzle> Function(
  ({int size, int seed, int clues}) request,
);

class AppModel extends ChangeNotifier
    implements BoardControls, RejectionControls {
  AppModel({
    required this.storage,
    required Map<String, dynamic> snapshot,
    DateTime Function()? today,
    PuzzleLoader? loader,
    BootTime? Function()? bootTime,
    this.debugTools = false,
    this.connectivity,
    this.onPersisted,
  }) : _wallClock = today ?? DateTime.now,
       _loader = loader,
       _bootTime = bootTime ?? (() => null),
       _prefs = UserPreferences.fromJson(_map(snapshot['preferences'])) {
    _levelOneDemoSeen = snapshot['levelOneDemoSeen'] is bool
        ? snapshot['levelOneDemoSeen'] as bool
        : snapshot.isNotEmpty;
    _tutorialStatus.addAll(
      _map(snapshot['mechanicTutorials'])
          .map((key, value) => MapEntry(key, value.toString())),
    );
    _freezeSerial = snapshot['freezeSerial'] as int? ?? 0;
    streak = PlayStreak(_map(snapshot['playStreak']));
    _achievements = AchievementLedger(_map(snapshot['nativeAchievements']));
    activity = EconomyActivity(_map(snapshot['economyActivity']));
    _attempts.addAll(_map(snapshot['attempts']));
    for (final entry in _map(snapshot['results']).entries) {
      final data = _map(entry.value);
      final time = data['milliseconds'];
      final hints = data['hints'];
      if (time is int && time >= 0 && hints is int && hints >= 0) {
        _results[entry.key] = (
          milliseconds: time,
          hints: hints,
          unassisted: data['unassisted'] == true || hints == 0,
        );
        final savedStars = data['stars'];
        if (savedStars is int && savedStars >= 0 && savedStars <= 3) {
          _levelStars[entry.key] = savedStars;
        }
      }
    }
    if (!snapshot.containsKey('playStreak')) {
      final historicalDays =
          _results.keys
              .where((key) => key.startsWith('daily/'))
              .map((key) => key.substring('daily/'.length))
              .where(
                (day) =>
                    DateTime.tryParse(day) != null &&
                    day.compareTo(todayKey) <= 0,
              )
              .toList()
            ..sort();
      for (final day in historicalDays) {
        streak.qualify(day);
      }
    }
    streak.reconcile(todayKey);
    for (final entry in _map(snapshot['dailyCheckpoints']).entries) {
      final data = _map(entry.value);
      final time = data['milliseconds'];
      final hints = data['hints'];
      if (time is int && time >= 0 && hints is int && hints >= 0) {
        _dailyCheckpoints[entry.key] = (
          milliseconds: time,
          hints: hints,
          unassisted: hints == 0,
        );
      }
    }
    _classicLevels.addAll(
      (snapshot['classicLevels'] as List? ?? []).whereType<String>(),
    );
    if (!snapshot.containsKey('classicLevels')) {
      _classicLevels.addAll(
        [
          ..._results.keys,
          ..._attempts.keys,
        ].where((key) => key.startsWith('levels/')),
      );
    }
    _legacyMechanicLevels.addAll(
      (snapshot['legacyMechanicLevels'] as List? ?? []).whereType<String>(),
    );
    if (!snapshot.containsKey('legacyMechanicLevels')) {
      _legacyMechanicLevels.addAll(
        [
          ..._results.keys,
          ..._attempts.keys,
        ].where((key) => key.startsWith('levels/')),
      );
    }
    final attackMinutes = snapshot['attackMinutes'];
    if (attackMinutes == 1 || attackMinutes == 3 || attackMinutes == 5) {
      _attackMinutes = attackMinutes as int;
    }
    final fortune = _map(snapshot['fortune']);
    if (fortune['boot'] is int && fortune['at'] is int) {
      _lastFreeFortune = (
        boot: fortune['boot'] as int,
        milliseconds: fortune['at'] as int,
      );
    }
    final pending = _map(fortune['pending']);
    if (pending
        case {
          'id': final String id,
          'prize': final String prize,
          'coins': final int coins,
        }
        when id.startsWith('wheel/') && coins > 0 && coins <= 160) {
      _pendingFortune = (
        id: id,
        prize: FortunePrize(prize, '$coins coins', 0, coins),
      );
    }
    _wheelClaims.addAll(_map(fortune['claims']).cast<String, int>());
    for (final row in (fortune['videos'] as List? ?? []).whereType<Map>()) {
      final boot = row['boot'];
      final at = row['at'];
      if (boot is int && at is int && at >= 0) {
        _wheelVideos.add((boot: boot, milliseconds: at));
      }
    }
    final savedProgression = _map(snapshot['progression']);
    progression = Progression(savedProgression);
    progression.migrateCrates(
      savedProgression,
      _bootTime(),
      snapshot['progressionBoot'],
      dayKey(_today()),
    );
    if (snapshot['progressionBoot'] != _bootTime()?.boot) {
      progression.active.clear();
    }
    final savedHints = snapshot['hintBalance'];
    final legacyHints = snapshot['hintTank'];
    _hintBalance = savedHints is int
        ? max(0, savedHints)
        : snapshot.isEmpty
        ? economy.starterHints
        : (legacyHints is int ? legacyHints.clamp(0, 3) : 0);
    if (savedHints is! int && (snapshot['schemaVersion'] as int? ?? 1) >= 4) {
      _hintBalance += _map(snapshot['hintCredits']).entries
          .where((entry) => !_retiredPuzzle(entry.key) && entry.value == 1)
          .length;
    }
    _hintEvents.addAll(
      (snapshot['hintEvents'] as List? ?? []).whereType<String>(),
    );
    for (final event in _map(snapshot['hintAdDays']).entries) {
      if (event.value is String) _hintAdDays[event.key] = event.value as String;
    }
    for (final event in _map(snapshot['boostAdDays']).entries) {
      if (event.value is String)
        _boostAdDays[event.key] = event.value as String;
    }
    _hintPurchaseSerial = snapshot['hintPurchaseSerial'] as int? ?? 0;
    _attempts.removeWhere((key, _) => _retiredPuzzle(key));
    final offer = _map(snapshot['coinOffer']);
    if (offer['levels'] is int) _coinOfferLevel = offer['levels'] as int;
    if (offer['boot'] is int && offer['milliseconds'] is int) {
      _lastCoinOffer = (
        boot: offer['boot'] as int,
        milliseconds: offer['milliseconds'] as int,
      );
    }
    final journey = _map(snapshot['journey']);
    final chests = journey['chapterChests'];
    if (chests is List) {
      _chapterChests.addAll(
        chests.whereType<int>().where((chapter) => chapter >= 0),
      );
    }
    _journeyClears = max(
      0,
      journey['clears'] is int ? journey['clears'] as int : 0,
    );
    // Economy 2.0 migration: discard obsolete unclaimed discovery queues
    // ('pending'), preserve claimed mystery IDs, and keep valid upcoming items.
    final claimedMysteries = journey['claimedMysteries'];
    if (claimedMysteries is List) {
      _claimedMysteries.addAll(claimedMysteries.whereType<int>());
    }
    final upcoming = journey['upcoming'];
    if (upcoming is String && _isValidMysteryItem(upcoming)) {
      _upcomingDiscoveryItem = upcoming;
    }
    final adStamp = _map(snapshot['lastAutomaticAd']);
    if (adStamp['boot'] is int && adStamp['milliseconds'] is int) {
      _lastAutomaticAd = (
        boot: adStamp['boot'] as int,
        milliseconds: adStamp['milliseconds'] as int,
      );
    }
    if (snapshot['attack'] case final Map data)
      attack = AttackRun.fromJson(data);
    if (snapshot['attackHistory'] case final List entries) {
      attackHistory.addAll(entries.whereType<Map>().map(AttackRun.fromJson));
    }
    _wallet = Wallet(
      snapshot['ledger'] ?? (snapshot.isEmpty ? null : <Object>[]),
      _today(),
      archivedCoins:
          (snapshot['archivedCoins'] ?? snapshot['archivedTrailCoins'])
              as int? ??
          0,
    );
    if (snapshot['coinAdDays'] is Map) {
      for (final event in _map(snapshot['coinAdDays']).entries) {
        if (event.value is String)
          _coinAdDays[event.key] = event.value as String;
      }
    } else {
      for (final entry in _wallet.history.where(
        (entry) => entry.id.startsWith('ad/'),
      )) {
        _coinAdDays[entry.id.substring(3)] = dayKey(entry.date.toLocal());
      }
    }
    for (final date in [
      ..._coinAdDays.values,
      ..._hintAdDays.values,
      ..._boostAdDays.values,
    ]) {
      _markRewardDay(date);
    }
    _restoreRetiredProgress(snapshot);
    _refundCrateUpgrades();
    _owned.addAll(
      PathwiseTheme.values.where((theme) => economy.themePrice(theme) == 0),
    );
    final owned = snapshot['ownedThemes'];
    if (owned is List) {
      _owned.addAll(
        PathwiseTheme.values.where((theme) => owned.contains(theme.name)),
      );
    }
    final tips = snapshot['ownedTips'];
    if (tips is List)
      _ownedTips.addAll(tips.map(PathTip.fromId).whereType<PathTip>());
    // A durable debit is also proof of ownership if an older or damaged
    // snapshot is missing the cosmetic list; never charge the same ID twice.
    for (final tip in PathTip.values) {
      if (_wallet.contains('tip/${tip.name}')) _ownedTips.add(tip);
    }
    final savedTip = PathTip.fromId(snapshot['equippedTip']);
    if (savedTip != null && _ownedTips.contains(savedTip))
      _equippedTip = savedTip;
    _themePass = snapshot['themePass'] == true;
    _removeAds = snapshot['removeAds'] == true;
    _premium = snapshot['premium'] == true;
    if (!ownsTheme(_prefs.theme)) _prefs.theme = PathwiseTheme.field;
    final savedSecret = snapshot['billingProfile'];
    if (savedSecret is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(savedSecret)) {
      _billingProfile = savedSecret;
    }
    final savedTime = snapshot['playMilliseconds'];
    _playMilliseconds = savedTime is int && savedTime >= 0
        ? savedTime
        : _results.values.fold(0, (sum, run) => sum + run.milliseconds);
    for (final key in _results.keys) {
      if (_levelFromKey(key) case final level?) {
        _highestUnlocked = max(_highestUnlocked, level + 1);
        _levelsSolved++;
      }
    }
    _coinOfferLevel ??= _levelsSolved;
    final savedUnlocked = snapshot['highestUnlocked'];
    if (savedUnlocked is int)
      _highestUnlocked = max(_highestUnlocked, savedUnlocked);
    if (snapshot['schemaVersion'] == null || snapshot['schemaVersion'] == 1) {
      for (final key in _attempts.keys) {
        final legacy = _levelFromKey(key);
        if (legacy != null && legacy <= legacyLevelCount) {
          _highestUnlocked = max(_highestUnlocked, legacy);
        }
      }
    }
    _updateLongestStreak();
    haptic = HapticService(enabled: _prefs.haptics);
    connectivity?.addListener(_onConnectivityChanged);
  }

  /// Null in unit tests that exercise rules without a network check.
  final ConnectivityService? connectivity;

  /// Receives every snapshot written to the device save, for cloud sync.
  final void Function(Map<String, dynamic> snapshot)? onPersisted;

  /// Whether network-dependent services (ads, billing, cloud sync) have
  /// connectivity. Core gameplay and local economy operate offline-first.
  bool get onlineReady => connectivity == null || connectivity!.online;

  void _onConnectivityChanged() {
    if (_disposed) return;
    _syncClock();
    _processCrates();
    notifyListeners();
  }

  int _retiredSolved = 0, _retiredClean = 0, _retiredRanks = 0;

  static bool _retiredPuzzle(String key) =>
      key.startsWith('expedition/') || key.startsWith('endless/');

  void _restoreRetiredProgress(Map<String, dynamic> snapshot) {
    _retiredSolved = snapshot['priorSolves'] as int? ?? 0;
    _retiredClean = snapshot['priorCleanSolves'] as int? ?? 0;
    _retiredRanks = snapshot['priorRanks'] as int? ?? 0;
    final progress = _map(snapshot['expeditionProgress']);
    if (progress.isNotEmpty) {
      int count(int mask) =>
          List.generate(10, (bit) => (mask >> bit) & 1).reduce((a, b) => a + b);
      _retiredSolved +=
          max(0, (progress['next'] as int? ?? 1) - 1) * 10 +
          count(progress['stages'] as int? ?? 0);
      _retiredClean +=
          (progress['qualifiedClean'] as int? ?? 0) +
          count(progress['clean'] as int? ?? 0);
    }
    _results.removeWhere((key, result) {
      if (!key.startsWith('expedition/')) return false;
      if (progress.isEmpty) {
        _retiredSolved++;
        if (result.unassisted) _retiredClean++;
      }
      return true;
    });
    _retiredRanks +=
        (progression.ranks.remove('trailYield') ?? 0) +
        (progression.ranks.remove('fieldwork') ?? 0);
    final unused = progression.inventory.remove('trailProvisions') ?? 0;
    final wasActive =
        (progression.active.remove('trailProvisions') ?? 0) > progressionTime;
    final history = _wallet.history.toList();
    final refund = history
        .where(
          (tx) =>
              tx.id.startsWith('research/trailYield/') ||
              tx.id.startsWith('research/fieldwork/'),
        )
        .fold(0, (total, tx) => total - tx.amount);
    final supplyRefund = history.reversed
        .where(
          (tx) =>
              tx.id.startsWith('boost/') &&
              tx.label == '50% more first-qualification base coins',
        )
        .take(unused + (wasActive ? 1 : 0))
        .fold(0, (total, tx) => total - tx.amount);
    _wallet.add(
      'migration/retired-upgrades',
      'Retired upgrades refund',
      refund + supplyRefund,
      _today(),
    );
  }

  void _refundCrateUpgrades() {
    final history = _wallet.history.toList();
    var refund = 0;
    final retiredPurchases = <String>{};
    for (final key in [
      'lucky',
      'rare',
      'legendaryCache',
      'expedition',
      'salvage',
      'discovery',
    ]) {
      final rank = progression.ranks.remove(key);
      if (rank == null) continue;
      _retiredRanks += rank;
      retiredPurchases.add(key);
      if (key == 'legendaryCache') retiredPurchases.add('expedition');
    }
    refund += history
        .where(
          (tx) =>
              tx.id.startsWith('research/') &&
              retiredPurchases.contains(tx.id.split('/')[1]) &&
              tx.amount < 0,
        )
        .fold(0, (sum, tx) => sum - tx.amount);
    for (final (key, label) in [
      ('crateValue', 'Double crate coins'),
      ('crateRarity', 'More rare crates'),
    ]) {
      final available =
          (progression.inventory.remove(key) ?? 0) +
          ((progression.active.remove(key) ?? 0) > progressionTime ? 1 : 0);
      refund += history.reversed
          .where(
            (tx) =>
                tx.id.startsWith('boost/') &&
                tx.label == label &&
                tx.amount < 0,
          )
          .take(available)
          .fold(0, (sum, tx) => sum - tx.amount);
    }
    _wallet.add(
      'migration/flying-crates',
      'Retired crate upgrades refund',
      refund,
      _today(),
    );
  }

  static Future<VerifiedPuzzle> _generate(
    ({int size, int seed, int clues}) request,
    int level,
    bool legacy,
  ) => compute(
    (request) =>
        generatePuzzle(request.$1, level: request.$2, legacy: request.$3),
    (request, level, legacy),
  );

  final BootTime? Function() _bootTime;
  BootTime? _lastAutomaticAd;
  BootTime? _lastCoinOffer;
  int? _coinOfferLevel;

  bool get canOfferCoinVideo {
    final now = _bootTime();
    final baseline = _coinOfferLevel;
    if (now == null ||
        baseline == null ||
        adFree ||
        storageError ||
        !_foreground ||
        !onlineReady ||
        activeId != null ||
        attack?.finished == false ||
        !canEarnAdBonus ||
        _levelsSolved - baseline < 5)
      return false;
    final last = _lastCoinOffer;
    if (last != null) {
      final elapsed = last.boot == now.boot
          ? now.milliseconds - last.milliseconds
          : now.milliseconds;
      if (elapsed < const Duration(minutes: 15).inMilliseconds) return false;
    }
    final ad = _lastAutomaticAd;
    if (ad != null) {
      final elapsed = ad.boot == now.boot
          ? now.milliseconds - ad.milliseconds
          : now.milliseconds;
      if (elapsed < EconomyRules.automaticAdGap.inMilliseconds) return false;
    }
    return true;
  }

  Future<bool> recordCoinOffer() async {
    if (!canOfferCoinVideo) return false;
    _lastCoinOffer = _bootTime();
    _coinOfferLevel = _levelsSolved;
    return flush();
  }

  Future<bool> reserveAutomaticAd() async {
    if (adFree || storageError || !_foreground) return false;
    final now = _bootTime();
    if (now == null) return false;
    final last = _lastAutomaticAd;
    if (last != null) {
      final elapsed = last.boot == now.boot
          ? now.milliseconds - last.milliseconds
          : now.milliseconds;
      if (elapsed < EconomyRules.automaticAdGap.inMilliseconds) return false;
    }
    _lastAutomaticAd = now;
    return flush();
  }

  void recordRewardedAdExit() {
    // Interstitial cooldown after rewarded ads is handled by AdFrequency.
    // Do not overwrite _lastAutomaticAd with the 3-minute automaticAdGap.
  }

  final _hintAdDays = <String, String>{};
  final _hintEvents = <String>{};
  AttackRun? attack;
  final attackHistory = <AttackRun>[];
  final attackRemaining = ValueNotifier(AttackRun.duration);
  Timer? _attackTicker;
  bool get attackClockReady => _bootTime() != null;
  int get attackBest =>
      attackHistory.fold(0, (best, run) => max(best, run.score));
  int get attackHighest =>
      attackHistory.fold(0, (best, run) => max(best, run.clears.length));

  bool _openingAttack = false;
  int _attackMinutes = 3;
  int get attackMinutes => _attackMinutes;

  void selectAttackMinutes(int minutes) {
    if (![1, 3, 5].contains(minutes) || minutes == _attackMinutes) return;
    _attackMinutes = minutes;
    notifyListeners();
    unawaited(flush());
  }

  int attackBestFor(int minutes) => attackHistory
      .where((run) => run.minutes == minutes)
      .fold(0, (best, run) => max(best, run.score));

  void stopAttack() {
    final run = attack;
    if (run == null || run.finished) return;
    if (activeId?.mode == PlayMode.attack) close();
    attack = null;
    _attackTicker?.cancel();
    _attackTicker = null;
    final prefix = 'attack/${run.id}/';
    _attempts.removeWhere((key, _) => key.startsWith(prefix));
    attackRemaining.value = Duration.zero;
    unawaited(flush());
    notifyListeners();
  }

  Future<bool> restartAttack() async {
    stopAttack();
    return openAttack();
  }

  Future<bool> openAttack() async {
    if (_openingAttack || _disposed) return false;
    _openingAttack = true;
    try {
      return await _openAttack();
    } finally {
      _openingAttack = false;
    }
  }

  Future<bool> _openAttack() async {
    final now = _bootTime();
    if (now == null || storageError) return false;
    refreshAttackClock();
    if (attack == null || attack!.finished) {
      final next = AttackRun(
        'v2-${now.boot}-${now.milliseconds}-${Random.secure().nextInt(1 << 32)}',
        now.boot,
        now.milliseconds + Duration(minutes: _attackMinutes).inMilliseconds,
        now.milliseconds,
        attackBestFor(_attackMinutes),
        minutes: _attackMinutes,
      );
      attack = next;
      if (!await flush()) {
        if (identical(attack, next)) attack = null;
        return false;
      }
    }
    if (_disposed) return false;
    final run = attack!;
    refreshAttackClock();
    await open(PuzzleId.attack('${run.id}/${run.clears.length}'));
    return true;
  }

  void refreshAttackClock() {
    final run = attack;
    final now = _bootTime();
    if (run == null || now == null || run.finished) return;
    final remaining = run.remaining(now);
    attackRemaining.value = Duration(milliseconds: remaining);
    if (remaining == 0) {
      final previous = achievementCounters;
      run.finished = true;
      _attackTicker?.cancel();
      _attackTicker = null;
      if (_wallet.add(
        'attack/${run.id}',
        'Time Attack reward',
        run.reward,
        _today(),
      )) {
        run.coins = run.reward;
      }
      attackHistory.add(run);
      if (run.clears.length >= 2) _qualifyStreak();
      _celebrateAchievements(previous);
      final beforeAchievements = coinBalance;
      _awardAchievements();
      run.coins += coinBalance - beforeAchievements;
      if (activeId?.mode == PlayMode.attack) {
        final key = activeId!.key;
        _attempts.remove(key);
        _game?.end();
        _syncClock();
      }
      unawaited(flush());
      notifyListeners();
    } else {
      _attackTicker ??= Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => refreshAttackClock(),
      );
    }
  }

  late final Progression progression;
  int get progressionTime =>
      _bootTime()?.milliseconds ?? _today().millisecondsSinceEpoch;
  Timer? _crateTimer;
  BootTime? _crateAnchor;
  int _unsavedCrateTime = 0;
  Crate? _fallingCrate;
  bool _crateRevealed = false;
  Crate? get fallingCrate => _fallingCrate;
  int get hintsRemaining => _hintBalance;

  bool research(Research item) {
    final rank = progression.rank(item);
    if (storageError ||
        rank >= item.limit ||
        !progression.unlocked(item) ||
        !_wallet.add(
          'research/${item.name}/$rank',
          item.title,
          -item.price(rank),
          _today(),
        ))
      return false;
    progression.ranks[item.name] = rank + 1;
    achievementRevision++;
    activity.event(EconomyEvent.researchBought, coinBalance);
    _awardAchievements();
    _progressionChanged();
    return true;
  }

  final _boostAdDays = <String, String>{};

  int boostAdsToday(Boost item) => _boostAdDays.entries
      .where(
        (entry) =>
            entry.key.startsWith('${item.name}/') && entry.value == todayKey,
      )
      .length;

  bool canEarnBoostAd(Boost item) =>
      !_disposed &&
      !storageError &&
      _rewardDayAvailable &&
      (item == Boost.doubleTen &&
              boostAdsToday(item) < economy.doubleBoostAdsPerDay ||
          item == Boost.tripleFifteen &&
              adsToday >= economy.coinAdMilestone &&
              boostAdsToday(item) == 0);

  Future<bool> grantBoostAd(Boost item, String event) async {
    if (!onlineReady) return false;
    if (!canEarnBoostAd(item) || !_hintEvents.add(event)) return false;
    _boostAdDays['${item.name}/$event'] = todayKey;
    _markRewardDay(todayKey);
    progression.inventory.update(
      item.name,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    notifyListeners();
    return flush();
  }

  bool buyBoost(Boost item) {
    if (storageError ||
        !item.availableToBuy ||
        !_wallet.add(
          'boost/${progression.serial}',
          item.title,
          -progression.discount(item.price),
          _today(),
        ))
      return false;
    progression.serial++;
    activity.event(EconomyEvent.boostBought, coinBalance);
    progression.inventory.update(
      item.name,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _progressionChanged();
    return true;
  }

  bool activateBoost(Boost item) {
    final now = progressionTime;
    if (storageError || !progression.canActivate(item, now)) return false;
    progression.activate(item, now);
    _progressionChanged();
    return true;
  }

  void setDebugResources({int? coins, int? hints}) {
    if (!developerMode || storageError) return;
    if (coins != null && coins >= 0) {
      _wallet.add(
        'debug/${progression.serial++}',
        'Developer adjustment',
        coins - coinBalance,
        _today(),
      );
    }
    if (hints != null && hints >= 0) _hintBalance = hints;
    _progressionChanged();
  }

  void forceCrateForDebug() {
    if (!kDebugMode ||
        !_inPlay ||
        _game == null ||
        complete ||
        activeId?.mode == PlayMode.attack ||
        _fallingCrate != null) {
      return;
    }
    _fallingCrate = (id: 'crate/debug/${progression.serial++}', coins: 25);
    notifyListeners();
  }

  bool revealCrate(Crate crate) {
    if (_fallingCrate != crate ||
        _crateRevealed ||
        isDrawing ||
        !_foreground ||
        storageError)
      return false;
    _crateRevealed = true;
    return true;
  }

  void dismissCrate(Crate crate) {
    if (_fallingCrate != crate) return;
    _fallingCrate = null;
    _crateRevealed = false;
    if (!_disposed) {
      _processCrates();
      notifyListeners();
    }
  }

  Future<bool> claimVerifiedCrate(Crate crate, String receipt) async {
    if (!onlineReady) return false;
    if (_disposed ||
        !_crateRevealed ||
        _fallingCrate != crate ||
        storageError ||
        receipt.isEmpty ||
        !_wallet.add(
          'crate-ad/$receipt',
          'Supply crate',
          crate.coins,
          _today(),
        )) {
      return false;
    }
    _fallingCrate = null;
    _crateRevealed = false;
    activity.event(EconomyEvent.crateCollected, coinBalance);
    if (crate.coins == crateTopPrize) {
      progression.legendary++;
      achievementRevision++;
    }
    _awardAchievements();
    _processCrates();
    final saved = await flush();
    if (!_disposed) {
      if (saved) haptic.complete();
      notifyListeners();
    }
    return saved;
  }

  void _progressionChanged() {
    haptic.selection();
    unawaited(flush());
    notifyListeners();
  }

  void _processCrates({bool ending = false}) {
    final now = _bootTime();
    final previous = _crateAnchor;
    final eligible =
        now != null &&
        onlineReady &&
        _foreground &&
        _inPlay &&
        _started &&
        _game != null &&
        activeId?.mode != PlayMode.attack &&
        !complete &&
        !storageError &&
        !ending &&
        !_crateRevealed;
    _crateAnchor = eligible ? now : null;
    if (eligible) {
      _crateTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _processCrates(),
      );
    } else {
      _crateTimer?.cancel();
      _crateTimer = null;
    }
    if (previous != null && now != null && previous.boot == now.boot) {
      final before = progression.crateWait;
      progression.accrueCrateTime(now.milliseconds - previous.milliseconds);
      _unsavedCrateTime += before - progression.crateWait;
    }
    if (ending) {
      _fallingCrate = null;
      _crateRevealed = false;
    }
    final crate = eligible && _fallingCrate == null && !isDrawing
        ? progression.considerCrate(now, () => Random.secure().nextInt(100))
        : null;
    if (crate != null) {
      _fallingCrate = crate;
      haptic.selection();
      unawaited(flush());
      notifyListeners();
    } else if (_unsavedCrateTime >= 10000 &&
        !isDrawing &&
        !complete &&
        !ending) {
      unawaited(flush());
    }
  }

  late int _hintBalance;
  int _hintPurchaseSerial = 0;
  int get hintAdsToday =>
      _hintAdDays.values.where((day) => day == dayKey(_today())).length;
  bool get canEarnHintAd =>
      !_disposed &&
      !storageError &&
      _rewardDayAvailable &&
      hintAdsToday < economy.hintAdsPerDay;

  Future<bool> buyHint() async {
    if (_disposed ||
        storageError ||
        !_wallet.add(
          'hint/purchase/$_hintPurchaseSerial',
          'Hint',
          -economy.hintPrice,
          _today(),
        ))
      return false;
    _hintPurchaseSerial++;
    _hintBalance++;
    notifyListeners();
    return flush();
  }

  Future<bool> grantHintAd(String event) async {
    if (!onlineReady) return false;
    if (!canEarnHintAd || !_hintEvents.add(event)) return false;
    _hintAdDays[event] = todayKey;
    _markRewardDay(todayKey);
    _hintBalance++;
    notifyListeners();
    return flush();
  }

  final Map<String, String> _tutorialStatus = {};
  final List<MechanicTutorial> _pendingTutorials = [];
  List<MechanicTutorial> get pendingMechanicTutorials =>
      List.unmodifiable(_pendingTutorials);
  Set<String> get acknowledgedMechanics => _tutorialStatus.keys.toSet();

  Future<bool> acknowledgeMechanic(
    MechanicTutorial mechanic, {
    required bool skipped,
  }) async {
    if (!_pendingTutorials.contains(mechanic)) return false;
    final previous = _tutorialStatus[mechanic.id];
    _tutorialStatus[mechanic.id] = skipped ? 'skipped' : 'completed';
    if (!await flush()) {
      if (previous == null) {
        _tutorialStatus.remove(mechanic.id);
      } else {
        _tutorialStatus[mechanic.id] = previous;
      }
      return false;
    }
    _pendingTutorials.remove(mechanic);
    _syncClock();
    notifyListeners();
    return true;
  }

  bool get _canPlay => _gameplayAllowed;

  bool get _gameplayAllowed {
    if (_pendingTutorials.isNotEmpty) return false;
    if (activeId?.mode != PlayMode.attack) return true;
    final now = _bootTime();
    return now != null && (attack?.remaining(now) ?? 0) > 0;
  }

  final bool debugTools;
  bool get developerMode => kDebugMode && debugTools;
  final GameStateStorage storage;
  final DateTime Function() _wallClock;
  int _debugDays = 0;
  DateTime _today() {
    final now = _wallClock();
    if (!developerMode || _debugDays == 0) return now;
    return DateTime(
      now.year,
      now.month,
      now.day + _debugDays,
      now.hour,
      now.minute,
    );
  }

  void advanceDebugDay({bool qualify = false}) {
    if (!developerMode || storageError) return;
    _debugDays++;
    if (qualify) _qualifyStreak();
    streak.reconcile(todayKey);
    _progressionChanged();
  }

  void grantDebugProgression() {
    if (!developerMode || storageError) return;
    for (final item in Research.values) {
      progression.ranks[item.name] = item.limit;
    }
    for (final boost in Boost.values) {
      progression.inventory[boost.name] =
          (progression.inventory[boost.name] ?? 0) + 1;
    }
    streak.freezes = economy.maxFreezes;
    _progressionChanged();
  }

  final PuzzleLoader? _loader;
  final _classicLevels = <String>{};
  final _legacyMechanicLevels = <String>{};
  final UserPreferences _prefs;
  late final Wallet _wallet;
  final _owned = <PathwiseTheme>{};
  final _ownedTips = <PathTip>{PathTip.classic};
  PathTip _equippedTip = PathTip.classic;
  bool _tipMutation = false;
  PathTip get equippedTip => _equippedTip;
  bool ownsTip(PathTip tip) => _ownedTips.contains(tip);

  /// Coin debit and ownership are persisted together in the same snapshot.
  Future<bool> buyTip(PathTip tip) async {
    if (_tipMutation ||
        _disposed ||
        storageError ||
        ownsTip(tip) ||
        tip.price <= 0)
      return false;
    _tipMutation = true;
    try {
      if (!_wallet.add(
        'tip/${tip.name}',
        'Unlocked ${tip.label}',
        -tip.price,
        _today(),
      ))
        return false;
      _ownedTips.add(tip);
      notifyListeners();
      return await flush();
    } finally {
      _tipMutation = false;
    }
  }

  Future<bool> equipTip(PathTip tip) async {
    if (_tipMutation || _disposed || storageError || !ownsTip(tip))
      return false;
    _tipMutation = true;
    try {
      _equippedTip = tip;
      notifyListeners();
      return await flush();
    } finally {
      _tipMutation = false;
    }
  }

  bool _themePass = false;
  bool _removeAds = false;
  bool _premium = false;
  bool get adFree => _removeAds || _premium;
  bool get premium => _premium;
  String? _billingProfile;
  int _highestUnlocked = 1;
  int _levelsSolved = 0;
  int _longestStreak = 0;
  int _playMilliseconds = 0;
  int _accountedMilliseconds = 0;
  final _chapterChests = <int>{};

  List<int> get pendingChapterChests => _chapterChests.toList()..sort();

  int chapterClears(int chapter) {
    var cleared = 0;
    for (
      var level = chapter * chapterSize + 1;
      level <= chapterEnd(chapter);
      level++
    ) {
      if (_results.containsKey('levels/$level')) cleared++;
    }
    return cleared;
  }

  bool chapterClaimed(int chapter) =>
      _wallet.contains('journey/chapter/$chapter');

  bool chapterReady(int chapter) =>
      _chapterChests.contains(chapter) && !chapterClaimed(chapter);

  Future<bool> claimChapter(int chapter) async {
    if (_disposed || storageError || !chapterReady(chapter)) return false;
    if (!_wallet.add(
      'journey/chapter/$chapter',
      'Chapter treasure',
      chapterRewardCoins,
      _today(),
    ))
      return false;
    _chapterChests.remove(chapter);
    _hintBalance += chapterRewardHints;
    notifyListeners();
    return flush();
  }

  int _journeyClears = 0;
  final _claimedMysteries = <int>{};
  String? _upcomingDiscoveryItem;
  Discovery? latestDiscovery;
  bool latestDiscoveryClaimed = false;
  int? discoveryStartPercent;
  bool chapterCompletedThisVisit = false;
  bool firstCampaignClear = false;
  int completionCoins = 0;
  int attemptStars = 0;
  int previousAttemptBestStars = 0;
  int earnedStarCoins = 0;
  int? selectedMultiplier;

  int get completionBonusCoins => firstCampaignClear
      ? _wallet.amountOf('journey/multiplier/${activeId?.level}')
      : 0;

  int get discoveryPercent =>
      _journeyClears % discoveryInterval * 100 ~/ discoveryInterval;
  int get _currentMysteryCycle => (_journeyClears ~/ discoveryInterval) + 1;

  bool _isValidMysteryItem(String item) {
    if (item == Discovery.fallback || item.startsWith('coins/')) return true;
    if (item.startsWith('boost/')) {
      return Boost.values.any((b) => 'boost/${b.name}' == item);
    }
    if (item.startsWith('tip/')) {
      return PathTip.values.any((t) => 'tip/${t.name}' == item && t.price > 0);
    }
    if (item.startsWith('theme/')) {
      return PathwiseTheme.values.any(
        (th) => 'theme/${th.name}' == item && economy.themePrice(th) > 0,
      );
    }
    return false;
  }

  String _nextEligibleDiscoveryItem({required int cycle}) {
    final chosen = selectMysteryReward(
      cycle: cycle,
      ownedTips: _ownedTips,
      ownedThemes: _owned,
      hasThemePass: hasThemePass,
    );
    return chosen.item;
  }

  /// The persisted mystery reward for the current 10-puzzle cycle.
  /// Reconciles deterministically if a selected cosmetic was unlocked early.
  String get upcomingDiscoveryItem {
    final current = _upcomingDiscoveryItem;
    if (current != null &&
        _isValidMysteryItem(current) &&
        !_ownsDiscoveryItem(current)) {
      return current;
    }
    final next = _nextEligibleDiscoveryItem(cycle: _currentMysteryCycle);
    _upcomingDiscoveryItem = next;
    return next;
  }

  bool _ownsDiscoveryItem(String item) {
    if (item.startsWith('tip/')) {
      return PathTip.values.any(
        (tip) => 'tip/${tip.name}' == item && ownsTip(tip),
      );
    }
    if (item.startsWith('theme/')) {
      return PathwiseTheme.values.any(
        (theme) => 'theme/${theme.name}' == item && ownsTheme(theme),
      );
    }
    return false;
  }

  Discovery displayedDiscovery(Discovery discovery) =>
      _ownsDiscoveryItem(discovery.item)
      ? selectMysteryReward(
          cycle: discovery.number,
          ownedTips: _ownedTips,
          ownedThemes: _owned,
          hasThemePass: hasThemePass,
          salt: 97,
        )
      : discovery;

  void _advanceJourney(int level) {
    firstCampaignClear = true;
    discoveryStartPercent = discoveryPercent;
    final chapter = chapterFor(level);
    chapterCompletedThisVisit = chapterClears(chapter) == chapterSize;
    if (chapterCompletedThisVisit && !chapterClaimed(chapter)) {
      _chapterChests.add(chapter);
    }
    final selectedItem = upcomingDiscoveryItem;
    _journeyClears++;
    if (_journeyClears % discoveryInterval != 0) return;
    final cycle = _journeyClears ~/ discoveryInterval;
    final item =
        _isValidMysteryItem(selectedItem) && !_ownsDiscoveryItem(selectedItem)
        ? selectedItem
        : _nextEligibleDiscoveryItem(cycle: cycle);
    latestDiscovery = Discovery(cycle, item);
    latestDiscoveryClaimed = false;
    _upcomingDiscoveryItem = _nextEligibleDiscoveryItem(
      cycle: _currentMysteryCycle,
    );
  }

  bool get canMultiplyCompletion =>
      firstCampaignClear &&
      activeId?.mode == PlayMode.levels &&
      !storageError &&
      !_wallet.contains('journey/multiplier/${activeId?.level}');

  void selectCompletionMultiplier(int multiplier) {
    if (!canMultiplyCompletion ||
        selectedMultiplier != null ||
        multiplier < 2 ||
        multiplier > 4)
      return;
    selectedMultiplier = multiplier;
    notifyListeners();
  }

  /// Captures the eligible completion before the ad opens. The SDK can finish
  /// after the player leaves the results screen.
  Future<bool> Function(String)? completionRewardCallback() {
    final id = activeId;
    final multiplier = selectedMultiplier;
    if (!canMultiplyCompletion || id == null || multiplier == null) return null;
    final level = id.level;
    return (_) async {
      if (_disposed ||
          !_wallet.add(
            'journey/multiplier/$level',
            'Level $level video bonus',
            economy.completionBonusCoins(multiplier, stars: attemptStars),
            _today(),
          ))
        return false;
      notifyListeners();
      return flush();
    };
  }

  /// Captures the current completed mystery reward before launching a rewarded
  /// ad so a legitimate SDK reward callback is never lost on interruption.
  Future<bool> Function(String)? mysteryRewardCallback() {
    final offer = latestDiscovery;
    if (offer == null || latestDiscoveryClaimed || storageError) return null;
    return (event) => claimMysteryReward(offer, eventId: event);
  }

  Future<bool> claimMysteryReward(Discovery offer, {String? eventId}) async {
    if (_disposed || storageError) return false;
    if (_claimedMysteries.contains(offer.number)) return false;
    final resolved = displayedDiscovery(offer);
    if (resolved.isCoins) {
      final txId = 'journey/mystery/${resolved.number}';
      if (!_wallet.add(txId, 'Mystery reward', resolved.coinAmount, _today())) {
        return false;
      }
    } else if (resolved.boost case final boost?) {
      progression.inventory.update(
        boost.name,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    } else if (resolved.tip case final tip?) {
      _ownedTips.add(tip);
    } else if (resolved.theme case final theme?) {
      _owned.add(theme);
      _awardAchievements();
    } else {
      return false;
    }
    _claimedMysteries.add(offer.number);
    if (eventId != null) _hintEvents.add(eventId);
    if (latestDiscovery?.number == offer.number) {
      latestDiscovery = resolved;
      latestDiscoveryClaimed = true;
    }
    notifyListeners();
    return flush();
  }

  void skipLatestDiscovery() {
    if (latestDiscovery == null || latestDiscoveryClaimed) return;
    latestDiscovery = null;
    latestDiscoveryClaimed = false;
    notifyListeners();
  }

  int lastReward = 0;
  List<NativeAchievement> recentAchievements = const [];
  int achievementRevision = 0;
  bool newBest = false;
  bool completedThisVisit = false;
  bool correctedByHint = false;
  late final HapticService haptic;
  final _attempts = <String, dynamic>{};
  final _results = <String, RunResult>{};
  final _levelStars = <String, int>{};
  final elapsed = ValueNotifier(Duration.zero);
  final _watch = Stopwatch();
  Timer? _tick;
  Timer? _saveTimer;
  Future<bool> _pendingWrite = Future.value(true);
  var _baseTime = Duration.zero;
  var _request = 0;
  var _foreground = true;
  var _disposed = false;
  var _inPlay = false;
  var _started = false;
  var _usedClear = false;
  late final AchievementLedger _achievements;
  GameController? _game;
  PuzzleId? activeId;
  bool loading = false;
  String? loadError;
  bool storageError = false;

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : {};

  final _dailyCheckpoints = <String, RunResult>{};

  PuzzleId get daily => PuzzleId.daily(dayKey(_today()));

  PuzzleId dailyCurrent(String day) {
    final last = PuzzleId.daily(day);
    if (result(last) != null || hasAttempt(last)) return last;
    for (var index = 1; index < dailyCheckpointCount; index++) {
      final id = PuzzleId.dailyCheckpoint(day, index);
      if (!_dailyCheckpoints.containsKey(id.key)) return id;
    }
    return last;
  }

  RunResult? dailyCheckpointResult(PuzzleId id) => _dailyCheckpoints[id.key];

  List<RunResult> _completedDailyCheckpoints(String day) => [
    for (var index = 1; index < dailyCheckpointCount; index++)
      if (_dailyCheckpoints[PuzzleId.dailyCheckpoint(day, index).key]
          case final result?)
        result,
  ];
  PathwiseTheme get theme => _prefs.theme;
  bool get haptics => _prefs.haptics;
  bool get suggestSharing => _prefs.suggestSharing;

  Map<AchievementMetric, int> get achievementCounters => {
    AchievementMetric.solves: solved,
    AchievementMetric.hintFree: unassisted,
    AchievementMetric.precision: _achievements.precision,
    AchievementMetric.daily: _achievements.eligibleDailies,
    AchievementMetric.attackFinished: attackHighest > 0 ? 1 : 0,
    AchievementMetric.attackScore: attackBest,
    AchievementMetric.research: Research.values.fold(
      _retiredRanks,
      (sum, item) => sum + progression.rank(item),
    ),
    AchievementMetric.themes: _owned
        .where((theme) => economy.themePrice(theme) > 0)
        .length,
    AchievementMetric.crates: progression.legendary,
  };

  bool get achievementProgressNeedsOwner => _achievements.owner == null;

  bool achievementsBelongToOtherAccount(String account) =>
      _achievements.owner != null && _achievements.owner != account;

  Future<bool> bindAchievementProgress(String account) async {
    if (_disposed ||
        storageError ||
        achievementsBelongToOtherAccount(account)) {
      return false;
    }
    _achievements.owner = account;
    return flush();
  }

  Future<bool> confirmAchievements(String account, Map<String, int> progress) {
    if (_disposed || storageError) return Future.value(false);
    if (mapEquals(_achievements.confirmed[account], progress)) {
      return Future.value(true);
    }
    _achievements.confirm(account, progress);
    return flush();
  }

  bool earnedTheme(PathwiseTheme theme) => _owned.contains(theme);

  Puzzle? get puzzle => _game?.puzzle;
  List<int> get path => _game?.path ?? const [];
  int? get tip => _game?.tip;
  int? get hintCell => _game?.hintCell;
  int get hintsUsed => _game?.hintsUsed ?? 0;
  int get nextCheckpoint => _game?.nextCheckpoint ?? 1;
  bool get endedEarly => puzzle != null && !complete && tip == puzzle!.finish;
  bool get complete => _game?.complete ?? false;
  bool get isDrawing => _game?.isDrawing ?? false;
  bool get canUndo => _game?.canUndo ?? false;
  bool get canClear => !complete && (path.length > 1 || hintCell != null);
  bool get canHint => _canPlay && (_game?.canHint ?? false) && _hintBalance > 0;
  bool hasAttempt(PuzzleId id) => _attempts.containsKey(id.key);
  @visibleForTesting
  void addElapsedForTest(Duration delta) {
    _baseTime += delta;
    elapsed.value += delta;
  }

  RunResult? result(PuzzleId id) => _results[id.key];

  /// Highest earned star rating (0–3) for a completed campaign level, or null
  /// if not yet completed. Lazily migrates historical solve times without
  /// granting retroactive coins.
  int? starsFor(PuzzleId id) {
    if (id.mode != PlayMode.levels) return null;
    final run = _results[id.key];
    if (run == null) return null;
    final stored = _levelStars[id.key];
    if (stored != null) return stored;
    if (run.milliseconds <= 0) return 0;
    final derived = starThresholdsForLevel(id.level).rate(run.milliseconds);
    _levelStars[id.key] = derived;
    return derived;
  }

  StarThresholds? get activeStarThresholds =>
      _game != null && activeId?.mode == PlayMode.levels
      ? starThresholdsForBoard(_game!.board)
      : null;
  int get solved => _results.length + _retiredSolved;
  int get unassisted =>
      _results.values.where((value) => value.unassisted).length + _retiredClean;
  int get levelsSolved => _levelsSolved;
  int get highestUnlocked => _highestUnlocked;
  bool canPlayLevel(int level) =>
      level > 0 && (developerMode || level <= highestUnlocked);
  int get coinBalance => _wallet.balance;
  int get coinsEarned => _wallet.earned;
  int get coinsSpent => _wallet.spent;
  List<CoinTransaction> get transactions =>
      _wallet.history.toList().reversed.map((tx) {
        if (tx.id.startsWith('trail/') ||
            tx.id.startsWith('notes/') ||
            tx.id == 'achievement/cleanTrail' ||
            tx.id == 'achievement/expeditionClear') {
          return CoinTransaction(
            tx.id,
            'Previous mode reward',
            tx.amount,
            tx.date,
          );
        }
        return tx;
      }).toList();
  bool ownsTheme(PathwiseTheme theme) =>
      developerMode || hasThemePass || _owned.contains(theme);
  int get ownedThemes =>
      hasThemePass ? PathwiseTheme.values.length : _owned.length;
  bool get hasThemePass => _themePass || _premium;
  bool hasAchievement(Achievement achievement) =>
      _wallet.contains('achievement/${achievement.name}');
  int get longestStreak => _longestStreak;
  Duration get playTime => Duration(
    milliseconds:
        _playMilliseconds +
        max(0, _watch.elapsedMilliseconds - _accountedMilliseconds),
  );

  static int? _levelFromKey(String id) =>
      id.startsWith('levels/') ? int.tryParse(id.substring(7)) : null;

  bool unlockTheme(PathwiseTheme theme) {
    if (ownsTheme(theme) || storageError) return false;
    if (!_wallet.add(
      'theme/${theme.name}',
      'Unlocked ${theme.label}',
      -economy.themePrice(theme),
      _today(),
    ))
      return false;
    _owned.add(theme);
    achievementRevision++;
    activity.event(EconomyEvent.themeBought, coinBalance);
    _prefs.theme = theme;
    _awardAchievements();
    unawaited(flush());
    notifyListeners();
    return true;
  }

  late final EconomyActivity activity;
  void recordActivity(EconomyEvent event, [int count = 1]) {
    activity.event(event, coinBalance, count);
    unawaited(flush());
  }

  BootTime? _lastFreeFortune;
  final _wheelClaims = <String, int>{};
  int get fortuneWait => freeFortuneWait(_lastFreeFortune, _bootTime());
  final _wheelVideos = <BootTime>[];

  ({String id, FortunePrize prize})? _pendingFortune;
  FortunePrize? get pendingFortune => _pendingFortune?.prize;

  Future<bool> settleFortune(FortunePrize prize) async {
    final pending = _pendingFortune;
    if (_disposed || pending == null || !identical(pending.prize, prize))
      return false;
    if (_wallet.add(
      pending.id,
      'Fortune Wheel · ${prize.label}',
      prize.coins,
      _today(),
    )) {
      activity.prize(prize.label, 1);
      activity.event(
        pending.id.startsWith('wheel/free/')
            ? EconomyEvent.wheelFree
            : EconomyEvent.wheelVerified,
        coinBalance,
      );
    }
    _pendingFortune = null;
    final saved = await flush();
    if (!_disposed) notifyListeners();
    return saved;
  }

  bool _activeWheelVideo(BootTime stamp, BootTime now) =>
      freeFortuneWait(stamp, now) > 0;

  int get fortuneVideosRemaining {
    final now = _bootTime();
    if (_disposed || storageError || now == null) return 0;
    return max(
      0,
      economy.wheelAdsPerDay -
          _wheelVideos.where((stamp) => _activeWheelVideo(stamp, now)).length,
    );
  }

  Future<FortunePrize?> spinRewardedFortune(
    FortuneCatalog catalog,
    String event, {
    Random? random,
  }) async {
    if (!onlineReady) return null;
    final now = _bootTime();
    final id = 'wheel/video/$event';
    if (_pendingFortune != null ||
        now == null ||
        fortuneVideosRemaining == 0 ||
        _wallet.contains(id) ||
        !_hintEvents.add(id)) {
      return null;
    }
    final prize = catalog.pick((random ?? Random.secure()).nextInt(100));
    _pendingFortune = (id: id, prize: prize);
    _wheelVideos.removeWhere((stamp) => !_activeWheelVideo(stamp, now));
    _wheelVideos.add(now);
    final saved = await flush();
    if (!_disposed) notifyListeners();
    return saved ? prize : null;
  }

  Future<FortunePrize?> spinFreeFortune(
    FortuneCatalog catalog, {
    Random? random,
  }) async {
    final clock = _bootTime();
    if (_disposed ||
        storageError ||
        _pendingFortune != null ||
        clock == null ||
        freeFortuneWait(_lastFreeFortune, clock) != 0) {
      return null;
    }
    final prize = catalog.pick((random ?? Random.secure()).nextInt(100));
    _lastFreeFortune = clock;
    _pendingFortune = (
      id: 'wheel/free/${clock.boot}/${clock.milliseconds}',
      prize: prize,
    );
    final saved = await flush();
    if (!_disposed) notifyListeners();
    return saved ? prize : null;
  }

  Future<bool> applyVerifiedFortune(
    FortuneCatalog catalog,
    FortuneStatus status,
  ) async {
    // Legacy receipts can arrive after an upgrade. Already credited counts
    // stay credited. Unclaimed retired prizes settle once as coins.
    final values = {
      for (final prize in catalog.prizes) prize.id: prize.coins,
      'boost': 35,
      'cache': 20,
    };
    if (_disposed ||
        storageError ||
        status.version != 2 ||
        status.counts.keys.any((id) => !values.containsKey(id)) ||
        _wheelClaims.entries.any(
          (claim) => (status.counts[claim.key] ?? 0) < claim.value,
        )) {
      return false;
    }
    final total = status.counts.values.fold(0, (sum, count) => sum + count);
    var coins = 0;
    var changed = false;
    for (final entry in status.counts.entries) {
      final delta = entry.value - (_wheelClaims[entry.key] ?? 0);
      if (delta == 0) continue;
      changed = true;
      _wheelClaims[entry.key] = entry.value;
      final value = values[entry.key]!;
      activity.prize('$value coins', delta);
      activity.event(EconomyEvent.wheelVerified, coinBalance, delta);
      coins += value * delta;
    }
    if (!changed) return false;
    _wallet.add(
      'wheel/verified/$total',
      'Fortune Wheel · verified rewards',
      coins,
      _today(),
    );
    final saved = await flush();
    if (!_disposed) notifyListeners();
    return saved;
  }

  final _coinAdDays = <String, String>{};
  String? _lastRewardedDay;
  bool get _rewardDayAvailable =>
      _lastRewardedDay == null || todayKey.compareTo(_lastRewardedDay!) >= 0;

  void _markRewardDay(String day) {
    if (_lastRewardedDay == null || day.compareTo(_lastRewardedDay!) > 0) {
      _lastRewardedDay = day;
    }
  }

  int get adsToday => _coinAdDays.values.where((day) => day == todayKey).length;

  /// The milestone bonus for today has already been paid.
  bool get coinMilestoneClaimed =>
      _wallet.contains('ad-milestone/${dayKey(_today())}');

  /// The next eligible video also earns the milestone bonus. Mirrors the rule
  /// in [grantAdBonus], so the Store never promises a bonus that will not pay.
  bool get nextCoinVideoEarnsMilestone =>
      canEarnAdBonus &&
      adsToday + 1 == economy.coinAdMilestone &&
      !coinMilestoneClaimed;
  bool get canEarnAdBonus =>
      !storageError &&
      _rewardDayAvailable &&
      adsToday < economy.rewardedAdsPerDay;

  Future<bool> grantAdBonus(String id) async {
    if (!onlineReady) return false;
    if (_disposed || !canEarnAdBonus) return false;
    final now = _today();
    final milestone = 'ad-milestone/${dayKey(now)}';
    final earnsMilestone =
        adsToday + 1 == economy.coinAdMilestone && !_wallet.contains(milestone);
    if (!_wallet.add(
      'ad/$id',
      'Optional video bonus',
      economy.rewardedAdCoins,
      now,
    )) {
      return false;
    }
    _coinAdDays[id] = dayKey(now);
    _markRewardDay(dayKey(now));
    if (earnsMilestone) {
      _wallet.add(
        milestone,
        'Fourth video bonus',
        economy.coinAdMilestoneBonus,
        now,
      );
    }
    notifyListeners();
    return flush();
  }

  Future<String?> billingProfile() async {
    if (_disposed) return null;
    final random = Random.secure();
    _billingProfile ??= List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return await flush() ? _billingProfile : null;
  }

  Future<bool> applyVerifiedPurchase(
    String grant, {
    required int coins,
    required bool themes,
    bool removeAds = false,
    bool bundle = false,
  }) async {
    if (_disposed || (coins <= 0 && !themes && !removeAds && !bundle))
      return false;
    if (themes) _themePass = true;
    if (removeAds) _removeAds = true;
    if (bundle) {
      _premium = true;
      _wallet.add(
        'premium/bonus',
        'Premium bonus',
        economy.premiumBonus,
        _today(),
      );
    }
    if (coins > 0)
      _wallet.add('purchase/$grant', 'Google Play coin pack', coins, _today());
    _awardAchievements();
    notifyListeners();
    return flush();
  }

  void _awardAchievements() {
    final conditions = {
      Achievement.trailhead: levelsSolved >= 1,
      Achievement.trailblazer: levelsSolved >= 12,
      Achievement.pathfinder: levelsSolved >= 50,
      Achievement.dailyHabit: longestStreak >= 3,
      Achievement.weeklyRitual: longestStreak >= 7,
      Achievement.unaided: unassisted >= 10,
      Achievement.collector: ownedThemes >= 6,
      Achievement.timeTrial: attackHighest >= 3,
      Achievement.twentyFive: levelsSolved >= 25,
      Achievement.hundred: levelsSolved >= 100,
      Achievement.fiveHundred: levelsSolved >= 500,
      Achievement.thousand: levelsSolved >= 1000,
      Achievement.researcher:
          Research.values.fold(
            0,
            (total, item) => total + progression.rank(item),
          ) >=
          10,
      Achievement.legendaryCrate: progression.legendary > 0,
    };
    for (final achievement in Achievement.values) {
      if (conditions[achievement]!) {
        _wallet.add(
          'achievement/${achievement.name}',
          achievement.title,
          achievement.coins + progression.effect(Research.mastery),
          _today(),
        );
      }
    }
  }

  int get dailySolved =>
      _results.keys.where((key) => key.startsWith('daily/')).length;

  Duration? best(PlayMode mode) {
    int? bestTime;
    for (final record in _results.entries) {
      if (!record.key.startsWith('${mode.name}/')) continue;
      final time = record.value.milliseconds;
      if (bestTime == null || time < bestTime) bestTime = time;
    }
    return bestTime == null ? null : Duration(milliseconds: bestTime);
  }

  late final PlayStreak streak;
  int _freezeSerial = 0;
  String get todayKey => dayKey(_today());

  int? recentStreakDay;

  void _qualifyStreak() {
    final day = todayKey;
    if (!streak.qualify(day)) return;
    final count = streak.count;
    recentStreakDay = count;
    if (EconomyRules.milestones[count] case final reward?) {
      if (_wallet.add(
        'play-streak/${streak.first}/$count',
        '$count-day streak',
        reward.coins,
        _today(),
      )) {
        _hintBalance += reward.hints;
      }
    }
    if (count % economy.streakInterval == 0) {
      _wallet.add(
        'play-streak-week/$day',
        '$count-day streak bonus',
        economy.streakBonus + progression.effect(Research.specialist),
        _today(),
      );
    }
  }

  Future<bool> buyFreeze() async {
    if (_disposed || storageError) return false;
    final before = streak.checkedThrough;
    streak.reconcile(todayKey);
    if (streak.freezes >= economy.maxFreezes ||
        !_wallet.add(
          'freeze/$_freezeSerial',
          'Streak Freeze',
          -economy.freezePrice,
          _today(),
        )) {
      if (before != streak.checkedThrough) {
        notifyListeners();
        await flush();
      }
      return false;
    }
    _freezeSerial++;
    streak.freezes++;
    notifyListeners();
    return flush();
  }

  int get dailyStreak {
    final now = _today();
    var day = DateTime.utc(now.year, now.month, now.day);
    if (result(PuzzleId.daily(dayKey(day))) == null) {
      day = day.subtract(const Duration(days: 1));
    }
    return _streakEnding(day);
  }

  int _streakEnding(DateTime day) {
    var count = 0;
    while (result(PuzzleId.daily(dayKey(day))) != null) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  void _updateLongestStreak() {
    final days = [
      for (final key in _results.keys.where((key) => key.startsWith('daily/')))
        if (DateTime.tryParse('${key.substring(6)}T00:00:00Z') case final day?)
          day,
    ]..sort();
    DateTime? previous;
    var streak = 0;
    for (final day in days) {
      streak = previous != null && day.difference(previous).inDays == 1
          ? streak + 1
          : 1;
      _longestStreak = max(_longestStreak, streak);
      previous = day;
    }
  }

  Future<void> open(PuzzleId id, {bool replay = false}) async {
    if (id.mode == PlayMode.levels && !canPlayLevel(id.level)) return;
    if (_inPlay) _leave();
    final request = ++_request;
    _pendingTutorials.clear();
    activeId = id;
    _inPlay = true;
    _started = false;
    _usedClear = false;
    _game = null;
    _watch.reset();
    _accountedMilliseconds = 0;
    lastReward = 0;
    completionCoins = 0;
    attemptStars = 0;
    previousAttemptBestStars = 0;
    earnedStarCoins = 0;
    latestDiscovery = null;
    latestDiscoveryClaimed = false;
    discoveryStartPercent = null;
    chapterCompletedThisVisit = false;
    firstCampaignClear = false;
    selectedMultiplier = null;
    recentStreakDay = null;
    recentAchievements = const [];
    newBest = false;
    completedThisVisit = false;
    correctedByHint = false;
    _baseTime = Duration.zero;
    elapsed.value = Duration.zero;
    loadError = null;
    loading = true;
    notifyListeners();

    try {
      final generation = id.generation;
      final board =
          await (_loader?.call(generation) ??
              _generate(
                generation,
                id.mode == PlayMode.levels ? id.level : 0,
                false,
              ));
      if (_disposed || request != _request) return;
      final game = GameController(board);
      _game = game;
      if (id.mode != PlayMode.attack) {
        _pendingTutorials.addAll(
          unseenMechanics(board.puzzle, acknowledgedMechanics),
        );
      }
      final stored = _map(replay ? null : _attempts[id.key]);
      final recorded = replay
          ? null
          : (result(id) ?? dailyCheckpointResult(id));
      try {
        if (stored.isNotEmpty) {
          game.restore(
            List<int>.from(stored['path'] as List),
            (stored['history'] as List)
                .map((step) => List<int>.from(step as List))
                .toList(),
            stored['hints'] as int,
            stored['hintCell'] as int?,
          );
          final savedTime = stored['milliseconds'] as int;
          _baseTime = Duration(milliseconds: savedTime < 0 ? 0 : savedTime);
          _started = stored['started'] == true;
          _usedClear = stored['usedClear'] != false;
        } else if (recorded != null) {
          game.restore(board.solution, [], recorded.hints, null);
          _baseTime = Duration(milliseconds: recorded.milliseconds);
        }
      } on TypeError {
        _attempts.remove(id.key);
      }
      if (replay) {
        _attempts.remove(id.key);
        unawaited(flush());
      }
      _syncClock();
    } catch (_) {
      if (_disposed || request != _request) return;
      loadError = 'This puzzle couldn’t be prepared.';
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        _processCrates();
        notifyListeners();
      }
    }
  }

  bool canStep(int cell) => _game?.canStep(cell) ?? false;

  @override
  RejectedMove? rejectionFor(int cell) =>
      _inPlay && _foreground && _canPlay ? _game?.rejectionFor(cell) : null;

  @override
  void rejectHaptic() => haptic.error();

  bool begin(int cell) {
    final game = _game;
    if (game == null || !_inPlay || !_foreground || !_canPlay) return false;
    final before = game.length;
    if (!game.begin(cell)) return false;
    if (game.length != before) _edited();
    return true;
  }

  void step(int cell) {
    if (!_foreground || !_canPlay) return;
    final checkpoint = nextCheckpoint;
    if (_game?.step(cell) case RouteEdit.advance || RouteEdit.retract) {
      _edited(connectedCheckpoint: nextCheckpoint > checkpoint);
    }
  }

  void end() {
    final changed = _game?.end() ?? false;
    if (changed) {
      _processCrates();
      _saveSoon();
    }
    // Always notify on stroke end so deferred offline notices or UI listeners
    // update cleanly even if the path did not change.
    notifyListeners();
  }

  void tap(int cell) {
    if (begin(cell)) end();
  }

  void undo() {
    if (!_canPlay || !(_game?.undo() ?? false)) return;
    _edited();
  }

  void clear() {
    if (!_canPlay || !(_game?.clear() ?? false)) return;
    _usedClear = true;
    _edited();
    unawaited(flush());
  }

  void hint() {
    if (!canHint) return;
    final used = hintsUsed;
    final conflict = _game!.routeConflicts;
    if (!_game!.hint(
      segment: used == 0
          ? 1
          : used == 1
          ? 3
          : 5,
    ))
      return;
    correctedByHint = conflict;
    if (activeId?.mode == PlayMode.attack) attack?.unassisted = false;
    _hintBalance--;
    _edited();
    unawaited(flush());
  }

  void _celebrateAchievements(Map<AchievementMetric, int> previous) {
    final current = achievementCounters;
    if (!mapEquals(previous, current)) achievementRevision++;
    recentAchievements = [
      for (final item in nativeAchievements)
        if (item.earned(current) && !item.earned(previous)) item,
    ];
  }

  void _edited({bool connectedCheckpoint = false}) {
    _started = true;
    if (_crateAnchor == null || complete) {
      _processCrates();
    }
    _syncClock();
    if (complete) {
      final id = activeId!;
      if (id.mode == PlayMode.attack) {
        final run = attack!;
        final now = _bootTime();
        _attempts.remove(id.key);
        if (now != null && run.clear(now)) {
          haptic.complete();
          unawaited(flush());
          unawaited(open(PuzzleId.attack('${run.id}/${run.clears.length}')));
        } else {
          refreshAttackClock();
        }
        return;
      }
      if (id.checkpoint != null) {
        _dailyCheckpoints.putIfAbsent(
          id.key,
          () => (
            milliseconds: elapsed.value.inMilliseconds,
            hints: hintsUsed,
            unassisted: hintsUsed == 0,
          ),
        );
        _attempts.remove(id.key);
        haptic.complete();
        unawaited(flush());
        notifyListeners();
        return;
      }
      final previousAchievements = achievementCounters;
      final previous = result(id);
      final stages = id.mode == PlayMode.daily
          ? _completedDailyCheckpoints(id.value as String)
          : const <RunResult>[];
      final time = stages.fold(
        elapsed.value.inMilliseconds,
        (total, stage) => total + stage.milliseconds,
      );
      final totalHints = stages.fold(
        hintsUsed,
        (total, stage) => total + stage.hints,
      );
      final improved = previous == null || time < previous.milliseconds;
      newBest = improved;
      completedThisVisit = true;
      final coinsBefore = coinBalance;
      _results[id.key] = (
        milliseconds: improved ? time : previous.milliseconds,
        hints: improved ? totalHints : previous.hints,
        unassisted: totalHints == 0 || (previous?.unassisted ?? false),
      );
      final mult = progression.multiplier(progressionTime);
      var levelStars = 0;
      if (id.mode == PlayMode.levels) {
        final prevStars = previous == null ? 0 : (starsFor(id) ?? 0);
        levelStars = starThresholdsForBoard(_game!.board).rate(time);
        final bestStars = max(prevStars, levelStars);
        attemptStars = levelStars;
        previousAttemptBestStars = prevStars;
        _levelStars[id.key] = bestStars;
        if (previous != null && bestStars > prevStars) {
          for (var s = prevStars + 1; s <= bestStars; s++) {
            _wallet.add(
              'star/${id.key}/$s',
              'Level ${id.level} $s-star bonus',
              mult,
              _today(),
            );
          }
          earnedStarCoins = coinBalance - coinsBefore;
        }
      }
      if (previous == null) {
        if (totalHints == 0 && !_usedClear && stages.isEmpty)
          _achievements.precision++;
        if (id.mode == PlayMode.levels) {
          _levelsSolved++;
          _advanceJourney(id.level);
          _highestUnlocked = max(_highestUnlocked, id.level + 1);
          earnedStarCoins = levelStars * mult;
        }
        final goldenBonus = totalHints == 0
            ? progression.effect(Research.golden)
            : 0;
        final coinsEarned = id.mode == PlayMode.levels
            ? economy.campaignClearCoins(
                multiplier: mult,
                magnetBonus: progression.effect(Research.magnet),
                goldenBonus: goldenBonus,
                momentumBonus: _levelsSolved % 5 == 0
                    ? progression.effect(Research.momentum)
                    : 0,
                stars: levelStars,
              )
            : economy.dailyClearCoins(
                multiplier: mult,
                fortuneBonus: progression.effect(Research.fortune),
                goldenBonus: goldenBonus,
              );
        _wallet.add(
          'clear/${id.key}',
          'Completed ${id.title}',
          coinsEarned,
          _today(),
        );
        completionCoins = coinBalance - coinsBefore;
        if (id.mode == PlayMode.daily) {
          _achievements.daily(id.value as String, _bootTime());
          _updateLongestStreak();
        }
        _qualifyStreak();
      }
      _awardAchievements();
      lastReward = coinBalance - coinsBefore;
      _celebrateAchievements(previousAchievements);
      _attempts.remove(id.key);
      haptic.complete();
      unawaited(flush());
    } else {
      if (endedEarly || connectedCheckpoint) {
        haptic.light();
      } else {
        haptic.selection();
      }
      _saveSoon();
    }
    notifyListeners();
  }

  Future<void> completeLevelOneFromDemo() async {
    final id = const PuzzleId.level(1);
    if (result(id) != null) return;
    final previousAchievements = achievementCounters;
    final coinsBefore = coinBalance;
    _results[id.key] = (milliseconds: 15000, hints: 0, unassisted: true);
    final demoStars = starThresholdsForLevel(1).rate(15000);
    _levelStars[id.key] = demoStars;
    _achievements.precision++;
    _levelsSolved++;
    _advanceJourney(1);
    _highestUnlocked = max(_highestUnlocked, 2);
    _wallet.add(
      'clear/${id.key}',
      'Completed ${id.title}',
      economy.campaignClearCoins(
        multiplier: progression.multiplier(progressionTime),
        magnetBonus: progression.effect(Research.magnet),
        goldenBonus: progression.effect(Research.golden),
        momentumBonus: 0,
        stars: demoStars,
      ),
      _today(),
    );
    _qualifyStreak();
    _awardAchievements();
    lastReward = coinBalance - coinsBefore;
    _celebrateAchievements(previousAchievements);
    _attempts.remove(id.key);
    haptic.complete();
    notifyListeners();
    await flush();
  }

  void close() {
    _leave();
    _game = null;
    activeId = null;
    loading = false;
    notifyListeners();
  }

  void _leave() {
    _request++;
    _processCrates(ending: true);
    _game?.end();
    _inPlay = false;
    _syncClock();
    unawaited(flush());
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _game?.end();
      if (!_crateRevealed) _fallingCrate = null;
    }
    _processCrates();
    _syncClock();
    if (!foreground) unawaited(flush());
    notifyListeners();
  }

  void refreshDate() {
    final before = streak.checkedThrough;
    streak.reconcile(todayKey);
    if (before != streak.checkedThrough) unawaited(flush());
    notifyListeners();
  }

  void setTheme(PathwiseTheme theme) {
    if (!ownsTheme(theme)) return;
    _prefs.theme = theme;
    notifyListeners();
    unawaited(flush());
  }

  void setHaptics(bool enabled) {
    _prefs.haptics = enabled;
    haptic.enabled = enabled;
    haptic.light();
    notifyListeners();
    unawaited(flush());
  }

  void setSharingSuggestions(bool enabled) {
    _prefs.suggestSharing = enabled;
    notifyListeners();
    unawaited(flush());
  }

  void _syncClock() {
    final shouldRun =
        _foreground && _inPlay && _started && !complete && _canPlay;
    if (shouldRun && !_watch.isRunning) {
      _watch.start();
      _tick = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _clock(),
      );
    } else if (!shouldRun && _watch.isRunning) {
      _watch.stop();
      _tick?.cancel();
      _tick = null;
    }
    _clock();
  }

  void _clock() => elapsed.value = _baseTime + _watch.elapsed;

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(flush()),
    );
  }

  late bool _levelOneDemoSeen;
  bool get shouldOfferLevelOneDemo => !_levelOneDemoSeen && !storageError;

  Future<bool> markLevelOneDemoSeen() async {
    if (!shouldOfferLevelOneDemo) return false;
    _levelOneDemoSeen = true;
    return flush();
  }

  Future<bool> flush() {
    _unsavedCrateTime = 0;
    _playMilliseconds += max(
      0,
      _watch.elapsedMilliseconds - _accountedMilliseconds,
    );
    _accountedMilliseconds = _watch.elapsedMilliseconds;
    _saveTimer?.cancel();
    _saveTimer = null;
    final id = activeId;
    final game = _game;
    if (id != null &&
        game != null &&
        !complete &&
        _started &&
        _gameplayAllowed) {
      _attempts[id.key] = {
        'path': game.path,
        'history': game.history,
        'hints': hintsUsed,
        'hintCell': hintCell,
        'started': _started,
        'usedClear': _usedClear,
        'milliseconds': (_baseTime + _watch.elapsed).inMilliseconds,
      };
    }
    final snapshot = _snapshotMap();
    final payload = jsonEncode(snapshot);
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await storage.save(payload);
        onPersisted?.call(snapshot);
        if (storageError && !_disposed) {
          storageError = false;
          notifyListeners();
        }
        return true;
      } catch (_) {
        if (!storageError && !_disposed) {
          storageError = true;
          notifyListeners();
        }
        return false;
      }
    });
    return _pendingWrite;
  }

  /// The complete device save. Cloud sync uses the same map as its payload.
  Map<String, dynamic> snapshotMap() => _snapshotMap();

  Map<String, dynamic> _snapshotMap() => {
    'schemaVersion': GameStateStorage.schemaVersion,
    if (_journeyClears != 0 ||
        _upcomingDiscoveryItem != null ||
        _chapterChests.isNotEmpty ||
        _claimedMysteries.isNotEmpty)
      'journey': {
        'clears': _journeyClears,
        if (_upcomingDiscoveryItem case final upcoming?) 'upcoming': upcoming,
        if (_chapterChests.isNotEmpty) 'chapterChests': pendingChapterChests,
        if (_claimedMysteries.isNotEmpty)
          'claimedMysteries': _claimedMysteries.toList()..sort(),
      },
    'levelOneDemoSeen': _levelOneDemoSeen,
    'mechanicTutorials': _tutorialStatus,
    'nativeAchievements': _achievements.toJson(),
    'priorSolves': _retiredSolved,
    'priorCleanSolves': _retiredClean,
    'priorRanks': _retiredRanks,
    'progression': progression.toJson(),
    'economyActivity': activity.toJson(),
    'progressionBoot': _bootTime()?.boot,
    'playStreak': streak.toJson(),
    'freezeSerial': _freezeSerial,
    'classicLevels': _classicLevels.toList(),
    'legacyMechanicLevels': _legacyMechanicLevels.toList(),
    'hintBalance': _hintBalance,
    'hintPurchaseSerial': _hintPurchaseSerial,
    'hintAdDays': _hintAdDays,
    'coinAdDays': _coinAdDays,
    'boostAdDays': _boostAdDays,
    'hintEvents': _hintEvents.toList(),
    'attack': attack?.toJson(),
    'attackMinutes': _attackMinutes,
    'dailyCheckpoints': {
      for (final entry in _dailyCheckpoints.entries)
        entry.key: {
          'milliseconds': entry.value.milliseconds,
          'hints': entry.value.hints,
        },
    },
    'fortune': {
      if (_lastFreeFortune case final stamp?) ...{
        'boot': stamp.boot,
        'at': stamp.milliseconds,
      },
      'claims': _wheelClaims,
      if (_pendingFortune case final pending?)
        'pending': {
          'id': pending.id,
          'prize': pending.prize.id,
          'coins': pending.prize.coins,
        },
      'videos': [
        for (final stamp in _wheelVideos)
          {'boot': stamp.boot, 'at': stamp.milliseconds},
      ],
    },
    'archivedCoins': _wallet.archivedCoins,
    if (_coinOfferLevel case final levels?)
      'coinOffer': {
        'levels': levels,
        if (_lastCoinOffer case final offer?) ...{
          'boot': offer.boot,
          'milliseconds': offer.milliseconds,
        },
      },
    if (_lastAutomaticAd case final stamp?)
      'lastAutomaticAd': {
        'boot': stamp.boot,
        'milliseconds': stamp.milliseconds,
      },
    'attackHistory': [for (final run in attackHistory) run.toJson()],
    'removeAds': _removeAds,
    'premium': _premium,
    'preferences': _prefs.toJson(),
    'ledger': _wallet.toJson(),
    'ownedThemes': [for (final theme in _owned) theme.name],
    'ownedTips': [for (final tip in _ownedTips) tip.name],
    'equippedTip': _equippedTip.name,
    'themePass': _themePass,
    'billingProfile': _billingProfile,
    'playMilliseconds': _playMilliseconds,
    'highestUnlocked': _highestUnlocked,
    'attempts': _attempts,
    'results': {
      for (final entry in _results.entries)
        entry.key: {
          'milliseconds': entry.value.milliseconds,
          'hints': entry.value.hints,
          'unassisted': entry.value.unassisted,
          if (_levelStars[entry.key] case final stars?) 'stars': stars,
        },
    },
  };

  /// Adopts ownership shown by Google Play. Permanent entitlements follow the
  /// store's record rather than the cloud save, so a refund removes them.
  void reconcileOwnedProducts(Set<String> owned) {
    final changed =
        _themePass != owned.contains(themePassProduct) ||
        _removeAds != owned.contains(removeAdsProduct) ||
        _premium != owned.contains(premiumProduct);
    _themePass = owned.contains(themePassProduct);
    _removeAds = owned.contains(removeAdsProduct);
    _premium = owned.contains(premiumProduct);
    if (changed) {
      notifyListeners();
      unawaited(flush());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    connectivity?.removeListener(_onConnectivityChanged);
    _tick?.cancel();
    _saveTimer?.cancel();
    _attackTicker?.cancel();
    attackRemaining.dispose();
    _crateTimer?.cancel();
    elapsed.dispose();
    super.dispose();
  }
}
