enum Trail {
  foothills('Foothills'),
  ridgeline('Ridgeline'),
  summit('Summit');

  const Trail(this.title);
  final String title;
  static const stages = 10;
  static const requiredMarks = 2;

  ({int size, int clues}) difficulty(int stage) {
    final band = switch (stage) {
      < 3 => 0,
      < 7 => 1,
      _ => 2,
    };
    final size = (index + band + 4).clamp(4, 7);
    final base = [0, 0, 0, 0, 11, 15, 19, 23][size];
    final firstAtSize = index == 2 && band == 2 ? 3 : [0, 3, 7][band];
    final withinBand = stage - firstAtSize;
    return (size: size, clues: base - withinBand - index * 2 - band);
  }
}

enum FieldMark {
  noHint('Solve without hints'),
  noClear('Solve without Clear');

  const FieldMark(this.label);
  final String label;

  static FieldMark? at(int stage) => switch (stage) {
    1 || 6 => noHint,
    3 || 8 => noClear,
    _ => null,
  };
}

enum ExpeditionOutcome { active, qualified, missedMarks, abandoned }

final class ExpeditionRun {
  ExpeditionRun(this.trail, this.serial);

  factory ExpeditionRun.fromJson(Map data) {
    final run =
        ExpeditionRun(
            Trail.values.byName(data['trail'] as String),
            data['serial'] as int,
          )
          ..stage = data['stage'] as int
          ..marks = Set<int>.from(data['marks'] as List)
          ..milliseconds = data['milliseconds'] as int
          ..usedClear = data['usedClear'] == true
          ..coins = data['coins'] as int
          ..outcome = ExpeditionOutcome.values.byName(
            data['outcome'] as String,
          );
    if (run.serial < 0 ||
        run.stage < 0 ||
        run.stage > Trail.stages ||
        run.milliseconds < 0 ||
        run.coins < 0 ||
        run.marks.any(
          (stage) =>
              stage < 0 || stage >= run.stage || FieldMark.at(stage) == null,
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
  int coins = 0;
  ExpeditionOutcome outcome = ExpeditionOutcome.active;

  bool get active => outcome == ExpeditionOutcome.active;

  void finishStage(int time, {required bool usedHint}) {
    if (!active) return;
    final earned = switch (FieldMark.at(stage)) {
      FieldMark.noHint => !usedHint,
      FieldMark.noClear => !usedClear,
      null => false,
    };
    if (earned) marks.add(stage);
    milliseconds += time;
    usedClear = false;
    stage++;
    if (stage == Trail.stages) {
      outcome = marks.length >= Trail.requiredMarks
          ? ExpeditionOutcome.qualified
          : ExpeditionOutcome.missedMarks;
    }
  }

  Map<String, Object> toJson() => {
    'trail': trail.name,
    'serial': serial,
    'stage': stage,
    'marks': marks.toList(),
    'milliseconds': milliseconds,
    'usedClear': usedClear,
    'coins': coins,
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
