import 'package:flutter/services.dart';

import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/economy_activity.dart';
import '../model/fortune.dart';

typedef FortuneCatalogLoader = Future<FortuneCatalog> Function();

Future<FortuneCatalog> defaultFortuneCatalogLoader() async => FortuneCatalog(
  await rootBundle.loadString('assets/data/fortune-prizes.json'),
);

/// Presentation logic and spin orchestration for the Fortune Wheel.
class FortuneViewModel {
  FortuneViewModel({
    required this.model,
    required this.ads,
    FortuneCatalogLoader? catalogLoader,
  }) : _catalogLoader = catalogLoader ?? defaultFortuneCatalogLoader;

  final AppModel model;
  final AdService ads;
  final FortuneCatalogLoader _catalogLoader;

  Future<FortuneCatalog> loadCatalog() => _catalogLoader();

  int get freeWaitMs => model.fortuneWait;
  bool get freeReady => freeWaitMs == 0 && model.pendingFortune == null;
  int get videosRemaining => model.fortuneVideosRemaining;
  bool get videoReady => ads.readyFor(RewardPlacement.wheel);

  Future<FortunePrize?> spinFree(FortuneCatalog catalog) async {
    model.recordActivity(EconomyEvent.wheelRequested);
    return model.spinFreeFortune(catalog);
  }

  Future<FortunePrize?> spinRewarded(
    FortuneCatalog catalog, {
    required bool Function() canPresent,
  }) async {
    if (model.fortuneVideosRemaining == 0) return null;
    if (!ads.readyFor(RewardPlacement.wheel)) {
      await ads.prepare(canPresent: canPresent);
      return null;
    }
    model.recordActivity(EconomyEvent.wheelRequested);
    FortunePrize? won;
    await ads.watchVideo(
      (event) async {
        won = await model.spinRewardedFortune(catalog, event);
        return won != null;
      },
      placement: RewardPlacement.wheel,
      canPresent: canPresent,
      waitForReward: true,
    );
    return won;
  }

  Future<bool> settle(FortunePrize prize) => model.settleFortune(prize);
}
