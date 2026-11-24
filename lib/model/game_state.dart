import '../logic/puzzle_generator.dart';

enum PlayMode { levels, daily, attack }

const legacyLevelCount = 36;
const levelsPerPage = 12;
const levelCount = 1000;
const dailyCheckpointCount = 3;

int pageForLevel(int level) => (level - 1) ~/ levelsPerPage;
int firstLevelOnPage(int page) => 1 + page * levelsPerPage;

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

  int get size => switch (mode) {
    PlayMode.levels =>
      level <= 30
          ? 4
          : level <= 100
          ? 5
          : level <= 300
          ? 6
          : 7,
    PlayMode.daily => checkpoint == null ? 6 : 3 + checkpoint!,
    PlayMode.attack => (4 + attackIndex ~/ 3).clamp(4, 7),
  };

  int get attackIndex => int.parse((value as String).split('/').last);
  bool get _variedAttack =>
      mode == PlayMode.attack && (value as String).startsWith('v2-');

  String? get layoutLabel => !_variedAttack || attackIndex < 3
      ? null
      : switch (attackIndex % 3) {
          0 => 'Guided checkpoints',
          1 => 'Sparse checkpoints',
          _ => 'Standard checkpoints',
        };

  int get level => value as int;

  ({int size, int seed, int clues}) get generation {
    if (mode == PlayMode.attack) {
      final baseline = [0, 0, 0, 0, 8, 10, 14, 16][size];
      final variation = switch (layoutLabel) {
        'Guided checkpoints' => 2,
        'Sparse checkpoints' => -2,
        _ => 0,
      };
      return (
        size: size,
        seed: puzzleSeed('pathwise-attack-${_variedAttack ? 'v2' : 'v1'}/$key'),
        clues: baseline + variation,
      );
    }
    if (mode == PlayMode.levels) {
      final baseline = [0, 0, 0, 0, 8, 11, 15, 18][size];
      final reduction = (level ~/ 200).clamp(0, 4);
      return (
        size: size,
        seed: puzzleSeed('pathwise-catalogue-v3/$key'),
        clues: baseline - reduction,
      );
    }
    final difficulty = mode == PlayMode.levels ? ((value as int) - 1) % 9 : 5;
    final targets = [0, 0, 0, 0, 7, 10, 14, 18];
    return (
      size: size,
      seed: puzzleSeed('pathwise-v1/$key'),
      clues: targets[size] + (difficulty < 3 ? 2 : (difficulty >= 7 ? -2 : 0)),
    );
  }
}

typedef RunResult = ({int milliseconds, int hints, bool unassisted});
