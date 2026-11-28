import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android identity and launcher agree', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final activity = File(
      'android/app/src/main/java/com/shenmareparas/pathwise/MainActivity.java',
    ).readAsStringSync();
    expect(gradle, contains('namespace = "com.shenmareparas.pathwise"'));
    expect(gradle, contains('applicationId = "com.shenmareparas.pathwise"'));
    expect(activity, startsWith('package com.shenmareparas.pathwise;'));
    expect(
      manifest,
      contains('android:name="com.shenmareparas.pathwise.MainActivity"'),
    );
    expect(manifest, contains('android:label="\${pathwiseAppLabel}"'));
    expect(gradle, contains('applicationIdSuffix = ".debug"'));
    expect(
      gradle,
      contains('manifestPlaceholders["pathwiseAppLabel"] = "Pathwise Debug"'),
    );
    expect(
      gradle,
      contains('manifestPlaceholders["pathwiseAppLabel"] = "Pathwise"'),
    );
    expect(gradle, contains('minifyEnabled = true'));
    expect(gradle, contains('shrinkResources = true'));
    expect(gradle, contains('PATHWISE_ADMOB_APP_ID'));
    expect(gradle, contains('signingConfigs.release'));
  });
}
