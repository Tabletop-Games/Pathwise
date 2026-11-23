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
        'hintCredits': {'levels/1': 1},
      });
      await app.open(const PuzzleId.level(1));
      expect(app.hintTank, 3);
      expect(app.freeHints, 0);
      expect(app.extraHints, 0);
      expect(app.canHint, false);
      app.dispose();
    },
  );

  test(
    'tank is shared, refills to three and cannot supply fourth or fifth hint',
    () async {
      final storage = MemoryStorage();
      final app = model(storage);
      expect(app.hintTank, 3);
      expect(app.buyTankRefill(), false);
      await app.open(const PuzzleId.level(1));
      app.hint();
      expect(app.hintTank, 2);
      expect(app.buyTankRefill(), true);
      expect(app.hintTank, 3);
      expect(app.freeHints, 2);
      await app.open(const PuzzleId.daily('2026-11-23'));
      app.hint();
      expect(app.hintTank, 2);
      await app.open(const PuzzleId.level(1), replay: true);
      app.hint();
      app.clear();
      app.hint();
      app.clear();
      expect(app.hintTank, 0);
      expect(app.freeHints, 0);
      expect(await app.grantTankRefill('verified-refill'), true);
      expect(await app.grantTankRefill('verified-refill'), false);
      expect(app.hintTank, 3);
      expect(app.canHint, false);
      expect(await app.grantRewardedHint('levels/1', 'verified-fourth'), true);
      app.hint();
      app.clear();
      expect(app.hintTank, 3);
      expect(app.canHint, false);
      expect(await app.grantRewardedHint('levels/1', 'verified-fourth'), false);
      await app.flush();
      app.dispose();
      final restored = model(storage, await storage.load());
      await restored.open(const PuzzleId.level(1), replay: true);
      expect(restored.hintTank, 3);
      expect(restored.canHint, false);
      expect(
        await restored.grantRewardedHint('levels/1', 'verified-fifth'),
        true,
      );
      restored.hint();
      restored.clear();
      expect(restored.canHint, false);
      restored.dispose();
    },
  );

  test(
    'research debit and boost inventory survive restore without stacking',
    () async {
      final storage = MemoryStorage();
      final app = model(storage);
      expect(app.research(Research.magnet), false);
      await app.applyVerifiedPurchase('test-pack', coins: 500, themes: false);
      expect(app.research(Research.magnet), true);
      expect(app.progression.effect(Research.magnet), 2);
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
