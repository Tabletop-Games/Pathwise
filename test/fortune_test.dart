import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../lib/model/app_model.dart';
import '../lib/model/field_notes.dart';
import '../lib/model/fortune.dart';
import '../lib/model/progression.dart';
import '../lib/model/time_attack.dart';
import 'app_model_test.dart' show MemoryStorage;

class FixedRoll implements Random {
  FixedRoll(this.roll);
  final int roll;
  @override
  int nextInt(int max) => roll;
  @override
  bool nextBool() => roll.isEven;
  @override
  double nextDouble() => roll / 100;
}

FortuneStatus status(Map<String, int> counts, {int spins = 4}) =>
    FortuneStatus.fromJson({
      'now': 1000000000,
      'stamps': List.filled(spins, 1000000000),
      'counts': counts,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = FortuneCatalog(
    File('backend/fortune-prizes.json').readAsStringSync(),
  );

  test('published weights describe every deterministic roll exactly', () {
    final found = <String, int>{};
    for (var roll = 0; roll < 100; roll++) {
      final prize = catalog.pick(roll);
      found.update(prize.id, (value) => value + 1, ifAbsent: () => 1);
      expect(catalog.center(prize), inExclusiveRange(0, 1));
    }
    for (final prize in catalog.prizes) {
      expect(found[prize.id], prize.weight);
    }
    expect(() => catalog.pick(100), throwsRangeError);
  });

  test('free spin survives restart, ignores wall time and uses rolling elapsed time', () async {
    final storage = MemoryStorage();
    BootTime clock = (boot: 1, milliseconds: 500);
    var wallTime = DateTime.utc(2026, 11, 23);
    AppModel launch(Map<String, dynamic> snapshot) => AppModel(
      storage: storage,
      snapshot: snapshot,
      bootTime: () => clock,
      today: () => wallTime,
    );
    var app = launch({});
    final draws = await Future.wait([
      app.spinFreeFortune(catalog, random: FixedRoll(0)),
      app.spinFreeFortune(catalog, random: FixedRoll(0)),
    ]);
    expect(draws.whereType<FortunePrize>().single.coins, 8);
    expect(app.coinBalance, 48);
    expect(app.hintTank, 3);
    app.dispose();

    app = launch(await storage.load());
    wallTime = wallTime.add(const Duration(days: 700));
    expect(await app.spinFreeFortune(catalog), isNull);
    clock = (boot: 1, milliseconds: 500 + fortuneWindowMs - 1);
    expect(app.fortuneWait, 1);
    clock = (boot: 1, milliseconds: 500 + fortuneWindowMs);
    expect(
      (await app.spinFreeFortune(catalog, random: FixedRoll(0)))!.coins,
      8,
    );
    clock = (boot: 2, milliseconds: 100);
    expect(await app.spinFreeFortune(catalog), isNull);
    clock = (boot: 2, milliseconds: fortuneWindowMs);
    expect(
      (await app.spinFreeFortune(catalog, random: FixedRoll(0)))!.coins,
      8,
    );
    expect(app.coinBalance, 64);
    app.dispose();
  });

  test('verified cumulative rewards account once across concurrent delivery and restart', () async {
    final storage = MemoryStorage();
    var app = AppModel(storage: storage, snapshot: {});
    expect(await app.spinFreeFortune(catalog), isNull);
    final verified = status({'sprout': 3, 'boost': 1});
    final applied = await Future.wait([
      app.applyVerifiedFortune(catalog, verified),
      app.applyVerifiedFortune(catalog, verified),
    ]);
    expect(applied.where((value) => value), hasLength(1));
    expect(verified.remaining(0), 0);
    expect(verified.remaining(fortuneWindowMs - 1), 0);
    expect(verified.remaining(fortuneWindowMs), 4);
    expect(app.coinBalance, 64);
    expect(app.progression.inventory[Boost.doubleTen.name], 1);
    expect(app.hintTank, 3);
    app.dispose();
    app = AppModel(storage: storage, snapshot: await storage.load());
    expect(await app.applyVerifiedFortune(catalog, verified), false);
    expect(
      await app.applyVerifiedFortune(
        catalog,
        status({'sprout': 2, 'boost': 1}),
      ),
      false,
    );
    expect(
      await app.applyVerifiedFortune(
        catalog,
        status({'sprout': 3, 'boost': 1, 'cache': 1}),
      ),
      true,
    );
    expect(app.coinBalance, 84);
    expect(app.progression.inventory[Boost.doubleTen.name], 1);
    app.dispose();
  });

  test('advanced cost and benefit bounds and single-slot boost caps hold', () {
    final progress = Progression({
      'ranks': {for (final item in Research.values) item.name: item.limit + 5},
      'inventory': {for (final boost in Boost.values) boost.name: 1},
    });
    for (final item in Research.values) {
      final costs = List.generate(item.limit, item.price);
      expect(costs, everyElement(greaterThan(0)));
      expect(costs.last, lessThan(200000));
      for (var i = 1; i < costs.length; i++) {
        expect(costs[i], greaterThan(costs[i - 1]));
        expect(item.effectAt(i + 1), greaterThan(item.effectAt(i)));
      }
      expect(progress.rank(item), item.limit);
      expect(() => item.price(item.limit), throwsRangeError);
    }
    expect(progress.durationBonus, 72);
    expect(progress.discount(100), 66);
    expect(progress.refillPrice, 16);
    expect(progress.crateOdds(1).reduce((a, b) => a + b), 100);
    expect(progress.trailQualification(32, 1), 102);
    progress.activate(Boost.quadrupleTen, 1);
    expect(progress.canActivate(Boost.doubleTen, 2), false);
    expect(progress.multiplier(2), 4);
    expect(progress.canActivate(Boost.trailProvisions, 2), true);
    progress.activate(Boost.trailProvisions, 2);
    expect(progress.trailQualification(32, 2), 118);
    expect(progress.multiplier(2), 4);
  });

  test(
    'field notes rotate, pay once after reload and disregard backwards days',
    () async {
      final storage = MemoryStorage();
      var now = DateTime.utc(2026, 11, 23);
      AppModel launch(Map<String, dynamic> snapshot) =>
          AppModel(storage: storage, snapshot: snapshot, today: () => now);
      var app = launch({});
      final today = app.fieldNotesDay;
      expect(FieldNotes.goals(today), hasLength(3));
      final goal = FieldNotes.goals(today).first;
      for (var i = 0; i < 16; i++) {
        app.notes.observe(today, {
          NoteGoal.solve,
          NoteGoal.crate,
          NoteGoal.trail,
          NoteGoal.clean,
        });
      }
      expect(await app.claimFieldNote(goal), true);
      expect(await app.claimFieldNote(null), true);
      expect(app.coinBalance, 104);
      app.dispose();
      app = launch(await storage.load());
      expect(await app.claimFieldNote(goal), false);
      expect(await app.claimFieldNote(null), false);
      now = now.subtract(const Duration(days: 1));
      expect(app.notes.observe(app.fieldNotesDay, {NoteGoal.solve}), 0);
      expect(await app.claimFieldNote(goal), false);
      app.dispose();
    },
  );
}
