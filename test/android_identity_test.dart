import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android identity and launcher agree', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final activity = File('android/app/src/main/java/com/shenmareparas/pathwise/MainActivity.java').readAsStringSync();
    expect(gradle, contains('namespace = "com.shenmareparas.pathwise"'));
    expect(gradle, contains('applicationId = "com.shenmareparas.pathwise"'));
    expect(activity, startsWith('package com.shenmareparas.pathwise;'));
    expect(manifest, contains('android:name=".MainActivity"'));
    expect(gradle, contains('minifyEnabled = true'));
    expect(gradle, contains('shrinkResources = true'));
    expect(gradle, contains('PATHWISE_ADMOB_APP_ID'));
    expect(gradle, contains('signingConfigs.release'));
  });
}
