import 'dart:math';

import 'economy.dart';

/// Elapsed milliseconds since Android boot, including time spent asleep.
typedef BootTime = ({int boot, int milliseconds});

final class AttackRun {
  AttackRun(
    this.id,
    this.boot,
    this.deadline,
    this.puzzleStarted,
    this.previousBest, {
    this.minutes = 3,
    this.unassisted = true,
    List<int>? clears,
    this.finished = false,
    this.coins = 0,
  }) : clears = clears ?? [];

  factory AttackRun.fromJson(Map data) => AttackRun(
    data['id'] as String,
    data['boot'] as int,
    data['deadline'] as int,
    data['puzzleStarted'] as int,
    data['previousBest'] as int,
    minutes: data['minutes'] as int? ?? 10,
    unassisted: data['unassisted'] == true,
    clears: List<int>.from(data['clears'] as List),
    finished: data['finished'] == true,
    coins: data['coins'] as int? ?? 0,
  );

  static const duration = Duration(minutes: 3);
  final String id;
  final int boot, deadline, previousBest, minutes;
  int puzzleStarted;
  final List<int> clears;
  bool finished;
  bool unassisted;
  int coins;
  int get score => clears.length * 100;
  int get average =>
      clears.isEmpty ? 0 : clears.reduce((a, b) => a + b) ~/ clears.length;
  int get fastest => clears.isEmpty ? 0 : clears.reduce(min);
  int get reward => economy.attackReward(clears.length);
  bool get canRank => finished && unassisted && score > 0;
  bool get record => score > previousBest;
  int remaining(BootTime now) => finished || now.boot != boot
      ? 0
      : (deadline - now.milliseconds).clamp(
          0,
          Duration(minutes: minutes).inMilliseconds,
        );
  bool clear(BootTime now) {
    if (remaining(now) == 0) return false;
    clears.add(max(0, now.milliseconds - puzzleStarted));
    puzzleStarted = now.milliseconds;
    return true;
  }

  Map<String, Object> toJson() => {
    'id': id,
    'boot': boot,
    'minutes': minutes,
    'unassisted': unassisted,
    'deadline': deadline,
    'puzzleStarted': puzzleStarted,
    'clears': clears,
    'previousBest': previousBest,
    'finished': finished,
    'coins': coins,
  };
}
