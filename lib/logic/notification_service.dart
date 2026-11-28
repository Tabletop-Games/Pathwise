import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/notification_preferences.dart';

enum NotificationCategory { daily, streak, invite }

final class ScheduledNotificationInfo {
  const ScheduledNotificationInfo({
    required this.id,
    required this.category,
    required this.channel,
    required this.title,
    required this.body,
    required this.scheduledAt,
    this.isTest = false,
  });

  final int id;
  final NotificationCategory category;
  final String channel;
  final String title;
  final String body;
  final DateTime scheduledAt;
  final bool isTest;
}

abstract interface class NotificationBackend {
  Future<bool> canPostNotifications();
  Future<bool> requestPermission();
  Future<void> openNotificationSettings();
  Future<void> schedule({
    required int id,
    required String channel,
    required String title,
    required String body,
    required String category,
    required int triggerAtMillis,
  });
  Future<void> showNow({
    required int id,
    required String channel,
    required String title,
    required String body,
    required String category,
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<String?> consumeInitialTap();
  void setTapHandler(void Function(String category)? onTap);
}

final class PlatformNotificationBackend implements NotificationBackend {
  static const _channel = MethodChannel(
    'com.shenmareparas.pathwise/notifications',
  );
  final bool _supported = !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> canPostNotifications() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canPost') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openNotificationSettings() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  @override
  Future<void> schedule({
    required int id,
    required String channel,
    required String title,
    required String body,
    required String category,
    required int triggerAtMillis,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('schedule', {
        'id': id,
        'channel': channel,
        'title': title,
        'body': body,
        'category': category,
        'triggerAt': triggerAtMillis,
      });
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  @override
  Future<void> showNow({
    required int id,
    required String channel,
    required String title,
    required String body,
    required String category,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('showNow', {
        'id': id,
        'channel': channel,
        'title': title,
        'body': body,
        'category': category,
      });
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  @override
  Future<String?> consumeInitialTap() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('consumeInitialTap');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void setTapHandler(void Function(String category)? onTap) {
    if (!_supported) return;
    if (onTap == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationTap') {
        final category = call.arguments;
        if (category is String && category.isNotEmpty) {
          onTap(category);
        }
      }
    });
  }
}

/// Pure adaptive timing & reminder planning logic.
final class AdaptiveNotificationScheduler {
  const AdaptiveNotificationScheduler();

  static bool isQuietMinute(int minuteOfDay, int quietStart, int quietEnd) {
    if (quietStart == quietEnd) return false;
    if (quietStart < quietEnd) {
      return minuteOfDay >= quietStart && minuteOfDay < quietEnd;
    }
    return minuteOfDay >= quietStart || minuteOfDay < quietEnd;
  }

  /// Picks a preferred reminder time (minutes since midnight) from recent
  /// gameplay timestamps, respecting quiet hours and falling back to
  /// [prefs.preferredMinutes] when fewer than 3 qualifying sessions exist.
  int chooseReminderMinutes(NotificationPreferences prefs, DateTime targetDay) {
    var chosen = prefs.preferredMinutes;
    if (prefs.adaptiveTiming && prefs.activityTimestamps.length >= 3) {
      final isWeekend = targetDay.weekday >= DateTime.saturday;
      final times = [
        for (final ms in prefs.activityTimestamps)
          DateTime.fromMillisecondsSinceEpoch(ms),
      ];
      final daySpecific = times
          .where((dt) => (dt.weekday >= DateTime.saturday) == isWeekend)
          .toList();
      final pool = daySpecific.length >= 6 ? daySpecific : times;
      final buckets = List<double>.filled(24, 0.0);
      for (var i = 0; i < pool.length; i++) {
        // Recent sessions weigh more than older ones.
        final weight = 0.6 + 0.4 * ((i + 1) / pool.length);
        buckets[pool[i].hour] += weight;
      }
      var bestHour = prefs.preferredMinutes ~/ 60;
      var bestScore = -1.0;
      for (var h = 0; h < 24; h++) {
        final minute = h * 60;
        if (isQuietMinute(
          minute,
          prefs.quietStartMinutes,
          prefs.quietEndMinutes,
        )) {
          continue;
        }
        if (buckets[h] > bestScore) {
          bestScore = buckets[h];
          bestHour = h;
        }
      }
      if (bestScore > 0) {
        // Remind ~15 minutes before the player's usual peak hour.
        chosen = (bestHour * 60 - 15) % (24 * 60);
        if (chosen < 0) chosen += 24 * 60;
      }
    }

    if (isQuietMinute(chosen, prefs.quietStartMinutes, prefs.quietEndMinutes)) {
      // Shift cleanly to the end of quiet hours.
      chosen = prefs.quietEndMinutes;
    }
    return chosen;
  }

  List<ScheduledNotificationInfo> plan({
    required NotificationPreferences prefs,
    required DateTime now,
    required bool dailySolvedToday,
    required int currentStreak,
    required bool streakQualifiedToday,
    required bool streakProtectedToday,
    required bool inGameplay,
  }) {
    if (!prefs.enabled) return const [];

    final planned = <ScheduledNotificationInfo>[];
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // Decide primary day for daily/streak reminder: today if not yet solved
    // and target time hasn't passed, otherwise tomorrow.
    final todayMinutes = chooseReminderMinutes(prefs, today);
    final todayCandidate = DateTime(
      today.year,
      today.month,
      today.day,
      todayMinutes ~/ 60,
      todayMinutes % 60,
    );
    final canScheduleToday =
        !inGameplay &&
        todayCandidate.isAfter(now.add(const Duration(minutes: 5)));

    // 1. Streak reminder (only when a streak genuinely exists and is not yet
    //    qualified or freeze-protected today).
    final streakAtRiskToday =
        prefs.streakReminder &&
        currentStreak > 0 &&
        !streakQualifiedToday &&
        !streakProtectedToday;

    if (streakAtRiskToday && canScheduleToday) {
      planned.add(
        ScheduledNotificationInfo(
          id: NotificationService.streakId,
          category: NotificationCategory.streak,
          channel: NotificationService.channelStreak,
          title: 'Keep your $currentStreak-day streak going',
          body: 'Solve a quick puzzle today to keep your streak alive.',
          scheduledAt: todayCandidate,
        ),
      );
      return planned;
    }

    // 2. Daily challenge reminder (suppressed for today when already solved).
    if (prefs.dailyReminder) {
      final targetDay = (!dailySolvedToday && canScheduleToday)
          ? today
          : tomorrow;
      final mins = chooseReminderMinutes(prefs, targetDay);
      final at = DateTime(
        targetDay.year,
        targetDay.month,
        targetDay.day,
        mins ~/ 60,
        mins % 60,
      );
      planned.add(
        ScheduledNotificationInfo(
          id: NotificationService.dailyId,
          category: NotificationCategory.daily,
          channel: NotificationService.channelDaily,
          title: 'Daily challenge ready',
          body: "Today's puzzle is ready. Can you solve it?",
          scheduledAt: at,
        ),
      );
    }

    // 3. Occasional friendly gameplay invitation (2 days out, only when not
    //    competing with a daily/streak reminder on the same day).
    if (prefs.inviteReminder) {
      final inviteDay = today.add(const Duration(days: 2));
      final mins = chooseReminderMinutes(prefs, inviteDay);
      final at = DateTime(
        inviteDay.year,
        inviteDay.month,
        inviteDay.day,
        mins ~/ 60,
        mins % 60,
      );
      const messages = [
        'Ready for a little brain exercise?',
        'Take a moment to unwind with a puzzle.',
        'Your next Pathwise puzzle is waiting.',
      ];
      final body =
          messages[(inviteDay.day + inviteDay.month) % messages.length];
      planned.add(
        ScheduledNotificationInfo(
          id: NotificationService.inviteId,
          category: NotificationCategory.invite,
          channel: NotificationService.channelInvites,
          title: 'Pathwise',
          body: body,
          scheduledAt: at,
        ),
      );
    }

    return planned;
  }
}

/// Offline-first local notification coordinator.
class NotificationService extends ChangeNotifier {
  NotificationService({
    NotificationBackend? backend,
    AdaptiveNotificationScheduler? scheduler,
    DateTime Function()? now,
  }) : _backend = backend ?? PlatformNotificationBackend(),
       _scheduler = scheduler ?? const AdaptiveNotificationScheduler(),
       _now = now ?? DateTime.now;

  static const int dailyId = 1001;
  static const int streakId = 1002;
  static const int inviteId = 1003;

  static const int testDailyId = 2001;
  static const int testStreakId = 2002;
  static const int testInviteId = 2003;
  static const int testDelayedId = 2004;

  static const String channelDaily = 'pathwise_daily';
  static const String channelStreak = 'pathwise_streak';
  static const String channelInvites = 'pathwise_invites';

  final NotificationBackend _backend;
  final AdaptiveNotificationScheduler _scheduler;
  final DateTime Function() _now;

  List<ScheduledNotificationInfo> _scheduled = const [];
  List<ScheduledNotificationInfo> get scheduled =>
      List.unmodifiable(_scheduled);
  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;
  String? _lastHandledTapSignature;

  void attachTapHandler(void Function(NotificationCategory category) onTap) {
    _backend.setTapHandler((raw) {
      final category = _parseCategory(raw);
      if (category != null) onTap(category);
    });
    unawaited(
      _backend.consumeInitialTap().then((raw) {
        if (raw == null) return;
        final sig = '$raw:${_now().millisecondsSinceEpoch ~/ 1000}';
        if (_lastHandledTapSignature == sig) return;
        _lastHandledTapSignature = sig;
        final category = _parseCategory(raw);
        if (category != null) onTap(category);
      }),
    );
  }

  static NotificationCategory? _parseCategory(String raw) => switch (raw) {
    'daily' => NotificationCategory.daily,
    'streak' => NotificationCategory.streak,
    'invite' => NotificationCategory.invite,
    _ => null,
  };

  Future<bool> refreshPermission() async {
    _permissionGranted = await _backend.canPostNotifications();
    notifyListeners();
    return _permissionGranted;
  }

  Future<bool> requestPermission() async {
    _permissionGranted = await _backend.requestPermission();
    notifyListeners();
    return _permissionGranted;
  }

  Future<void> openSystemSettings() => _backend.openNotificationSettings();

  int adaptiveMinutesFor(NotificationPreferences prefs, [DateTime? day]) =>
      _scheduler.chooseReminderMinutes(prefs, day ?? _now());

  Future<void> syncSchedule({
    required NotificationPreferences prefs,
    required bool dailySolvedToday,
    required int currentStreak,
    required bool streakQualifiedToday,
    required bool streakProtectedToday,
    required bool inGameplay,
  }) async {
    _permissionGranted = await _backend.canPostNotifications();
    final planned = _permissionGranted
        ? _scheduler.plan(
            prefs: prefs,
            now: _now(),
            dailySolvedToday: dailySolvedToday,
            currentStreak: currentStreak,
            streakQualifiedToday: streakQualifiedToday,
            streakProtectedToday: streakProtectedToday,
            inGameplay: inGameplay,
          )
        : const <ScheduledNotificationInfo>[];

    final activeIds = {for (final item in planned) item.id};
    for (final id in const [dailyId, streakId, inviteId]) {
      if (!activeIds.contains(id)) {
        await _backend.cancel(id);
      }
    }
    for (final item in planned) {
      await _backend.schedule(
        id: item.id,
        channel: item.channel,
        title: item.title,
        body: item.body,
        category: item.category.name,
        triggerAtMillis: item.scheduledAt.millisecondsSinceEpoch,
      );
    }
    _scheduled = planned;
    notifyListeners();
  }

  Future<void> sendTestNow(NotificationCategory category) async {
    final (id, channel, title, body) = _testPayload(category);
    await _backend.showNow(
      id: id,
      channel: channel,
      title: title,
      body: body,
      category: category.name,
    );
  }

  Future<void> scheduleTestDelayed(
    NotificationCategory category, {
    Duration delay = const Duration(seconds: 5),
  }) async {
    final (_, channel, title, body) = _testPayload(category);
    final at = _now().add(delay);
    await _backend.schedule(
      id: testDelayedId,
      channel: channel,
      title: '$title (Scheduled Test)',
      body: body,
      category: category.name,
      triggerAtMillis: at.millisecondsSinceEpoch,
    );
  }

  Future<void> cancelTestNotifications() async {
    for (final id in const [
      testDailyId,
      testStreakId,
      testInviteId,
      testDelayedId,
    ]) {
      await _backend.cancel(id);
    }
  }

  static (int, String, String, String) _testPayload(
    NotificationCategory category,
  ) => switch (category) {
    NotificationCategory.daily => (
      testDailyId,
      channelDaily,
      'Daily challenge ready (Test)',
      "Today's puzzle is ready. Can you solve it?",
    ),
    NotificationCategory.streak => (
      testStreakId,
      channelStreak,
      'Keep your streak going (Test)',
      'Solve a quick puzzle today to keep your streak alive.',
    ),
    NotificationCategory.invite => (
      testInviteId,
      channelInvites,
      'Pathwise (Test)',
      'Ready for a little brain exercise?',
    ),
  };

  @override
  void dispose() {
    _backend.setTapHandler(null);
    super.dispose();
  }
}
