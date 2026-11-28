import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<String> _importsOf(File file) {
  final lines = file.readAsLinesSync();
  return [
    for (final line in lines)
      if (line.trimLeft().startsWith('import ')) line.trim(),
  ];
}

List<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

void main() {
  group('MVVM architectural import boundaries', () {
    test('pure domain models do not depend on UI, views, or cloud', () {
      for (final file in _dartFiles('lib/model')) {
        final name = file.uri.pathSegments.last;
        if (name == 'app_themes.dart' || name == 'app_model.dart') continue;
        final imports = _importsOf(file);
        for (final imp in imports) {
          expect(
            imp,
            isNot(contains('package:flutter/')),
            reason: '$name must stay pure Dart ($imp)',
          );
          expect(
            imp,
            isNot(contains('package:material_ui/')),
            reason: '$name must not import material_ui ($imp)',
          );
          expect(
            imp,
            isNot(contains('../views/')),
            reason: '$name must not import views ($imp)',
          );
          expect(
            imp,
            isNot(contains('../cloud/')),
            reason: '$name must not import cloud ($imp)',
          );
        }
      }
    });

    test('cloud layer does not depend on views, logic, or models', () {
      for (final file in _dartFiles('lib/cloud')) {
        final name = file.uri.pathSegments.last;
        final imports = _importsOf(file);
        for (final imp in imports) {
          expect(imp, isNot(contains('../views/')), reason: '$name: $imp');
          expect(imp, isNot(contains('../logic/')), reason: '$name: $imp');
          expect(imp, isNot(contains('../model/')), reason: '$name: $imp');
        }
      }
    });

    test('logic layer does not depend on views, UI, or AppModel', () {
      for (final file in _dartFiles('lib/logic')) {
        final name = file.uri.pathSegments.last;
        final imports = _importsOf(file);
        for (final imp in imports) {
          expect(imp, isNot(contains('../views/')), reason: '$name: $imp');
          expect(imp, isNot(contains('../ui/')), reason: '$name: $imp');
          expect(
            imp,
            isNot(contains('package:material_ui/')),
            reason: '$name: $imp',
          );
          expect(
            imp,
            isNot(contains('app_model.dart')),
            reason: '$name must not depend upward on AppModel ($imp)',
          );
        }
      }
    });

    test('viewmodels do not depend on views or material_ui', () {
      for (final file in _dartFiles('lib/viewmodels')) {
        final name = file.uri.pathSegments.last;
        final imports = _importsOf(file);
        for (final imp in imports) {
          expect(imp, isNot(contains('../views/')), reason: '$name: $imp');
          expect(
            imp,
            isNot(contains('package:material_ui/')),
            reason: '$name: $imp',
          );
        }
      }
    });

    test('views do not directly import in_app_update_flutter', () {
      for (final file in _dartFiles('lib/views')) {
        final name = file.uri.pathSegments.last;
        final imports = _importsOf(file);
        for (final imp in imports) {
          expect(
            imp,
            isNot(contains('package:in_app_update_flutter/')),
            reason: '$name should use UpdateService ($imp)',
          );
        }
      }
    });

    test('dormant iOS/StoreKit code is absent from Android-only services', () {
      final ads = File('lib/logic/ad_service.dart').readAsStringSync();
      final billing = File('lib/logic/billing_service.dart').readAsStringSync();
      expect(ads, isNot(contains('PATHWISE_ADMOB_IOS_')));
      expect(ads, isNot(contains('TargetPlatform.iOS')));
      expect(billing, isNot(contains('verifyStoreKitPurchase')));
      expect(billing, isNot(contains('TargetPlatform.iOS')));
    });
  });
}
