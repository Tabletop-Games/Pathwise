import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Semantic haptic feedback categories across Pathwise.
enum HapticEvent {
  button,
  tab,
  toggle,
  step,
  retract,
  checkpoint,
  ice,
  portal,
  keyCollected,
  gateUnlocked,
  invalidMove,
  puzzleComplete,
  starReveal,
  coinReward,
  hint,
  research,
  boost,
  cosmetic,
  treasure,
  mysteryReveal,
  wheelTick,
  wheelResult,
  celebrate,
  countdown,
  attackFinished,
  multiplierStop,
  rejectAction,
}

enum HapticKind { tick, light, medium, heavy, confirm, reject }

abstract interface class HapticBackend {
  Future<bool> trigger(HapticKind kind);
}

final class PlatformHapticBackend implements HapticBackend {
  static const _channel = MethodChannel('games.tabletop.pathwise/haptics');
  bool _nativeSupported = true;

  @override
  Future<bool> trigger(HapticKind kind) async {
    if (!kIsWeb && Platform.isAndroid && _nativeSupported) {
      try {
        final handled = await _channel.invokeMethod<bool>('trigger', {
          'kind': kind.name,
        });
        if (handled == true) return true;
        if (handled == false) return false;
      } on MissingPluginException {
        _nativeSupported = false;
      } on PlatformException {
        _nativeSupported = false;
      }
    }
    switch (kind) {
      case HapticKind.tick:
        await HapticFeedback.selectionClick();
      case HapticKind.light:
        await HapticFeedback.lightImpact();
      case HapticKind.medium:
      case HapticKind.confirm:
        await HapticFeedback.mediumImpact();
      case HapticKind.heavy:
      case HapticKind.reject:
        await HapticFeedback.heavyImpact();
    }
    return true;
  }
}

/// Centralizes semantic haptic feedback with rate-limiting, deduplication,
/// lifecycle suppression, and graceful fallback on unsupported hardware.
class HapticService {
  HapticService({
    bool enabled = false,
    HapticBackend? backend,
    DateTime Function()? now,
  }) : _enabled = enabled,
       _backend = backend ?? PlatformHapticBackend(),
       _now = now ?? DateTime.now;

  static const _globalMinGapMs = 24;

  final HapticBackend _backend;
  final DateTime Function() _now;

  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool value) {
    _enabled = value;
    if (!value) _cancelPending();
  }

  bool _foreground = true;
  bool _adPlaying = false;
  DateTime? _lastGlobal;
  final Map<HapticEvent, DateTime> _lastByEvent = {};
  final List<Timer> _patternTimers = [];
  Object? _lastRejectionToken;

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) _cancelPending();
  }

  void setAdPlaying(bool adPlaying) {
    _adPlaying = adPlaying;
    if (adPlaying) _cancelPending();
  }

  void resetRejectionDeduplication() {
    _lastRejectionToken = null;
  }

  void _cancelPending() {
    for (final timer in _patternTimers) {
      timer.cancel();
    }
    _patternTimers.clear();
  }

  bool get _canFire => _enabled && _foreground && !_adPlaying;

  void trigger(HapticEvent event, {Object? dedupeToken}) {
    if (!_canFire) return;
    if (event == HapticEvent.invalidMove && dedupeToken != null) {
      if (_lastRejectionToken == dedupeToken) return;
      _lastRejectionToken = dedupeToken;
    }

    final now = _now();
    final cooldownMs = _cooldownMs(event);
    final prevEvent = _lastByEvent[event];
    if (prevEvent != null &&
        now.difference(prevEvent).inMilliseconds < cooldownMs) {
      return;
    }
    if (_lastGlobal != null &&
        now.difference(_lastGlobal!).inMilliseconds < _globalMinGapMs &&
        !_isHighPriority(event)) {
      return;
    }

    _lastByEvent[event] = now;
    _lastGlobal = now;

    switch (event) {
      case HapticEvent.puzzleComplete:
      case HapticEvent.treasure:
      case HapticEvent.mysteryReveal:
      case HapticEvent.celebrate:
        _firePattern(const [(0, HapticKind.confirm), (95, HapticKind.light)]);
      case HapticEvent.invalidMove:
      case HapticEvent.rejectAction:
        unawaited(_backend.trigger(HapticKind.reject));
      case HapticEvent.button:
      case HapticEvent.tab:
      case HapticEvent.step:
      case HapticEvent.retract:
      case HapticEvent.wheelTick:
      case HapticEvent.countdown:
        unawaited(_backend.trigger(HapticKind.tick));
      case HapticEvent.toggle:
      case HapticEvent.checkpoint:
      case HapticEvent.ice:
      case HapticEvent.keyCollected:
      case HapticEvent.starReveal:
      case HapticEvent.coinReward:
      case HapticEvent.hint:
        unawaited(_backend.trigger(HapticKind.light));
      case HapticEvent.portal:
      case HapticEvent.gateUnlocked:
      case HapticEvent.research:
      case HapticEvent.boost:
      case HapticEvent.cosmetic:
      case HapticEvent.wheelResult:
      case HapticEvent.attackFinished:
      case HapticEvent.multiplierStop:
        unawaited(_backend.trigger(HapticKind.medium));
    }
  }

  void _firePattern(List<(int delayMs, HapticKind kind)> steps) {
    _cancelPending();
    for (final (delayMs, kind) in steps) {
      if (delayMs == 0) {
        unawaited(_backend.trigger(kind));
      } else {
        late final Timer timer;
        timer = Timer(Duration(milliseconds: delayMs), () {
          _patternTimers.remove(timer);
          if (_canFire) unawaited(_backend.trigger(kind));
        });
        _patternTimers.add(timer);
      }
    }
  }

  static bool _isHighPriority(HapticEvent event) => switch (event) {
    HapticEvent.puzzleComplete ||
    HapticEvent.treasure ||
    HapticEvent.mysteryReveal ||
    HapticEvent.celebrate ||
    HapticEvent.invalidMove ||
    HapticEvent.rejectAction ||
    HapticEvent.wheelResult ||
    HapticEvent.attackFinished => true,
    _ => false,
  };

  static int _cooldownMs(HapticEvent event) => switch (event) {
    HapticEvent.step => 38,
    HapticEvent.retract => 45,
    HapticEvent.button || HapticEvent.tab || HapticEvent.toggle => 40,
    HapticEvent.wheelTick => 50,
    HapticEvent.checkpoint || HapticEvent.starReveal => 60,
    HapticEvent.ice ||
    HapticEvent.portal ||
    HapticEvent.keyCollected ||
    HapticEvent.gateUnlocked ||
    HapticEvent.coinReward => 75,
    HapticEvent.hint ||
    HapticEvent.research ||
    HapticEvent.boost ||
    HapticEvent.cosmetic ||
    HapticEvent.multiplierStop => 100,
    HapticEvent.wheelResult ||
    HapticEvent.puzzleComplete ||
    HapticEvent.treasure ||
    HapticEvent.mysteryReveal ||
    HapticEvent.celebrate ||
    HapticEvent.attackFinished => 150,
    HapticEvent.invalidMove || HapticEvent.rejectAction => 140,
    HapticEvent.countdown => 200,
  };

  // Convenience wrappers preserving compatibility with existing callers/tests.
  void selection() => trigger(HapticEvent.button);
  void light() => trigger(HapticEvent.toggle);
  void error() => trigger(HapticEvent.invalidMove);
  void complete() => trigger(HapticEvent.puzzleComplete);

  void dispose() {
    _cancelPending();
  }
}
