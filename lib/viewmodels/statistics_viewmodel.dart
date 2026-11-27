import 'dart:math' as math;

import '../model/app_model.dart';
import '../model/economy.dart';
import '../model/game_state.dart';
import '../model/journey.dart';
import '../model/time_attack.dart';
import '../model/user_preferences.dart';

final class AchievementProgressItem {
  const AchievementProgressItem({
    required this.achievement,
    required this.earned,
    required this.current,
    required this.target,
    required this.unitLabel,
  });

  final Achievement achievement;
  final bool earned;
  final int current;
  final int target;
  final String unitLabel;

  bool get inProgress => !earned && current > 0;
  double get fraction => target <= 0 ? 1.0 : (current / target).clamp(0.0, 1.0);
  String get progressText => '$current / $target $unitLabel';
}

/// Pure presentation-model snapshot for [StatisticsView].
/// Aggregates player metrics and achievement progress without widget coupling.
final class StatisticsSummary {
  const StatisticsSummary({
    required this.chapter,
    required this.chapterTitle,
    required this.currentLevel,
    required this.chapterProgress,
    required this.chapterCompleted,
    required this.chapterTotal,
    required this.totalSolved,
    required this.hintFree,
    required this.totalStars,
    required this.possibleStars,
    required this.threeStar,
    required this.twoStar,
    required this.oneStar,
    required this.zeroStar,
    required this.levelsSolved,
    required this.bestLevelTime,
    required this.dailySolved,
    required this.dailyStreak,
    required this.longestStreak,
    required this.longestPlayStreak,
    required this.bestDailyTime,
    required this.dayStreak,
    required this.playTime,
    required this.attackBestScore,
    required this.attackHighestClears,
    required this.attackBest1m,
    required this.attackBest3m,
    required this.attackBest5m,
    required this.recentAttackRuns,
    required this.ownedThemes,
    required this.totalThemes,
    required this.ownedTips,
    required this.totalTips,
    required this.achievements,
    required this.unlockedAchievements,
  });

  factory StatisticsSummary.fromModel(AppModel model) {
    final chapter = chapterFor(model.highestUnlocked);
    final chapterStart = chapter * chapterSize + 1;
    final completedInChapter = (model.highestUnlocked - chapterStart).clamp(
      0,
      chapterSize,
    );
    final stars = model.campaignStarStats;
    final achievements = [
      for (final item in Achievement.values) _buildAchievement(model, item),
    ];

    return StatisticsSummary(
      chapter: chapter,
      chapterTitle: chapterName(chapter),
      currentLevel: model.highestUnlocked,
      chapterProgress: completedInChapter / chapterSize,
      chapterCompleted: completedInChapter,
      chapterTotal: chapterSize,
      totalSolved: model.solved,
      hintFree: model.unassisted,
      totalStars: stars.totalStars,
      possibleStars: model.levelsSolved * 3,
      threeStar: stars.threeStar,
      twoStar: stars.twoStar,
      oneStar: stars.oneStar,
      zeroStar: stars.zeroStar,
      levelsSolved: model.levelsSolved,
      bestLevelTime: model.best(PlayMode.levels),
      dailySolved: model.dailySolved,
      dailyStreak: model.dailyStreak,
      longestStreak: model.longestStreak,
      longestPlayStreak: math.max(model.streak.longest, model.streak.count),
      bestDailyTime: model.best(PlayMode.daily),
      dayStreak: model.streak.count,
      playTime: model.playTime,
      attackBestScore: model.attackBest,
      attackHighestClears: model.attackHighest,
      attackBest1m: model.attackBestFor(1),
      attackBest3m: model.attackBestFor(3),
      attackBest5m: model.attackBestFor(5),
      recentAttackRuns: model.attackHistory.reversed.take(3).toList(),
      ownedThemes: model.ownedThemes,
      totalThemes: PathwiseTheme.values.length,
      ownedTips: model.ownedTipsCount,
      totalTips: PathTip.values.length,
      achievements: achievements,
      unlockedAchievements: achievements.where((a) => a.earned).length,
    );
  }

  final int chapter;
  final String chapterTitle;
  final int currentLevel;
  final double chapterProgress;
  final int chapterCompleted;
  final int chapterTotal;

  final int totalSolved;
  final int hintFree;
  final int totalStars;
  final int possibleStars;
  final int threeStar;
  final int twoStar;
  final int oneStar;
  final int zeroStar;
  final int levelsSolved;
  final Duration? bestLevelTime;

  final int dailySolved;
  final int dailyStreak;
  final int longestStreak;
  final int longestPlayStreak;
  final Duration? bestDailyTime;
  final int dayStreak;
  final Duration playTime;

  final int attackBestScore;
  final int attackHighestClears;
  final int attackBest1m;
  final int attackBest3m;
  final int attackBest5m;
  final List<AttackRun> recentAttackRuns;

  final int ownedThemes;
  final int totalThemes;
  final int ownedTips;
  final int totalTips;

  final List<AchievementProgressItem> achievements;
  final int unlockedAchievements;

  static AchievementProgressItem _buildAchievement(
    AppModel model,
    Achievement item,
  ) {
    final earned = model.hasAchievement(item);
    final (int raw, int target, String unit) = switch (item) {
      Achievement.trailhead => (model.levelsSolved, 1, 'level'),
      Achievement.trailblazer => (model.levelsSolved, 12, 'levels'),
      Achievement.pathfinder => (model.levelsSolved, 50, 'levels'),
      Achievement.twentyFive => (model.levelsSolved, 25, 'levels'),
      Achievement.hundred => (model.levelsSolved, 100, 'levels'),
      Achievement.fiveHundred => (model.levelsSolved, 500, 'levels'),
      Achievement.thousand => (model.levelsSolved, 1000, 'levels'),
      Achievement.dailyHabit => (model.longestStreak, 3, 'days'),
      Achievement.weeklyRitual => (model.longestStreak, 7, 'days'),
      Achievement.unaided => (model.unassisted, 10, 'puzzles'),
      Achievement.collector => (model.ownedThemes, 6, 'themes'),
      Achievement.timeTrial => (model.attackHighest, 3, 'clears'),
      Achievement.researcher => (model.researchRankCount, 10, 'ranks'),
      Achievement.legendaryCrate => (
        model.progression.legendary > 0 ? 1 : 0,
        1,
        'crate',
      ),
    };
    return AchievementProgressItem(
      achievement: item,
      earned: earned,
      current: earned ? target : raw.clamp(0, target),
      target: target,
      unitLabel: unit,
    );
  }
}
