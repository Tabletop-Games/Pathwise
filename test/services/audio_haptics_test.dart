import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/logic/haptic_service.dart';
import '../../lib/logic/sound_service.dart';
import '../../lib/model/app_model.dart';
import '../support/fixtures.dart';

final class _FakeSoundBackend implements SoundBackend {
  final List<String> played = [];
  final List<double> volumes = [];
  int pauseCalls = 0;
  int resumeCalls = 0;
  int preloadCalls = 0;

  @override
  Future<void> preload(List<String> assets) async {
    preloadCalls++;
  }

  @override
  Future<void> play(
    String asset, {
    required double volume,
    double rate = 1.0,
    int priority = 1,
  }) async {
    played.add(asset);
    volumes.add(volume);
  }

  @override
  Future<void> pauseAll() async => pauseCalls++;

  @override
  Future<void> resumeAll() async => resumeCalls++;

  @override
  Future<void> dispose() async {}
}

final class _FakeHapticBackend implements HapticBackend {
  _FakeHapticBackend({this.supported = true});
  final bool supported;
  final List<HapticKind> fired = [];

  @override
  Future<bool> trigger(HapticKind kind) async {
    if (!supported) return false;
    fired.add(kind);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio & Haptics services', () {
    test(
      'preferences are independent and volume persists across mute',
      () async {
        final storage = MemoryStorage();
        final soundBackend = _FakeSoundBackend();
        final hapticBackend = _FakeHapticBackend();
        final model = AppModel(
          storage: storage,
          snapshot: {},
          sound: SoundService(backend: soundBackend),
          haptic: HapticService(backend: hapticBackend),
        );

        expect(model.soundEnabled, isTrue);
        expect(model.haptics, isTrue);
        expect(model.soundVolume, closeTo(0.75, 1e-9));

        model.setSoundVolume(0.42, preview: true);
        expect(model.soundVolume, closeTo(0.42, 1e-9));
        expect(
          soundBackend.played,
          contains('assets/audio/sfx_checkpoint.wav'),
        );

        model.setSoundEnabled(false);
        expect(model.soundEnabled, isFalse);
        expect(model.haptics, isTrue);
        expect(model.soundVolume, closeTo(0.42, 1e-9));

        final countBefore = soundBackend.played.length;
        model.sound.play(SoundEvent.button);
        expect(soundBackend.played.length, countBefore);

        model.setSoundEnabled(true);
        expect(model.soundEnabled, isTrue);
        expect(model.soundVolume, closeTo(0.42, 1e-9));

        model.setHaptics(false);
        expect(model.haptics, isFalse);
        expect(model.soundEnabled, isTrue);

        await model.flush();
        final restored = AppModel(
          storage: storage,
          snapshot: await storage.load(),
        );
        expect(restored.soundEnabled, isTrue);
        expect(restored.haptics, isFalse);
        expect(restored.soundVolume, closeTo(0.42, 1e-9));

        model.dispose();
        restored.dispose();
      },
    );

    test(
      'rate-limiting, deduplication, lifecycle, and ad suppression work',
      () {
        var now = DateTime(2026, 11, 27, 12, 0, 0);
        final soundBackend = _FakeSoundBackend();
        final hapticBackend = _FakeHapticBackend();
        final sound = SoundService(
          enabled: true,
          volume: 0.8,
          backend: soundBackend,
          now: () => now,
        );
        final haptic = HapticService(
          enabled: true,
          backend: hapticBackend,
          now: () => now,
        );

        // Step cooldown deduplicates rapid bursts.
        sound.play(SoundEvent.step);
        sound.play(SoundEvent.step);
        haptic.trigger(HapticEvent.step);
        haptic.trigger(HapticEvent.step);
        expect(soundBackend.played.length, 1);
        expect(hapticBackend.fired.length, 1);

        // Invalid move deduplicates same gesture token.
        now = now.add(const Duration(milliseconds: 200));
        haptic.trigger(HapticEvent.invalidMove, dedupeToken: (0, 1));
        now = now.add(const Duration(milliseconds: 200));
        haptic.trigger(HapticEvent.invalidMove, dedupeToken: (0, 1));
        expect(hapticBackend.fired.length, 2);

        haptic.resetRejectionDeduplication();
        now = now.add(const Duration(milliseconds: 200));
        haptic.trigger(HapticEvent.invalidMove, dedupeToken: (0, 1));
        expect(hapticBackend.fired.length, 3);

        // Background and ads suppress both audio and haptics.
        sound.setForeground(false);
        haptic.setForeground(false);
        expect(soundBackend.pauseCalls, 1);
        now = now.add(const Duration(seconds: 1));
        sound.play(SoundEvent.coinReward);
        haptic.trigger(HapticEvent.coinReward);
        expect(soundBackend.played.length, 1);
        expect(hapticBackend.fired.length, 3);

        sound.setForeground(true);
        haptic.setForeground(true);
        expect(soundBackend.resumeCalls, 1);

        sound.setAdPlaying(true);
        haptic.setAdPlaying(true);
        now = now.add(const Duration(seconds: 1));
        sound.play(SoundEvent.coinReward);
        haptic.trigger(HapticEvent.coinReward);
        expect(soundBackend.played.length, 1);
        expect(hapticBackend.fired.length, 3);

        sound.setAdPlaying(false);
        haptic.setAdPlaying(false);
        now = now.add(const Duration(seconds: 1));
        sound.play(SoundEvent.coinReward);
        haptic.trigger(HapticEvent.coinReward);
        expect(soundBackend.played.length, 2);
        expect(hapticBackend.fired.length, 4);
      },
    );

    test('unsupported haptic hardware fails gracefully', () {
      final backend = _FakeHapticBackend(supported: false);
      final haptic = HapticService(enabled: true, backend: backend);
      expect(() => haptic.trigger(HapticEvent.puzzleComplete), returnsNormally);
      expect(backend.fired, isEmpty);
      haptic.dispose();
    });
  });

  test('rejection haptic follows the preference', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final haptic = HapticService();
    haptic.error();
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    haptic.enabled = true;
    haptic.error();
    await Future<void>.delayed(Duration.zero);
    expect(calls.single.method, 'HapticFeedback.vibrate');
    expect(calls.single.arguments, 'HapticFeedbackType.heavyImpact');
  });
}
