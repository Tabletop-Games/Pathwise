import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/game_state.dart';
import 'package:pathwise/model/progression.dart';

import '../support/fixtures.dart';

AppModel model(
  MemoryStorage storage, [
  Map<String, dynamic> saved = const {},
]) =>
    AppModel(storage: storage, snapshot: saved, loader: (_) async => fixture());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('global hints support unlimited ownership and one rewarded receipt per video', () async {
    final storage = MemoryStorage();
    final app = model(storage);
    expect(app.hintsRemaining, 3);
    expect(await app.buyHint(), false);
    await app.applyVerifiedPurchase('funds', coins: 900, themes: false);
    expect(await app.buyHint(), true);
    for (var index = 0; index < 10; index++) {
      expect(await app.buyHint(), true);
    }
    for (var index = 0; index < 5; index++) {
      expect(await app.grantHintAd('hint-$index'), true);
      expect(await app.grantHintAd('hint-$index'), false);
    }
    expect(await app.grantHintAd('sixth'), true);
    expect(await app.grantHintAd('sixth'), false);
    expect(app.hintsRemaining, 20);
    await app.open(const PuzzleId.level(1));
    for (var index = 0; index < 8; index++) {
      app.hint();
      app.clear();
    }
    expect(app.hintsRemaining, 12);
    await app.open(const PuzzleId.level(1), replay: true);
    await app.flush();
    final restored = model(storage, await storage.load());
    expect(restored.hintsRemaining, 12);
    app.dispose();
    restored.dispose();
  });

  test('boost videos, the fourth-ad gate and inventory persist', () async {
    final storage = MemoryStorage();
    final app = model(storage);
    expect(await app.grantBoostAd(Boost.tripleFifteen, 'locked'), false);
    for (var index = 0; index < 4; index++) {
      expect(await app.grantAdBonus('coin-$index'), true);
    }
    expect(await app.grantBoostAd(Boost.tripleFifteen, 'triple'), true);
    expect(await app.grantBoostAd(Boost.tripleFifteen, 'triple-again'), false);
    for (var index = 0; index < 5; index++) {
      expect(await app.grantBoostAd(Boost.doubleTen, 'boost-$index'), true);
      expect(await app.grantBoostAd(Boost.doubleTen, 'boost-$index'), false);
    }
    await app.flush();
    final restored = model(storage, await storage.load());
    expect(restored.progression.inventory[Boost.doubleTen.name], 5);
    expect(restored.progression.inventory[Boost.tripleFifteen.name], 1);
    expect(restored.canEarnBoostAd(Boost.doubleTen), true);
    expect(restored.canEarnBoostAd(Boost.tripleFifteen), false);
    app.dispose();
    restored.dispose();
  });

  test(
    'research debit and boost inventory survive restore without stacking',
    () async {
      final storage = MemoryStorage();
      final app = model(storage);
      expect(app.research(Research.magnet), true);
      expect(app.progression.effect(Research.magnet), 1);
      await app.applyVerifiedPurchase('test-pack', coins: 500, themes: false);
      expect(app.buyBoost(Boost.doubleTen), true);
      expect(app.buyBoost(Boost.tripleFifteen), true);
      expect(app.activateBoost(Boost.doubleTen), true);
      expect(app.activateBoost(Boost.tripleFifteen), false);
      await app.flush();
      final restored = model(storage, await storage.load());
      expect(restored.progression.multiplier(restored.progressionTime), 2);
      expect(
        restored.progression.multiplier(restored.progressionTime + 601000),
        1,
      );
      expect(restored.progression.inventory[Boost.tripleFifteen.name], 1);
      app.dispose();
      restored.dispose();
    },
  );
}
