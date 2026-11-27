import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/game_state_storage.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/fortune.dart';
import '../lib/model/game_state.dart';
import '../lib/model/progression.dart';
import '../lib/model/user_preferences.dart';
import '../lib/viewmodels/crate_viewmodel.dart';
import '../lib/viewmodels/fortune_viewmodel.dart';
import '../lib/viewmodels/gameplay_viewmodel.dart';
import '../lib/viewmodels/home_viewmodel.dart';
import '../lib/viewmodels/journey_viewmodel.dart';
import '../lib/viewmodels/progression_viewmodel.dart';
import '../lib/viewmodels/store_viewmodel.dart';
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
    'StoreViewModel handles shortfalls, purchases, and pack recommendations',
    () async {
      final model = AppModel(storage: _MemStorage(), snapshot: {});
      final ads = AdService();
      final billing = BillingService(persist: (_) async => true);
      final vm = StoreViewModel(model: model, ads: ads, billing: billing);

      expect(StoreViewModel.recommendedCoinPack(400)?.coins, 500);
      expect(StoreViewModel.recommendedCoinPack(50000)?.coins, 18000);

      final themeRes = vm.buyTheme(PathwiseTheme.canyon);
      expect(themeRes, isA<StoreInsufficientCoins>());

      final tipRes = await vm.buyTip(PathTip.crystal);
      expect(tipRes, isA<StoreInsufficientCoins>());

      model.dispose();
      ads.dispose();
      billing.dispose();
    },
  );

  test(
    'ProgressionViewModel computes boost duration and research availability',
    () {
      final model = AppModel(storage: _MemStorage(), snapshot: {});
      final ads = AdService();
      final vm = ProgressionViewModel(model: model, ads: ads);

      expect(
        vm.boostDuration(Boost.doubleTen).inMilliseconds,
        model.progression.boostDurationMs(Boost.doubleTen),
      );
      expect(vm.researchAvailability().open, greaterThan(0));
      expect(vm.buyResearch(Research.magnet), isA<ProgressionActionDone>());
      expect(
        vm.buyBoost(Boost.tripleFifteen),
        isA<ProgressionInsufficientCoins>(),
      );

      model.dispose();
      ads.dispose();
    },
  );

  test('StreakViewModel computes freeze shortfall and milestones', () async {
    final model = AppModel(storage: _MemStorage(), snapshot: {});
    final vm = StreakViewModel(model);

    expect(vm.milestones, isNotEmpty);
    expect(vm.freezeFull, isFalse);
    expect(await vm.buyFreeze(), isA<FreezeInsufficientCoins>());

    model.dispose();
  });

  test('JourneyViewModel parses jump targets and bounds', () {
    final max = JourneyViewModel.maxLevelForExtent(132.0);
    expect(max, greaterThan(1000000));
    expect(JourneyViewModel.parseJumpLevel('0', maxLevel: max), isNull);
    expect(JourneyViewModel.parseJumpLevel('abc', maxLevel: max), isNull);
    expect(JourneyViewModel.parseJumpLevel('42', maxLevel: max), 42);
    expect(
      JourneyViewModel.parseJumpLevel('${max + 1}', maxLevel: max),
      isNull,
    );
  });

  test('GameplayViewModel, HomeViewModel, FortuneViewModel, CrateViewModel initialize cleanly', () {
    final model = AppModel(storage: _MemStorage(), snapshot: {});
    final ads = AdService();
    final gameplay = GameplayViewModel(model: model, ads: ads);
    final home = HomeViewModel(model: model, ads: ads);
    final fortune = FortuneViewModel(
      model: model,
      ads: ads,
      catalogLoader: () async =>
          FortuneCatalog('[{"id":"a","label":"8","weight":100,"coins":8}]'),
    );
    final crate = CrateViewModel(model: model, ads: ads);

    expect(
      gameplay.summarizeCompletion(const PuzzleId.level(1)).nextPuzzle?.level,
      2,
    );
    expect(home.canOpenPuzzle(const PuzzleId.level(1)), isTrue);
    expect(home.canOpenPuzzle(const PuzzleId.level(2)), isFalse);
    expect(fortune.videosRemaining, 0);
    expect(crate.reveal((id: 'x', coins: 25)), isFalse);

    model.dispose();
    ads.dispose();
  });

  test('FortuneStatus preserves legacy 4-stamp limit', () {
    final now = DateTime.utc(2026, 11, 27).millisecondsSinceEpoch;
    final status = FortuneStatus.fromJson({
      'version': 2,
      'now': now,
      'stamps': List.generate(4, (i) => now - i * 1000),
      'counts': <String, int>{},
    });
    expect(status.remaining(0), 0);
  });
}
