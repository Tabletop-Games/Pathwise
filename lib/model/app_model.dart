import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../logic/game_controller.dart';
import '../logic/game_state_storage.dart';
import '../logic/haptic_service.dart';
import '../logic/puzzle.dart';
import '../logic/puzzle_generator.dart';
import 'economy.dart';
import 'expedition.dart';
import 'game_state.dart';
import 'progression.dart';
import 'time_attack.dart';
import 'user_preferences.dart';

typedef PuzzleLoader = Future<VerifiedPuzzle> Function(
  ({int size, int seed, int clues}) request,
);

class AppModel extends ChangeNotifier {
  AppModel({
    required this.storage,
    required Map<String, dynamic> snapshot,
    DateTime Function()? today,
    PuzzleLoader? loader,
    BootTime? Function()? bootTime,
  }) : _today = today ?? DateTime.now,
       _loader = loader ?? _generate,
       _bootTime = bootTime ?? (() => null),
       _prefs = UserPreferences.fromJson(_map(snapshot['preferences'])) {
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
      }
    }
    progression = Progression(_map(snapshot['progression']));
    if (snapshot['progressionBoot'] != _bootTime()?.boot) {
      progression.active.clear();
      progression.crate = null;
      progression.nextCrate = 0;
    }
    _hintTank = (snapshot['hintTank'] as int? ?? 3).clamp(0, 3);
    _refillSerial = snapshot['refillSerial'] as int? ?? 0;
    for (final row in _map(snapshot['hintUsage']).entries) {
      if (row.value is int) _hintUsage[row.key] = row.value as int;
    }
    if ((snapshot['schemaVersion'] as int? ?? 1) >= 4) {
      for (final row in _map(snapshot['hintCredits']).entries) {
        if (row.value == 1) _hintCredits[row.key] = 1;
      }
    }
    _hintEvents.addAll(
      (snapshot['hintEvents'] as List? ?? []).whereType<String>(),
    );
    if ((snapshot['schemaVersion'] as int? ?? 1) < 3) {
      for (final row in _attempts.entries) {
        final count = _map(row.value)['hints'];
        if (count is int) _hintUsage[row.key] = count;
      }
      for (final row in _results.entries) {
        _hintUsage[row.key] = max(_hintUsage[row.key] ?? 0, row.value.hints);
      }
    }
    _attempts.removeWhere((key, _) => key.startsWith('endless/'));
    _hintUsage.removeWhere((key, _) => key.startsWith('endless/'));
    _hintCredits.removeWhere((key, _) => key.startsWith('endless/'));
    if (snapshot['expedition'] case final Map data) {
      expedition = ExpeditionRun.fromJson(data);
    }
    _expeditionSerial = snapshot['expeditionSerial'] as int? ?? 0;
    for (final trail in Trail.values) {
      final record = _map(snapshot['trailRecords'])[trail.name];
      if (record is Map) _trailRecords[trail] = TrailRecord.fromJson(record);
    }
    if (snapshot['expeditionHistory'] case final List entries) {
      _expeditionHistory.addAll(
        entries.whereType<Map>().map(ExpeditionRun.fromJson),
      );
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
    _wallet = Wallet(snapshot['ledger'], _today());
    _owned.addAll(
      PathwiseTheme.values.where(
        (theme) =>
            theme != PathwiseTheme.basinGold && economy.themePrice(theme) == 0,
      ),
    );
    final owned = snapshot['ownedThemes'];
    if (owned is List) {
      _owned.addAll(
        PathwiseTheme.values.where((theme) => owned.contains(theme.name)),
      );
    }
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
  }

  static Future<VerifiedPuzzle> _generate(
    ({int size, int seed, int clues}) request,
  ) => compute(generatePuzzle, request);

  final BootTime? Function() _bootTime;
  BootTime? _lastAutomaticAd;

  Future<bool> reserveAutomaticAd() async {
    if (adFree || storageError || !_foreground) return false;
    final now = _bootTime();
    if (now == null) return false;
    final last = _lastAutomaticAd;
    if (last != null) {
      final elapsed = last.boot == now.boot
          ? now.milliseconds - last.milliseconds
          : now.milliseconds;
      if (elapsed < economy.automaticAdGap.inMilliseconds) return false;
    }
    _lastAutomaticAd = now;
    return flush();
  }

  void recordRewardedAdExit() {
    final now = _bootTime();
    if (now != null) {
      _lastAutomaticAd = now;
      unawaited(flush());
    }
  }

  final _hintUsage = <String, int>{};
  final _hintCredits = <String, int>{};
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
        '${now.boot}-${now.milliseconds}-${Random.secure().nextInt(1 << 32)}',
        now.boot,
        now.milliseconds + AttackRun.duration.inMilliseconds,
        now.milliseconds,
        attackBest,
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
      final beforeAchievements = coinBalance;
      _awardAchievements();
      run.coins += coinBalance - beforeAchievements;
      if (activeId?.mode == PlayMode.attack) {
        final key = activeId!.key;
        _attempts.remove(key);
        _hintUsage.remove(key);
        _hintCredits.remove(key);
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

  ExpeditionRun? expedition;
  var _expeditionSerial = 0;
  bool expeditionSaving = false;
  final _expeditionHistory = <ExpeditionRun>[];
  final _trailRecords = <Trail, TrailRecord>{};

  List<ExpeditionRun> get expeditionHistory =>
      List.unmodifiable(_expeditionHistory);
  TrailRecord? trailRecord(Trail trail) => _trailRecords[trail];
  int get trailsQualified =>
      _trailRecords.values.where((record) => record.fastest != null).length;
  bool trailRewardClaimed(Trail trail, int stage) =>
      _wallet.contains('trail/${trail.name}/$stage');
  bool trailUnlocked(Trail trail) =>
      trail.index == 0 ||
      trailRecord(Trail.values[trail.index - 1])?.fastest != null;
  PuzzleId? get expeditionPuzzle {
    final run = expedition;
    return run == null || !run.active
        ? null
        : PuzzleId.expedition(run.trail, run.serial, run.stage);
  }

  Future<bool> startExpedition(Trail trail) async {
    if (_disposed ||
        expeditionSaving ||
        activeId != null ||
        expedition?.active == true ||
        storageError ||
        !trailUnlocked(trail))
      return false;
    final previous = expedition;
    final run = ExpeditionRun(trail, _expeditionSerial++);
    expedition = run;
    expeditionSaving = true;
    notifyListeners();
    final saved = await flush();
    if (!saved) expedition = previous;
    expeditionSaving = false;
    if (!_disposed) notifyListeners();
    return saved;
  }

  Future<bool> abandonExpedition() {
    final run = expedition;
    if (run == null || !run.active || activeId != null || storageError) {
      return Future.value(false);
    }
    _forgetExpeditionAttempt(expeditionPuzzle!.key);
    run.outcome = ExpeditionOutcome.abandoned;
    _archiveExpedition(run);
    notifyListeners();
    return flush();
  }

  void _forgetExpeditionAttempt(String key) {
    _attempts.remove(key);
    _hintUsage.remove(key);
    _hintCredits.remove(key);
  }

  void _archiveExpedition(ExpeditionRun run) {
    _trailRecords.putIfAbsent(run.trail, TrailRecord.new).record(run);
    _expeditionHistory.add(run);
    if (_expeditionHistory.length > 12) _expeditionHistory.removeAt(0);
  }

  void _completeExpeditionStage(PuzzleId id) {
    final run = expedition!;
    final stage = run.stage;
    final time = elapsed.value.inMilliseconds;
    final before = coinBalance;
    final recordKey = 'expedition/${run.trail.name}/$stage';
    final prior = _results[recordKey];
    final usedHint = (_hintUsage[id.key] ?? 0) != 0;
    final improved = prior == null || time < prior.milliseconds;
    _results[recordKey] = (
      milliseconds: improved ? time : prior.milliseconds,
      hints: improved ? hintsUsed : prior.hints,
      unassisted: !usedHint || (prior?.unassisted ?? false),
    );
    _forgetExpeditionAttempt(id.key);
    run.finishStage(time, usedHint: usedHint);
    final qualified = run.outcome == ExpeditionOutcome.qualified;
    _wallet.add(
      'trail/${run.trail.name}/${run.stage}',
      '${run.trail.title} · stage ${run.stage}',
      economy.expeditionReward(run.stage, qualified: qualified),
      _today(),
    );
    if (qualified && run.trail == Trail.summit)
      _owned.add(PathwiseTheme.basinGold);
    if (!run.active) _archiveExpedition(run);
    _awardAchievements();
    lastReward = coinBalance - before;
    run.coins += lastReward;
    haptic.complete();
    unawaited(flush());
    notifyListeners();
  }

  int get freeHints => max(0, 3 - (_hintUsage[activeId?.key] ?? 0));
  int get extraHints => _hintCredits[activeId?.key] ?? 0;
  bool get canRequestExtraHint =>
      activeId != null &&
      (_game?.canHint ?? false) &&
      !complete &&
      !loading &&
      !storageError &&
      freeHints == 0 &&
      extraHints == 0 &&
      _canPlay;

  Future<bool> grantRewardedHint(String puzzle, String event) async {
    if (_disposed ||
        storageError ||
        (_hintUsage[puzzle] ?? 0) < 3 ||
        (_hintCredits[puzzle] ?? 0) != 0 ||
        (puzzle.startsWith('expedition/') && puzzle != expeditionPuzzle?.key) ||
        (puzzle.startsWith('attack/') &&
            (attack?.finished != false ||
                !puzzle.startsWith('attack/${attack!.id}/'))) ||
        !_hintEvents.add(event))
      return false;
    _hintCredits.update(puzzle, (value) => value + 1, ifAbsent: () => 1);
    notifyListeners();
    return flush();
  }

  late final Progression progression;
  int get progressionTime =>
      _bootTime()?.milliseconds ?? _today().millisecondsSinceEpoch;
  Timer? _crateTimer;

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
    _awardAchievements();
    _progressionChanged();
    return true;
  }

  bool buyBoost(Boost item) {
    if (storageError ||
        !_wallet.add(
          'boost/${progression.serial}',
          item.title,
          -progression.discount(item.price),
          _today(),
        ))
      return false;
    progression.serial++;
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

  Crate? get supplyCrate {
    final crate = progression.crate;
    return crate != null && crate.deadline > progressionTime ? crate : null;
  }

  bool claimCrate(String id) {
    final crate = supplyCrate;
    if ((_game?.isDrawing ?? false) ||
        crate == null ||
        crate.id != id ||
        storageError ||
        !_wallet.add(
          id,
          '${crate.rarity.name} supply crate',
          crate.coins,
          _today(),
        ))
      return false;
    progression.crate = null;
    if (crate.rarity == CrateRarity.legendary) progression.legendary++;
    _awardAchievements();
    _progressionChanged();
    return true;
  }

  void _progressionChanged() {
    haptic.selection();
    unawaited(flush());
    notifyListeners();
  }

  void _checkCrate() {
    final id = activeId;
    if (!_foreground ||
        id == null ||
        id.mode == PlayMode.attack ||
        loading ||
        complete ||
        !_started ||
        storageError ||
        (_game?.isDrawing ?? false))
      return;
    final previous = progression.crate;
    final oldNext = progression.nextCrate;
    final spawned = progression.considerCrate(
      progressionTime,
      dayKey(_today()),
      Random.secure().nextInt(100),
    );
    if (spawned ||
        previous != progression.crate ||
        oldNext != progression.nextCrate) {
      unawaited(flush());
      notifyListeners();
    }
  }

  int _hintTank = 3;
  int _refillSerial = 0;
  int get hintTank => _hintTank;
  bool get canRefillTank => !_disposed && !storageError && _hintTank < 3;
  int get refillPrice => progression.refillPrice;

  bool buyTankRefill() {
    if (!canRefillTank ||
        !_wallet.add(
          'tank/$_refillSerial',
          'Hint tank refill',
          -refillPrice,
          _today(),
        ))
      return false;
    _fillTank();
    return true;
  }

  Future<bool> grantTankRefill(String event) async {
    if (!canRefillTank || !_hintEvents.add(event)) return false;
    return _fillTank();
  }

  Future<bool> _fillTank() {
    _hintTank = 3;
    _refillSerial++;
    notifyListeners();
    return flush();
  }

  bool get _canPlay {
    if (activeId?.mode != PlayMode.attack) return true;
    final now = _bootTime();
    return now != null && (attack?.remaining(now) ?? 0) > 0;
  }

  final GameStateStorage storage;
  final DateTime Function() _today;
  final PuzzleLoader _loader;
  final UserPreferences _prefs;
  late final Wallet _wallet;
  final _owned = <PathwiseTheme>{};
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
  int lastReward = 0;
  bool newBest = false;
  bool completedThisVisit = false;
  bool correctedByHint = false;
  late final HapticService haptic;
  final _attempts = <String, dynamic>{};
  final _results = <String, RunResult>{};
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
  GameController? _game;
  PuzzleId? activeId;
  bool loading = false;
  String? loadError;
  bool storageError = false;

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : {};

  PuzzleId get daily => PuzzleId.daily(dayKey(_today()));
  PathwiseTheme get theme => _prefs.theme;
  bool get haptics => _prefs.haptics;
  Puzzle? get puzzle => _game?.puzzle;
  List<int> get path => _game?.path ?? const [];
  int? get tip => _game?.tip;
  int? get hintCell => _game?.hintCell;
  int get hintsUsed => _game?.hintsUsed ?? 0;
  int get nextCheckpoint => _game?.nextCheckpoint ?? 1;
  bool get complete => _game?.complete ?? false;
  bool get canUndo => _game?.canUndo ?? false;
  bool get canClear => !complete && (path.length > 1 || hintCell != null);
  bool get canHint =>
      _canPlay &&
      (_game?.canHint ?? false) &&
      (freeHints > 0 ? hintTank > 0 : extraHints > 0);
  bool hasAttempt(PuzzleId id) => _attempts.containsKey(id.key);
  RunResult? result(PuzzleId id) => _results[id.key];
  int get solved => _results.length;
  int get unassisted =>
      _results.values.where((value) => value.unassisted).length;
  int get levelsSolved => _levelsSolved;
  int get highestUnlocked => _highestUnlocked;
  bool canPlayLevel(int level) => level > 0 && level <= highestUnlocked;
  int get coinBalance => _wallet.balance;
  int get coinsEarned => _wallet.earned;
  int get coinsSpent => _wallet.spent;
  List<CoinTransaction> get transactions =>
      _wallet.history.toList().reversed.toList();
  bool ownsTheme(PathwiseTheme theme) => hasThemePass || _owned.contains(theme);
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
    if (theme == PathwiseTheme.basinGold || ownsTheme(theme) || storageError)
      return false;
    if (!_wallet.add(
      'theme/${theme.name}',
      'Unlocked ${theme.label}',
      -economy.themePrice(theme),
      _today(),
    ))
      return false;
    _owned.add(theme);
    _prefs.theme = theme;
    _awardAchievements();
    unawaited(flush());
    notifyListeners();
    return true;
  }

  int get adsToday => _wallet.history
      .where(
        (tx) =>
            tx.id.startsWith('ad/') &&
            dayKey(tx.date.toLocal()) == dayKey(_today()),
      )
      .length;
  bool get canEarnAdBonus =>
      !storageError && adsToday < economy.rewardedAdsPerDay;

  Future<bool> grantAdBonus(String id) async {
    if (_disposed || !canEarnAdBonus) return false;
    if (!_wallet.add(
      'ad/$id',
      'Optional video bonus',
      economy.rewardedAdCoins,
      _today(),
    ))
      return false;
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
      Achievement.expeditionClear: Trail.values.any(
        (trail) => trailRecord(trail)?.fastest != null,
      ),
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
    if (id.mode == PlayMode.expedition &&
        (replay || id.key != expeditionPuzzle?.key))
      return;
    if (_inPlay) _leave();
    final request = ++_request;
    activeId = id;
    _inPlay = true;
    _started = false;
    _game = null;
    _watch.reset();
    _accountedMilliseconds = 0;
    lastReward = 0;
    newBest = false;
    completedThisVisit = false;
    correctedByHint = false;
    _baseTime = Duration.zero;
    elapsed.value = Duration.zero;
    loadError = null;
    loading = true;
    notifyListeners();

    try {
      final board = await _loader(id.generation);
      if (_disposed || request != _request) return;
      final game = GameController(board);
      _game = game;
      final stored = _map(replay ? null : _attempts[id.key]);
      final recorded = replay ? null : result(id);
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
        notifyListeners();
      }
    }
  }

  bool canStep(int cell) => _game?.canStep(cell) ?? false;

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
    if (_game?.step(cell) case RouteEdit.advance || RouteEdit.retract)
      _edited();
  }

  void end() {
    if (_game?.end() ?? false) {
      _saveSoon();
      notifyListeners();
    }
  }

  void tap(int cell) {
    if (begin(cell)) end();
  }

  void undo() {
    if (_canPlay && (_game?.undo() ?? false)) _edited();
  }

  void clear() {
    if (!_canPlay || !(_game?.clear() ?? false)) return;
    if (activeId?.mode == PlayMode.expedition) expedition!.usedClear = true;
    _edited();
    if (activeId?.mode == PlayMode.expedition) unawaited(flush());
  }

  void hint() {
    if (!canHint) return;
    final key = activeId!.key;
    final used = _hintUsage[key] ?? 0;
    final useCredit = freeHints == 0;
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
    if (useCredit) {
      _hintCredits[key] = extraHints - 1;
    } else {
      _hintTank--;
    }
    _hintUsage[key] = used + 1;
    _edited();
    unawaited(flush());
  }

  void _edited() {
    _started = true;
    _crateTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkCrate(),
    );
    _syncClock();
    if (complete) {
      final id = activeId!;
      if (id.mode == PlayMode.attack) {
        final run = attack!;
        final now = _bootTime();
        _attempts.remove(id.key);
        _hintUsage.remove(id.key);
        _hintCredits.remove(id.key);
        if (now != null && run.clear(now)) {
          haptic.complete();
          unawaited(flush());
          unawaited(open(PuzzleId.attack('${run.id}/${run.clears.length}')));
        } else {
          refreshAttackClock();
        }
        return;
      }
      if (id.mode == PlayMode.expedition) {
        _completeExpeditionStage(id);
        return;
      }
      final previous = result(id);
      final time = elapsed.value.inMilliseconds;
      final improved = previous == null || time < previous.milliseconds;
      newBest = improved;
      completedThisVisit = true;
      final coinsBefore = coinBalance;
      _results[id.key] = (
        milliseconds: improved ? time : previous.milliseconds,
        hints: improved ? hintsUsed : previous.hints,
        unassisted: hintsUsed == 0 || (previous?.unassisted ?? false),
      );
      if (previous == null) {
        if (id.mode == PlayMode.levels) {
          _levelsSolved++;
          _highestUnlocked = max(_highestUnlocked, id.level + 1);
        }
        _wallet.add(
          'clear/${id.key}',
          'Completed ${id.title}',
          (economy.clearReward(id.mode) +
                  (id.mode == PlayMode.levels
                      ? progression.effect(Research.magnet)
                      : 0) +
                  (id.mode == PlayMode.daily
                      ? progression.effect(Research.fortune)
                      : 0) +
                  (hintsUsed == 0 ? progression.effect(Research.golden) : 0) +
                  (id.mode == PlayMode.levels && _levelsSolved % 5 == 0
                      ? progression.effect(Research.momentum)
                      : 0)) *
              progression.multiplier(progressionTime),
          _today(),
        );
        if (id.mode == PlayMode.daily) {
          _updateLongestStreak();
          final day = DateTime.parse('${id.value}T00:00:00Z');
          final streak = _streakEnding(day);
          if (streak > 0 && streak % economy.streakInterval == 0) {
            _wallet.add(
              'streak/${id.key}',
              '$streak-day streak',
              economy.streakBonus + progression.effect(Research.specialist),
              _today(),
            );
          }
        }
      }
      _awardAchievements();
      lastReward = coinBalance - coinsBefore;
      _attempts.remove(id.key);
      haptic.complete();
      unawaited(flush());
    } else {
      haptic.selection();
      _saveSoon();
    }
    notifyListeners();
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
    _game?.end();
    _inPlay = false;
    _syncClock();
    unawaited(flush());
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) _game?.end();
    _syncClock();
    if (!foreground) unawaited(flush());
    notifyListeners();
  }

  void refreshDate() => notifyListeners();

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

  Future<bool> flush() {
    _playMilliseconds += max(
      0,
      _watch.elapsedMilliseconds - _accountedMilliseconds,
    );
    _accountedMilliseconds = _watch.elapsedMilliseconds;
    _saveTimer?.cancel();
    _saveTimer = null;
    final id = activeId;
    final game = _game;
    if (id != null && game != null && !complete && _started && _canPlay) {
      _attempts[id.key] = {
        'path': game.path,
        'history': game.history,
        'hints': hintsUsed,
        'hintCell': hintCell,
        'started': _started,
        'milliseconds': (_baseTime + _watch.elapsed).inMilliseconds,
      };
    }
    final payload = jsonEncode({
      'schemaVersion': GameStateStorage.schemaVersion,
      'progression': progression.toJson(),
      'progressionBoot': _bootTime()?.boot,
      'hintTank': _hintTank,
      'refillSerial': _refillSerial,
      'hintUsage': _hintUsage,
      'hintCredits': _hintCredits,
      'hintEvents': _hintEvents.toList(),
      'attack': attack?.toJson(),
      'expedition': expedition?.toJson(),
      'expeditionSerial': _expeditionSerial,
      'expeditionHistory': [for (final run in _expeditionHistory) run.toJson()],
      'trailRecords': {
        for (final entry in _trailRecords.entries)
          entry.key.name: entry.value.toJson(),
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
          },
      },
    });
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await storage.save(payload);
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

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _saveTimer?.cancel();
    _attackTicker?.cancel();
    attackRemaining.dispose();
    _crateTimer?.cancel();
    elapsed.dispose();
    super.dispose();
  }
}
