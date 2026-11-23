import 'game_state.dart';

class PlayStreak {
  PlayStreak(Map data)
    : count = data['count'] as int? ?? 0,
      longest = data['longest'] as int? ?? 0,
      freezes = data['freezes'] as int? ?? 0,
      first = data['first'] as String?,
      lastEarned = data['lastEarned'] as String?,
      checkedThrough = data['checkedThrough'] as String?,
      days = Map<String, String>.from(data['days'] as Map? ?? {});

  int count, longest, freezes;
  String? first, lastEarned, checkedThrough;
  final Map<String, String> days;

  static DateTime calendarDate(String day) =>
      DateTime.parse('${day}T00:00:00Z');

  void reconcile(String today) {
    final checked = checkedThrough;
    if (checked == null || checked.compareTo(today) >= 0) return;
    var cursor = calendarDate(checked).add(const Duration(days: 1));
    final target = calendarDate(today);
    while (cursor.isBefore(target) && count > 0) {
      if (freezes == 0) {
        count = 0;
        first = null;
        break;
      }
      freezes--;
      days[dayKey(cursor)] = 'protected';
      cursor = cursor.add(const Duration(days: 1));
    }
    final yesterday = dayKey(target.subtract(const Duration(days: 1)));
    if (yesterday.compareTo(checked) > 0) checkedThrough = yesterday;
  }

  bool qualify(String today) {
    if (lastEarned case final last? when last.compareTo(today) >= 0) {
      return false;
    }
    if (checkedThrough case final checked? when checked.compareTo(today) >= 0) {
      return false;
    }
    reconcile(today);
    first ??= today;
    lastEarned = checkedThrough = today;
    days[today] = 'played';
    count++;
    if (count > longest) longest = count;
    final cutoff = dayKey(
      calendarDate(today).subtract(const Duration(days: 14)),
    );
    days.removeWhere((day, _) => day.compareTo(cutoff) < 0);
    return true;
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'longest': longest,
    'freezes': freezes,
    'first': first,
    'lastEarned': lastEarned,
    'checkedThrough': checkedThrough,
    'days': days,
  };
}
