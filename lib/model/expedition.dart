import '../logic/puzzle_generator.dart';

extension type const Trail(int number) {
  static const foothills = Trail(1);
  static const ridgeline = Trail(2);
  static const summit = Trail(3);
  static const stages = 10;
  static const requiredMarks = 2;

  String? get legacyName => switch (number) {
    1 => 'foothills',
    2 => 'ridgeline',
    3 => 'summit',
    _ => null,
  };
  static Trail? legacy(String? name) => switch (name) {
    'foothills' => foothills,
    'ridgeline' => ridgeline,
    'summit' => summit,
    _ => null,
  };

  int get seed => puzzleSeed('pathwise-trail-v2/$number');
  int get biome => seed % 5;
  Trail get next => Trail(number + 1);
  String get title => switch (number) {
    1 => 'Foothills',
    2 => 'Ridgeline',
    3 => 'Summit',
    _ =>
      '${['Mist', 'Copper', 'Still', 'Dawn', 'Slate', 'Amber', 'Wind', 'Silver'][(seed ~/ 5) % 8]} '
          '${['Basin', 'Mesa', 'Grove', 'Pass', 'Bluffs'][biome]}',
  };

  int get band => switch (number) {
    <= 3 => 0,
    <= 10 => 1,
    <= 25 => 2,
    <= 50 => 3,
    <= 100 => 4,
    _ => 5,
  };
  String get difficultyLabel => [
    'Introduction',
    'Exploration',
    'Developing mastery',
    'Advanced',
    'Expert',
    'Sustained mastery',
  ][band];

  ({int size, int clues}) difficulty(int stage) {
    final section = stage < 3
        ? 0
        : stage < 7
        ? 1
        : 2;
    if (number <= 3) {
      final index = number - 1;
      final size = (index + section + 4).clamp(4, 7);
      final base = [0, 0, 0, 0, 11, 15, 19, 23][size];
      final firstAtSize = index == 2 && section == 2 ? 3 : [0, 3, 7][section];
      return (
        size: size,
        clues: base - (stage - firstAtSize) - index * 2 - section,
      );
    }
    final size = (5 + section + (band >= 2 ? 1 : 0)).clamp(5, 7);
    final densityTarget = [0, 0, 0, 0, 0, 13, 17, 20][size];
    return (
      size: size,
      clues: (densityTarget - band - (stage % 3) - section + seed % 3 - 1)
          .clamp(11, densityTarget),
    );
  }

  Map<int, FieldMark> get objectives {
    if (legacyName != null) {
      return {
        1: FieldMark.noHint,
        3: FieldMark.noClear,
        6: FieldMark.noHint,
        8: FieldMark.noClear,
      };
    }
    return {
      for (final (index, start) in [1, 3, 6, 8].indexed)
        start + ((seed >> index) & 1):
            FieldMark.values[(index + seed) % FieldMark.values.length],
    };
  }
}

enum FieldMark {
  noHint('Solve without hints'),
  noClear('Solve without Clear'),
  noUndo('Solve without Undo'),
  clean('Solve without hints or Clear');

  const FieldMark(this.label);
  final String label;

  bool earned({required bool hint, required bool clear, required bool undo}) =>
      switch (this) {
        noHint => !hint,
        noClear => !clear,
        noUndo => !undo,
        clean => !hint && !clear,
      };
}

enum ExpeditionOutcome { active, qualified, missedMarks, abandoned }

final class ExpeditionRun {
  ExpeditionRun(this.trail, this.serial);

