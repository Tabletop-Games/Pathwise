import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../model/economy.dart';
import 'ad_frequency.dart';

/// Consent-aware cache with post-game placements and a separate opt-in video.
class AdService extends ChangeNotifier {
  AdService({this.reserveInterstitial, this.onRewardedClosed});
  final Future<bool> Function()? reserveInterstitial;
  final VoidCallback? onRewardedClosed;
  bool _reserving = false;
  static const _test =
      !kReleaseMode && bool.fromEnvironment('PATHWISE_ADS_TEST');
  static const _enabled = bool.fromEnvironment('PATHWISE_ADS_ENABLED');
  static const _privacyConfigured = bool.fromEnvironment(
    'PATHWISE_ADS_CONSENT_CONFIGURED',
  );
  static const _prodInterstitial = String.fromEnvironment(
    'PATHWISE_ADMOB_INTERSTITIAL',
  );
  static const _prodRewarded = String.fromEnvironment(
    'PATHWISE_ADMOB_REWARDED',
  );
  static const _ttl = Duration(minutes: 45);
  static const _bannerUnit = String.fromEnvironment('PATHWISE_ADMOB_BANNER');
  static const _network = MethodChannel('games.tabletop.pathwise/clock');
  final _frequency = AdFrequency(
    minimumGap: economy.automaticAdGap,
    rewardedGap: economy.afterRewardedGap,
    exitsPerInterstitial: economy.exitsPerInterstitial,
  );
  final _watch = Stopwatch()..start();
  bool _checkingReward = false;
  bool get canLoadBanner => _canRequest && enabled;
  int get consentRevision => _consentGeneration;
  String get bannerUnit =>
      _test ? 'ca-app-pub-3940256099942544/9214589741' : _bannerUnit;
  bool get bannerConfigured => _test || validAdUnit(_bannerUnit);
  Future<bool> _online() async {
    try {
      return await _network.invokeMethod<bool>('online') == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  bool get enabled =>
      defaultTargetPlatform == TargetPlatform.android &&
      (_test ||
          (_enabled &&
              _privacyConfigured &&
              validAdUnit(_prodInterstitial) &&
              validAdUnit(_prodRewarded)));
  static bool validAdUnit(String id) =>
      RegExp(r'^ca-app-pub-[0-9]{16}/[0-9]{10}$').hasMatch(id) &&
      !id.startsWith('ca-app-pub-3940256099942544/');
  bool get testMode => _test;
  bool get privacyRequired => _privacyRequired;
  bool _privacyRequired = false;
  bool _disposed = false;
  bool _canRequest = false;
  bool _preparing = false;
  Ad? _showing;
  bool get _fullScreen => _showing != null;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;
  int _consentGeneration = 0;
  (InterstitialAd, DateTime)? _interstitial;
  (RewardedAd, DateTime)? _rewarded;
  bool get videoReady => ready(_rewarded) && _canRequest && !_fullScreen;
  String? message;

  bool ready((Ad, DateTime)? cached) =>
      cached != null && DateTime.now().difference(cached.$2) < _ttl;

  /// Invoke only from screens outside gameplay.
  Future<void> prepare({required bool Function() canPresent}) async {
    if (!enabled || _disposed || _preparing || _fullScreen) return;
    if (_canRequest) {
      _preload();
      return;
    }
    _preparing = true;
    final updated = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => updated.complete(),
        (error) => updated.completeError(StateError('Consent update failed')),
      );
      await updated.future.timeout(const Duration(seconds: 10));
      if (_disposed || !canPresent()) return;
      final form = Completer<void>();
      ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error == null) {
          form.complete();
        } else {
          form.completeError(StateError('Consent form unavailable'));
        }
      });
      await form.future.timeout(const Duration(seconds: 15));
      await _refreshConsent();
    } catch (_) {
      _report('Ad services are currently unavailable.');
    } finally {
      _preparing = false;
    }
  }

  Future<void> privacyOptions() async {
    if (!_privacyRequired || _fullScreen || _preparing || _disposed) return;
    _preparing = true;
    _canRequest = false;
    _consentGeneration++;
    _clearCache();
    _report(null);
    try {
      final done = Completer<void>();
      ConsentForm.showPrivacyOptionsForm((error) {
        if (error == null) {
          done.complete();
        } else {
          done.completeError(StateError('Privacy choices unavailable'));
        }
      });
      await done.future.timeout(const Duration(seconds: 15));
      await _refreshConsent();
    } catch (_) {
      _report('Privacy choices could not be loaded.');
    } finally {
      _preparing = false;
    }
  }

  Future<void> _refreshConsent() async {
    _privacyRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    if (_disposed) return;
    _canRequest = await ConsentInformation.instance.canRequestAds();
    if (_canRequest && !_disposed) {
      await MobileAds.instance.initialize();
      _preload();
    }
    _report(null);
  }

  void _preload() {
    if (!_canRequest || _disposed) return;
    final generation = _consentGeneration;
    if (!_loadingInterstitial && !ready(_interstitial)) {
      _interstitial?.$1.dispose();
      _interstitial = null;
      _loadingInterstitial = true;
      unawaited(
        InterstitialAd.load(
          adUnitId: _test
              ? 'ca-app-pub-3940256099942544/1033173712'
              : _prodInterstitial,
          request: const AdRequest(),
          adLoadCallback: InterstitialAdLoadCallback(
            onAdLoaded: (ad) {
              _loadingInterstitial = false;
              if (_disposed ||
                  !_canRequest ||
                  generation != _consentGeneration) {
                ad.dispose();
              } else {
                _interstitial = (ad, DateTime.now());
              }
            },
            onAdFailedToLoad: (_) => _loadingInterstitial = false,
          ),
        ).catchError((Object _) {
          _loadingInterstitial = false;
        }),
      );
    }
    if (!_loadingRewarded && !ready(_rewarded)) {
      _rewarded?.$1.dispose();
      _rewarded = null;
      _loadingRewarded = true;
      unawaited(
        RewardedAd.load(
          adUnitId: _test
              ? 'ca-app-pub-3940256099942544/5224354917'
              : _prodRewarded,
          request: const AdRequest(),
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (ad) {
              _loadingRewarded = false;
              if (_disposed ||
                  !_canRequest ||
                  generation != _consentGeneration) {
                ad.dispose();
              } else {
                _rewarded = (ad, DateTime.now());
                _report(null);
              }
            },
            onAdFailedToLoad: (_) {
              _loadingRewarded = false;
              _report('No videos available. Try again later.');
            },
          ),
        ).catchError((Object _) {
          _loadingRewarded = false;
          _report('No videos available. Try again later.');
        }),
      );
    }
  }

  Future<void> afterCompletedExit({
    required bool canPresent,
    bool Function()? stillPresent,
  }) async {
    if (!enabled || _disposed) return;
    _frequency.completedExit();
    final now = _watch.elapsed;
    if (!canPresent ||
        !_canRequest ||
        _fullScreen ||
        !ready(_interstitial) ||
        !_frequency.eligible(now)) {
      _preload();
      return;
    }
    if (_reserving) return;
    _reserving = true;
    try {
      if (reserveInterstitial != null && !await reserveInterstitial!()) return;
      if (_disposed ||
          _fullScreen ||
          !_canRequest ||
          !ready(_interstitial) ||
          stillPresent?.call() == false)
        return;
    } finally {
      _reserving = false;
    }
    final ad = _interstitial!.$1;
    _interstitial = null;
    _frequency.attemptedInterstitial(now);
    _showing = ad;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => _finished(ad),
      onAdFailedToShowFullScreenContent: (_, _) => _finished(ad),
    );
    unawaited(ad.show().catchError((Object _) => _finished(ad)));
  }

  Future<bool> watchVideo(
    Future<bool> Function(String) reward, {
    bool Function()? canPresent,
  }) async {
    if (!videoReady || _disposed || _checkingReward) return false;
    _checkingReward = true;
    final online = await _online();
    _checkingReward = false;
    if (!online || !videoReady || _disposed || canPresent?.call() == false) {
      _report('Video unavailable. Check your connection and try again.');
      return false;
    }
    final ad = _rewarded!.$1;
    _rewarded = null;
    _showing = ad;
    var granted = false;
    final id = List.generate(
      3,
      (_) => Random.secure().nextInt(1 << 32).toRadixString(16),
    ).join('-');
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => _finished(ad),
      onAdFailedToShowFullScreenContent: (_, _) => _finished(ad),
    );
    _report(null);
    unawaited(
      ad
          .show(
            onUserEarnedReward: (_, _) async {
              if (granted || _disposed) return;
              granted = true;
              if (!await _online() || _disposed) return;
              unawaited(
                reward(id).then((saved) {
                  if (!saved) _report('The video bonus could not be saved.');
                }),
              );
            },
          )
          .catchError((Object _) => _finished(ad)),
    );
    return true;
  }

  void _finished(Ad ad) {
    if (!identical(_showing, ad)) return;
    if (ad is RewardedAd) {
      _frequency.rewardedClosed(_watch.elapsed);
      onRewardedClosed?.call();
    }
    _showing = null;
    unawaited(ad.dispose());
    _preload();
    _report(null);
  }

  void _report(String? value) {
    if (_disposed) return;
    message = value;
    notifyListeners();
  }

  void _clearCache() {
    _interstitial?.$1.dispose();
    _rewarded?.$1.dispose();
    _interstitial = null;
    _rewarded = null;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_showing?.dispose());
    _showing = null;
    _clearCache();
    super.dispose();
  }
}
