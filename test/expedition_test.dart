import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/game_state_storage.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/expedition.dart';
import '../lib/model/game_state.dart';
import '../lib/model/user_preferences.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

Future<AppModel> load(MemoryStorage storage) async => AppModel(
  storage: storage,
  snapshot: await storage.load(),
  loader: (_) async => fixture(),
);

Future<void> finishStage(AppModel app, {bool missMark = false}) async {
  final stage = app.expedition!.stage;
  await app.open(app.expeditionPuzzle!);
  if (missMark) {
    switch (app.expedition!.trail.objectives[stage]) {
      case FieldMark.noHint:
        app.hint();
      case FieldMark.noClear:
        app.tap(1);
        app.clear();
      case FieldMark.noUndo:
        app.tap(1);
        app.undo();
      case FieldMark.clean:
        app.tap(1);
        app.clear();
      case null:
        break;
    }
  }
  complete(app);
  expect(app.expedition!.stage, stage + 1);
  app.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'schema 4 preserves shared and daily progress while retiring old routes',
    () async {
      final storage = MemoryStorage();
      final app = AppModel(
        storage: storage,
        snapshot: {
          'schemaVersion': 4,
          'hintTank': 1,
          'hintUsage': {'endless/2': 2, 'daily/2026-11-23': 3},
          'hintCredits': {'endless/2': 1, 'daily/2026-11-23': 1},
          'attempts': {'endless/2': {}},
          'results': {
            'endless/1': {'milliseconds': 25, 'hints': 0},
          },
        },
        loader: (_) async => fixture(),
      );
      await app.open(const PuzzleId.daily('2026-11-23'));
      expect(app.hintTank, 1);
      expect(app.extraHints, 1);
      expect(app.solved, 1);
      await app.flush();
      final saved = await storage.load();
      expect(saved['schemaVersion'], GameStateStorage.schemaVersion);
      expect(saved['attempts'], isNot(contains('endless/2')));
      expect(saved['hintCredits'], isNot(contains('endless/2')));
      app.dispose();
    },
  );

  test('fastest records ignore abandoned or missed runs and improve only on qualification', () {
    final record = TrailRecord();
    for (final (outcome, time) in [
      (ExpeditionOutcome.missedMarks, 100),
      (ExpeditionOutcome.abandoned, 20),
      (ExpeditionOutcome.qualified, 400),
      (ExpeditionOutcome.qualified, 500),
      (ExpeditionOutcome.qualified, 300),
    ]) {
      record.record(
        ExpeditionRun(Trail.foothills, 0)
          ..outcome = outcome
          ..milliseconds = time,
      );
    }
    expect(record.fastest, 300);
  });

  test(
    'qualification unlocks the next trail, reward, record and cosmetic',
    () async {
      final storage = MemoryStorage();
      var app = await load(storage);
      expect(await app.startExpedition(Trail.ridgeline), false);
      expect(app.ownsTheme(PathwiseTheme.basinGold), false);
      expect(app.unlockTheme(PathwiseTheme.basinGold), false);
      for (final trail in [Trail.foothills, Trail.ridgeline, Trail.summit]) {
        expect(await app.startExpedition(trail), true);
        expect(await app.startExpedition(trail), false);
        for (var stage = 0; stage < Trail.stages; stage++) {
          await finishStage(app);
        }
        expect(app.expedition!.outcome, ExpeditionOutcome.qualified);
        expect(app.expeditionPuzzle, isNull);
        expect(app.expedition!.marks, {1, 3, 6, 8});
        expect(app.trailRecord(trail)!.fastest, isNotNull);
      }
      expect(app.coinsEarned, 40 + 3 * (12 + 12 + 36) + 30 + 35);
      expect(app.hasAchievement(Achievement.expeditionClear), true);
      expect(app.ownsTheme(PathwiseTheme.basinGold), true);
      expect(app.trailsQualified, 3);
      expect(await app.flush(), true);
      app.dispose();

      app = await load(storage);
      expect(app.ownsTheme(PathwiseTheme.basinGold), true);
      expect(app.expeditionHistory.length, 3);
      expect(app.currentTrail, const Trail(4));
      expect(app.trailUnlocked(const Trail(4)), true);
      expect((await app.loadTrailRecord(Trail.foothills))!.deepest, 10);
      expect((await app.loadTrailRecord(Trail.summit))!.marks, 4);
      final balance = app.coinBalance;
      expect(await app.startExpedition(Trail.foothills), true);
      for (var stage = 0; stage < Trail.stages; stage++) {
        await finishStage(app);
      }
      expect(app.coinBalance, balance);
      expect(app.expedition!.coins, 0);
      expect(app.solved, 30);
      app.dispose();
    },
  );

  test('missing marks permits all ten solves but does not qualify or pay the finish bonus', () async {
    final app = await load(MemoryStorage());
    await app.startExpedition(Trail.foothills);
    for (var stage = 0; stage < Trail.stages; stage++) {
      await finishStage(app, missMark: true);
    }
    expect(app.expedition!.outcome, ExpeditionOutcome.missedMarks);
    expect(app.expedition!.marks, isEmpty);
    expect(app.hintTank, 1);
    expect(app.trailRecord(Trail.foothills)!.fastest, isNull);
    expect((await app.loadTrailRecord(Trail.foothills))!.deepest, 10);
    expect(app.trailUnlocked(Trail.ridgeline), false);
    expect(app.coinBalance, 64);
    app.dispose();
  });

  test(
    'process recreation preserves route, mark eligibility and stage hints',
    () async {
      final storage = MemoryStorage();
      var app = await load(storage);
      await app.startExpedition(Trail.foothills);
      for (var stage = 0; stage < 3; stage++) {
        await finishStage(app);
      }
      expect(app.expedition!.coins, 12);
      final id = app.expeditionPuzzle!;
      await app.open(id);
      app.tap(1);
      app.clear();
      app.hint();
      app.tap(1);
      app.setForeground(false);
      await app.flush();
      app.dispose();

      app = await load(storage);
      expect(app.expeditionPuzzle!.key, id.key);
      await app.open(app.expeditionPuzzle!);
      expect(app.path, [0, 1]);
      expect(app.freeHints, 2);
      expect(app.hintTank, 2);
      complete(app);
      expect(app.expedition!.marks, {1});
      expect(app.expedition!.stage, 4);
      app.close();
      expect(await app.abandonExpedition(), true);
      expect(app.expedition!.outcome, ExpeditionOutcome.abandoned);
      expect(await app.abandonExpedition(), false);
      app.dispose();
      app = await load(storage);
      expect(app.expeditionHistory.single.outcome, ExpeditionOutcome.abandoned);
      expect((await app.loadTrailRecord(Trail.foothills))!.deepest, 4);
      await app.startExpedition(Trail.foothills);
      expect(app.expeditionPuzzle!.key, isNot(id.key));
      for (var stage = 0; stage < 3; stage++) {
        await finishStage(app);
      }
      expect(app.coinBalance, 52);
      app.dispose();
    },
  );

  test('verified extra hints are scoped to the stage and cannot earn a hint-free mark', () async {
    final app = await load(MemoryStorage());
    await app.startExpedition(Trail.foothills);
    await finishStage(app);
    final id = app.expeditionPuzzle!;
    await app.open(id);
    for (var i = 0; i < 3; i++) {
      app.hint();
      app.clear();
    }
    expect(app.hintTank, 0);
    expect(app.freeHints, 0);
    expect(app.buyTankRefill(), true);
    expect(app.canHint, false);
    expect(await app.grantRewardedHint(id.key, 'receipt'), true);
    app.hint();
    app.clear();
    expect(app.hintTank, 3);
    expect(app.canHint, false);
    expect(await app.grantRewardedHint(id.key, 'receipt'), false);
    complete(app);
    expect(app.expedition!.marks, isEmpty);
    expect(await app.grantRewardedHint(id.key, 'late-receipt'), false);
    app.dispose();
  });

  test(
    'later stages use larger boards and sparser clues with stable run seeds',
    () {
      for (final trail in [Trail.foothills, Trail.ridgeline, Trail.summit]) {
        final first = PuzzleId.expedition(trail, 0, 0).generation;
        final next = PuzzleId.expedition(trail, 0, 1).generation;
        final last = PuzzleId.expedition(trail, 0, 9).generation;
        expect(next.size, first.size);
        expect(next.clues, lessThan(first.clues));
        expect(last.size, greaterThan(first.size));
        expect(
          last.clues / (last.size * last.size),
          lessThan(first.clues / (first.size * first.size)),
        );
        expect(PuzzleId.expedition(trail, 0, 0).generation, first);
        expect(
          PuzzleId.expedition(trail, 1, 0).generation.seed,
          isNot(first.seed),
        );
      }
    },
  );
}
