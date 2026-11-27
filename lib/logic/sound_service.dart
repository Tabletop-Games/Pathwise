import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Semantic sound events across Pathwise.
enum SoundEvent {
  button,
  tab,
  toggle,
  dialogOpen,
  error,
  step,
  retract,
  checkpoint,
  ice,
  portal,
  keyCollected,
  gateUnlocked,
  invalidMove,
  hint,
  puzzleComplete,
  countdown,
  attackFinished,
  starReveal,
  coinReward,
  multiplierStop,
  mysteryReveal,
  treasure,
  wheelTick,
  wheelResult,
  research,
  boost,
  cosmetic,
  celebrate,
}

abstract interface class SoundBackend {
  Future<void> preload(List<String> assets);
  Future<void> play(
    String asset, {
    required double volume,
    double rate = 1.0,
    int priority = 1,
  });
  Future<void> pauseAll();
  Future<void> resumeAll();
  Future<void> dispose();
}

final class PlatformSoundBackend implements SoundBackend {
  static const _channel = MethodChannel('games.tabletop.pathwise/audio');
  bool _supported = !kIsWeb && Platform.isAndroid;

  @override
  Future<void> preload(List<String> assets) async {
    if (!_supported || assets.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('preload', {'assets': assets});
    } on MissingPluginException {
      _supported = false;
    } on PlatformException {
      _supported = false;
    }
  }

  @override
  Future<void> play(
    String asset, {
    required double volume,
    double rate = 1.0,
    int priority = 1,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('play', {
        'asset': asset,
        'volume': volume,
        'rate': rate,
        'priority': priority,
      });
    } on MissingPluginException {
      _supported = false;
    } on PlatformException {
      // Ignore transient playback failures cleanly.
    }
  }

  @override
  Future<void> pauseAll() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('pauseAll');
    } on MissingPluginException {
      _supported = false;
    } on PlatformException {
      // Ignore.
    }
  }

  @override
  Future<void> resumeAll() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('resumeAll');
    } on MissingPluginException {
      _supported = false;
    } on PlatformException {
      // Ignore.
    }
  }

  @override
  Future<void> dispose() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('dispose');
    } on MissingPluginException {
      _supported = false;
    } on PlatformException {
      // Ignore.
    }
  }
}

/// Centralized, offline-first sound effect coordinator with preloading,
/// priority/cooldown gating, concurrency bounds, lifecycle & ad handling.
class SoundService {
  SoundService({
    this.enabled = true,
    double volume = 0.75,
    SoundBackend? backend,
    DateTime Function()? now,
  }) : _volume = volume.clamp(0.0, 1.0).toDouble(),
       _backend = backend ?? PlatformSoundBackend(),
       _now = now ?? DateTime.now;

  static const _allAssets = <String>[
    'assets/audio/sfx_ui_tap.wav',
    'assets/audio/sfx_dialog.wav',
    'assets/audio/sfx_step.wav',
    'assets/audio/sfx_retract.wav',
    'assets/audio/sfx_checkpoint.wav',
    'assets/audio/sfx_ice.wav',
    'assets/audio/sfx_portal.wav',
    'assets/audio/sfx_key.wav',
    'assets/audio/sfx_gate.wav',
    'assets/audio/sfx_invalid.wav',
    'assets/audio/sfx_hint.wav',
    'assets/audio/sfx_complete.wav',
    'assets/audio/sfx_star.wav',
    'assets/audio/sfx_coin.wav',
    'assets/audio/sfx_upgrade.wav',
    'assets/audio/sfx_reward.wav',
    'assets/audio/sfx_wheel_tick.wav',
  ];

  static const _maxConcurrentWindow = 4;
  static const _concurrencyWindowMs = 140;

  final SoundBackend _backend;
  final DateTime Function() _now;

  bool enabled;
  double _volume;
  double get volume => _volume;
  set volume(double value) {
    _volume = value.clamp(0.0, 1.0).toDouble();
  }

  bool _foreground = true;
  bool _adPlaying = false;
  bool _preloaded = false;
  int _stepVariant = 0;

  final Map<SoundEvent, DateTime> _lastByEvent = {};
  final List<(DateTime at, int priority)> _recentStreams = [];