  factory ExpeditionRun.fromJson(Map data) {
    final run =
        ExpeditionRun(
            data['trail'] is int
                ? Trail(data['trail'] as int)
                : Trail.legacy(data['trail'] as String)!,
            data['serial'] as int,
          )
          ..stage = data['stage'] as int
          ..marks = Set<int>.from(data['marks'] as List)
          ..milliseconds = data['milliseconds'] as int
          ..usedClear = data['usedClear'] == true
          ..usedUndo = data['usedUndo'] == true
          ..cleanStages = data['cleanStages'] as int? ?? 0
          ..personalBest = data['personalBest'] == true
          ..coins = data['coins'] as int
          ..milestoneCoins = data['milestoneCoins'] as int? ?? 0
          ..outcome = ExpeditionOutcome.values.byName(
            data['outcome'] as String,
          );
    if (run.trail.number < 1 ||
        run.serial < 0 ||
        run.stage < 0 ||
        run.stage > Trail.stages ||
        run.milliseconds < 0 ||
        run.coins < 0 ||
        run.marks.any(
          (stage) =>
              stage < 0 ||
              stage >= run.stage ||
              !run.trail.objectives.containsKey(stage),
        ) ||
        (run.stage == Trail.stages) !=
            (run.outcome == ExpeditionOutcome.qualified ||
                run.outcome == ExpeditionOutcome.missedMarks) ||
        (run.outcome == ExpeditionOutcome.qualified &&
            run.marks.length < Trail.requiredMarks) ||
        (run.outcome == ExpeditionOutcome.missedMarks &&
            run.marks.length >= Trail.requiredMarks)) {
      throw const FormatException('Invalid saved expedition run');
    }
    return run;
  }

  final Trail trail;
  final int serial;
  int stage = 0;
  Set<int> marks = {};
  int milliseconds = 0;
  bool usedClear = false;
  bool usedUndo = false;
  int cleanStages = 0;
  bool personalBest = false;
  int coins = 0;
  int milestoneCoins = 0;
  ExpeditionOutcome outcome = ExpeditionOutcome.active;

  bool get active => outcome == ExpeditionOutcome.active;

  void finishStage(int time, {required bool usedHint}) {
    if (!active) return;
    if (trail.objectives[stage]?.earned(
          hint: usedHint,
          clear: usedClear,
          undo: usedUndo,
        ) ==
        true)
      marks.add(stage);
    if (!usedHint && !usedClear && !usedUndo) cleanStages++;
    milliseconds += time;
    usedClear = false;
    usedUndo = false;
    stage++;
    if (stage == Trail.stages) {
      outcome = marks.length >= Trail.requiredMarks
          ? ExpeditionOutcome.qualified
          : ExpeditionOutcome.missedMarks;
    }
  }

  Map<String, Object> toJson() => {
    'trail': trail.number,
    'serial': serial,
    'stage': stage,
    'marks': marks.toList(),
    'milliseconds': milliseconds,
    'usedClear': usedClear,
    'usedUndo': usedUndo,
    'cleanStages': cleanStages,
    'personalBest': personalBest,
    'coins': coins,
    'milestoneCoins': milestoneCoins,
    'outcome': outcome.name,
  };
}

final class TrailRecord {
  TrailRecord({this.deepest = 0, this.marks = 0, this.fastest});
  factory TrailRecord.fromJson(Map data) => TrailRecord(
    deepest: data['deepest'] as int,
    marks: data['marks'] as int,
    fastest: data['fastest'] as int?,
  );

  int deepest;
  int marks;
  int? fastest;

  void merge(TrailRecord record) {
    if (record.deepest > deepest) deepest = record.deepest;
    if (record.marks > marks) marks = record.marks;
    if (record.fastest case final time?) {
      if (fastest == null || time < fastest!) fastest = time;
    }
  }

  void record(ExpeditionRun run) {
    if (run.stage > deepest) deepest = run.stage;
    if (run.marks.length > marks) marks = run.marks.length;
    if (run.outcome == ExpeditionOutcome.qualified &&
        (fastest == null || run.milliseconds < fastest!)) {
      fastest = run.milliseconds;
    }
  }

  Map<String, Object?> toJson() => {
    'deepest': deepest,
    'marks': marks,
    'fastest': fastest,
  };
}
