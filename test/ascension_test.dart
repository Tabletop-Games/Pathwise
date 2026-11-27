import 'package:flutter_test/flutter_test.dart';

import '../lib/model/app_model.dart';
import '../lib/model/game_state.dart';
import '../lib/model/progression.dart';
import 'app_model_test.dart' show MemoryStorage, fixture;

AppModel model(
  MemoryStorage storage, [
  Map<String, dynamic> saved = const {},
]) =>
    AppModel(storage: storage, snapshot: saved, loader: (_) async => fixture());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'development coin-funded extra hints cannot carry into release',
    () async {
      final app = model(MemoryStorage(), {
        'schemaVersion': 3,
        'hintUsage': {'levels/1': 3},
        'attempts': {
          'levels/1': {
            'path': [0],
            'history': <Object>[],
            'hints': 3,
            'milliseconds': 0,
            'started': true,
          },
        },
        'hintCredits': {'levels/1': 1},
      });
      await app.open(const PuzzleId.level(1));
      expect(app.hintsRemaining, 0);

      expect(app.canHint, false);
      app.dispose();
    },
  );

  test(
    'global hints support unlimited ownership and five daily ad receipts',
    () async {
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
      expect(await app.grantHintAd('sixth'), false);
      expect(app.hintsRemaining, 19);
      await app.open(const PuzzleId.level(1));
      for (var index = 0; index < 8; index++) {
        app.hint();
        app.clear();
      }
      expect(app.hintsRemaining, 11);
      await app.open(const PuzzleId.level(1), replay: true);
      await app.flush();
      final restored = model(storage, await storage.load());
      expect(restored.hintsRemaining, 11);
      expect(restored.hintAdsToday, 5);
      app.dispose();
      restored.dispose();
    },
  );

  test('ad boost limits, fourth-ad gate and inventory persist', () async {
    final storage = MemoryStorage();
    final app = model(storage);
    expect(await app.grantBoostAd(Boost.tripleFifteen, 'locked'), false);
    for (var index = 0; index < 4; index++) {
      expect(await app.grantAdBonus('coin-$index'), true);
    }
    expect(await app.grantBoostAd(Boost.tripleFifteen, 'triple'), true);
    expect(await app.grantBoostAd(Boost.tripleFifteen, 'triple-again'), false);
    for (var index = 0; index < 3; index++) {
      expect(await app.grantBoostAd(Boost.doubleTen, 'boost-$index'), true);
      expect(await app.grantBoostAd(Boost.doubleTen, 'boost-$index'), false);
    }
    expect(await app.grantBoostAd(Boost.doubleTen, 'fourth'), false);
    await app.flush();
    final restored = model(storage, await storage.load());
    expect(restored.progression.inventory[Boost.doubleTen.name], 3);
    expect(restored.progression.inventory[Boost.tripleFifteen.name], 1);
    expect(restored.canEarnBoostAd(Boost.doubleTen), false);
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
