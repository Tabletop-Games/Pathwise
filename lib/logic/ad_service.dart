import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Consent-aware cache with post-game placements and a separate opt-in video.
class AdService extends ChangeNotifier {
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
  static const _minGap = Duration(minutes: 4);
  static const _clearsBetweenAds = 5;

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
  bool _fullScreen = false;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;
  int _consentGeneration = 0;
  int _clears = 0;
  DateTime? _lastInterstitial;
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

  void afterCompletedExit({required bool canPresent}) {
    if (!enabled || _disposed) return;
    _clears++;
    final now = DateTime.now();
    if (!canPresent ||
        !_canRequest ||
        _fullScreen ||
        !ready(_interstitial) ||
        _clears < _clearsBetweenAds ||
        (_lastInterstitial != null &&
            now.difference(_lastInterstitial!) < _minGap)) {
      _preload();
      return;
    }
    final ad = _interstitial!.$1;
    _interstitial = null;
    _clears = 0;
    _lastInterstitial = now;
    _fullScreen = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => _finished(ad),
      onAdFailedToShowFullScreenContent: (_, _) => _finished(ad),
    );
    unawaited(ad.show().catchError((Object _) => _finished(ad)));
  }

  void watchVideo(Future<bool> Function(String) reward) {
    if (!videoReady || _disposed) return;
    final ad = _rewarded!.$1;
    _rewarded = null;
    _fullScreen = true;
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
            onUserEarnedReward: (_, _) {
              if (granted || _disposed) return;
              granted = true;
              unawaited(
                reward(id).then((saved) {
                  if (!saved) _report('The video bonus could not be saved.');
                }),
              );
            },
          )
          .catchError((Object _) => _finished(ad)),
    );
  }

  void _finished(Ad ad) {
    if (!_fullScreen) return;
    _fullScreen = false;
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
    _clearCache();
    super.dispose();
  }
}
