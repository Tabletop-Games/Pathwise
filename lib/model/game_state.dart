import '../logic/puzzle_generator.dart';

enum PlayMode { levels, daily, endless, attack }

const legacyLevelCount = 36;
const levelsPerPage = 12;

int pageForLevel(int level) => (level - 1) ~/ levelsPerPage;
int firstLevelOnPage(int page) => 1 + page * levelsPerPage;

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final class PuzzleId {
  const PuzzleId._(this.mode, this.value);

  const PuzzleId.level(int number) : this._(PlayMode.levels, number);
  const PuzzleId.daily(String day) : this._(PlayMode.daily, day);
  const PuzzleId.endless(int number) : this._(PlayMode.endless, number);

  const PuzzleId.attack(String key) : this._(PlayMode.attack, key);

  final PlayMode mode;
  final Object value;
  String get key => '${mode.name}/$value';

  String get title => switch (mode) {
    PlayMode.attack => 'Time Attack',
    PlayMode.levels => 'Level $value',
    PlayMode.daily => 'Daily challenge',
    PlayMode.endless => 'Endless · $value',
  };

  int get size => switch (mode) {
    PlayMode.levels => level <= legacyLevelCount ? 4 + ((level - 1) ~/ 9) : 7,
    PlayMode.daily => 6,
    PlayMode.attack => (4 + attackIndex ~/ 3).clamp(4, 7),
    PlayMode.endless => 5 + (((value as int) - 1) % 3),
  };

  int get attackIndex => int.parse((value as String).split('/').last);
  int get level => value as int;

  ({int size, int seed, int clues}) get generation {
    if (mode == PlayMode.attack) {
      return (
        size: size,
        seed: puzzleSeed('pathwise-attack-v1/$key'),
        clues: [0, 0, 0, 0, 8, 10, 14, 16][size],
      );
    }
    if (mode == PlayMode.levels && level > legacyLevelCount) {
      // Higher bands ask players to infer longer sections between clues.
      // The generator keeps additional clues whenever uniqueness requires them.
      final removed = switch (level) {
        < 100 => 1,
        < 150 => 2,
        < 300 => 3,
        < 500 => 4,
        < 1000 => 5,
        _ => 6,
      };
      return (
        size: size,
        seed: puzzleSeed('pathwise-v2/$key'),
        clues: 17 - removed,
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
