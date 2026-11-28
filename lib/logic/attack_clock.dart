import 'dart:async';

import 'package:flutter/services.dart';

import '../model/time_attack.dart';

class AttackClock {
  static const _channel = MethodChannel('com.shenmareparas.pathwise/clock');
  final _watch = Stopwatch()..start();
  BootTime? _anchor;
  int _position = 0;

  Future<void> sync() async {
    try {
      final value = await _channel
          .invokeListMethod<int>('bootTime')
          .timeout(const Duration(seconds: 2));
      if (value == null || value.length != 2 || value.first < 0) return;
      _anchor = (boot: value.first, milliseconds: value.last);
      _position = _watch.elapsedMilliseconds;
    } on MissingPluginException {
      // Desktop tests can inject a clock.
    } on TimeoutException {
      // Avoid blocking startup if the native clock is slow.
    } on PlatformException {
      // Preserve the last monotonic anchor if a platform read fails.
    }
  }

  BootTime? read() {
    final anchor = _anchor;
    return anchor == null
        ? null
        : (
            boot: anchor.boot,
            milliseconds:
                anchor.milliseconds + _watch.elapsedMilliseconds - _position,
          );
  }
}
