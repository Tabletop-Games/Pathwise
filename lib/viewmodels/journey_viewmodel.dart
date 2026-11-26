import 'dart:math';

import '../logic/ad_service.dart';
import '../logic/connectivity_service.dart';
import '../model/app_model.dart';
import '../model/economy.dart';
import '../model/journey.dart';
import '../model/user_preferences.dart';

/// Presentation logic for Campaign Journey navigation, chapters, chests,
/// mystery rewards, and completion multipliers.
class JourneyViewModel {
  JourneyViewModel({required this.model, required this.ads, this.connectivity});

  final AppModel model;
  final AdService ads;
  final ConnectivityService? connectivity;

  static int maxLevelForExtent(double extent, {int slotsPerChapter = 27}) =>
      (1 << 49) ~/ max(1.0, extent) ~/ slotsPerChapter * chapterSize;

  static int? parseJumpLevel(String input, {required int maxLevel}) {
    final target = int.tryParse(input.trim());
    if (target == null || target < 1 || target > maxLevel) return null;
    return target;
  }

  Future<bool> claimChapter(int chapter) => model.claimChapter(chapter);

  Future<bool> watchCompletionMultiplier({
    required int multiplier,
    required bool Function() canPresent,
  }) async {
    model.selectCompletionMultiplier(multiplier);
    final reward = model.completionRewardCallback();
    if (reward == null) return false;
    return ads.watchVideo(reward, canPresent: canPresent, waitForReward: true);
  }

  Future<bool> claimMystery(
    Discovery offer, {
    required bool isCoins,
    required bool Function() canPresent,
  }) async {
    if (!isCoins) {
      return model.claimMysteryReward(offer);
    }
    if (!model.onlineReady) {
      await connectivity?.retry();
    }
    if (model.onlineReady && !ads.videoReady) {
      await ads.prepare(canPresent: canPresent);
    }
    if (!model.onlineReady || !ads.videoReady) return false;
    final reward = model.mysteryRewardCallback();
    if (reward == null) return false;
    return ads.watchVideo(reward, canPresent: canPresent, waitForReward: true);
  }

  Future<bool> equipTip(PathTip tip) => model.equipTip(tip);

  void equipTheme(PathwiseTheme theme) => model.setTheme(theme);
}
