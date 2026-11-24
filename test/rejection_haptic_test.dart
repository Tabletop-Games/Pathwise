import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/haptic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
