import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/game_state.dart';

/// Presentation logic for the Home screen and puzzle launch/exit coordination.
class HomeViewModel {
  HomeViewModel({required this.model, required this.ads});

  final AppModel model;
  final AdService ads;

  bool canOpenPuzzle(PuzzleId id) {
    if (model.activeId != null) return false;
    if (id.mode == PlayMode.levels && !model.canPlayLevel(id.level)) {
      return false;
    }
    return true;
  }

  Future<bool> preparePuzzle(PuzzleId id, {bool replay = false}) async {
    if (!canOpenPuzzle(id)) return false;
    if (id.mode == PlayMode.attack) {
      return model.openAttack();
    }
    await model.open(id, replay: replay);
    return true;
  }

  Future<void> handlePuzzleExit({
    required bool completedBeforeExit,
    required bool canPresentAd,
    required bool Function() stillPresent,
  }) async {
    model.close();
    if (!model.adFree && completedBeforeExit) {
      await ads.afterCompletedExit(
        canPresent: canPresentAd && !model.adFree,
        stillPresent: stillPresent,
      );
    }
  }
}