  Future<void> preload() async {
    if (_preloaded) return;
    _preloaded = true;
    await _backend.preload(_allAssets);
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) {
      unawaited(_backend.pauseAll());
    } else if (enabled && !_adPlaying) {
      unawaited(_backend.resumeAll());
    }
  }

  void setAdPlaying(bool adPlaying) {
    _adPlaying = adPlaying;
    if (adPlaying) {
      unawaited(_backend.pauseAll());
    } else if (enabled && _foreground) {
      unawaited(_backend.resumeAll());
    }
  }

  bool get _canPlay => enabled && _volume > 0.001 && _foreground && !_adPlaying;

  void play(SoundEvent event, {int? starIndex}) {
    if (!_canPlay) return;
    final now = _now();
    final spec = _specFor(event, starIndex: starIndex);

    final prev = _lastByEvent[event];
    if (prev != null && now.difference(prev).inMilliseconds < spec.cooldownMs) {
      return;
    }

    _recentStreams.removeWhere(
      (entry) => now.difference(entry.$1).inMilliseconds > _concurrencyWindowMs,
    );
    if (_recentStreams.length >= _maxConcurrentWindow && spec.priority < 3) {
      return;
    }

    _lastByEvent[event] = now;
    _recentStreams.add((now, spec.priority));

    final effectiveVolume = (_volume * spec.gain).clamp(0.0, 1.0).toDouble();
    unawaited(
      _backend.play(
        spec.asset,
        volume: effectiveVolume,
        rate: spec.rate,
        priority: spec.priority,
      ),
    );
  }

  void playVolumePreview() {
    play(SoundEvent.checkpoint);
  }

  ({String asset, double gain, double rate, int priority, int cooldownMs})
  _specFor(SoundEvent event, {int? starIndex}) {
    switch (event) {
      case SoundEvent.button:
        return (
          asset: 'assets/audio/sfx_ui_tap.wav',
          gain: 0.65,
          rate: 1.0,
          priority: 1,
          cooldownMs: 45,
        );
      case SoundEvent.tab:
        return (
          asset: 'assets/audio/sfx_ui_tap.wav',
          gain: 0.60,
          rate: 1.08,
          priority: 1,
          cooldownMs: 45,
        );
      case SoundEvent.toggle:
        return (
          asset: 'assets/audio/sfx_ui_tap.wav',
          gain: 0.68,
          rate: 1.14,
          priority: 1,
          cooldownMs: 45,
        );
      case SoundEvent.dialogOpen:
        return (
          asset: 'assets/audio/sfx_dialog.wav',
          gain: 0.60,
          rate: 1.0,
          priority: 1,
          cooldownMs: 120,
        );
      case SoundEvent.step:
        const rates = [0.97, 1.0, 1.03, 1.06];
        final rate = rates[_stepVariant++ % rates.length];
        return (
          asset: 'assets/audio/sfx_step.wav',
          gain: 0.55,
          rate: rate,
          priority: 0,
          cooldownMs: 42,
        );
      case SoundEvent.retract:
        return (
          asset: 'assets/audio/sfx_retract.wav',
          gain: 0.52,
          rate: 0.98,
          priority: 0,
          cooldownMs: 48,
        );
      case SoundEvent.checkpoint:
        return (
          asset: 'assets/audio/sfx_checkpoint.wav',
          gain: 0.80,
          rate: 1.0,
          priority: 2,
          cooldownMs: 80,
        );
      case SoundEvent.ice:
        return (
          asset: 'assets/audio/sfx_ice.wav',
          gain: 0.72,
          rate: 1.0,
          priority: 2,
          cooldownMs: 90,
        );
      case SoundEvent.portal:
        return (
          asset: 'assets/audio/sfx_portal.wav',
          gain: 0.78,
          rate: 1.0,
          priority: 2,
          cooldownMs: 110,
        );
      case SoundEvent.keyCollected:
        return (
          asset: 'assets/audio/sfx_key.wav',
          gain: 0.80,
          rate: 1.0,
          priority: 2,
          cooldownMs: 100,
        );
      case SoundEvent.gateUnlocked:
        return (
          asset: 'assets/audio/sfx_gate.wav',
          gain: 0.82,
          rate: 1.0,
          priority: 2,
          cooldownMs: 100,
        );
      case SoundEvent.invalidMove:
      case SoundEvent.error:
        return (
          asset: 'assets/audio/sfx_invalid.wav',
          gain: 0.75,
          rate: 1.0,
          priority: 2,
          cooldownMs: 150,
        );
      case SoundEvent.hint:
        return (
          asset: 'assets/audio/sfx_hint.wav',
          gain: 0.78,
          rate: 1.0,
          priority: 2,
          cooldownMs: 120,
        );
      case SoundEvent.puzzleComplete:
      case SoundEvent.attackFinished:
        return (
          asset: 'assets/audio/sfx_complete.wav',
          gain: 0.92,
          rate: 1.0,
          priority: 3,
          cooldownMs: 220,
        );
      case SoundEvent.starReveal:
        final pitch = switch (starIndex) {
          1 => 1.0,
          2 => 1.122,
          3 => 1.26,
          _ => 1.0,
        };
        return (
          asset: 'assets/audio/sfx_star.wav',
          gain: 0.75,
          rate: pitch,
          priority: 2,
          cooldownMs: 70,
        );
      case SoundEvent.coinReward:
      case SoundEvent.multiplierStop:
        return (
          asset: 'assets/audio/sfx_coin.wav',
          gain: 0.78,
          rate: 1.0,
          priority: 2,
          cooldownMs: 100,
        );
      case SoundEvent.research:
      case SoundEvent.boost:
      case SoundEvent.cosmetic:
        return (
          asset: 'assets/audio/sfx_upgrade.wav',
          gain: 0.85,
          rate: 1.0,
          priority: 3,
          cooldownMs: 140,
        );
      case SoundEvent.treasure:
      case SoundEvent.mysteryReveal:
      case SoundEvent.wheelResult:
      case SoundEvent.celebrate:
        return (
          asset: 'assets/audio/sfx_reward.wav',
          gain: 0.92,
          rate: 1.0,
          priority: 3,
          cooldownMs: 200,
        );
      case SoundEvent.wheelTick:
      case SoundEvent.countdown:
        return (
          asset: 'assets/audio/sfx_wheel_tick.wav',
          gain: 0.62,
          rate: 1.0,
          priority: 1,
          cooldownMs: 50,
        );
    }
  }

  Future<void> dispose() => _backend.dispose();
}
