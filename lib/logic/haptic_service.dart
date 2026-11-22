import 'package:flutter/services.dart';

/// Centralizes haptic feedback and honors the player's preference.
class HapticService {
  HapticService({this.enabled = false});

  bool enabled;

  void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }

  void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  void complete() {
    if (enabled) HapticFeedback.mediumImpact();
  }
}
