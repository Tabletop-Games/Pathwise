import '../logic/puzzle_generator.dart';

enum PlayMode { levels, daily, endless }

const levelCount = 36;

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final class PuzzleId {
  const PuzzleId._(this.mode, this.value);

  const PuzzleId.level(int number) : this._(PlayMode.levels, number);
  const PuzzleId.daily(String day) : this._(PlayMode.daily, day);
  const PuzzleId.endless(int number) : this._(PlayMode.endless, number);

  final PlayMode mode;
  final Object value;
  String get key => '${mode.name}/$value';

  String get title => switch (mode) {
    PlayMode.levels => 'Level $value',
    PlayMode.daily => 'Daily challenge',
    PlayMode.endless => 'Endless · $value',
  };

  int get size => switch (mode) {
    PlayMode.levels => 4 + (((value as int) - 1) ~/ 9),
    PlayMode.daily => 6,
    PlayMode.endless => 5 + (((value as int) - 1) % 3),
  };

  ({int size, int seed, int clues}) get generation {
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
