import '../logic/engine/schedule.dart';
import '../logic/engine/spec.dart';

enum PlayMode { levels, daily, attack }

const dailyCheckpointCount = 3;

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final class PuzzleId {
  const PuzzleId._(this.mode, this.value, [this.checkpoint]);

  const PuzzleId.level(int number) : this._(PlayMode.levels, number);
  const PuzzleId.daily(String day) : this._(PlayMode.daily, day);
  const PuzzleId.dailyCheckpoint(String day, int number)
    : this._(PlayMode.daily, day, number);
  const PuzzleId.attack(String key) : this._(PlayMode.attack, key);

  final PlayMode mode;
  final Object value;
  final int? checkpoint;
  String get key => checkpoint == null
      ? '${mode.name}/$value'
      : 'daily-checkpoint/$value/$checkpoint';

  String get title => switch (mode) {
    PlayMode.attack => 'Time Attack',
    PlayMode.levels => 'Level $value',
    PlayMode.daily =>
      checkpoint == null
          ? 'Daily challenge'
          : 'Daily · $checkpoint/$dailyCheckpointCount',
  };

  /// The generation spec: board size, difficulty band, structure and
  /// mechanics. It depends only on the identity, never on the player.
  PuzzleSpec get spec => switch (mode) {
    PlayMode.levels => campaignSpec(level),
    PlayMode.daily => dailySpec(value as String, checkpoint),
    PlayMode.attack => attackSpec(value as String, attackIndex),
  };

  int get size => spec.size;

  int get attackIndex => int.parse((value as String).split('/').last);
  String? get layoutLabel => mode != PlayMode.attack || attackIndex < 3
      ? null
      : switch (attackIndex % 3) {
          0 => 'Guided checkpoints',
          1 => 'Sparse checkpoints',
          _ => 'Standard checkpoints',
        };

  int get level => value as int;
}

typedef RunResult = ({int milliseconds, int hints, bool unassisted});
