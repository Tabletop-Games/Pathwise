import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/game_state_storage.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import '../lib/viewmodels/crate_viewmodel.dart';
import '../lib/viewmodels/home_viewmodel.dart';
import '../lib/viewmodels/streak_viewmodel.dart';

class _MemStorage extends GameStateStorage {
  String? raw;

  @override
  Future<Map<String, dynamic>> load() async => {};

  @override
  Future<void> save(String payload) async {
    raw = payload;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'StreakViewModel reports the freeze price and refuses without coins',
    () async {
      final model = AppModel(storage: _MemStorage(), snapshot: {});
      final vm = StreakViewModel(model);

      expect(vm.count, 0);
      expect(vm.freezePrice, economy.freezePrice);
      expect(vm.freezeFull, isFalse);
      final result = await vm.buyFreeze();
      expect(result, isA<FreezeInsufficientCoins>());
      expect(
        (result as FreezeInsufficientCoins).shortfall,
        economy.freezePrice - model.coinBalance,
      );

      model.dispose();
    },
  );

  test('HomeViewModel only opens an unlocked puzzle while none is active', () {
    final model = AppModel(storage: _MemStorage(), snapshot: {});
    final ads = AdService();
    final home = HomeViewModel(model: model, ads: ads);

    expect(home.canOpenPuzzle(const PuzzleId.level(1)), isTrue);
    expect(home.canOpenPuzzle(const PuzzleId.level(2)), isFalse);

    model.dispose();
    ads.dispose();
  });

  test('CrateViewModel refuses to reveal a crate that was never offered', () {
    final model = AppModel(storage: _MemStorage(), snapshot: {});
    final ads = AdService();
    final crate = CrateViewModel(model: model, ads: ads);

    expect(crate.reveal((id: 'x', coins: 25)), isFalse);

    model.dispose();
    ads.dispose();
  });
}
