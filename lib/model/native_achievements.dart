enum AchievementMetric {
  solves,
  hintFree,
  precision,
  daily,
  attackFinished,
  attackScore,
  research,
  themes,
  crates,
}

final class NativeAchievement {
  const NativeAchievement(
    this.id,
    this.name,
    this.description,
    this.metric,
    this.target, {
    this.incremental = false,
    this.hidden = false,
  });

  final String id, name, description;
  final AchievementMetric metric;
  final int target;
  final bool incremental, hidden;

  int progress(Map<AchievementMetric, int> counters) =>
      (counters[metric] ?? 0).clamp(0, target);
  bool earned(Map<AchievementMetric, int> counters) =>
      progress(counters) == target;
}

const nativeAchievements = [
  NativeAchievement(
    'firstSteps',
    'First Steps',
    'Solve your first progression puzzle.',
    AchievementMetric.solves,
    1,
  ),
  NativeAchievement(
    'gettingStarted',
    'Getting Started',
    'Solve 10 progression puzzles.',
    AchievementMetric.solves,
    10,
    incremental: true,
  ),
  NativeAchievement(
    'apprentice',
    'Puzzle Apprentice',
    'Solve 50 progression puzzles.',
    AchievementMetric.solves,
    50,
    incremental: true,
  ),
  NativeAchievement(
    'enthusiast',
    'Puzzle Enthusiast',
    'Solve 100 progression puzzles.',
    AchievementMetric.solves,
    100,
    incremental: true,
  ),
  NativeAchievement(
    'expert',
    'Puzzle Expert',
    'Solve 500 progression puzzles.',
    AchievementMetric.solves,
    500,
    incremental: true,
  ),
  NativeAchievement(
    'master',
    'Puzzle Master',
    'Solve 1,000 progression puzzles.',
    AchievementMetric.solves,
    1000,
    incremental: true,
  ),
  NativeAchievement(
    'legend',
    'Puzzle Legend',
    'Solve 5,000 progression puzzles.',
    AchievementMetric.solves,
    5000,
    incremental: true,
  ),
  NativeAchievement(
    'immortal',
    'Puzzle Immortal',
    'Solve 10,000 progression puzzles.',
    AchievementMetric.solves,
    10000,
    incremental: true,
    hidden: true,
  ),
  NativeAchievement(
    'independent',
    'Independent Thinker',
    'Solve a progression puzzle without hints.',
    AchievementMetric.hintFree,
    1,
  ),
  NativeAchievement(
    'cleanSweep',
    'Clean Sweep',
    'Solve 25 progression puzzles without hints.',
    AchievementMetric.hintFree,
    25,
    incremental: true,
  ),
  NativeAchievement(
    'untouchable',
    'Untouchable',
    'Solve 100 progression puzzles without hints.',
    AchievementMetric.hintFree,
    100,
    incremental: true,
  ),
  NativeAchievement(
    'pureLogic',
    'Pure Logic',
    'Solve 500 progression puzzles without hints.',
    AchievementMetric.hintFree,
    500,
    incremental: true,
  ),
  NativeAchievement(
    'firstTry',
    'First-Try Genius',
    'Solve a fresh progression puzzle without using Clear or hints.',
    AchievementMetric.precision,
    1,
  ),
  NativeAchievement(
    'precision',
    'Perfect Precision',
    'Solve 100 fresh progression puzzles without using Clear or hints.',
    AchievementMetric.precision,
    100,
    incremental: true,
  ),
  NativeAchievement(
    'dailyDiscovery',
    'Daily Discovery',
    'Solve your first eligible Daily Challenge.',
    AchievementMetric.daily,
    1,
  ),
  NativeAchievement(
    'dailyRoutine',
    'Daily Routine',
    'Solve 7 eligible Daily Challenges.',
    AchievementMetric.daily,
    7,
    incremental: true,
  ),
  NativeAchievement(
    'dailyDevotion',
    'Daily Devotion',
    'Solve 30 eligible Daily Challenges.',
    AchievementMetric.daily,
    30,
    incremental: true,
  ),
  NativeAchievement(
    'dailyVeteran',
    'Daily Veteran',
    'Solve 100 eligible Daily Challenges.',
    AchievementMetric.daily,
    100,
    incremental: true,
  ),
  NativeAchievement(
    'dailyLegend',
    'Daily Legend',
    'Solve 365 eligible Daily Challenges.',
    AchievementMetric.daily,
    365,
    incremental: true,
    hidden: true,
  ),
  NativeAchievement(
    'againstTheClock',
    'Against the Clock',
    'Finish a Time Attack session with at least one solve.',
    AchievementMetric.attackFinished,
    1,
  ),
  NativeAchievement(
    'quickDraw',
    'Quick Draw',
    'Score 300 points in a single Time Attack session.',
    AchievementMetric.attackScore,
    300,
  ),
  NativeAchievement(
    'speedSolver',
    'Speed Solver',
    'Score 600 points in a single Time Attack session.',
    AchievementMetric.attackScore,
    600,
  ),
  NativeAchievement(
    'timeLord',
    'Time Lord',
    'Score 1,000 points in a single Time Attack session.',
    AchievementMetric.attackScore,
    1000,
    hidden: true,
  ),
  NativeAchievement(
    'firstInvestment',
    'First Investment',
    'Purchase your first Research rank.',
    AchievementMetric.research,
    1,
  ),
  NativeAchievement(
    'researcher',
    'Researcher',
    'Purchase 25 Research ranks.',
    AchievementMetric.research,
    25,
    incremental: true,
  ),
  NativeAchievement(
    'masterResearcher',
    'Master Researcher',
    'Purchase 100 Research ranks.',
    AchievementMetric.research,
    100,
    incremental: true,
  ),
  NativeAchievement(
    'themeCollector',
    'Theme Collector',
    'Individually unlock 5 themes through Themes.',
    AchievementMetric.themes,
    5,
    incremental: true,
  ),
  NativeAchievement(
    'styleMaster',
    'Style Master',
    'Individually unlock 15 themes through Themes.',
    AchievementMetric.themes,
    15,
    incremental: true,
  ),
  NativeAchievement(
    'luckyFind',
    'Lucky Find',
    'Collect a Legendary supply crate.',
    AchievementMetric.crates,
    1,
    hidden: true,
  ),
];

