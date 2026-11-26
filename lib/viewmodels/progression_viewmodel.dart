import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/economy.dart';
import '../model/economy_activity.dart';
import '../model/progression.dart';

sealed class ProgressionActionResult {
  const ProgressionActionResult();
}

final class ProgressionActionDone extends ProgressionActionResult {
  const ProgressionActionDone([this.message]);
  final String? message;
}

final class ProgressionInsufficientCoins extends ProgressionActionResult {
  const ProgressionInsufficientCoins({
    required this.itemName,
    required this.shortfall,
  });
  final String itemName;
  final int shortfall;
}

final class ProgressionActionFailed extends ProgressionActionResult {
  const ProgressionActionFailed(this.message);
  final String message;
}

typedef BoostAdState = ({
  int limit,
  int todayCount,
  bool milestoneLocked,
  bool canEarn,
  bool videoReady,
});

/// Presentation logic for Research & Boosts.
class ProgressionViewModel {
  ProgressionViewModel({required this.model, required this.ads});

  final AppModel model;
  final AdService ads;

  Duration boostDuration(Boost boost) =>
      Duration(milliseconds: model.progression.boostDurationMs(boost));

  bool canWatchBoostAd(Boost boost) =>
      ads.enabled && (boost == Boost.doubleTen || boost == Boost.tripleFifteen);

  BoostAdState boostAdState(Boost boost) {
    final limit = boost == Boost.doubleTen ? economy.doubleBoostAdsPerDay : 1;
    final todayCount = model.boostAdsToday(boost);
    final milestoneLocked =
        boost == Boost.tripleFifteen &&
        model.adsToday < economy.coinAdMilestone;
    return (
      limit: limit,
      todayCount: todayCount,
      milestoneLocked: milestoneLocked,
      canEarn: model.canEarnBoostAd(boost),
      videoReady: ads.readyFor(RewardPlacement.boost),
    );
  }

  ({int open, int affordable}) researchAvailability() {
    var open = 0;
    var affordable = 0;
    for (final item in Research.values) {
      final rank = model.progression.rank(item);
      if (rank >= item.limit || !model.progression.unlocked(item)) continue;
      open++;
      if (model.coinBalance >= item.price(rank)) affordable++;
    }
    return (open: open, affordable: affordable);
  }

  void recordResearchPanelViewed() {
    final counts = researchAvailability();
    if (counts.open == 0) return;
    model.recordActivity(
      counts.affordable > 0
          ? EconomyEvent.researchAffordable
          : EconomyEvent.researchUnavailable,
    );
  }

  ProgressionActionResult buyResearch(Research item) {
    final rank = model.progression.rank(item);
    if (rank >= item.limit || !model.progression.unlocked(item)) {
      return const ProgressionActionFailed('Upgrade is currently locked.');
    }
    final price = item.price(rank);
    if (model.coinBalance < price) {
      return ProgressionInsufficientCoins(
        itemName: item.title,
        shortfall: price - model.coinBalance,
      );
    }
    if (model.research(item)) {
      return ProgressionActionDone('${item.title} upgraded.');
    }
    return const ProgressionActionFailed(
      'Unable to apply upgrade right now. Please try again.',
    );
  }

  ProgressionActionResult buyBoost(Boost boost) {
    if (!boost.availableToBuy) {
      return const ProgressionActionFailed('Boost is not available to buy.');
    }
    final price = model.progression.discount(boost.price);
    if (model.coinBalance < price) {
      return ProgressionInsufficientCoins(
        itemName: boost.title,
        shortfall: price - model.coinBalance,
      );
    }
    if (model.buyBoost(boost)) {
      return ProgressionActionDone('${boost.title} added to inventory.');
    }
    return const ProgressionActionFailed(
      'Unable to buy boost right now. Please try again.',
    );
  }

  bool activateBoost(Boost boost) => model.activateBoost(boost);

  Future<ProgressionActionResult> watchBoostVideo(
    Boost boost, {
    required bool Function() canPresent,
  }) async {
    if (!model.canEarnBoostAd(boost)) {
      return const ProgressionActionFailed(
        'Video offer unavailable right now.',
      );
    }
    if (!ads.readyFor(RewardPlacement.boost)) {
      await ads.prepare(canPresent: canPresent);
      return const ProgressionActionDone();
    }
    var granted = false;
    await ads.watchVideo(
      (id) async {
        granted = await model.grantBoostAd(boost, id);
        return granted;
      },
      placement: RewardPlacement.boost,
      canPresent: canPresent,
      waitForReward: true,
    );
    if (granted) {
      return ProgressionActionDone('${boost.title} added to inventory.');
    }
    return const ProgressionActionDone();
  }
}
