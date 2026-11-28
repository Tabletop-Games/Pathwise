import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/user_preferences.dart';
import 'package:pathwise/ui/game_ui.dart';

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
        reason: '${theme.label} surface',
      );
      expect(
        contrast(palette.ink, palette.cardBottom),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} cardBottom',
      );
      expect(
        contrast(scheme.primary, scheme.onPrimary),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} primary',
      );
      expect(
        contrast(palette.buttonTop, palette.onRoute),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} buttonTop',
      );
      expect(
        contrast(palette.accent, palette.onAccent),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} accent',
      );
      expect(
        contrast(scheme.secondary, scheme.onSecondary),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} apply',
      );
      if (theme == PathwiseTheme.signal) {
        expect(
          contrast(palette.ink, palette.surface),
          greaterThanOrEqualTo(7.0),
          reason: 'High Contrast AAA ink/surface',
        );
      }
    }
  });

  test('theme foregrounds meet 4.5:1 against their paired surfaces', () {
    double contrast(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    for (final theme in PathwiseTheme.values) {
      final palette = BoardPalette.palettes[theme]!;
      for (final (foreground, background) in [
        (palette.ink, palette.surface),
        (palette.muted, palette.canvas),
        (palette.onRoute, palette.route),
        (palette.onAccent, palette.accent),
      ]) {
        expect(
          contrast(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: theme.label,
        );
      }
    }
  });
}