/// Counters that older saves could not reconstruct from aggregate records.
final class AchievementLedger {
  AchievementLedger(Map<String, dynamic> json)
    : precision = _count(json['precision']),
      eligibleDailies = _count(json['eligibleDailies']),
      lastDaily = json['lastDaily'] is String
          ? json['lastDaily'] as String
          : null,
      dailyBoot = _count(json['dailyBoot']),
      dailyTime = _count(json['dailyTime']),
      owner = json['owner'] is String ? json['owner'] as String : null {
    final saved = json['confirmed'];
    if (saved is! Map) return;
    for (final entry in saved.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is Map) {
        confirmed[key] = {
          for (final row in value.entries)
            if (row.key is String && row.value is int)
              row.key as String: _count(row.value),
        };
      }
    }
  }

  static int _count(Object? value) => value is int && value > 0 ? value : 0;

  int precision, eligibleDailies;
  String? lastDaily, owner;
  int dailyBoot, dailyTime;
  final confirmed = <String, Map<String, int>>{};

  void daily(String date, ({int boot, int milliseconds})? now) {
    if (now == null || now.boot < 0) return;
    final previous = lastDaily;
    if (previous != null) {
      if (date.compareTo(previous) <= 0 || now.boot < dailyBoot) return;
      final lowerBound = now.boot == dailyBoot
          ? now.milliseconds - dailyTime
          : now.milliseconds;
      if (lowerBound < const Duration(hours: 20).inMilliseconds) return;
    }
    eligibleDailies++;
    lastDaily = date;
    dailyBoot = now.boot;
    dailyTime = now.milliseconds;
  }

  void confirm(String account, Map<String, int> progress) {
    confirmed.remove(account);
    confirmed[account] = Map.of(progress);
    while (confirmed.length > 3) {
      confirmed.remove(confirmed.keys.first);
    }
  }

  Map<String, Object?> toJson() => {
    'precision': precision,
    'eligibleDailies': eligibleDailies,
    'lastDaily': lastDaily,
    'dailyBoot': dailyBoot,
    'dailyTime': dailyTime,
    'confirmed': confirmed,
    'owner': owner,
  };
}
