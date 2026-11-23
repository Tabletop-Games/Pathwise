import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/puzzle_generator.dart';
import '../lib/logic/puzzle_solver.dart';
import '../lib/logic/trail_record_storage.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/expedition.dart';
import '../lib/model/game_state.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;
import 'expedition_test.dart' show finishStage;

Map<String, dynamic> progress(int next) => {
  'expeditionProgress': {
    'next': next,
    'claims': 0,
    'stages': 0,
    'clean': 0,
    'qualifiedClean': 0,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('representative and random high-index trails are deterministic, valid and feasible', () {
    final random = Random(125);
    for (final number in [
      1,
      3,
      4,
      10,
      100,
      1000,
      10000,
      100000,
      9007199254740991,
      for (var i = 0; i < 20; i++) 4 + random.nextInt(200000),
    ]) {
      final trail = Trail(number);
      final objectives = trail.objectives;
      expect(objectives.length, 4);
      expect(objectives.keys, everyElement(inInclusiveRange(1, 9)));
      expect(
        objectives.values.every(
          (mark) => mark.earned(hint: false, clear: false, undo: false),
        ),
        true,
      );
      final run = ExpeditionRun(trail, 7);
      for (var stage = 0; stage < Trail.stages; stage++) {
        final id = PuzzleId.expedition(trail, 7, stage);
        final request = id.generation;
        expect(id.key, PuzzleId.expedition(trail, 7, stage).key);
        expect(request, PuzzleId.expedition(trail, 7, stage).generation);
        expect(
          request.seed,
          isNot(PuzzleId.expedition(trail, 8, stage).generation.seed),
        );
        expect(request.size, inInclusiveRange(4, 7));
        final board = number <= 3
            ? generatePuzzle(request)
            : generateExpeditionPuzzle(request);
        expect(solve(board.puzzle).unique, true, reason: id.key);
        expect(board.solution.length, board.puzzle.area);
        run.finishStage(20, usedHint: false);
      }
      expect(run.outcome, ExpeditionOutcome.qualified);
      expect(run.marks.length, 4);
      expect(trail.next.number, number + 1);
    }
  });

  test(
    'legacy Summit save opens Trail 4 and preserves rewards and old records',
    () async {
      final storage = MemoryStorage();
      final app = AppModel(
        storage: storage,
        snapshot: {
          'schemaVersion': 5,
          'trailRecords': {
            for (final trail in ['foothills', 'ridgeline', 'summit'])
              trail: {'deepest': 10, 'marks': 3, 'fastest': 30000},
          },
          'results': {
            'endless/1': {'milliseconds': 12, 'hints': 0},
            'expedition/summit/0': {'milliseconds': 10, 'hints': 0},
          },
          'ownedThemes': ['basinGold'],
          'ledger': [
            {
              'id': 'trail/summit/10',
              'label': 'Summit',
              'amount': 36,
              'at': '2026-01-01T00:00:00Z',
            },
          ],
        },
        loader: (_) async => fixture(),
      );
      expect(app.currentTrail, const Trail(4));
      expect(app.solved, 31);
      expect(app.unassisted, 2);
      expect(app.coinBalance, 36);
      expect(await app.flush(), true);
      app.dispose();
      final again = AppModel(storage: storage, snapshot: await storage.load());
      expect((await again.loadTrailRecord(Trail.summit))!.fastest, 30000);
      expect(again.trailRewardClaimed(Trail.summit, 10), true);
      expect(again.currentTrail, const Trail(4));
      again.dispose();
    },
  );

  test('a high trail advances offline, can continue immediately and cannot repay on replay', () async {
    final storage = MemoryStorage();
    var app = AppModel(
      storage: storage,
      snapshot: progress(100000),
      loader: (_) async => fixture(),
    );
    const trail = Trail(100000);
    expect(await app.startExpedition(trail), true);
    for (var i = 0; i < 9; i++) {
      await finishStage(app);
    }
    await app.open(app.expeditionPuzzle!);
    complete(app);
    expect(app.currentTrail.number, 100001);
    expect(app.expedition!.coins, 4 + 4 + 32 + 4 + 60 + 30 + 35 + 45);
    final balance = app.coinBalance;
    expect(
      await app.startExpedition(app.currentTrail, fromSummary: true),
      true,
    );
    await app.open(app.expeditionPuzzle!);
    expect(app.activeId?.expedition.trail.number, 100001);
    app.close();
    await app.abandonExpedition();
    expect(await app.flush(), true);
    app.dispose();

    app = AppModel(
      storage: storage,
      snapshot: await storage.load(),
      loader: (_) async => fixture(),
    );
    expect((await app.loadTrailRecord(trail))!.marks, 4);
    expect(await app.startExpedition(trail), true);
    for (var i = 0; i < 10; i++) {
      await finishStage(app);
    }
    expect(app.coinBalance, balance);
    expect(app.expedition!.coins, 0);
    expect(app.currentTrail.number, 100001);
    app.dispose();
  });

  test(
    '10,000 ideal trails have controlled income and bounded wallet rows',
    () {
      final now = DateTime.utc(2026);
      final wallet = Wallet(null, now);
      var total = 0;
      for (var number = 1; number <= 10000; number++) {
        for (final stage in [3, 6, 10]) {
          final amount =
              economy.expeditionReward(number, stage, qualified: true) +
              (number > 3 && stage == 10 ? 4 : 0);
          total += amount;
          expect(
            wallet.add('trail/$number/$stage', 'Stage', amount, now),
            true,
          );
        }
        final milestone = economy.expeditionMilestone(number);
        total += milestone;
        wallet.add('trail/$number/milestone', 'Milestone', milestone, now);
      }
      expect(total / 100000, lessThan(5));
      expect(wallet.toJson().length, 33);
      expect(wallet.balance, 40 + total);
      expect(wallet.archivedTrailCoins, greaterThan(0));
      final reloaded = Wallet(
        wallet.toJson(),
        now,
        archivedTrailCoins: wallet.archivedTrailCoins,
      );
      expect(reloaded.balance, wallet.balance);
      expect(reloaded.earned, wallet.earned);
      expect(economy.nextExpeditionMilestone(100001), 100025);
      expect(economy.expeditionMilestone(100025), 24);
      expect(economy.expeditionMilestone(100100), 60);
    },
  );

  test('an Undo mark is forfeited across an offline restart', () async {
    const trail = Trail(4);
    final stage = trail.objectives.entries
        .firstWhere((entry) => entry.value == FieldMark.noUndo)
        .key;
    final storage = MemoryStorage();
    var app = AppModel(
      storage: storage,
      snapshot: progress(4),
      loader: (_) async => fixture(),
    );
    await app.startExpedition(trail);
    for (var i = 0; i < stage; i++) {
      await finishStage(app);
    }
    final id = app.expeditionPuzzle!;
    await app.open(id);
    app.tap(1);
    app.undo();
    expect(app.expedition!.usedUndo, true);
    await app.flush();
    app.dispose();

    app = AppModel(
      storage: storage,
      snapshot: await storage.load(),
      loader: (_) async => fixture(),
    );
    expect(app.expeditionPuzzle!.key, id.key);
    expect(app.expedition!.usedUndo, true);
    await finishStage(app);
    expect(app.expedition!.marks.contains(stage), false);
    while (app.expeditionPuzzle != null) {
      await finishStage(app);
    }
    expect(app.expedition!.outcome, ExpeditionOutcome.qualified);
    app.dispose();
  });

  test(
    'snapshot rows remain bounded over repeated high-trail qualifications',
    () async {
      final storage = MemoryStorage();
      const start = 100000;
      final app = AppModel(
        storage: storage,
        snapshot: progress(start),
        loader: (_) async => fixture(),
      );
      for (var number = start; number < start + 35; number++) {
        expect(await app.startExpedition(Trail(number)), true);
        for (var stage = 0; stage < Trail.stages; stage++) {
          await finishStage(app);
        }
      }
      expect(await app.flush(), true);
      final snapshot = await storage.load();
      expect((snapshot['expeditionProgress'] as Map)['next'], start + 35);
      expect(snapshot['results'], isEmpty);
      expect(snapshot['expeditionHistory'], hasLength(12));
      expect(
        (snapshot['ledger'] as List).where(
          (row) => (row['id'] as String).startsWith('trail/'),
        ),
        hasLength(32),
      );
      expect(snapshot['archivedTrailCoins'], greaterThan(0));
      app.dispose();
    },
  );

  test(
    'high-index durable record uses only one page and merges old bests',
    () async {
      final directory = await Directory.systemTemp.createTemp('trail-records-');
      addTearDown(() => directory.delete(recursive: true));
      final storage = TrailRecordStorage(directory);
      const high = Trail(100000);
      await storage.merge(
        high,
        TrailRecord(deepest: 10, marks: 2, fastest: 25),
      );
      await storage.merge(high, TrailRecord(deepest: 9, marks: 4, fastest: 30));
      await storage.merge(
        high,
        TrailRecord(deepest: 10, marks: 3, fastest: 20),
      );
      final reopened = TrailRecordStorage(directory);
      final record = (await reopened.read(high))!;
      expect(reopened.read(const Trail(1)), completion(isNull));
      expect(record.deepest, 10);
      expect(record.marks, 4);
      expect(record.fastest, 20);
      final files = await directory.list().toList();
      expect(files.length, 1);
      expect(await (files.single as File).length(), 2560);
    },
  );
}
