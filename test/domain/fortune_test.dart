import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/model/app_model.dart';
import '../../lib/model/fortune.dart';
import '../../lib/model/time_attack.dart';
import '../support/fixtures.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = FortuneCatalog(
    File('assets/data/fortune-prizes.json').readAsStringSync(),
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

  test('six equal wedges always land on the preselected coin, independent of weights', () {
    expect(catalog.prizes.map((p) => p.coins), [8, 15, 25, 40, 70, 100]);
    expect(catalog.prizes.map((p) => p.weight), [30, 25, 20, 15, 8, 2]);
    expect(FortuneCatalog.segmentTurns * 360, 60);
    var rotation = 0.0;
    for (final prize in catalog.prizes) {
      final next = catalog.destination(rotation, prize);
      expect(next - rotation, greaterThanOrEqualTo(5));
      expect(catalog.atPointer(next), same(prize));
      final alignment = next + catalog.center(prize);
      expect(alignment, closeTo(alignment.round(), 1e-10));
      expect(
        catalog.atPointer(catalog.destination(rotation, prize, rotations: 0)),
        same(prize),
      );
      rotation = next;
    }
  });

  test('seeded draws match the published weights (chi-squared)', () {
    const draws = 100000;
    final rng = Random(1984);
    final hits = <String, int>{};
    for (var draw = 0; draw < draws; draw++) {
      hits.update(
        catalog.pick(rng.nextInt(100)).id,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final statistic = catalog.prizes.fold(0.0, (sum, prize) {
      final expected = draws * prize.weight / 100;
      return sum + pow(hits[prize.id]! - expected, 2) / expected;
    });
    expect(statistic, lessThan(20.52)); // df=5, p=.001
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
    expect(app.coinBalance, 50);
    final saved = await storage.load();
    app.dispose();
    app = launch(saved);
    final recovered = app.pendingFortune!;
    expect(recovered.coins, 8);
    expect(await app.settleFortune(recovered), isTrue);
    expect(await app.settleFortune(recovered), isFalse);
    expect(app.coinBalance, 58);
    expect(app.hintsRemaining, 3);
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
    await app.settleFortune(app.pendingFortune!);
    clock = (boot: 2, milliseconds: 100);
    expect(await app.spinFreeFortune(catalog), isNull);
    clock = (boot: 2, milliseconds: fortuneWindowMs);
    expect(
      (await app.spinFreeFortune(catalog, random: FixedRoll(0)))!.coins,
      8,
    );
    await app.settleFortune(app.pendingFortune!);
    expect(app.coinBalance, 74);
    app.dispose();
  });

  test(
    'video spins pay once per receipt, are not capped, and survive a restart',
    () async {
      final storage = MemoryStorage();
      final clock = (boot: 1, milliseconds: 500);
      AppModel launch(Map<String, dynamic> snapshot) =>
          AppModel(storage: storage, snapshot: snapshot, bootTime: () => clock);
      var app = launch({});
      final prizes = await Future.wait([
        app.spinRewardedFortune(catalog, 'first', random: FixedRoll(0)),
        app.spinRewardedFortune(catalog, 'first', random: FixedRoll(99)),
      ]);
      expect(prizes.nonNulls.single.coins, 8);
      await app.settleFortune(prizes.nonNulls.single);
      for (var spin = 2; spin <= 9; spin++) {
        expect(
          await app.spinRewardedFortune(catalog, 'video-$spin'),
          isNotNull,
        );
        await app.settleFortune(app.pendingFortune!);
      }
      expect(app.fortuneVideoAvailable, isTrue);
      expect(await app.spinFreeFortune(catalog), isNotNull);
      await app.settleFortune(app.pendingFortune!);
      final balance = app.coinBalance;
      app.dispose();

      app = launch(await storage.load());
      expect(app.coinBalance, balance);
      expect(await app.spinRewardedFortune(catalog, 'first'), isNull);
      expect(await app.spinRewardedFortune(catalog, 'new'), isNotNull);
      app.dispose();
    },
  );
}
