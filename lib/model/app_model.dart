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
import 'game_state.dart';
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
  }) : _today = today ?? DateTime.now,
       _loader = loader ?? _generate,
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
    _wallet = Wallet(snapshot['ledger'], _today());
    _owned.addAll(
      PathwiseTheme.values.where((theme) => economy.themePrice(theme) == 0),
    );
    final owned = snapshot['ownedThemes'];
    if (owned is List) {
      _owned.addAll(
        PathwiseTheme.values.where((theme) => owned.contains(theme.name)),
      );
    }
    _themePass = snapshot['themePass'] == true;
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
    if (snapshot['schemaVersion'] != 2) {
      for (final key in _attempts.keys) {
        final legacy = _levelFromKey(key);
        if (legacy != null && legacy <= legacyLevelCount) {
          _highestUnlocked = max(_highestUnlocked, legacy);
        }
      }
    }
    _updateLongestStreak();
    _endlessIndex =
        1 + _results.keys.where((key) => key.startsWith('endless/')).length;
    haptic = HapticService(enabled: _prefs.haptics);
  }

  static Future<VerifiedPuzzle> _generate(
    ({int size, int seed, int clues}) request,
  ) => compute(generatePuzzle, request);

  final GameStateStorage storage;
  final DateTime Function() _today;
  final PuzzleLoader _loader;
  final UserPreferences _prefs;
  late final Wallet _wallet;
  final _owned = <PathwiseTheme>{};
  bool _themePass = false;
  String? _billingProfile;
  int _highestUnlocked = 1;
  int _levelsSolved = 0;
  int _longestStreak = 0;
  int _playMilliseconds = 0;
  int _accountedMilliseconds = 0;
  int lastReward = 0;
  bool newBest = false;
  bool completedThisVisit = false;
  late final HapticService haptic;
  final _attempts = <String, dynamic>{};
  final _results = <String, RunResult>{};
  final elapsed = ValueNotifier(Duration.zero);
  final _watch = Stopwatch();
  Timer? _tick;
  Timer? _saveTimer;
  Future<bool> _pendingWrite = Future.value(true);
  var _baseTime = Duration.zero;
  var _endlessIndex = 1;
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
  PuzzleId get endless => PuzzleId.endless(_endlessIndex);
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
  bool get canHint => _game != null && !complete && hintCell == null;
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
  bool ownsTheme(PathwiseTheme theme) => _themePass || _owned.contains(theme);
  int get ownedThemes =>
      _themePass ? PathwiseTheme.values.length : _owned.length;
  bool get hasThemePass => _themePass;
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
    _prefs.theme = theme;
    _awardAchievements();
    unawaited(flush());
    notifyListeners();
    return true;
  }

  int get _adsToday => _wallet.history
      .where(
        (tx) =>
            tx.id.startsWith('ad/') &&
            dayKey(tx.date.toLocal()) == dayKey(_today()),
      )
      .length;
  bool get canEarnAdBonus =>
      !storageError && _adsToday < economy.rewardedAdsPerDay;

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
  }) async {
    if (_disposed || (coins <= 0 && !themes)) return false;
    if (themes) _themePass = true;
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
    };
    for (final achievement in Achievement.values) {
      if (conditions[achievement]!) {
        _wallet.add(
          'achievement/${achievement.name}',
          achievement.title,
          achievement.coins,
          _today(),
        );
      }
    }
  }

  int get dailySolved =>
      _results.keys.where((key) => key.startsWith('daily/')).length;
  int get endlessSolved => _endlessIndex - 1;

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
    if (game == null || !_inPlay) return false;
    final before = game.length;
    if (!game.begin(cell)) return false;
    if (game.length != before) _edited();
    return true;
  }

  void step(int cell) {
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
    if (_game?.undo() ?? false) _edited();
  }

  void clear() {
    if (_game?.clear() ?? false) _edited();
  }

  void hint() {
    if (_game?.hint() ?? false) _edited();
  }

  void _edited() {
    _started = true;
    _syncClock();
    if (complete) {
      final id = activeId!;
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
      if (id.mode == PlayMode.endless && id.value == _endlessIndex)
        _endlessIndex++;
      if (previous == null) {
        if (id.mode == PlayMode.levels) {
          _levelsSolved++;
          _highestUnlocked = max(_highestUnlocked, id.level + 1);
        }
        _wallet.add(
          'clear/${id.key}',
          'Completed ${id.title}',
          economy.clearReward(id.mode),
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
              economy.streakBonus,
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
    final shouldRun = _foreground && _inPlay && _started && !complete;
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
    if (id != null && game != null && !complete && _started) {
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
      'schemaVersion': 2,
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
    elapsed.dispose();
    super.dispose();
  }
}
