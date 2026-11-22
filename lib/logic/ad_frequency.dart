class AdFrequency {
  AdFrequency({
    this.minimumGap = const Duration(minutes: 4),
    this.rewardedGap = const Duration(minutes: 1),
    this.exitsPerInterstitial = 5,
  }) : assert(minimumGap >= const Duration(seconds: 60));

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
