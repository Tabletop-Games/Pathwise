import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/logic/game_state_storage.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/economy.dart';
import 'package:pathwise/model/progression.dart';

class _FailingStorage extends GameStateStorage {
  bool fail = false;

  @override
  Future<Map<String, dynamic>> load() async => {};

  @override
  Future<void> save(String payload) async {
    if (fail) throw StateError('disk full');
  }
}

void main() {
  test(
    'AppModel rolls back async ad/purchase mutations when flush fails',
    () async {
      final storage = _FailingStorage();
      final model = AppModel(storage: storage, snapshot: {});
      storage.fail = true;

      expect(await model.grantAdBonus('ad-1'), isFalse);
      expect(model.coinBalance, economy.starterCoins);
      expect(model.adsToday, 0);

      expect(await model.grantHintAd('hint-1'), isFalse);
      expect(model.hintsRemaining, economy.starterHints);

      expect(await model.grantBoostAd(Boost.doubleTen, 'boost-1'), isFalse);
      expect(model.progression.inventory[Boost.doubleTen.name] ?? 0, 0);

      expect(
        await model.applyVerifiedPurchase('grant-1', coins: 500, themes: true),
        isFalse,
      );
      expect(model.coinBalance, economy.starterCoins);
      expect(model.hasThemePass, isFalse);

      // Recover storage and verify retries succeed without duplicate blocks.
      storage.fail = false;
      expect(await model.flush(), isTrue);
      expect(await model.grantAdBonus('ad-1'), isTrue);
      expect(model.coinBalance, economy.starterCoins + economy.rewardedAdCoins);
      model.dispose();
    },
  );

  test(
    'AppModel flush passes an independent snapshot copy to onPersisted',
    () async {
      final storage = _FailingStorage();
      Map<String, dynamic>? captured;
      final model = AppModel(
        storage: storage,
        snapshot: {},
        onPersisted: (snap) => captured = snap,
      );
      await model.flush();
      expect(captured, isNotNull);
      captured!['hintBalance'] = 9999;
      expect(model.hintsRemaining, economy.starterHints);
      model.dispose();
    },
  );
}
