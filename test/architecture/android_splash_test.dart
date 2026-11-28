import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android launch resources use the black splash and launcher icon', () {
    for (final variant in ['values', 'values-night']) {
      final styles = File('android/app/src/main/res/$variant/styles.xml')
          .readAsStringSync();
      expect(styles, contains('<color name="pathwise_splash">#000000</color>'));
    }
    for (final variant in ['values-v31', 'values-night-v31']) {
      final styles = File('android/app/src/main/res/$variant/styles.xml')
          .readAsStringSync();
      expect(styles, contains('android:windowSplashScreenBackground'));
      expect(styles, contains('@mipmap/pathwise_route_launcher'));
    }
    for (final variant in ['drawable', 'drawable-v21']) {
      final launch = File(
        'android/app/src/main/res/$variant/launch_background.xml',
      ).readAsStringSync();
      expect(launch, contains('@mipmap/pathwise_route_launcher'));
      expect(launch, contains('android:gravity="center"'));
    }
  });
}
