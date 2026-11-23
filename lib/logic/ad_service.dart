import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../model/economy.dart';
import 'ad_frequency.dart';

enum RewardPlacement { coins, hint, wheel, crate, boost }

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

  static const _ttl = Duration(minutes: 45);
  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;
  String get _bannerUnit => _ios
      ? const String.fromEnvironment('PATHWISE_ADMOB_IOS_BANNER')
      : const String.fromEnvironment('PATHWISE_ADMOB_BANNER');
  String get _prodInterstitial => _ios
      ? const String.fromEnvironment('PATHWISE_ADMOB_IOS_INTERSTITIAL')
      : const String.fromEnvironment('PATHWISE_ADMOB_INTERSTITIAL');
  String get _prodRewarded => _ios
      ? const String.fromEnvironment('PATHWISE_ADMOB_IOS_REWARDED')
      : const String.fromEnvironment('PATHWISE_ADMOB_REWARDED');
  static const _network = MethodChannel('games.tabletop.pathwise/clock');
  final _frequency = AdFrequency(
    minimumGap: EconomyRules.automaticAdGap,
    rewardedGap: economy.afterRewardedGap,
    exitsPerInterstitial: economy.exitsPerInterstitial,
  );
  final _watch = Stopwatch()..start();
  bool _checkingReward = false;
  bool get canLoadBanner => _canRequest && enabled;
  int get consentRevision => _consentGeneration;
  String get bannerUnit => _test
      ? (_ios
            ? 'ca-app-pub-3940256099942544/2435281174'
            : 'ca-app-pub-3940256099942544/9214589741')
      : _bannerUnit;
  bool get bannerConfigured => _test || validAdUnit(_bannerUnit);
  Future<bool> isOnline() async {
    try {
      return await _network
              .invokeMethod<bool>('online')
              .timeout(const Duration(seconds: 2)) ==
          true;
    } on TimeoutException {
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Set<String> get _productionUnits => [
    _prodInterstitial,
    _bannerUnit,
    for (final placement in RewardPlacement.values)
      if (placement != RewardPlacement.wheel &&
          placement != RewardPlacement.crate &&
          placement != RewardPlacement.boost)
        _unit(placement),
  ].toSet();

  bool get enabled =>
      (defaultTargetPlatform == TargetPlatform.android || _ios) &&
      (_test ||
          (kReleaseMode &&
              _enabled &&
              _privacyConfigured &&
              _productionUnits.length == 4 &&
              _productionUnits.every(validAdUnit)));
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
  final _loadingRewarded = <RewardPlacement>{};
  int _consentGeneration = 0;
  (InterstitialAd, DateTime)? _interstitial;
  final _rewarded = <RewardPlacement, (RewardedAd, DateTime)>{};
  bool readyFor(RewardPlacement placement) =>
      ready(_rewarded[placement]) && _canRequest && !_fullScreen;
  bool get wheelConfigured =>
      enabled &&
      (_test ||
          (validAdUnit(_unit(RewardPlacement.wheel)) &&
              !_productionUnits.contains(_unit(RewardPlacement.wheel))));
  bool get videoReady => readyFor(RewardPlacement.coins);
  String _unit(RewardPlacement placement) => switch (placement) {
    RewardPlacement.coins ||
    RewardPlacement.crate ||
    RewardPlacement.boost => _prodRewarded,
    RewardPlacement.hint =>
      _ios
          ? const String.fromEnvironment('PATHWISE_ADMOB_IOS_EXTRA_HINT')
          : const String.fromEnvironment('PATHWISE_ADMOB_EXTRA_HINT'),
    RewardPlacement.wheel =>
      _ios
          ? const String.fromEnvironment('PATHWISE_ADMOB_IOS_WHEEL')
          : const String.fromEnvironment('PATHWISE_ADMOB_WHEEL'),
  };
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
      if (_ios &&
          !_test &&
          await _network.invokeMethod<bool>('adsConfigured') != true) {
        _report('Ad services are currently unavailable.');
        return;
      }
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
              ? (_ios
                    ? 'ca-app-pub-3940256099942544/4411468910'
                    : 'ca-app-pub-3940256099942544/1033173712')
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
    for (final placement in RewardPlacement.values) {
      if (placement == RewardPlacement.wheel && !wheelConfigured) continue;
      if (!_test && !validAdUnit(_unit(placement))) continue;
      if (ready(_rewarded[placement]) || !_loadingRewarded.add(placement))
        continue;
      _rewarded.remove(placement)?.$1.dispose();
      unawaited(
        RewardedAd.load(
          adUnitId: _test
              ? (_ios
                    ? 'ca-app-pub-3940256099942544/1712485313'
                    : 'ca-app-pub-3940256099942544/5224354917')
              : _unit(placement),
          request: const AdRequest(),
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (ad) {
              _loadingRewarded.remove(placement);
              if (_disposed ||
                  !_canRequest ||
                  generation != _consentGeneration) {
                ad.dispose();
              } else {
                _rewarded[placement] = (ad, DateTime.now());
                _report(null);
              }
            },
            onAdFailedToLoad: (_) {
              _loadingRewarded.remove(placement);
              _report('No videos available. Try again later.');
            },
          ),
        ).catchError((Object _) {
          _loadingRewarded.remove(placement);
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
    RewardPlacement placement = RewardPlacement.coins,
    bool waitForReward = false,
  }) async {
    if (!readyFor(placement) || _disposed || _checkingReward) return false;
    _checkingReward = true;
    final online = await isOnline();
    _checkingReward = false;
    if (!online ||
        !readyFor(placement) ||
        _disposed ||
        canPresent?.call() == false) {
      _report('Video unavailable. Check your connection and try again.');
      return false;
    }
    final ad = _rewarded.remove(placement)!.$1;
    _showing = ad;
    var granted = false;
    var closed = false;
    final settled = waitForReward ? Completer<void>() : null;
    void finishReward() {
      if (settled != null && !settled.isCompleted) settled.complete();
    }

    final id = List.generate(
      3,
      (_) => Random.secure().nextInt(1 << 32).toRadixString(16),
    ).join('-');
    final expiry = Timer(const Duration(minutes: 3), () {
      closed = true;
      _finished(ad);
      finishReward();
    });
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        expiry.cancel();
        closed = true;
        _finished(ad);
        if (!granted) finishReward();
      },
      onAdFailedToShowFullScreenContent: (_, _) {
        expiry.cancel();
        closed = true;
        _finished(ad);
        finishReward();
      },
    );
    _report(null);
    unawaited(
      ad
          .show(
            onUserEarnedReward: (_, _) async {
              if (granted || closed || _disposed) return;
              granted = true;
              try {
                if (!await reward(id)) {
                  _report('The video bonus could not be saved.');
                }
              } catch (_) {
                _report('The video bonus could not be saved.');
              } finally {
                finishReward();
              }
            },
          )
          .catchError((Object _) {
            expiry.cancel();
            closed = true;
            _finished(ad);
            finishReward();
          }),
    );
    if (settled != null) {
      await settled.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {},
      );
    }
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
    for (final ad in _rewarded.values) {
      ad.$1.dispose();
    }
    _interstitial = null;
    _rewarded.clear();
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
