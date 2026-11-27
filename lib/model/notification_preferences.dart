/// Preferences and bounded activity timestamps for adaptive local notifications.
class NotificationPreferences {
  NotificationPreferences({
    this.enabled = false,
    this.dailyReminder = true,
    this.streakReminder = true,
    this.inviteReminder = true,
    this.adaptiveTiming = true,
    this.preferredMinutes = 19 * 60,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 8 * 60,
    this.permissionAsked = false,
    List<int>? activityTimestamps,
  }) : activityTimestamps = List<int>.from(activityTimestamps ?? const []);

  static const int maxActivityHistory = 40;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    int clampMinutes(Object? raw, int fallback) =>
        raw is int ? raw.clamp(0, 23 * 60 + 59) : fallback;

    final rawHistory = json['activityTimestamps'];
    final history = <int>[
      if (rawHistory is List)
        for (final item in rawHistory.whereType<int>()) item,
    ];
    if (history.length > maxActivityHistory) {
      history.removeRange(0, history.length - maxActivityHistory);
    }

    return NotificationPreferences(
      enabled: json['enabled'] == true,
      dailyReminder: json['dailyReminder'] != false,
      streakReminder: json['streakReminder'] != false,
      inviteReminder: json['inviteReminder'] != false,
      adaptiveTiming: json['adaptiveTiming'] != false,
      preferredMinutes: clampMinutes(json['preferredMinutes'], 19 * 60),
      quietStartMinutes: clampMinutes(json['quietStartMinutes'], 22 * 60),
      quietEndMinutes: clampMinutes(json['quietEndMinutes'], 8 * 60),
      permissionAsked: json['permissionAsked'] == true,
      activityTimestamps: history,
    );
  }

  bool enabled;
  bool dailyReminder;
  bool streakReminder;
  bool inviteReminder;
  bool adaptiveTiming;
  int preferredMinutes;
  int quietStartMinutes;
  int quietEndMinutes;
  bool permissionAsked;
  final List<int> activityTimestamps;

  void recordActivity(int epochMillis) {
    if (activityTimestamps.isNotEmpty &&
        (epochMillis - activityTimestamps.last).abs() < 10 * 60 * 1000) {
      return;
    }
    activityTimestamps.add(epochMillis);
    if (activityTimestamps.length > maxActivityHistory) {
      activityTimestamps.removeRange(
        0,
        activityTimestamps.length - maxActivityHistory,
      );
    }
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'dailyReminder': dailyReminder,
    'streakReminder': streakReminder,
    'inviteReminder': inviteReminder,
    'adaptiveTiming': adaptiveTiming,
    'preferredMinutes': preferredMinutes,
    'quietStartMinutes': quietStartMinutes,
    'quietEndMinutes': quietEndMinutes,
    'permissionAsked': permissionAsked,
    'activityTimestamps': List<int>.from(activityTimestamps),
  };
}
