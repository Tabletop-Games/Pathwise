import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/user_preferences.dart';

void main() {
  test('every catalogue palette provides readable card and action colours', () {
    for (final theme in PathwiseTheme.values) {
      final palette = BoardPalette.palettes[theme]!;
      final scheme = palette.theme.colorScheme;
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
      }

      expect(
        contrast(palette.ink, palette.surface),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} name',
      );
      expect(
        contrast(scheme.primary, scheme.onPrimary),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} price',
      );
      expect(
        contrast(scheme.secondary, scheme.onSecondary),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} apply',
      );
    }
  });
}
