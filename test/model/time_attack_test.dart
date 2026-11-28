import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/model/app_model.dart';

import '../support/fixtures.dart';

AppModel app(
  MemoryStorage store, {
  Map<String, dynamic> data = const {},
  int Function()? now,
}) => AppModel(
  storage: store,
  snapshot: data,
  loader: (_) async => fixture(),
  bootTime: () => (boot: 5, milliseconds: now?.call() ?? 0),
)..setHaptics(false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Time Attack automatically advances, survives opening again, then pays once', () async {
    var time = 1000;
    final store = MemoryStorage();
    final model = app(store, now: () => time);
    expect(await model.openAttack(), isTrue);
    final original = model.attack!.id;
    final deadline = model.attack!.deadline;
    time += 5000;
    complete(model);
    await Future<void>.delayed(Duration.zero);
    expect(model.activeId!.attackIndex, 1);
    time += 7000;
    complete(model);
    await Future<void>.delayed(Duration.zero);
    expect(model.activeId!.attackIndex, 2);
    expect(model.levelsSolved, 0);
    model.setForeground(false);
    await model.flush();
    model.dispose();

    time += 30000;
    final restored = app(store, data: await store.load(), now: () => time);
    expect(await restored.openAttack(), isTrue);
    expect(restored.attack!.id, original);
    expect(restored.attack!.deadline, deadline);
    expect(restored.attackRemaining.value.inMilliseconds, deadline - time);
    time = deadline;
    restored.refreshAttackClock();
    expect(restored.attack!.finished, isTrue);
    expect(restored.attack!.average, 6000);
    expect(restored.attack!.fastest, 5000);
    expect(restored.attackBest, 200);
    expect(restored.attack!.coins, 6);
    expect(restored.coinBalance, 76);
    restored.refreshAttackClock();
    await restored.flush();
    final restarted = app(store, data: await store.load(), now: () => time);
    restarted.refreshAttackClock();
    expect(restarted.attackHistory, hasLength(1));
    expect(restarted.coinBalance, 76);
    restored.dispose();
    restarted.dispose();
  });

  test(
    'Time Attack durations, restart and stop preserve permanent state',
    () async {
      final store = MemoryStorage();
      var clock = (boot: 1, milliseconds: 100);
      final model = AppModel(
        storage: store,
        snapshot: {},
        bootTime: () => clock,
        loader: (_) async => fixture(),
      );
      final coins = model.coinBalance;
      model.selectAttackMinutes(1);
      expect(await model.openAttack(), true);
      expect(model.attackRemaining.value, const Duration(minutes: 1));
      final first = model.attack!.id;
      model.hint();
      expect(model.hintsRemaining, 2);
      expect(await model.restartAttack(), true);
      expect(model.attack!.id, isNot(first));
      expect(model.hintsRemaining, 2);
      expect(model.attackHistory, isEmpty);
      model.stopAttack();
      clock = (boot: 1, milliseconds: 1000000);
      model.refreshAttackClock();
      expect(model.attack, isNull);
      expect(model.coinBalance, coins);
      expect(model.attackHistory, isEmpty);
      await model.flush();
      final restored = app(store, data: await store.load());
      expect(restored.attackMinutes, 1);
      model.dispose();
      restored.dispose();
    },
  );
}
