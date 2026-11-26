import '../model/economy.dart';

class AdFrequency {
  AdFrequency({
    this.minimumGap = EconomyRules.automaticAdGap,
    Duration? rewardedGap,
    int? exitsPerInterstitial,
  }) : rewardedGap = rewardedGap ?? economy.afterRewardedGap,
       exitsPerInterstitial =
           exitsPerInterstitial ?? economy.exitsPerInterstitial,
       assert(minimumGap >= const Duration(seconds: 60));

  final Duration minimumGap;
  final Duration rewardedGap;
  final int exitsPerInterstitial;
  int _exits = 0;
  Duration? _lastInterstitial;
  Duration? _lastRewarded;

  void completedExit() => _exits++;
  bool eligible(Duration now) =>
      _exits >= exitsPerInterstitial &&
      (_lastInterstitial == null || now - _lastInterstitial! >= minimumGap) &&
      (_lastRewarded == null || now - _lastRewarded! >= rewardedGap);

  void attemptedInterstitial(Duration now) {
    _lastInterstitial = now;
    _exits = 0;
  }

  void rewardedClosed(Duration now) => _lastRewarded = now;
}
