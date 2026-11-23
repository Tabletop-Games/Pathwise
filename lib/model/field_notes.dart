enum NoteGoal {
  solve('First-time puzzle clears', 3),
  clean('Hint-free first clears', 2),
  trail('New Expedition stages', 1),
  crate('Supply crates collected', 1);

  const NoteGoal(this.title, this.target);
  final String title;
  final int target;
}

int noteDay(DateTime date) => date.toUtc().millisecondsSinceEpoch ~/ 86400000;

final class FieldNotes {
  FieldNotes(Map data)
    : day = data['day'] as int? ?? -1,
      week = data['week'] as int? ?? -1,
      weekly = data['weekly'] as int? ?? 0,
      claimed = data['claimed'] as int? ?? 0,
      weeklyClaimed = data['weeklyClaimed'] == true,
      daily = Map<String, int>.from(data['daily'] as Map? ?? {});

  static const dailyCoins = 9;
  static const weeklyCoins = 55;
  static const weeklyTarget = 16;
  int day, week, weekly, claimed;
  bool weeklyClaimed;
  final Map<String, int> daily;

  static int weekFor(int day) => (day + 3) ~/ 7;

  static Iterable<NoteGoal> goals(int day) => NoteGoal.values.where(
    (goal) => goal.index != day % NoteGoal.values.length,
  );

  int count(NoteGoal goal, int today) =>
      today == day ? daily[goal.name] ?? 0 : 0;

  bool wasClaimed(NoteGoal? goal, int today) => goal == null
      ? week == weekFor(today) && weeklyClaimed
      : today == day && (claimed & (1 << goal.index)) != 0;

  bool claimable(NoteGoal? goal, int today) =>
      !wasClaimed(goal, today) &&
      (goal == null
          ? week == weekFor(today) && weekly >= weeklyTarget
          : goals(today).contains(goal) && count(goal, today) >= goal.target);

  void markClaimed(NoteGoal? goal) {
    if (goal == null) {
      weeklyClaimed = true;
    } else {
      claimed |= 1 << goal.index;
    }
  }

  int observe(int today, Set<NoteGoal> events) {
    if (today < day) return 0;
    if (today > day) {
      day = today;
      daily.clear();
      claimed = 0;
    }
    if (week != weekFor(today)) {
      week = weekFor(today);
      weekly = 0;
      weeklyClaimed = false;
    }
    var completed = 0;
    for (final goal in goals(today).where(events.contains)) {
      final prior = daily[goal.name] ?? 0;
      if (prior >= goal.target) continue;
      daily[goal.name] = prior + 1;
      if (prior + 1 == goal.target) completed++;
    }
    if (events.contains(NoteGoal.solve) && weekly < weeklyTarget) {
      weekly++;
      if (weekly == weeklyTarget) completed++;
    }
    return completed;
  }

  Map<String, Object> toJson() => {
    'day': day,
    'week': week,
    'weekly': weekly,
    'daily': daily,
    'claimed': claimed,
    'weeklyClaimed': weeklyClaimed,
  };
}
