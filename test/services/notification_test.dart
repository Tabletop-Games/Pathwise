import 'package:flutter_test/flutter_test.dart';

import '../../lib/logic/notification_service.dart';
import '../../lib/model/notification_preferences.dart';

final class _FakeNotificationBackend implements NotificationBackend {
  bool granted = true;
  final Map<int, ({String category, int triggerAt})> scheduled = {};
  final List<int> shownNow = [];
  final List<int> cancelled = [];

  @override
  Future<bool> canPostNotifications() async => granted;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> schedule({
    required int id,
    required String channel,
    required String title,
    required String body,
    required String category,
    required int triggerAtMillis,
  }) async {
    scheduled[id] = (category: category, triggerAt: triggerAtMillis);
  }

  @override
  Future<void> showNow({
    required int id,
    required String channel,
    required String title,
    required String body,
    required String category,
  }) async {
    shownNow.add(id);
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();

  @override
  Future<String?> consumeInitialTap() async => null;

  @override
  void setTapHandler(void Function(String category)? onTap) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'adaptive scheduler respects history, quiet hours, and suppression',
    () {
      const scheduler = AdaptiveNotificationScheduler();
      final prefs = NotificationPreferences(
        enabled: true,
        adaptiveTiming: true,
        preferredMinutes: 19 * 60,
        quietStartMinutes: 22 * 60,
        quietEndMinutes: 8 * 60,
      );
      // Insufficient history (<3) falls back to preferredMinutes.
      expect(
        scheduler.chooseReminderMinutes(prefs, DateTime(2026, 11, 27)),
        19 * 60,
      );

      // Record 4 sessions around 20:30 -> learns ~19:45 (15m before 20:00 hour).
      for (var d = 23; d <= 26; d++) {
        prefs.recordActivity(
          DateTime(2026, 11, d, 20, 30).millisecondsSinceEpoch,
        );
      }
      final learned = scheduler.chooseReminderMinutes(
        prefs,
        DateTime(2026, 11, 27),
      );
      expect(learned, 19 * 60 + 45);

      // Quiet hours shift late-night peak (23:30) to quietEndMinutes (08:00).
      final quietPrefs = NotificationPreferences(
        enabled: true,
        adaptiveTiming: true,
        quietStartMinutes: 22 * 60,
        quietEndMinutes: 8 * 60,
      );
      for (var d = 23; d <= 26; d++) {
        quietPrefs.recordActivity(
          DateTime(2026, 11, d, 23, 15).millisecondsSinceEpoch,
        );
      }
      expect(
        scheduler.chooseReminderMinutes(quietPrefs, DateTime(2026, 11, 27)),
        19 * 60,
      );

      // Streak at risk prioritizes streak reminder today.
      final streakPlan = scheduler.plan(
        prefs: prefs,
        now: DateTime(2026, 11, 27, 10, 0),
        dailySolvedToday: false,
        currentStreak: 5,
        streakQualifiedToday: false,
        streakProtectedToday: false,
        inGameplay: false,
      );
      expect(streakPlan.length, 1);
      expect(streakPlan.single.category, NotificationCategory.streak);

      // Qualified streak & solved daily schedules tomorrow's daily + invite.
      final donePlan = scheduler.plan(
        prefs: prefs,
        now: DateTime(2026, 11, 27, 10, 0),
        dailySolvedToday: true,
        currentStreak: 5,
        streakQualifiedToday: true,
        streakProtectedToday: false,
        inGameplay: false,
      );
      expect(
        donePlan.any((n) => n.category == NotificationCategory.streak),
        isFalse,
      );
      final daily = donePlan.firstWhere(
        (n) => n.category == NotificationCategory.daily,
      );
      expect(daily.scheduledAt.day, 28);
    },
  );

  test('NotificationService isolates test IDs and cancels cleanly', () async {
    final backend = _FakeNotificationBackend();
    final service = NotificationService(
      backend: backend,
      now: () => DateTime(2026, 11, 27, 12, 0),
    );
    await service.sendTestNow(NotificationCategory.daily);
    expect(backend.shownNow, [NotificationService.testDailyId]);

    await service.scheduleTestDelayed(NotificationCategory.daily);
    expect(
      backend.scheduled.containsKey(NotificationService.testDelayedId),
      isTrue,
    );

    await service.cancelTestNotifications();
    expect(
      backend.scheduled.containsKey(NotificationService.testDelayedId),
      isFalse,
    );
    service.dispose();
  });
}
