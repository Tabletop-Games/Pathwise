import '../logic/ad_service.dart';
import '../logic/play_games.dart';
import '../model/app_model.dart';
import '../model/economy.dart';
import '../model/game_state.dart';

sealed class HintBuyResult {
  const HintBuyResult();
}

final class HintBought extends HintBuyResult {
  const HintBought();
}

final class HintInsufficientCoins extends HintBuyResult {
  const HintInsufficientCoins(this.shortfall);
  final int shortfall;
}

final class HintBuyFailed extends HintBuyResult {
  const HintBuyFailed();
}

typedef CompletionSummary = ({
  int levelCoins,
  int milestoneCoins,
  PuzzleId? nextPuzzle,
  bool showMultiplier,
});

/// Presentation logic for active gameplay, hints, completion summary,
/// and Time Attack score submission.
class GameplayViewModel {
  GameplayViewModel({required this.model, required this.ads});

  final AppModel model;
  final AdService ads;

  bool get canUseHintNow => model.hintsRemaining > 0 && model.canHint;

  /// Triggers a hint if available; returns false when the Hint Shop should open.
  bool tryUseHint() {
    if (model.isDrawing) return true;
    if (canUseHintNow) {
      model.hint();
      return true;
    }
    return false;
  }

  Future<HintBuyResult> buyHint() async {
    if (model.coinBalance < economy.hintPrice) {
      return HintInsufficientCoins(economy.hintPrice - model.coinBalance);
    }
    return await model.buyHint() ? const HintBought() : const HintBuyFailed();
  }

  Future<bool> watchHintVideo({required bool Function() canPresent}) async {
    if (!model.canEarnHintAd) return false;
    if (!ads.readyFor(RewardPlacement.hint)) {
      await ads.prepare(canPresent: canPresent);
      return false;
    }
    return ads.watchVideo(
      model.grantHintAd,
      placement: RewardPlacement.hint,
      canPresent: canPresent,
      waitForReward: true,
    );
  }

  CompletionSummary summarizeCompletion(PuzzleId id) {
    final next = switch (id.mode) {
      PlayMode.levels => PuzzleId.level(id.level + 1),
      PlayMode.daily =>
        id.checkpoint == null ? null : model.dailyCurrent(id.value as String),
      PlayMode.attack => null,
    };
    final levelCoins = model.completionCoins + model.earnedStarCoins;
    final milestoneCoins = model.lastReward > levelCoins
        ? model.lastReward - levelCoins
        : 0;
    return (
      levelCoins: levelCoins,
      milestoneCoins: milestoneCoins,
      nextPuzzle: next,
      showMultiplier:
          model.firstCampaignClear &&
          model.latestDiscovery == null &&
          id.mode == PlayMode.levels,
    );
  }

  Future<bool> submitAttackScore(int minutes, int score) async {
    if (!PlayGames.enabled) return false;
    if (!await PlayGames.isSignedIn() && !await PlayGames.signIn()) {
      return false;
    }
    return PlayGames.submitTimeAttackScore(minutes, score);
  }
}
