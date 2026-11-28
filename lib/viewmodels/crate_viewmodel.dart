import '../logic/ad_service.dart';
import '../model/app_model.dart';
import '../model/progression.dart';

/// Presentation logic for Supply Crate reveal, dismissal, and rewarded claim.
class CrateViewModel {
  CrateViewModel({required this.model, required this.ads});

  final AppModel model;
  final AdService ads;

  bool reveal(Crate crate) => model.revealCrate(crate);

  Future<({bool shown, bool claimed})> claimWithVideo(
    Crate crate, {
    required bool Function() canPresent,
  }) async {
    if (!ads.readyFor(RewardPlacement.crate)) {
      await ads.prepare(canPresent: canPresent);
    }
    if (!ads.readyFor(RewardPlacement.crate)) {
      return (shown: false, claimed: false);
    }
    var claimed = false;
    final shown = await ads.watchVideo(
      (receipt) async {
        claimed = await model.claimVerifiedCrate(crate, receipt);
        return claimed;
      },
      placement: RewardPlacement.crate,
      canPresent: canPresent,
      waitForReward: true,
    );
    return (shown: shown, claimed: claimed);
  }
}
