import 'package:flutter_test/flutter_test.dart';

import '../../lib/logic/ad_frequency.dart';
import '../../lib/model/app_model.dart';
import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frequency requires completed exits, monotonic spacing and post-reward cooldown', () {
    final caps = AdFrequency();
    for (var i = 0; i < 4; i++) {
      caps.completedExit();
    }
    expect(caps.eligible(Duration.zero), isFalse);
    caps.completedExit();
    expect(caps.eligible(Duration.zero), isTrue);
    caps.attemptedInterstitial(Duration.zero);
    for (var i = 0; i < 5; i++) {
      caps.completedExit();
    }
    expect(caps.eligible(const Duration(milliseconds: 179999)), isFalse);
    expect(caps.eligible(const Duration(minutes: 3)), isTrue);
    caps.rewardedClosed(const Duration(seconds: 235));
    expect(caps.eligible(const Duration(seconds: 294)), isFalse);
    expect(caps.eligible(const Duration(seconds: 295)), isTrue);
  });

  test(
    'persisted ad pacing also protects the first minutes after a reboot',
    () async {
      var clock = 60000;
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'lastAutomaticAd': {'boot': 4, 'milliseconds': 2000000},
        },
        bootTime: () => (boot: 5, milliseconds: clock),
      );
      expect(await model.reserveAutomaticAd(), isFalse);
      clock = 179999;
      expect(await model.reserveAutomaticAd(), isFalse);
      clock = 180000;
      expect(await model.reserveAutomaticAd(), isTrue);
      expect(await model.reserveAutomaticAd(), isFalse);
      model.dispose();
    },
  );
}
